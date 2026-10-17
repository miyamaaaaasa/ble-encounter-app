import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_encounter/models/encounter_record.dart';
import 'package:ble_encounter/models/template_message.dart';
import 'package:ble_encounter/ui/widgets/encounter_highlights.dart';

EncounterRecord person(String name, {bool revealed = true, int phrase = 0}) =>
    EncounterRecord(
        peerId: name,
        name: name,
        colorIndex: 0,
        firstMet: DateTime(2026, 10, 18),
        lastMet: DateTime(2026, 10, 18),
        meetCount: 1,
        rssi: -60,
        isRevealed: revealed,
        template: TemplateMessage(phraseIndex: phrase));

void main() {
  testWidgets(
      'each person keeps their own message; pending identities stay hidden',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EncounterHighlights(people: [
      person('そら'),
      person('はな', phrase: 1),
      person('未公開の相手', revealed: false),
    ]))));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('未公開の相手'), findsNothing);
    await t.tap(find.byTooltip('次の人'));
    await t.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(
        t
            .widget<Text>(
                find.text(person('はな', phrase: 1).template.phraseText))
            .data,
        person('はな', phrase: 1).template.phraseText);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('large Japanese names and text fit at 320 logical pixels',
      (t) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.3)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: EncounterHighlights(
                            people: [person('あいうえおかきくけこさしすせそたちつてと')])))))));
    await t.pump();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
