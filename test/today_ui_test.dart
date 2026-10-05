import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/core/peer_id.dart';

import 'package:ble_encounter/models/encounter_record.dart';
import 'package:ble_encounter/providers/ble_providers.dart';
import 'package:ble_encounter/providers/broadcast_provider.dart';
import 'package:ble_encounter/services/broadcast_service.dart';
import 'package:ble_encounter/ui/theme/palette.dart';
import 'package:ble_encounter/ui/today_screen.dart';
import 'package:ble_encounter/ui/widgets/ui_kit.dart';
import 'package:ble_encounter/ui/widgets/user_icon.dart';

class _App extends AppNotifier {
  final AppState initial;
  int reveals = 0;
  _App(this.initial);
  @override
  AppState build() => initial;
  @override
  Future<void> revealToday() async => reveals++;
}

class _Broadcasts extends BroadcastNotifier {
  bool dismissed = false;
  @override
  Future<void> refresh() async {
    state = BroadcastState(
        banner: dismissed
            ? null
            : Broadcast(
                id: 1,
                title: '運営からのお知らせ',
                body: '文化祭へようこそ！',
                createdAt: DateTime.now(),
              ));
  }

  @override
  Future<void> dismissBanner() async {
    dismissed = true;
    await refresh();
  }
}

const _items = [
  DockItem(asset: 'assets/icons/nav_today.png', label: '今日'),
  DockItem(asset: 'assets/icons/nav_plaza.png', label: '広場'),
  DockItem(asset: 'assets/icons/nav_game.png', label: 'ゲーム'),
  DockItem(asset: 'assets/icons/nav_badge.png', label: 'バッジ'),
  DockItem(asset: 'assets/icons/nav_kakera.png', label: 'カケラ'),
  DockItem(custom: UserIcon(), label: 'じぶん'),
  DockItem(asset: 'assets/icons/nav_settings.png', label: '設定'),
];

EncounterRecord _person(String name, DateTime date, {bool revealed = true}) =>
    EncounterRecord(
        peerId: name,
        name: name,
        colorIndex: 0,
        firstMet: date,
        lastMet: date,
        meetCount: 5,
        rssi: -65,
        isRevealed: revealed,
        peerPixels: List.generate(256, (i) => (i ~/ 16 + i % 16) % 15));

Future<void> _pump(WidgetTester tester, _App app, _Broadcasts broadcasts,
    {double width = 390,
    double textScale = 1,
    bool dark = false,
    ValueChanged<int>? onSelect,
    GlobalKey? captureKey}) async {
  Palette.night = dark;
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appProvider.overrideWith(() => app),
        broadcastProvider.overrideWith((ref) => broadcasts),
      ],
      child: MaterialApp(
          theme: ThemeData(fontFamily: const bool.fromEnvironment('WRITE_TODAY_SCREENSHOTS') ? 'TodayQA' : null),
          home: MediaQuery(
        data: MediaQueryData(
            size: Size(width, 844), textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(
            key: captureKey,
            child: Scaffold(
              backgroundColor: Palette.cream,
              body: const TodayScreen(),
              bottomNavigationBar: GameDock(
                  items: _items, selected: 0, onSelect: onSelect ?? (_) {}),
            )),
      ))));
  await tester.pump(const Duration(seconds: 1));
  if (const bool.fromEnvironment('WRITE_TODAY_SCREENSHOTS')) {
    await tester.runAsync(() async {
      final context = tester.element(find.byType(TodayScreen));
      for (final path in [
        'assets/today/plaza_light.png', 'assets/today/plaza_dark.png',
        ..._items.where((item) => item.asset != null).map((item) => item.asset!),
        'assets/gate/gate_morning.png', 'assets/gate/gate_noon.png', 'assets/gate/gate_night.png',
      ]) {
        await precacheImage(AssetImage(path), context);
      }
    });
    await tester.pump();
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('WRITE_TODAY_SCREENSHOTS') && Platform.isWindows) {
      final font = FontLoader('TodayQA')
        ..addFont(File(r'C:\Windows\Fonts\meiryo.ttc').readAsBytes().then(ByteData.sublistView));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
  });
  tearDown(() => Palette.night = false);

  testWidgets(
      'Both themes, narrow screens and enlarged text retain seven tabs and metadata',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, 8);
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 2.0]) {
          final app =
              _App(AppState(isLoading: false, isRunning: true, encounters: [
            _person('そらの長い名前もそのまま表示', morning),
            _person('こむぎ', morning),
            _person('みどり', morning),
            _person('はな', morning.subtract(const Duration(days: 1)))
          ]));
          final key = GlobalKey();
          int? selected;
          await _pump(tester, app, _Broadcasts(),
              width: width,
              textScale: scale,
              dark: dark,
              onSelect: (i) => selected = i,
              captureKey: key);
          expect(tester.takeException(), isNull);
          expect(find.text('きょうは 3人 と出会えたよ'), findsOneWidget);
          expect(find.text('すれ違い中！ · よく見る'), findsOneWidget);
          expect(find.textContaining('すれ違ったよ'), findsOneWidget);
          for (final item in _items) {
            expect(find.text(item.label), findsOneWidget);
          }
          await tester.ensureVisible(find.byType(PageView).first);
          await tester.pump();
          await tester.drag(find.byType(PageView).first, Offset(-width * 0.36, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('こむぎ'), findsOneWidget);
          await tester.tap(find.text('設定'));
          expect(selected, 6);
          if (const bool.fromEnvironment('WRITE_TODAY_SCREENSHOTS') &&
              width == 390 &&
              scale == 1) {
            await tester.runAsync(() async {
              final boundary = key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file =
                  File('qa_out/today-v2/${dark ? 'dark' : 'light'}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.scrollUntilVisible(find.text('はな'), 300,
              scrollable: find.byType(Scrollable).first);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(find.text('はな'), findsOneWidget);
          await _dispose(tester);
        }
      }
    }
  });

  testWidgets(
      'Pending people stay hidden, broadcast dismiss and gate reveal retain callbacks',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, 8);
    final app = _App(AppState(isLoading: false, encounters: [
      _person('未開封の相手', morning, revealed: false),
    ]));
    final broadcasts = _Broadcasts();
    await _pump(tester, app, broadcasts);
    expect(find.text('未開封の相手'), findsNothing);
    expect(find.text('おやすみ中'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(broadcasts.dismissed, isTrue);
    expect(find.text('文化祭へようこそ！'), findsNothing);
    // ponytail: live clock; inject a clock if pre-09:00 QA must exercise reveal.
    if (now.hour >= 9) {
      await tester.ensureVisible(find.text('1人 あける！'));
      await tester.tap(find.text('1人 あける！'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('未開封の相手'), findsOneWidget);
      await tester.tap(find.text('スキップ'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(app.reveals, 1);
    }
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });
}
