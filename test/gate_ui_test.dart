import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_encounter/models/encounter_record.dart';
import 'package:ble_encounter/ui/gate_reveal_screen.dart';
import 'package:ble_encounter/ui/theme/palette.dart';

List<EncounterRecord> people(int count) => List.generate(
    count,
    (i) => EncounterRecord(
          peerId: 'private-id-$i',
          name: '非公開の名前$i',
          colorIndex: 0,
          firstMet: DateTime(2026, 10, 1),
          lastMet: DateTime(2026, 10, 6, 8, 37),
          meetCount: i.isEven ? 1 : 5,
          rssi: -65,
          peerPixels: List.generate(256, (p) => p % 16),
        ));

void main() {
  testWidgets(
      '0/1/many result cards support both themes and enlarged text without private fields',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => Palette.night = false);
    for (final dark in [false, true]) {
      Palette.night = dark;
      for (final count in [0, 1, 8, 24]) {
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: GateRevealScreen(
                    encounters: people(count),
                    date: DateTime(2026, 10, 6),
                    resultOnly: true,
                    onReveal: () async =>
                        fail('Review must not change encounter state')))));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('private-id-'), findsNothing);
        expect(find.textContaining('非公開の名前'), findsNothing);
        expect(find.textContaining('08:37'), findsNothing);
        expect(find.text('スキップ'), findsNothing);
        if (count == 0)
          expect(find.text('今日はのんびりみたい。'), findsOneWidget);
        else
          expect(find.text('$count人'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('Gate skip saves exactly once; result review has no ceremony',
      (tester) async {
    int saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: GateRevealScreen(
            encounters: people(24),
            date: DateTime(2026, 10, 6),
            onReveal: () async {
              saves++;
            })));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('門がひらきます…'), findsOneWidget);
    await tester.tap(find.text('スキップ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(saves, 1);
    expect(find.text('24人'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Failed save stays retryable and never silently drops encounters',
      (tester) async {
    int tries = 0;
    await tester.pumpWidget(MaterialApp(
        home: GateRevealScreen(
            encounters: people(1),
            date: DateTime(2026, 10, 6),
            onReveal: () async {
              if (++tries == 1) throw Exception('offline');
            })));
    await tester.pump();
    await tester.tap(find.text('スキップ'));
    await tester.pump();
    expect(find.text('閉じる'), findsOneWidget);
    await tester.ensureVisible(find.text('もう一度保存する'));
    await tester.tap(find.text('もう一度保存する'));
    await tester.pump();
    expect(tries, 2);
    expect(find.text('と出会いました！'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
