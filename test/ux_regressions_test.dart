import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/core/peer_id.dart';
import 'package:ble_encounter/models/own_profile.dart';
import 'package:ble_encounter/providers/ble_providers.dart';
import 'package:ble_encounter/providers/broadcast_provider.dart';
import 'package:ble_encounter/providers/puzzle_providers.dart';
import 'package:ble_encounter/ui/home_screen.dart';
import 'package:ble_encounter/ui/settings_screen.dart';
import 'package:ble_encounter/ui/onboarding_screen.dart';

class _App extends AppNotifier {
  int starts = 0;
  @override
  AppState build() => const AppState(
      isLoading: false, ownProfile: OwnProfile(name: 'Test', colorIndex: 0));
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> onResumed() async {}
}

class _Puzzle extends PuzzleNotifier {
  @override
  PuzzleState build() => const PuzzleState();
}

class _Broadcasts extends BroadcastNotifier {
  @override
  Future<void> refresh() async {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
  });

  testWidgets('home resumes automatic BLE but respects explicit stop',
      (t) async {
    final app = _App();
    await t.pumpWidget(ProviderScope(overrides: [
      appProvider.overrideWith(() => app),
      puzzleProvider.overrideWith(_Puzzle.new),
      broadcastProvider.overrideWith((ref) => _Broadcasts()),
    ], child: const MaterialApp(home: HomeScreen())));
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(app.starts, 1);
    await app.stop();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(app.starts, 1, reason: 'manual stop must survive resume');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  });

  testWidgets('denied BLE permission is explained with OS settings recovery',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var settingsOpened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async {
      if (call.method == 'requestPermissions') {
        return {for (final id in call.arguments as List) id: 4};
      }
      if (call.method == 'openAppSettings') {
        settingsOpened = true;
        return true;
      }
      return null;
    });
    final app = _App();
    await t.pumpWidget(ProviderScope(
        overrides: [appProvider.overrideWith(() => app)],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen()))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('起動'));
    await t.tap(find.text('起動'));
    await t.pumpAndSettle();
    expect(app.starts, 0);
    expect(find.textContaining('許可が必要'), findsOneWidget);
    final recovery = find.text('アプリの設定を開く');
    await t.ensureVisible(recovery);
    await t.tap(recovery);
    await t.pumpAndSettle();
    expect(settingsOpened, isTrue);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('onboarding awaits completion failure and permits retry',
      (t) async {
    var attempts = 0;
    await t.pumpWidget(MaterialApp(home: OnboardingScreen(onDone: () async {
      attempts++;
      if (attempts == 1) throw StateError('initialization failed');
    })));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('スキップ'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('tutorial-next')));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull);
    expect(find.textContaining('もう一度お試しください'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tutorial-next')));
    await t.pump(const Duration(milliseconds: 50));
    expect(attempts, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('privacy disclosure includes server storage and encrypted backup',
      (t) async {
    await t.pumpWidget(ProviderScope(
        overrides: [appProvider.overrideWith(_App.new)],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen()))));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('データの扱い'), 400);
    final policy = find.widgetWithText(ListTile, 'データの扱い');
    expect(find.descendant(of: policy, matching: find.textContaining('サーバー')),
        findsOneWidget);
    expect(find.descendant(of: policy, matching: find.textContaining('暗号化')),
        findsOneWidget);
    expect(find.descendant(of: policy, matching: find.textContaining('GPS')),
        findsOneWidget);
    expect(find.textContaining('デバイス内にのみ保存'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
