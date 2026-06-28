import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/ble_config.dart';
import '../providers/ble_providers.dart'
    show appProvider, scanIntervalProvider;
import '../services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool   _encounterEnabled = true;
  bool   _updateEnabled    = true;
  bool   _eventEnabled     = true;
  bool   _soundEnabled     = true;
  bool   _vibrationEnabled = true;
  String _version          = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await NotificationService.loadSettings();
    PackageInfo info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {
      info = PackageInfo(
          appName: 'はじめましてこんにちは',
          packageName: '',
          version: '1.5.13',
          buildNumber: '20');
    }
    if (!mounted) return;
    setState(() {
      _encounterEnabled = settings.encounterEnabled;
      _updateEnabled    = settings.updateEnabled;
      _eventEnabled     = settings.eventEnabled;
      _soundEnabled     = settings.soundEnabled;
      _vibrationEnabled = settings.vibrationEnabled;
      _version          = 'beta${info.version}';
    });
  }

  Future<void> _toggleEncounter(bool value) async {
    setState(() => _encounterEnabled = value);
    await NotificationService.setPref(
        NotificationService.prefEncounterEnabled, value);
    if (value) await NotificationService.scheduleGateNotifications();
  }

  Future<void> _toggleUpdate(bool value) async {
    setState(() => _updateEnabled = value);
    await NotificationService.setPref(
        NotificationService.prefUpdateEnabled, value);
  }

  Future<void> _toggleEvent(bool value) async {
    setState(() => _eventEnabled = value);
    await NotificationService.setPref(
        NotificationService.prefEventEnabled, value);
  }

  Future<void> _toggleSound(bool value) async {
    setState(() => _soundEnabled = value);
    await NotificationService.setPref(
        NotificationService.prefSoundEnabled, value);
  }

  Future<void> _toggleVibration(bool value) async {
    setState(() => _vibrationEnabled = value);
    await NotificationService.setPref(
        NotificationService.prefVibrationEnabled, value);
  }

  Future<void> _showIntervalPicker() async {
    final si = ref.read(scanIntervalProvider);
    int tempIndex = ScanInterval.values.indexOf(si);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('キャンセル'),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text('検出タイミング',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                CupertinoButton(
                  child: const Text('完了'),
                  onPressed: () {
                    ref.read(appProvider.notifier)
                        .setScanInterval(ScanInterval.values[tempIndex]);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                    initialItem: tempIndex),
                itemExtent: 40,
                onSelectedItemChanged: (i) => tempIndex = i,
                children: ScanInterval.values
                    .map((v) => Center(child: Text(v.label)))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final si    = ref.watch(scanIntervalProvider);

    return CustomScrollView(
      slivers: [
        const CupertinoSliverNavigationBar(
          largeTitle: Text('設定'),
          border: null,
        ),
        SliverList(
          delegate: SliverChildListDelegate([

            // ─── BLE 通信 ──────────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('BLE 通信'),
              children: [
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.bluetooth,
                    color: state.isRunning
                        ? CupertinoColors.systemBlue
                        : CupertinoColors.systemGrey),
                  title: Text(state.isRunning ? 'スキャン中' : '停止中'),
                  subtitle: Text(
                    state.isRunning
                        ? 'バックグラウンドでも動作しています'
                        : 'Bluetoothをオンにすると自動で復帰します',
                  ),
                  trailing: state.isRunning
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              ref.read(appProvider.notifier).stop(),
                          child: const Text('停止',
                              style: TextStyle(
                                  color: CupertinoColors.destructiveRed)),
                        )
                      : CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () async {
                            final ok = await ref
                                .read(appProvider.notifier)
                                .requestPermissions();
                            if (ok && mounted) {
                              await ref.read(appProvider.notifier).start();
                            }
                          },
                          child: const Text('起動'),
                        ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.timer,
                      color: CupertinoColors.systemGrey),
                  title: const Text('検出タイミング'),
                  additionalInfo: Text(
                    si.label,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey),
                  ),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _showIntervalPicker,
                ),
              ],
            ),

            // ─── 通知 ─────────────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('通知'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.bell,
                      color: CupertinoColors.systemRed),
                  title: const Text('開門通知'),
                  subtitle: const Text('朝9:00 / 昼12:00 / 夜21:00'),
                  trailing: CupertinoSwitch(
                    value: _encounterEnabled,
                    onChanged: _toggleEncounter,
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.speaker_3_fill,
                      color: CupertinoColors.systemOrange),
                  title: const Text('イベント通知'),
                  subtitle: const Text('特別イベント・お知らせ'),
                  trailing: CupertinoSwitch(
                    value: _eventEnabled,
                    onChanged: _toggleEvent,
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.arrow_down_circle,
                      color: CupertinoColors.systemGreen),
                  title: const Text('アプリ更新'),
                  subtitle: const Text('新バージョンのお知らせ'),
                  trailing: CupertinoSwitch(
                    value: _updateEnabled,
                    onChanged: _toggleUpdate,
                  ),
                ),
              ],
            ),

            // ─── 通知スタイル ─────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('通知スタイル'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.volume_up,
                      color: CupertinoColors.systemPurple),
                  title: const Text('サウンド'),
                  trailing: CupertinoSwitch(
                    value: _soundEnabled,
                    onChanged: _toggleSound,
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.waveform,
                      color: CupertinoColors.systemIndigo),
                  title: const Text('バイブレーション'),
                  trailing: CupertinoSwitch(
                    value: _vibrationEnabled,
                    onChanged: _toggleVibration,
                  ),
                ),
              ],
            ),

            // ─── プライバシー ─────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('プライバシー'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.shield_lefthalf_fill,
                      color: CupertinoColors.systemGreen),
                  title: const Text('データの扱い'),
                  subtitle: const Text(
                      'GPS 不使用・BLE のみ・データはデバイス内にのみ保存'),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.lock_fill,
                      color: CupertinoColors.systemGrey),
                  title: const Text('リアルタイム検知の秘匿'),
                  subtitle: const Text(
                      '個人特定を防ぐため、すれ違いデータは結果演出完了後にのみ公開されます'),
                ),
              ],
            ),

            // ─── アプリ情報 ───────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('アプリ情報'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.info_circle,
                      color: CupertinoColors.systemBlue),
                  title: const Text('バージョン'),
                  additionalInfo: Text(
                    _version,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ]),
        ),
      ],
    );
  }
}
