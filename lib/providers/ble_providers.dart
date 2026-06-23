import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/peer_id.dart';
import '../models/own_profile.dart';
import '../models/encounter_record.dart';
import '../models/template_message.dart';
import '../services/advertiser.dart';
import '../services/scanner.dart';
import '../services/profile_storage.dart';
import '../services/notification_service.dart';

// ─── State ──────────────────────────────────────────────────────────────────

class AppState {
  final bool isLoading;
  final bool isRunning;
  final OwnProfile? ownProfile;
  final List<EncounterRecord> encounters;
  final bool hasNewEncounter;
  final String? errorMessage;

  const AppState({
    this.isLoading = true,
    this.isRunning = false,
    this.ownProfile,
    this.encounters = const [],
    this.hasNewEncounter = false,
    this.errorMessage,
  });

  AppState copyWith({
    bool? isLoading,
    bool? isRunning,
    OwnProfile? ownProfile,
    List<EncounterRecord>? encounters,
    bool? hasNewEncounter,
    String? errorMessage,
  }) =>
      AppState(
        isLoading: isLoading ?? this.isLoading,
        isRunning: isRunning ?? this.isRunning,
        ownProfile: ownProfile ?? this.ownProfile,
        encounters: encounters ?? this.encounters,
        hasNewEncounter: hasNewEncounter ?? this.hasNewEncounter,
        errorMessage: errorMessage,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class AppNotifier extends Notifier<AppState> {
  final _advertiser = BleAdvertiser();
  final _scanner    = BleScanner();
  final _storage    = ProfileStorage();

  final _cooldown = <String, DateTime>{};

  StreamSubscription<EncounterEvent>?       _encounterSub;
  StreamSubscription<BluetoothAdapterState>? _btStateSub;

  @override
  AppState build() {
    _loadData();
    // Bluetooth ON/OFF に連動して自動起動・停止する
    _btStateSub = FlutterBluePlus.adapterState.listen(_onBluetoothState);
    return const AppState();
  }

  // Bluetooth アダプター状態の変化を処理
  Future<void> _onBluetoothState(BluetoothAdapterState btState) async {
    debugPrint('[App] BT state: $btState');
    if (btState == BluetoothAdapterState.on) {
      // ロード完了済み & プロフィールあり & 未起動 のとき自動起動
      if (!state.isLoading && state.ownProfile != null && !state.isRunning) {
        await start();
      }
    } else if (btState == BluetoothAdapterState.off ||
               btState == BluetoothAdapterState.turningOff) {
      if (state.isRunning) {
        // BT が切れた — スキャンを停止してUIを更新（advertiser は OS が自動停止）
        await _encounterSub?.cancel();
        _encounterSub = null;
        try { await _scanner.stop(); } catch (_) {}
        state = state.copyWith(isRunning: false, errorMessage: null);
        debugPrint('[App] BT off — stopped');
      }
    }
  }

  Future<void> _loadData() async {
    final profile    = await _storage.loadOwnProfile();
    final encounters = await _storage.loadEncounters();
    state = state.copyWith(
      isLoading: false,
      ownProfile: profile,
      encounters: encounters,
    );
    if (profile != null) {
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
    if (state.isRunning) return;
    final profile = state.ownProfile;
    if (profile == null) {
      state = state.copyWith(errorMessage: 'プロフィールを設定してください');
      return;
    }

    // BT が無効なら黙って返る（adapterState リスナーが ON になったとき再度呼ぶ）
    try {
      final btState = await FlutterBluePlus.adapterState.first;
      if (btState != BluetoothAdapterState.on) {
        debugPrint('[App] BT not ready ($btState), waiting...');
        return;
      }
    } catch (_) {}

    try {
      // 既存のサブスクリプションをクリーンアップしてから再登録
      await _encounterSub?.cancel();
      _encounterSub = _scanner.encounters.listen(_onEncounter);

      await _advertiser.startForegroundService();
      await _advertiser.startAdvertise(PeerId.bytes, profile.toScanPayload());
      await _scanner.start();
      state = state.copyWith(isRunning: true, errorMessage: null);
      debugPrint('[App] started peerId=${PeerId.hex}');

      final notifSettings = await NotificationService.loadSettings();
      if (notifSettings.dailyEnabled) {
        await NotificationService.scheduleDailyNotification(
          hour: notifSettings.hour,
          minute: notifSettings.minute,
        );
      }
    } catch (e) {
      debugPrint('[App] start error: $e');
      state = state.copyWith(isRunning: false, errorMessage: '起動エラー: $e');
    }
  }

  // ─── Stop ────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    if (!state.isRunning) return;
    await _encounterSub?.cancel();
    _encounterSub = null;
    await _scanner.stop();
    try {
      await _advertiser.stopAdvertise();
      await _advertiser.stopForegroundService();
    } catch (_) {}
    state = state.copyWith(isRunning: false);
  }

  void clearNewEncounterFlag() {
    state = state.copyWith(hasNewEncounter: false);
  }

  // ─── Encounter ───────────────────────────────────────────────────────────

  Future<void> _onEncounter(EncounterEvent event) async {
    final peerId = event.peerId;
    debugPrint('[Encounter] name=${event.name} id=${peerId.substring(28)}');

    final last = _cooldown[peerId];
    if (last != null && DateTime.now().difference(last).inMinutes < 60) {
      debugPrint('[Encounter] cooldown skip');
      return;
    }
    _cooldown[peerId] = DateTime.now();

    await _upsertEncounter(
      peerId: peerId,
      name: event.name,
      colorIndex: event.colorIndex,
      template: event.template,
      rssi: event.rssi,
    );

    debugPrint('[App] encountered: ${event.name}');
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
      final updated = existing.updatedWith(
        lastMet: now,
        rssi: rssi,
        name: name,
        template: template,
      );
      list.insert(0, updated);
    } else {
      list.insert(
        0,
        EncounterRecord(
          peerId: peerId,
          name: name,
          colorIndex: colorIndex,
          firstMet: now,
          lastMet: now,
          meetCount: 1,
          rssi: rssi,
          template: template,
        ),
      );
    }

    final trimmed = list.take(500).toList();
    state = state.copyWith(encounters: trimmed, hasNewEncounter: true);
    await _storage.saveEncounters(trimmed);
  }

  @override
  void dispose() {
    _btStateSub?.cancel();
    _encounterSub?.cancel();
    _scanner.dispose();
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final appProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);
