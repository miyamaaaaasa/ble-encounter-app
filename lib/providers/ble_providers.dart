import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ble_config.dart';
import '../core/peer_id.dart';
import '../models/app_badge.dart';
import '../models/own_profile.dart';
import '../models/encounter_record.dart';
import '../models/template_message.dart';
import '../services/advertiser.dart';
import '../services/badge_service.dart';
import '../services/scanner.dart';
import '../services/profile_storage.dart';
import '../services/notification_service.dart';

// スキャン間隔プロバイダー（設定画面 → サイクルへ即時反映）
final scanIntervalProvider = StateProvider<ScanInterval>((ref) => ScanInterval.two);

// ─── State ──────────────────────────────────────────────────────────────────

class AppState {
  final bool isLoading;
  final bool isRunning;
  final OwnProfile? ownProfile;
  final List<EncounterRecord> encounters;
  final List<AppBadge> badges;
  final bool hasNewEncounter;
  final List<AppBadge> newlyEarnedBadges;
  final String? errorMessage;

  const AppState({
    this.isLoading = true,
    this.isRunning = false,
    this.ownProfile,
    this.encounters = const [],
    this.badges = const [],
    this.hasNewEncounter = false,
    this.newlyEarnedBadges = const [],
    this.errorMessage,
  });

