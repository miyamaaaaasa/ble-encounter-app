import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_encounter/ui/widgets/sorapi.dart';

void main() {
  testWidgets('guide walks but stops in hidden tabs and reduced motion',
      (t) async {
    Widget host(bool active, bool reduced) => MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(
              size: const Size(800, 600), disableAnimations: reduced),
          child: TickerMode(
              enabled: active,
              child: const Center(child: Sorapi(mood: SorapiMood.walk))),
        ));
    String asset() =>
        (t.widget<Image>(find.byType(Image)).image as AssetImage).assetName;
    await t.pumpWidget(host(true, false));
    final first = asset();
    await t.pump(const Duration(milliseconds: 180));
    expect(asset(), isNot(first));
    await t.pumpWidget(host(false, false));
    final paused = asset();
    await t.pump(const Duration(seconds: 1));
    expect(asset(), paused);
    await t.pumpWidget(host(true, true));
    await t.pump(const Duration(seconds: 1));
    expect(asset(), paused);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
