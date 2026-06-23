import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/ble_providers.dart';
import '../services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _notifHour = 21;
  int _notifMinute = 0;
  bool _dailyEnabled = true;
  bool _updateEnabled = true;
  bool _eventEnabled = true;
  String _version = '';

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
          appName: 'すれ違い',
          packageName: '',
          version: '1.3.0',
          buildNumber: '5');
    }
    if (!mounted) return;
    setState(() {
      _notifHour = settings.hour;
      _notifMinute = settings.minute;
      _dailyEnabled = settings.dailyEnabled;
      _updateEnabled = settings.updateEnabled;
      _eventEnabled = settings.eventEnabled;
      _version = 'v${info.version}';
    });
  }

  Future<void> _pickNotifTime() async {
    TimeOfDay? picked;
    try {
      picked = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay(hour: _notifHour, minute: _notifMinute),
        helpText: '通知する時刻を選んでください',
      );
    } catch (_) {
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _notifHour = picked!.hour;
      _notifMinute = picked.minute;
    });
    if (_dailyEnabled) {
      await NotificationService.scheduleDailyNotification(
        hour: picked.hour,
        minute: picked.minute,
      );
      if (mounted) {
        final hh = picked.hour.toString().padLeft(2, '0');
        final mm = picked.minute.toString().padLeft(2, '0');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$hh:$mm に通知します')),
        );
      }
    }
  }

  Future<void> _toggleDaily(bool value) async {
    setState(() => _dailyEnabled = value);
    if (value) {
      await NotificationService.scheduleDailyNotification(
          hour: _notifHour, minute: _notifMinute);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final notifTime =
        '${_notifHour.toString().padLeft(2, '0')}:${_notifMinute.toString().padLeft(2, '0')}';

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('設定')),
        SliverList(
          delegate: SliverChildListDelegate([

            // ─── BLE ─────────────────────────────────────────────
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
                  : const Text('アプリ再起動で自動復帰します'),
              trailing: state.isRunning
                  ? OutlinedButton(
                      onPressed: () =>
                          ref.read(appProvider.notifier).stop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error,
                        side: BorderSide(
                            color:
                                Theme.of(context).colorScheme.error),
                      ),
                      child: const Text('停止'),
                    )
                  : FilledButton.tonal(
                      onPressed: () async {
                        final ok = await ref
                            .read(appProvider.notifier)
                            .requestPermissions();
                        if (ok && mounted) {
                          await ref
                              .read(appProvider.notifier)
                              .start();
                        }
                      },
                      child: const Text('起動'),
                    ),
            ),
            const Divider(indent: 16, endIndent: 16),

            // ─── 通知設定 ─────────────────────────────────────────
            _SectionHeader('通知'),

            // 本日の結果（まとめ通知）
            SwitchListTile(
              secondary: const Icon(Icons.summarize_outlined),
              title: const Text('本日の通信結果'),
              subtitle:
                  const Text('毎日指定した時間に1日のまとめをお知らせします'),
              value: _dailyEnabled,
              onChanged: _toggleDaily,
            ),

            // 時刻設定
            AnimatedOpacity(
              opacity: _dailyEnabled ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('通知時刻'),
                subtitle: Text(notifTime),
                trailing: const Icon(Icons.chevron_right),
                enabled: _dailyEnabled,
                onTap: _dailyEnabled ? _pickNotifTime : null,
              ),
            ),

            // アプリ更新
            SwitchListTile(
              secondary: const Icon(Icons.system_update_outlined),
              title: const Text('アプリ更新'),
              subtitle: const Text('新バージョンのお知らせ'),
              value: _updateEnabled,
              onChanged: _toggleUpdate,
            ),

            // イベント
            SwitchListTile(
              secondary: const Icon(Icons.celebration_outlined),
              title: const Text('イベント'),
              subtitle: const Text('特別イベントのお知らせ'),
              value: _eventEnabled,
              onChanged: _toggleEvent,
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── プライバシー ─────────────────────────────────────
            _SectionHeader('プライバシー'),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('データの扱い'),
              subtitle: Text(
                  'GPS 不使用・BLE のみ・すれ違い時刻は日付単位で記録・データはデバイス内にのみ保存'),
            ),
            const ListTile(
              leading: Icon(Icons.notifications_off_outlined),
              title: Text('リアルタイム通知は無効'),
              subtitle: Text(
                  'すれ違った瞬間の即時通知はプライバシー保護のため送信しません'),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ─── アプリ情報 ───────────────────────────────────────
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