  AppState copyWith({
    bool? isLoading,
    bool? isRunning,
    OwnProfile? ownProfile,
    List<EncounterRecord>? encounters,
    List<AppBadge>? badges,
    bool? hasNewEncounter,
    List<AppBadge>? newlyEarnedBadges,
    String? errorMessage,
  }) =>
      AppState(
        isLoading:         isLoading ?? this.isLoading,
        isRunning:         isRunning ?? this.isRunning,
        ownProfile:        ownProfile ?? this.ownProfile,
        encounters:        encounters ?? this.encounters,
        badges:            badges ?? this.badges,
        hasNewEncounter:   hasNewEncounter ?? this.hasNewEncounter,
        newlyEarnedBadges: newlyEarnedBadges ?? this.newlyEarnedBadges,
        errorMessage:      errorMessage,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class AppNotifier extends Notifier<AppState> {
  final _advertiser = BleAdvertiser();
  final _scanner    = BleScanner();
  final _storage    = ProfileStorage();
  final _rng        = Random();

  final _notifScheduled = <String, DateTime>{};
  bool _userStopped = false;

  bool   _cycleActive    = false;
  bool   _cycleOnActive  = false;
  bool   _starting       = false;
  Timer? _cycleTimer;
  ScanInterval _scanInterval = ScanInterval.two;

  StreamSubscription<EncounterEvent>?        _encounterSub;
  StreamSubscription<String>?                _departureSub;
  StreamSubscription<BluetoothAdapterState>? _btStateSub;

  @override
  AppState build() {
    _loadData();
    _btStateSub = FlutterBluePlus.adapterState.listen(_onBluetoothState);
    return const AppState();
  }

  Future<void> _onBluetoothState(BluetoothAdapterState btState) async {
    debugPrint('[App] BT state: $btState');
    if (btState == BluetoothAdapterState.on) {
      if (!_userStopped && !state.isLoading &&
          state.ownProfile != null && !state.isRunning) {
        await start();
      }
    } else if (btState == BluetoothAdapterState.off ||
               btState == BluetoothAdapterState.turningOff) {
      if (state.isRunning) {
        _stopCycle();
        await _encounterSub?.cancel();
        _encounterSub = null;
        await _departureSub?.cancel();
        _departureSub = null;
        try { await _scanner.stop(); } catch (e) {
          debugPrint('[App] scanner stop error: $e');
        }
        try { await _advertiser.stopAdvertise(); } catch (e) {
          debugPrint('[App] stopAdvertise(bt-off) error: $e');
        }
        try { await _advertiser.stopForegroundService(); } catch (e) {
          debugPrint('[App] stopForegroundService(bt-off) error: $e');
        }
        state = state.copyWith(isRunning: false, errorMessage: null);
        debugPrint('[App] BT off — fully stopped');
      }
    }
  }

  // エンカウント時刻 → 開門時刻（どの「ゲート」に属するか）
  static DateTime gateTimeFor(DateTime t) {
    if (t.hour < 9)  return DateTime(t.year, t.month, t.day, 9);
    if (t.hour < 12) return DateTime(t.year, t.month, t.day, 12);
    if (t.hour < 21) return DateTime(t.year, t.month, t.day, 21);
    // 21:00以降 → 翌日9:00
    final next = t.add(const Duration(days: 1));
    return DateTime(next.year, next.month, next.day, 9);
  }

  Future<void> _loadData() async {
    final profile   = await _storage.loadOwnProfile();
    var encounters  = await _storage.loadEncounters();
    final badges    = await BadgeService.load();

    // スキャン間隔を復元
    final prefs = await SharedPreferences.getInstance();
    final savedInterval = prefs.getInt(ScanIntervalX.prefKey) ?? ScanInterval.two.index;
    _scanInterval = ScanIntervalX.fromIndex(savedInterval);
    ref.read(scanIntervalProvider.notifier).state = _scanInterval;

    // 自動救済: ゲート時刻が過去になった未開封エンカウントを解放
    final now = DateTime.now();
    final hasOldUnrevealed = encounters.any(
      (e) => !e.isRevealed && gateTimeFor(e.lastMet).isBefore(now),
    );
    if (hasOldUnrevealed) {
      encounters = encounters.map((e) {
        if (!e.isRevealed && gateTimeFor(e.lastMet).isBefore(now)) return e.reveal();
        return e;
      }).toList();
      await _storage.saveEncounters(encounters);
      debugPrint('[App] auto-rescued past unrevealed encounters');
    }

    state = state.copyWith(
      isLoading:  false,
      ownProfile: profile,
      encounters: encounters,
      badges:     badges,
    );
    if (profile != null) {
      // Defer BLE start until after the UI has rendered the home screen.
      // Without this, permission dialogs appear while isLoading=false state
      // change hasn't been drawn yet, causing an apparent "frozen white screen".
      await Future.delayed(const Duration(milliseconds: 300));
      await _autoStart();
    }
  }

  Future<void> _autoStart() async {
    final ok = await requestPermissions();
    if (ok) await start();
  }

  // ─── Profile ─────────────────────────────────────────────────────────────

  Future<void> saveOwnProfile(OwnProfile profile) async {
    final isFirstSave = state.ownProfile == null;
    final withDate = profile.registeredAt != null
        ? profile
        : profile.copyWith(registeredAt: DateTime.now());
    await _storage.saveOwnProfile(withDate);
    state = state.copyWith(ownProfile: withDate, errorMessage: null);
    if (state.isRunning) {
      // プロフィール更新時: 次の ON サイクルで自動的に新プロフィールを使用
      // (強制再起動は不要)
      debugPrint('[App] profile updated, next cycle will use new payload');
    } else if (isFirstSave) {
      await _autoStart();
    }
  }

  // ─── Permissions ─────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    // iOS: bluetoothScan/Advertise/Connect は NSBluetoothAlwaysUsageDescription にマッピングされる
    // Android: 個別権限が必要
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      if (defaultTargetPlatform != TargetPlatform.iOS) Permission.locationWhenInUse,
      Permission.notification,
    ];

    final statuses = await permissions.request();

    final denied = statuses.entries
        .where((e) => e.value.isDenied || e.value.isPermanentlyDenied)
        .map((e) => e.key.toString())
        .toList();

    if (denied.isNotEmpty) {
      state = state.copyWith(errorMessage: '許可が必要です: ${denied.join(', ')}');
      return false;
    }
    return true;
  }

  // ─── Start ───────────────────────────────────────────────────────────────

