import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
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

// ─── State ──────────────────────────────────────────────────────────────────

class AppState {
  final bool isLoading;
  final bool isRunning;
  final OwnProfile? ownProfile;
  final List<EncounterRecord> encounters;
  final List<AppBadge> badges;
  final bool hasNewEncounter;
  final List<AppBadge> newlyEarnedBadges; // 通知表示用
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

  // peerId → 最後に notification を schedule した時刻（1日1回制限）
  final _notifScheduled = <String, DateTime>{};
  bool _userStopped = false; // 手動停止後は BT 復帰時に自動起動しない

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
      // 手動停止中は BT 復帰時に自動起動しない
      if (!_userStopped && !state.isLoading &&
          state.ownProfile != null && !state.isRunning) {
        await start();
      }
    } else if (btState == BluetoothAdapterState.off ||
               btState == BluetoothAdapterState.turningOff) {
      if (state.isRunning) {
        await _encounterSub?.cancel();
        _encounterSub = null;
        await _departureSub?.cancel();
        _departureSub = null;
        try { await _scanner.stop(); } catch (e) {
          debugPrint('[App] scanner stop error: $e');
        }
        // BT 強制 OFF 時もアドバタイズを明示的に停止
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

  Future<void> _loadData() async {
    final profile  = await _storage.loadOwnProfile();
    var encounters = await _storage.loadEncounters();
    final badges   = await BadgeService.load();

    // 翌日自動救済: 今日より前の未開封エンカウントを自動解放
    final todayStart = DateTime.now();
    final hasOldUnrevealed = encounters.any(
      (e) => !e.isRevealed && (
        e.lastMet.year < todayStart.year ||
        e.lastMet.month < todayStart.month ||
        e.lastMet.day < todayStart.day
      ),
    );
    if (hasOldUnrevealed) {
      encounters = encounters.map((e) {
        if (!e.isRevealed && !e.metToday) return e.reveal();
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
    if (profile != null) await _autoStart();
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
      try {
        await _advertiser.stopAdvertise();
        await _advertiser.startAdvertise(PeerId.bytes, withDate.toScanPayload());
      } catch (e) {
        debugPrint('[App] profile update error: $e');
      }
    } else if (isFirstSave) {
      await _autoStart();
    }
  }

  // ─── Permissions ─────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();

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
    _userStopped = false; // 明示的に起動 → 手動停止フラグをリセット
    if (state.isRunning) return;
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
      await _advertiser.startAdvertise(PeerId.bytes, profile.toScanPayload());
      await _scanner.start();
      state = state.copyWith(isRunning: true, errorMessage: null);
      debugPrint('[App] started peerId=${PeerId.hex}');

      final notifSettings = await NotificationService.loadSettings();
      if (notifSettings.dailyEnabled) {
        await NotificationService.scheduleDailyNotification(
          hour: notifSettings.hour,
        );
      }
    } catch (e) {
      debugPrint('[App] start error: $e');
      state = state.copyWith(isRunning: false, errorMessage: '起動エラー: $e');
    }
  }

  // ─── Stop ────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    _userStopped = true; // 手動停止 → BT 復帰後も自動起動しない
    if (!state.isRunning) return;
    await _encounterSub?.cancel();
    await _departureSub?.cancel();
    _encounterSub = null;
    _departureSub = null;
    // スキャン停止
    try { await _scanner.stop(); } catch (e) {
      debugPrint('[App] scanner stop error: $e');
    }
    // アドバタイズ停止（送信シャットダウン）
    try { await _advertiser.stopAdvertise(); } catch (e) {
      debugPrint('[App] stopAdvertise error: $e');
    }
    // フォアグラウンドサービス停止
    try { await _advertiser.stopForegroundService(); } catch (e) {
      debugPrint('[App] stopForegroundService error: $e');
    }
    state = state.copyWith(isRunning: false);
    debugPrint('[App] fully stopped (scan + advertise)');
  }

  void clearNewEncounterFlag() {
    state = state.copyWith(hasNewEncounter: false);
  }

  void clearNewBadges() {
    state = state.copyWith(newlyEarnedBadges: []);
  }

  // 結果演出完了時: 本日の unrevealed を一斉に解放 → バッジチェック
  Future<void> revealToday() async {
    final list = state.encounters.map((e) {
      if (e.metToday && !e.isRevealed) return e.reveal();
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
    // ウォームアップ振動（生存シグナル）は v1.4.1 で削除 → 切断通知に移行
    await _upsertEncounter(
      peerId:     event.peerId,
      name:       event.name,
      colorIndex: event.colorIndex,
      template:   event.template,
      rssi:       event.rssi,
    );
    debugPrint('[App] encountered: ${event.name}');
  }

  // 切断イベント → ランダム 10〜60分後に通知スケジュール
  Future<void> _onDeparture(String peerId) async {
    final last = _notifScheduled[peerId];
    final now  = DateTime.now();
    // 同じ人に対し12時間以内に重複スケジュールしない
    if (last != null && now.difference(last).inHours < 12) {
      debugPrint('[Departure] skip notif for ${peerId.substring(28)} (cooldown)');
      return;
    }
    _notifScheduled[peerId] = now;

    final delayMin = _rng.nextInt(51) + 10; // 10〜60分
    final settings = await NotificationService.loadSettings();
    await NotificationService.scheduleEncounterNotification(
      peerId:       peerId,
      delayMinutes: delayMin,
      revealHour:   settings.hour,
    );
    debugPrint('[Departure] scheduled notif in ${delayMin}min for ${peerId.substring(28)}');
  }

  Future<void> _upsertEncounter({
    required String peerId,
    required String name,
    required int colorIndex,
    required TemplateMessage template,
    required int rssi,
  }) async {
    final now  = DateTime.now();
    final list = List<EncounterRecord>.from(state.encounters);
    final idx  = list.indexWhere((e) => e.peerId == peerId);

    if (idx >= 0) {
      final existing = list.removeAt(idx);
      list.insert(0, existing.updatedWith(
        lastMet:  now,
        rssi:     rssi,
        name:     name,
        template: template,
      ));
    } else {
      list.insert(0, EncounterRecord(
        peerId:     peerId,
        name:       name,
        colorIndex: colorIndex,
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

  @override
  void dispose() {
    _btStateSub?.cancel();
    _encounterSub?.cancel();
    _departureSub?.cancel();
    _scanner.dispose();
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final appProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);
