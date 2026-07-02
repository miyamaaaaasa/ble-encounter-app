import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/ble_config.dart';
import '../providers/ble_providers.dart'
    show appProvider, scanIntervalProvider;
import '../providers/theme_provider.dart';
import '../services/data_export_service.dart';
import '../services/game_storage.dart';
import '../services/notification_service.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool   _encounterEnabled = true;
  bool   _bannerEnabled    = true;
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
          version: '1.5.14',
          buildNumber: '21');
    }
    if (!mounted) return;
    setState(() {
      _encounterEnabled = settings.encounterEnabled;
      _bannerEnabled    = settings.bannerEnabled;
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

  Future<void> _toggleBanner(bool value) async {
    setState(() => _bannerEnabled = value);
    await NotificationService.setPref(
        NotificationService.prefBannerEnabled, value);
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

  Future<void> _onExport() async {
    final state = ref.read(appProvider);
    try {
      final gameData = await GameStorage.load();
      await DataExportService.exportAll(
        profile:    state.ownProfile,
        encounters: state.encounters,
        badges:     state.badges,
        gameData:   gameData,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポートエラー: $e')),
      );
    }
  }

  Future<void> _onImport() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('データをインポート'),
        content: const Text(
          '現在のデータはバックアップファイルで上書きされます。\n続けますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('インポート'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final result = await DataExportService.importFromFile();
      if (result == null) return;
      await ref.read(appProvider.notifier).applyImport(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'インポート完了: ${result.encounters.length}人 / ${result.badges.length}個のバッジ',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('インポートエラー: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state     = ref.watch(appProvider);
    final si        = ref.watch(scanIntervalProvider);
    final themeMode = ref.watch(themeProvider);

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('設定')),
        SliverList(
          delegate: SliverChildListDelegate([

            // ─── 外観・ヘルプ ─────────────────────────────────────────────
            _SectionHeader('外観・ヘルプ'),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('テーマ'),
              subtitle: Text(switch (themeMode) {
                ThemeMode.light => '昼の広場（ライト）',
                ThemeMode.dark => '夜の広場（ダーク）',
                ThemeMode.system => 'システムに合わせる',
              }),
              trailing: DropdownButton<ThemeMode>(
                value: themeMode,
                items: const [
                  DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('☀️ 昼', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('🌙 夜', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('📱 自動', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) {
                  if (v != null) ref.read(themeProvider.notifier).set(v);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('チュートリアルをもう一度見る'),
              subtitle: const Text('アプリの遊びかたをおさらい'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (ctx) => OnboardingScreen(
                    onDone: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── BLE ─────────────────────────────────────────────────────
            _SectionHeader('BLE 通信'),
            ListTile(
              leading: Icon(
                state.isRunning
                    ? Icons.bluetooth_searching
                    : Icons.bluetooth_disabled,
                color: state.isRunning
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(state.isRunning ? 'スキャン中' : '停止中'),
              subtitle: state.isRunning
                  ? const Text('バックグラウンドでも動作しています')
                  : const Text('Bluetoothをオンにすると自動で復帰します'),
              trailing: state.isRunning
                  ? OutlinedButton(
                      onPressed: () =>
                          ref.read(appProvider.notifier).stop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error,
                        side: BorderSide(
                            color: Theme.of(context).colorScheme.error),
                      ),
                      child: const Text('停止'),
                    )
                  : FilledButton.tonal(
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

            // ─── 検出タイミング ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('検出タイミング',
                            style: TextStyle(fontSize: 15)),
                        Text(
                          '時計に同期 — 全デバイスが同じタイミングで通信',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        if (si.needsBatteryWarning)
                          Text(
                            '⚡ バッテリー消費が増加します',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .error),
                          ),
                      ],
                    ),
                  ),
                  DropdownButton<ScanInterval>(
                    value: si,
                    items: ScanInterval.values
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.label,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      ref
                          .read(appProvider.notifier)
                          .setScanInterval(v);
                    },
                  ),
                ],
              ),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── 通知 ─────────────────────────────────────────────────────
            _SectionHeader('通知'),

            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('開門通知'),
              subtitle: const Text('朝9:00 / 昼12:00 / 夜21:00 に通知'),
              value: _encounterEnabled,
              onChanged: _toggleEncounter,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.radar_outlined),
              title: const Text('すれ違い検知通知'),
              subtitle: const Text('すれ違い後10〜30分でこっそり通知'),
              value: _bannerEnabled,
              onChanged: _toggleBanner,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.campaign_outlined),
              title: const Text('イベント通知'),
              subtitle: const Text('特別イベント・お知らせを受信'),
              value: _eventEnabled,
              onChanged: _toggleEvent,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.system_update_outlined),
              title: const Text('アプリ更新'),
              subtitle: const Text('新バージョンのお知らせ'),
              value: _updateEnabled,
              onChanged: _toggleUpdate,
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── サウンド / バイブ ─────────────────────────────────────────
            _SectionHeader('通知スタイル'),

            SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('サウンド'),
              value: _soundEnabled,
              onChanged: _toggleSound,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.vibration_outlined),
              title: const Text('バイブレーション'),
              value: _vibrationEnabled,
              onChanged: _toggleVibration,
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── データ管理 ───────────────────────────────────────────────
            _SectionHeader('データ管理'),

            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('データをエクスポート'),
              subtitle: const Text(
                  'プロフィール・すれ違い記録・バッジ・ゲームデータをバックアップ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _onExport,
            ),

            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('データをインポート'),
              subtitle: const Text('バックアップファイルからデータを復元（上書き）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _onImport,
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── プライバシー ─────────────────────────────────────────────
            _SectionHeader('プライバシー'),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('データの扱い'),
              subtitle: Text(
                  'GPS 不使用・BLE のみ・データはデバイス内にのみ保存'),
            ),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('リアルタイム検知の秘匿'),
              subtitle: Text(
                  '個人特定を防ぐため、すれ違いデータは結果演出完了後にのみ公開されます'),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── アプリ情報 ───────────────────────────────────────────────
            _SectionHeader('アプリ情報'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('バージョン'),
              trailing: Text(
                _version,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13),
              ),
            ),

            const SizedBox(height: 40),
          ]),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
