import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/ble_providers.dart';
import 'providers/theme_provider.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/profile_screen.dart';
import 'ui/theme/palette.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    // Palette.night を確定させてから全ウィジェットを構築する
    final platformDark = SchedulerBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    Palette.night = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformDark,
    };

    return MaterialApp(
      key: ValueKey(Palette.night), // モード切替で全体を再構築
      title: 'はじめましてこんにちは',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(false),
      darkTheme: _buildTheme(true),
      themeMode: mode,
      home: const _RootScreen(),
    );
  }

  // ライト = 昼の広場（クリーム×パステル）
  // ダーク = 夜の広場（提灯の灯る深い藍。単純な黒にしない）
  static ThemeData _buildTheme(bool dark) {
    final cream = dark ? const Color(0xFF1B2035) : const Color(0xFFFBF3E4);
    final ink = dark ? const Color(0xFFF2EADA) : const Color(0xFF4A3C31);
    final card = dark ? const Color(0xFF272E4E) : const Color(0xFFFFFDF8);
    final line = dark ? const Color(0xFF3A415F) : const Color(0xFFE5D5BE);
    const coral = Color(0xFFFF8A70);
    final scheme = ColorScheme.fromSeed(
      seedColor: coral,
      brightness: dark ? Brightness.dark : Brightness.light,
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
        backgroundColor: dark ? const Color(0xFF3A415F) : ink,
        contentTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: coral, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: line),
    );
  }
}

class _RootScreen extends ConsumerStatefulWidget {
  const _RootScreen();

  @override
  ConsumerState<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<_RootScreen> {
  bool? _onboardingDone; // null = 読み込み中

  @override
  void initState() {
    super.initState();
    OnboardingScreen.isDone().then((done) {
      if (mounted) setState(() => _onboardingDone = done);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);

    if (state.isLoading || _onboardingDone == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 初回はチュートリアルから
    if (!_onboardingDone!) {
      return OnboardingScreen(
        onDone: () => setState(() => _onboardingDone = true),
      );
    }

    if (state.ownProfile == null) {
      return const ProfileScreen(isFirstLaunch: true);
    }

    return const HomeScreen();
  }
}
