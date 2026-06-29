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
import 'puzzle/puzzle_board_screen.dart';

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
    PuzzleBoardScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 日次通知タップで今日タブ(0)に切り替え
    NotificationService.onDailyNotificationTap = () {
      if (mounted) setState(() => _selectedIndex = 0);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNewBadgeIfAny();
    });
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i == 0 || i == 1) {
            ref.read(appProvider.notifier).clearNewEncounterFlag();
          }
          setState(() => _selectedIndex = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: '広場',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'ミニゲーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'バッジ',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'カケラ',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'プロフィール',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
