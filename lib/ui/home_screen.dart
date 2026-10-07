import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../services/notification_service.dart';
import 'theme/palette.dart';
import 'widgets/ui_kit.dart';
import 'widgets/user_icon.dart';
import 'today_screen.dart';
import 'plaza_screen.dart';
import '../providers/broadcast_provider.dart';
import 'community_tabs.dart';

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
    GameCollectionScreen(),
    CatalogScreen(),
    SelfOverviewScreen(),
  ];
  static const _dockItems = [
    DockItem(asset: 'assets/icons/nav_today.png', label: '今日'),
    DockItem(asset: 'assets/icons/nav_plaza.png', label: '広場'),
    DockItem(asset: 'assets/icons/nav_game.png', label: 'ゲーム'),
    DockItem(custom: Icon(Icons.menu_book_outlined, size: 26), label: '図鑑'),
    DockItem(custom: UserIcon(size: 26, radius: 4), label: 'じぶん'),
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
      // iOSのロック中にネイティブ側が拾ったすれ違いを回収して照合する
      ref.read(appProvider.notifier).onResumed();
      // 復帰時に運営のお知らせを即取得する。定期ポーリング(2分)だけだと
      // 「配信 → 来場者がアプリを開く」の流れで最大2分待たせてしまう。
      ref.read(broadcastProvider.notifier).refresh();
    }
  }

  void _showNewBadgeIfAny() {
    ref.listenManual(appProvider.select((s) => s.newlyEarnedBadges), (_, next) {
      if (next.isEmpty || !mounted) return;
      for (final badge in next) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('バッジ獲得: ${badge.title}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
      ref.read(appProvider.notifier).clearNewBadges();
    });
  }

  void _selectTab(int i) {
    if (i == 0 || i == 1) {
      ref.read(appProvider.notifier).clearNewEncounterFlag();
    }
    setState(() => _selectedIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.cream,
      body: IndexedStack(
        index: _selectedIndex,
        children: List.generate(
            _screens.length,
            (i) =>
                TickerMode(enabled: i == _selectedIndex, child: _screens[i])),
      ),
      bottomNavigationBar: defaultTargetPlatform == TargetPlatform.iOS
          ? CupertinoTabBar(
              currentIndex: _selectedIndex,
              onTap: _selectTab,
              backgroundColor: Palette.card,
              activeColor: Palette.sky,
              inactiveColor: Palette.inkSoft,
              items: _dockItems
                  .map((item) => BottomNavigationBarItem(
                        icon: item.custom ??
                            Image.asset(item.asset!, width: 26, height: 26),
                        label: item.label,
                      ))
                  .toList())
          : GameDock(
              items: _dockItems,
              selected: _selectedIndex,
              onSelect: _selectTab,
            ),
    );
  }
}
