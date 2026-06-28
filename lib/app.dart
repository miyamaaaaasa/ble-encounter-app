import 'package:flutter/cupertino.dart';
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
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF378ADD),
        useMaterial3: true,
        brightness: Brightness.light,
        platform: TargetPlatform.iOS,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {TargetPlatform.iOS: CupertinoPageTransitionsBuilder()},
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF378ADD),
        useMaterial3: true,
        brightness: Brightness.dark,
        platform: TargetPlatform.iOS,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {TargetPlatform.iOS: CupertinoPageTransitionsBuilder()},
        ),
      ),
      home: const _RootScreen(),
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
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    if (state.ownProfile == null) {
      return const ProfileScreen(isFirstLaunch: true);
    }

    return const HomeScreen();
  }
}
