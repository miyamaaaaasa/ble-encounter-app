import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/ui/onboarding_screen.dart';
import 'package:ble_encounter/ui/theme/palette.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'dot_avatar_v1': 'retained avatar',
        'profile': 'retained profile',
      }));
  tearDown(() => Palette.night = false);

  testWidgets('all five pages fit small/large text in both themes', (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    for (final night in [false, true]) {
      Palette.night = night;
      for (final scale in [1.0, 2.0]) {
        t.view.physicalSize = const Size(320, 568);
        await t.pumpWidget(MaterialApp(
            key: UniqueKey(),
            home: MediaQuery(
                data: MediaQueryData(
                    size: const Size(320, 568),
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: OnboardingScreen(onDone: () {}))));
        await t.pump(const Duration(milliseconds: 50));
        for (var p = 0; p < 5; p++) {
          expect(find.byKey(ValueKey('tutorial-page-$p')).hitTestable(),
              findsOneWidget);
          expect(t.takeException(), isNull,
              reason: 'theme=$night scale=$scale page=$p');
          expect(find.byKey(const ValueKey('tutorial-next')).hitTestable(),
              findsOneWidget);
          if (p < 4) {
            await t.tap(find.byKey(const ValueKey('tutorial-next')));
            await t.pump();
            await t.pump(const Duration(milliseconds: 500));
            await t.pump();
          }
        }
        expect(await OnboardingScreen.isDone(), isFalse);
      }
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'skip explains Bluetooth; completion persists without deleting data',
      (t) async {
    var done = 0;
    await t
        .pumpWidget(MaterialApp(home: OnboardingScreen(onDone: () => done++)));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('スキップ'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    await t.pump();
    expect(done, 0);
    expect(await OnboardingScreen.isDone(), isFalse);
    expect(find.text('Bluetoothの使用'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tutorial-next')));
    await t.pump(const Duration(milliseconds: 50));
    expect(done, 1);
    expect(await OnboardingScreen.isDone(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dot_avatar_v1'), 'retained avatar');
    expect(prefs.getString('profile'), 'retained profile');
    // Reopening never resets completion or the existing profile.
    await t.pumpWidget(
        MaterialApp(key: UniqueKey(), home: OnboardingScreen(onDone: () {})));
    await t.pump(const Duration(milliseconds: 50));
    expect(await OnboardingScreen.isDone(), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('swipe forward and back works independently of buttons',
      (t) async {
    await t.pumpWidget(MaterialApp(home: OnboardingScreen(onDone: () {})));
    await t.pump(const Duration(milliseconds: 50));
    await t.drag(find.byType(PageView), const Offset(-700, 0));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('すれ違うと、\n気配が届く').hitTestable(), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(700, 0));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('ようこそ\nきょうの広場へ').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