  Future<void> start() async {
    _userStopped = false;
    if (state.isRunning || _starting) return;
    _starting = true;
    final profile = state.ownProfile;
    if (profile == null) {
      state = state.copyWith(errorMessage: 'プロフィールを設定してください');
      return;
    }
    try {
      final btState = await FlutterBluePlus.adapterState.first;
      if (btState != BluetoothAdapterState.on) {
        debugPrint('[App] BT not ready ($btState), waiting...');
        return;
      }
    } catch (_) {}

    try {
      await _encounterSub?.cancel();
      await _departureSub?.cancel();
      _encounterSub = _scanner.encounters.listen(_onEncounter);
      _departureSub = _scanner.departures.listen(_onDeparture);

      await _advertiser.startForegroundService();
      state = state.copyWith(isRunning: true, errorMessage: null);
      _starting = false; // isRunning=true になったのでロック解放
      debugPrint('[App] cycle started peerId=${PeerId.hex}');

      _startCycle();

      await NotificationService.scheduleGateNotifications();
    } catch (e) {
      debugPrint('[App] start error: $e');
      state = state.copyWith(isRunning: false, errorMessage: '起動エラー: $e');
    } finally {
      _starting = false;
    }
  }

  // ─── 間欠スキャンサイクル ─────────────────────────────────────────────────

  void _startCycle() {
    _cycleActive = true;
    _cycleTimer?.cancel();
    _doCycleOn(); // 即時1回目を開始
  }

  void _stopCycle() {
    _cycleActive = false;
    _cycleTimer?.cancel();
    _cycleTimer = null;
  }

  Future<void> _doCycleOn() async {
    if (!_cycleActive || _userStopped) return;
    // 並列実行防止: 前回の _doCycleOn がまだ async 処理中なら skip
    if (_cycleOnActive) {
      debugPrint('[Cycle] _doCycleOn skip (already running)');
      return;
    }
    _cycleOnActive = true;
    try {
      final profile = state.ownProfile;
      if (profile == null) return;

      final btState = await FlutterBluePlus.adapterState.first;
      if (btState != BluetoothAdapterState.on) {
        // BT がオフなら 30 秒後に再試行
        _cycleTimer = Timer(const Duration(seconds: 30), _doCycleOn);
        return;
      }
      await _advertiser.startAdvertise(PeerId.bytes, profile.toScanPayload());
      await _scanner.start();
      debugPrint('[Cycle] BLE ON — ${kScanOnSeconds}s (debug=$kDebugBle)');
    } catch (e) {
      debugPrint('[Cycle] ON error: $e');
    } finally {
      _cycleOnActive = false;
    }
    _cycleTimer = Timer(Duration(seconds: kScanOnSeconds), _doCycleOff);
  }

  Future<void> _doCycleOff() async {
    if (!_cycleActive) return;
    try { await _scanner.stop(); } catch (e) {
      debugPrint('[Cycle] scan stop error: $e');
    }
    try { await _advertiser.stopAdvertise(); } catch (e) {
      debugPrint('[Cycle] advertise stop error: $e');
    }
    final offSecs = _scanInterval.offSeconds;
    debugPrint('[Cycle] BLE OFF — ${offSecs}s スリープ (debug=$kDebugBle)');
    _cycleTimer = Timer(Duration(seconds: offSecs), _doCycleOn);
  }

