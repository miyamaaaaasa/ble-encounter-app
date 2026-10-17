import 'package:ble_encounter/models/encounter_record.dart';
import 'package:ble_encounter/core/peer_id.dart';
import 'package:ble_encounter/models/template_message.dart';
import 'package:ble_encounter/providers/ble_providers.dart';
import 'package:ble_encounter/providers/puzzle_providers.dart';
import 'package:ble_encounter/ui/encounter_detail_sheet.dart';
import 'package:ble_encounter/ui/plaza_screen.dart';
import 'package:ble_encounter/ui/theme/palette.dart';
import 'package:ble_encounter/ui/widgets/peer_icon.dart';
import 'package:ble_encounter/ui/widgets/plaza_scene.dart';
import 'package:ble_encounter/ui/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends AppNotifier {
  final List<EncounterRecord> encounters;
  _App(this.encounters);
  @override
  AppState build() => AppState(isLoading: false, encounters: encounters);
}

class _Puzzle extends PuzzleNotifier {
  @override
  PuzzleState build() => const PuzzleState();
}

EncounterRecord _person(String name, {bool revealed = true, int phrase = 5}) =>
    EncounterRecord(
        peerId: name,
        name: name,
        colorIndex: 0,
        firstMet: DateTime(2026, 10, 1),
        lastMet: DateTime(2026, 10, 18),
        meetCount: 25,
        rssi: -65,
        isRevealed: revealed,
        peerBadgeLevel: 1,
        template: TemplateMessage(phraseIndex: phrase),
        peerPixels: List.filled(256, 1));

Future<void> _pump(WidgetTester tester, List<EncounterRecord> encounters,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(320, 1000);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appProvider.overrideWith(() => _App(encounters)),
        puzzleProvider.overrideWith(_Puzzle.new),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: MediaQuery(
        data: MediaQueryData(
            size: const Size(320, 1000), textScaler: TextScaler.linear(scale)),
        child: const PlazaScreen(),
      )))));
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 12));
}

void main() {
  _controlsTests();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
  });
  tearDown(() => Palette.night = false);

  testWidgets(
      'Revealed residents retain portraits, phrases and details at large text',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peer = _person('とてもながい名前のドット絵の住民です');
    for (final night in [false, true]) {
      Palette.night = night;
      await _pump(tester, [peer, _person('まだひみつ', revealed: false)], scale: 2);
      final scene = tester.widget<PlazaScene>(find.byType(PlazaScene));
      expect(scene.residents, [peer]);
      expect(scene.totalCount, 1);
      final tile = find.byType(SoftPanel);
      await tester.scrollUntilVisible(tile, 250);
      await tester.pump();
      expect(find.text('まだひみつ'), findsNothing);
      expect(find.descendant(of: tile, matching: find.text(peer.name)),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile, matching: find.text(peer.template.phraseText)),
          findsOneWidget);
      expect(
          tester
              .widget<PeerIcon>(
                  find.descendant(of: tile, matching: find.byType(PeerIcon)))
              .size,
          64);
      expect(
          (tester
                  .widget<AnimatedContainer>(find.descendant(
                      of: tile, matching: find.byType(AnimatedContainer)))
                  .decoration as BoxDecoration)
              .color,
          Palette.card);
      expect(find.descendant(of: tile, matching: find.text('ホログラム')),
          findsOneWidget);
      expect(
          find.descendant(of: tile, matching: find.text('常連')), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('2026/10/18')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          tester
              .widget<EncounterDetailSheet>(find.byType(EncounterDetailSheet))
              .encounter,
          same(peer));
      await _dispose(tester);
    }
  });

  testWidgets(
      'Unrevealed residents leave helpful guidance and collection routes',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, [_person('まだひみつ', revealed: false)]);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('これから出会うみんなの場所'), findsOneWidget);
    expect(find.textContaining('「今日」で門をあけてみよう'), findsOneWidget);
    expect(find.text('まだひみつ'), findsNothing);
    expect(find.text('バッジ 0個'), findsOneWidget);
    expect(find.text('カケラ 0枚'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });
}

void _controlsTests() {
  tearDown(() => Palette.night = false);

  testWidgets('Custom controls support focus, keys, taps and button semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var chunky = 0;
    var round = 0;
    var panel = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ChunkyButton(label: '保存する', onTap: () => chunky++),
          RoundIconButton(icon: Icons.undo, onTap: () => round++),
          SoftPanel(onTap: () => panel++, child: const Text('くわしく見る')),
          const ChunkyButton(label: '準備中'),
        ]),
      ),
    ));

    expect(
        tester.getSemantics(find.byType(ChunkyButton).first),
        matchesSemantics(
            label: '保存する',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true));
    expect(tester.getSemantics(find.byType(ChunkyButton).last),
        matchesSemantics(label: '準備中', isButton: true, hasEnabledState: true));
    expect(find.byTooltip('元に戻す'), findsOneWidget);
    expect(
        tester.getSemantics(find.bySemanticsLabel('元に戻す')),
        matchesSemantics(
            label: '元に戻す',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true));
    expect(tester.getSize(find.byType(RoundIconButton)), const Size(48, 48));
    for (final control in [
      find.byType(ChunkyButton).first,
      find.byType(RoundIconButton),
      find.byType(SoftPanel)
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
          find.descendant(
              of: control,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container && widget.foregroundDecoration != null)),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.tap(control);
      await tester.pump();
    }
    expect([chunky, round, panel], [3, 3, 3]);
    await tester.tap(find.byType(ChunkyButton).last);
    expect([chunky, round, panel], [3, 3, 3]);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(ChunkyButton).first));
    await gesture.moveBy(const Offset(0, 300));
    await gesture.up();
    expect([chunky, round, panel], [3, 3, 3]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Button labels grow without overflow in both themes',
      (tester) async {
    for (final night in [false, true]) {
      Palette.night = night;
      for (final expand in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
            child: Center(
                child: SizedBox(
                    width: 220,
                    child: ChunkyButton(
                        label: 'このアイコンにする',
                        icon: Icons.check,
                        expand: expand,
                        onTap: () {}))),
          )),
        ));
        expect(
            tester.getSize(find.byType(ChunkyButton)).height, greaterThan(52));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('Default button contrast clears 4.5 and explicit colors survive',
      (tester) async {
    for (final night in [false, true]) {
      Palette.night = night;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        ChunkyButton(label: '既定の色', onTap: () {}),
        ChunkyButton(
            label: '指定した色',
            color: Colors.white,
            labelColor: Palette.tealDeep,
            onTap: () {}),
      ]))));
      final label = tester.widget<Text>(find.text('既定の色')).style!.color!;
      expect(label, Palette.nightSky);
      expect(
          (Palette.coral.computeLuminance() + .05) /
              (label.computeLuminance() + .05),
          greaterThanOrEqualTo(4.5));
      expect(tester.widget<Text>(find.text('指定した色')).style!.color,
          Palette.tealDeep);
      final fill = tester.widget<Container>(find.descendant(
          of: find.byType(ChunkyButton).last,
          matching: find.byWidgetPredicate((widget) =>
              widget is Container && widget.decoration is BoxDecoration)));
      expect((fill.decoration as BoxDecoration).color, Colors.white);
    }
  });
}
