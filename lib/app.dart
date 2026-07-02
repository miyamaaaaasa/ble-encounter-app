import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/ble_providers.dart';
import 'ui/home_screen.dart';
import 'ui/profile_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'はじめましてこんにちは',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      themeMode: ThemeMode.light, // 世界観統一のため常にパステルの昼の世界
      home: const _RootScreen(),
    );
  }

  // 「人と出会うことが楽しいコミュニティゲーム」テーマ。
  // Material部品は極力使わず、残った部品もクリーム×パステルに寄せる。
  static ThemeData _buildTheme() {
    const cream = Color(0xFFFBF3E4);
    const ink = Color(0xFF4A3C31);
    const coral = Color(0xFFFF8A70);
    final scheme = ColorScheme.fromSeed(
      seedColor: coral,
      brightness: Brightness.light,
      surface: cream,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: cream,
      textTheme: base.textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFDF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5D5BE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5D5BE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: coral, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE5D5BE)),
    );
  }
}

class _RootScreen extends ConsumerWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);

    if (state.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.ownProfile == null) {
      return const ProfileScreen(isFirstLaunch: true);
    }

    return const HomeScreen();
  }
}
