import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/ble_providers.dart' show appProvider, notifHourProvider;
import '../services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int  _notifHour        = 18;
  bool _dailyEnabled     = true;
  bool _updateEnabled    = true;
  bool _eventEnabled     = true;
  bool _soundEnabled     = true;
  bool _vibrationEnabled = true;
  String _version        = '';

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
          appName: 'はじめましてこんにちは', packageName: '',
          version: '1.5.9', buildNumber: '16');
    }
    if (!mounted) return;
    setState(() {
      _notifHour        = settings.hour;
      _dailyEnabled     = settings.dailyEnabled;
      _updateEnabled    = settings.updateEnabled;
      _eventEnabled     = settings.eventEnabled;
      _soundEnabled     = settings.soundEnabled;
      _vibrationEnabled = settings.vibrationEnabled;
      _version          = 'beta${info.version}';  // beta表記を強制
    });
  }

  // 固定時刻に変更（7日ロックチェック込み）
  Future<void> _changeHour(int? hour) async {
    if (hour == null) return;

    final canChange = await NotificationService.canChangeTime();
    if (!canChange) {
      final next = await NotificationService.nextAllowedChangeDate();
      if (!mounted) return;
      final mm = next?.month.toString().padLeft(2, '0') ?? '--';
      final dd = next?.day.toString().padLeft(2, '0') ?? '--';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('設定は1週間に1回しか変更できません（次回変更可能日: $mm/$dd）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await NotificationService.changeHour(hour);
    ref.read(notifHourProvider.notifier).state = hour; // 今日タブへ即時反映
    if (!mounted) return;
    setState(() => _notifHour = hour);
    final hh = hour.toString().padLeft(2, '0');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$hh:00 に通知します'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleDaily(bool value) async {
    setState(() => _dailyEnabled = value);
    if (value) {
      await NotificationService.scheduleDailyNotification(hour: _notifHour);
    } else {
      await NotificationService.cancelDailyNotification();
    }
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('設定')),
        SliverList(
          delegate: SliverChildListDelegate([

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
                        foregroundColor: Theme.of(context).colorScheme.error,
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
            const Divider(indent: 16, endIndent: 16),

            // ─── 通知 ─────────────────────────────────────────────────────
            _SectionHeader('通知'),

            SwitchListTile(
              secondary: const Icon(Icons.summarize_outlined),
              title: const Text('本日の結果通知'),
              subtitle: const Text('毎日指定時刻に結果をお知らせ'),
              value: _dailyEnabled,
              onChanged: _toggleDaily,
            ),

            // 固定時刻セレクター（0:00 / 9:00 / 12:00 / 18:00）
            AnimatedOpacity(
              opacity: _dailyEnabled ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_outlined, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('配信時刻',
                              style: TextStyle(fontSize: 15)),
                          Text(
                            '※ 変更は1週間に1回のみ',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<int>(
                      value: NotificationService.fixedHours
                              .contains(_notifHour)
                          ? _notifHour
                          : NotificationService.fixedHours.last,
                      items: NotificationService.fixedHours
                          .map((h) => DropdownMenuItem(
                                value: h,
                                child: Text(
                                    '${h.toString().padLeft(2, '0')}:00'),
                              ))
                          .toList(),
                      onChanged: _dailyEnabled ? _changeHour : null,
                    ),
                  ],
                ),
              ),
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

            // ─── プライバシー ─────────────────────────────────────────────
            _SectionHeader('プライバシー'),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('データの扱い'),
              subtitle: Text('GPS 不使用・BLE のみ・データはデバイス内にのみ保存'),
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
