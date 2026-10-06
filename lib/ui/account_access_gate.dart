import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/ble_providers.dart';
import '../providers/puzzle_providers.dart';
import '../providers/broadcast_provider.dart';
import '../services/api_service.dart';
import '../services/account_snapshot.dart';
import '../services/token_service.dart';
import '../services/notification_service.dart';
import 'widgets/user_icon.dart';
import 'onboarding_screen.dart';

/// Account state boundary; ordinary home UI and encounter rules stay unchanged.
class AccountAccessGate extends ConsumerStatefulWidget {
  final Widget child;
  const AccountAccessGate({super.key, required this.child});
  @override
  ConsumerState<AccountAccessGate> createState() => _AccountAccessGateState();
}

class _AccountAccessGateState extends ConsumerState<AccountAccessGate>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _checked = false, _resetting = false, _reconnecting = false;
  bool _entered = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.accountBlocked.addListener(_blocked);
    AccountSnapshot.onChanged = ApiService.checkAccount;
    _check();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  Future<void> _check() async {
    await ApiService.checkAccount();
    if (!mounted) return;
    if (ApiService.accountBlocked.value) await _blocked();
    if (mounted) setState(() => _checked = true);
  }

  Future<void> _blocked() async {
    if (!ApiService.accountBlocked.value || _resetting) return;
    setState(() => _resetting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(ApiService.blockedKey) != true ||
          prefs.getBool(ApiService.resetPendingKey) == true) {
        if (_entered) {
          await ref.read(appProvider.notifier).stop();
          ref.read(appProvider.notifier).dispose();
        }
        await ApiService.releaseBlockedAccount();
        await TokenService.clear();
        try {
          await NotificationService.cancelAccountNotifications();
        } catch (_) {
          // Notification permission/plugin failures must not retain account data.
        }
        await AccountSnapshot.clear();
        await prefs.remove(ApiService.resetPendingKey);
        OwnAvatarNotifier.instance.value = null;
        ref.invalidate(appProvider);
        ref.invalidate(puzzleProvider);
        ref.invalidate(broadcastProvider);
      }
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      _error = '初期状態への切り替えを完了できませんでした。再起動してください。';
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _reconnecting = true;
      _error = null;
    });
    try {
      if (!await ApiService.reconnectAccount()) {
        _error = 'まだ再接続できません。管理者による復元をご確認ください。';
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_done_v1', true);
        OwnAvatarNotifier.instance.value = null;
        // Force the existing avatar loader to read the restored art.
        OwnAvatarNotifier.reload();
        ref.invalidate(appProvider);
        ref.invalidate(puzzleProvider);
        ref.invalidate(broadcastProvider);
        await TokenService.init();
      }
    } catch (_) {
      _error = '通信状況を確認して、もう一度お試しください。';
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ApiService.accountBlocked.removeListener(_blocked);
    AccountSnapshot.onChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _resetting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!ApiService.accountBlocked.value) {
      _entered = true;
      return widget.child;
    }
    return Scaffold(
        body: SafeArea(
            child: Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            const Text('このアカウントは利用できません。復元後に再接続してください。'),
            TextButton(
                onPressed: _reconnecting ? null : _reconnect,
                child: Text(_reconnecting ? '再接続中…' : '復元したアカウントに再接続')),
            if (_error != null) Text(_error!),
          ])),
      Expanded(child: OnboardingScreen(onDone: () {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('アカウントの復元と再接続が必要です')));
      })),
    ])));
  }
}
