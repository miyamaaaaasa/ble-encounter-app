// 回帰テスト: 広場レベルの閾値
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_encounter/ui/widgets/plaza_scene.dart';

void main() {
  test('レベル閾値マッピング', () {
    const cases = {
      0: 1, 4: 1,
      5: 2, 14: 2,
      15: 3, 49: 3,
      50: 4, 99: 4,
      100: 5, 249: 5,
      250: 6, 9999: 6,
    };
    cases.forEach((total, lv) {
      expect(PlazaLevel.of(total).level, lv, reason: 'total=$total');
    });
  });

  test('レベル名', () {
    expect(PlazaLevel.of(0).name, 'はじまりの広場');
    expect(PlazaLevel.of(250).name, 'お祭り広場');
  });

  test('next: 最高レベルでは null', () {
    expect(PlazaLevel.next(250), isNull);
    expect(PlazaLevel.next(249)!.level, 6);
    expect(PlazaLevel.next(0)!.threshold, 5);
  });
}