  // ─── Stop ────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    _userStopped = true;
    if (!state.isRunning) return;
    _stopCycle(); // サイクルタイマーをキャンセル
    await _encounterSub?.cancel();
    await _departureSub?.cancel();
    _encounterSub = null;
    _departureSub = null;
    try { await _scanner.stop(); } catch (e) {
      debugPrint('[App] scanner stop error: $e');
    }
    try { await _advertiser.stopAdvertise(); } catch (e) {
      debugPrint('[App] stopAdvertise error: $e');
    }
    try { await _advertiser.stopForegroundService(); } catch (e) {
      debugPrint('[App] stopForegroundService error: $e');
    }
    state = state.copyWith(isRunning: false);
    debugPrint('[App] fully stopped (cycle + scan + advertise)');
  }

  void clearNewEncounterFlag() {
    state = state.copyWith(hasNewEncounter: false);
  }

  void clearNewBadges() {
    state = state.copyWith(newlyEarnedBadges: []);
  }

  // 結果演出完了時: ゲート時刻が過去の unrevealed を一斉に解放 → バッジチェック
  Future<void> revealToday() async {
    final now = DateTime.now();
    final list = state.encounters.map((e) {
      if (!e.isRevealed && gateTimeFor(e.lastMet).isBefore(now)) return e.reveal();
      return e;
    }).toList();

    final totalRevealed = list.where((e) => e.isRevealed).length;
    final updatedBadges = await BadgeService.checkCountBadges(
      totalRevealed: totalRevealed,
      existing: state.badges,
    );
    final newlyEarned = updatedBadges
        .where((b) => !state.badges.any((ob) => ob.id == b.id))
        .toList();

    state = state.copyWith(
      encounters:        list,
      hasNewEncounter:   false,
      badges:            updatedBadges,
      newlyEarnedBadges: newlyEarned,
    );
    await _storage.saveEncounters(list);
  }

  // ─── Encounter ───────────────────────────────────────────────────────────

  Future<void> _onEncounter(EncounterEvent event) async {
    debugPrint('[Encounter] name=${event.name} id=${event.peerId.substring(28)}');
    await _upsertEncounter(
      peerId:     event.peerId,
      name:       event.name,
      colorIndex: event.colorIndex,
      prefecture: event.prefecture,
      template:   event.template,
      rssi:       event.rssi,
    );
    debugPrint('[App] encountered: ${event.name}');
  }

  // 切断イベント → ランダム 10〜30分後に通知スケジュール
  Future<void> _onDeparture(String peerId) async {
    final last = _notifScheduled[peerId];
    final now  = DateTime.now();
    if (last != null && now.difference(last).inHours < 12) {
      debugPrint('[Departure] skip notif for ${peerId.substring(28)} (cooldown)');
      return;
    }
    _notifScheduled[peerId] = now;

    final delayMin = _rng.nextInt(21) + 10; // 10〜30分
    await NotificationService.scheduleEncounterNotification(
      peerId:       peerId,
      delayMinutes: delayMin,
    );
    debugPrint('[Departure] scheduled notif in ${delayMin}min for ${peerId.substring(28)}');
  }

  Future<void> setScanInterval(ScanInterval interval) async {
    _scanInterval = interval;
    ref.read(scanIntervalProvider.notifier).state = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ScanIntervalX.prefKey, interval.index);
    debugPrint('[App] scanInterval → ${interval.label}');
  }

  Future<void> _upsertEncounter({
    required String peerId,
    required String name,
    required int colorIndex,
    required int prefecture,
    required TemplateMessage template,
    required int rssi,
  }) async {
    final now  = DateTime.now();
    final list = List<EncounterRecord>.from(state.encounters);
    final idx  = list.indexWhere((e) => e.peerId == peerId);

    if (idx >= 0) {
      final existing = list.removeAt(idx);
      final newMeetCount =
          existing.metToday ? existing.meetCount : existing.meetCount + 1;
      list.insert(0, EncounterRecord(
        peerId:     existing.peerId,
        name:       name,
        colorIndex: existing.colorIndex,
        prefecture: prefecture != -1 ? prefecture : existing.prefecture,
        firstMet:   existing.firstMet,
        lastMet:    now,
        meetCount:  newMeetCount,
        rssi:       rssi,
        template:   template,
        isRevealed: existing.isRevealed && existing.metToday,
      ));
    } else {
      list.insert(0, EncounterRecord(
        peerId:     peerId,
        name:       name,
        colorIndex: colorIndex,
        prefecture: prefecture,
        firstMet:   now,
        lastMet:    now,
        meetCount:  1,
        rssi:       rssi,
        template:   template,
      ));
    }

    final trimmed = list.take(500).toList();
    state = state.copyWith(encounters: trimmed, hasNewEncounter: true);
    await _storage.saveEncounters(trimmed);
  }

  void dispose() {
    _stopCycle();
    _btStateSub?.cancel();
    _encounterSub?.cancel();
    _departureSub?.cancel();
    _scanner.dispose();
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final appProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);
