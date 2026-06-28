import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../services/notification_service.dart';
import 'today_screen.dart';
import 'plaza_screen.dart';
import 'minigame_screen.dart';
import 'badge_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    TodayScreen(),
    PlazaScreen(),
    MinigameScreen(),
    BadgeScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.onDailyNotificationTap = () {
      if (mounted) setState(() => _selectedIndex = 0);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNewBadgeIfAny();
    });
    // Battery optimization dialog intentionally removed — iOS does not have
    // this concept and the dialog was appearing incorrectly on iOS devices.
  }

  @override
  void dispose() {
    NotificationService.onDailyNotificationTap = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      final appState = ref.read(appProvider);
      if (!appState.isRunning && appState.ownProfile != null) {
        ref.read(appProvider.notifier).start();
      }
    }
  }

  void _showNewBadgeIfAny() {
    ref.listenManual(appProvider.select((s) => s.newlyEarnedBadges), (_, next) {
      if (next.isEmpty || !mounted) return;
      for (final badge in next) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${badge.emoji} バッジ獲得: ${badge.title}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
      ref.read(appProvider.notifier).clearNewBadges();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _selectedIndex,
        onTap: (i) {
          if (i == 0 || i == 1) {
            ref.read(appProvider.notifier).clearNewEncounterFlag();
          }
          setState(() => _selectedIndex = i);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.today),
            activeIcon: Icon(CupertinoIcons.today_fill),
            label: '今日',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            activeIcon: Icon(CupertinoIcons.person_2_fill),
            label: '広場',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.game_controller),
            activeIcon: Icon(CupertinoIcons.game_controller_solid),
            label: 'ゲーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.star),
            activeIcon: Icon(CupertinoIcons.star_fill),
            label: 'バッジ',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person),
            activeIcon: Icon(CupertinoIcons.person_fill),
            label: 'プロフィール',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            activeIcon: Icon(CupertinoIcons.settings_solid),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
