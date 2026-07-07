// 回帰テスト: モデルのシリアライズ往復（永続化不具合の再発防止）
// 「保存したデータが再起動後に消える/化ける」系バグをここで固定化する。
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_encounter/models/piece_data.dart';
import 'package:ble_encounter/models/dot_avatar.dart';
import 'package:ble_encounter/models/encounter_record.dart';
import 'package:ble_encounter/models/template_message.dart';

void main() {
  group('PieceData', () {
    test('toJson→fromJson で256画素が完全一致', () {
      final p = PieceData();
      for (int i = 0; i < 256; i++) {
        p.pixels[i] = i % 16;
      }
      final restored = PieceData.fromJson(p.toJson());
      expect(restored.pixels, p.pixels);
    });

    test('不正入力（null/型違い/長さ違い）は透明ピースにフォールバック', () {
      expect(PieceData.fromJson(null).isEmpty, isTrue);
      expect(PieceData.fromJson('garbage').isEmpty, isTrue);
      expect(PieceData.fromJson([1, 2, 3]).isEmpty, isTrue); // 長さ不足
    });

    test('setPixel は 0-15 にクランプされる', () {
      final p = PieceData();
      p.setPixel(0, 0, 99);
      expect(p.getPixel(0, 0), 15);
      p.setPixel(1, 0, -5);
      expect(p.getPixel(1, 0), 0);
    });
  });

  group('DotAvatar', () {
    test('toMap→fromMap 往復（16x16）', () {
      final a = DotAvatar(size: 16);
      a.setPixel(3, 4, 7);
      a.setPixel(15, 15, 14);
      final r = DotAvatar.fromMap(a.toMap());
      expect(r.size, 16);
      expect(r.getPixel(3, 4), 7);
      expect(r.getPixel(15, 15), 14);
    });

    test('toMap→fromMap 往復（32x32）', () {
      final a = DotAvatar(size: 32);
      a.setPixel(31, 0, 4);
      final r = DotAvatar.fromMap(a.toMap());
      expect(r.size, 32);
      expect(r.getPixel(31, 0), 4);
    });

    test('fill は同色の連結領域だけ塗る', () {
      final a = DotAvatar(size: 16); // 全面透明(15)
      // 縦の壁を作って左右を分断
      for (int y = 0; y < 16; y++) {
        a.setPixel(8, y, 14);
      }
      a.fill(0, 0, 6); // 左側を黄で塗る
      expect(a.getPixel(0, 0), 6);
      expect(a.getPixel(7, 15), 6); // 左側は塗られる
      expect(a.getPixel(8, 0), 14); // 壁はそのまま
      expect(a.getPixel(9, 0), 15); // 右側は塗られない
    });

    test('fill: 同色指定は無限ループしない', () {
      final a = DotAvatar(size: 16);
      a.fill(0, 0, 15); // 透明を透明で塗る
      expect(a.isEmpty, isTrue);
    });
  });

  group('EncounterRecord', () {
    test('toMap→fromMap で全フィールド一致（avatarUrlあり）', () {
      final e = EncounterRecord(
        peerId: 'abc123',
        name: 'Tarou',
        colorIndex: 3,
        prefecture: 12,
        firstMet: DateTime(2026, 7, 1, 10, 30),
        lastMet: DateTime(2026, 7, 4, 18, 5),
        meetCount: 7,
        rssi: -60,
        template: const TemplateMessage(
            statusIndex: 1, hobbyCategory: 2, hobbyDetail: 0, phraseIndex: 3),
        isRevealed: true,
        peerBadgeLevel: 4,
        avatarUrl: 'https://example.com/a.jpg',
      );
      final r = EncounterRecord.fromMap(e.toMap());
      expect(r.peerId, e.peerId);
      expect(r.name, e.name);
      expect(r.colorIndex, e.colorIndex);
      expect(r.prefecture, e.prefecture);
      expect(r.firstMet, e.firstMet);
      expect(r.lastMet, e.lastMet);
      expect(r.meetCount, e.meetCount);
      expect(r.template.phraseIndex, 3);
      expect(r.isRevealed, isTrue);
      expect(r.peerBadgeLevel, 4);
      expect(r.avatarUrl, e.avatarUrl);
    });

    test('avatarUrl 未設定(null)でも往復で壊れない', () {
      final e = EncounterRecord(
        peerId: 'x',
        name: 'n',
        colorIndex: 0,
        firstMet: DateTime(2026, 1, 1),
        lastMet: DateTime(2026, 1, 1),
        meetCount: 1,
        rssi: -70,
      );
      final r = EncounterRecord.fromMap(e.toMap());
      expect(r.avatarUrl, isNull);
      expect(r.peerBadgeLevel, 0);
    });

    test('encodeList→decodeList 往復', () {
      final list = [
        EncounterRecord(
          peerId: 'a',
          name: 'A',
          colorIndex: 1,
          firstMet: DateTime(2026, 2, 2),
          lastMet: DateTime(2026, 2, 3),
          meetCount: 2,
          rssi: -50,
        ),
      ];
      final r = EncounterRecord.decodeList(EncounterRecord.encodeList(list));
      expect(r.length, 1);
      expect(r.first.peerId, 'a');
      expect(r.first.meetCount, 2);
    });
  });

  group('ドット絵同期（Sprint A）', () {
    test('DotAvatar.toPiecePixels: 16x16はそのまま256画素', () {
      final a = DotAvatar(size: 16);
      a.setPixel(2, 3, 9);
      final px = a.toPiecePixels();
      expect(px.length, 256);
      expect(px[3 * 16 + 2], 9);
    });

    test('DotAvatar.toPiecePixels: 32x32は16x16へ間引き縮小', () {
      final a = DotAvatar(size: 32);
      // (0,0)ブロックを赤(4)に
      a.setPixel(0, 0, 4);
      final px = a.toPiecePixels();
      expect(px.length, 256);
      expect(px[0], 4); // 左上は保持される
    });

    test('EncounterRecord.peerPixels がシリアライズ往復で保持される', () {
      final pixels = List<int>.generate(256, (i) => i % 16);
      final e = EncounterRecord(
        peerId: 'p',
        name: 'N',
        colorIndex: 0,
        firstMet: DateTime(2026, 7, 4),
        lastMet: DateTime(2026, 7, 4),
        meetCount: 1,
        rssi: -60,
        peerPixels: pixels,
      );
      final r = EncounterRecord.fromMap(e.toMap());
      expect(r.peerPixels, pixels);
      // reveal() でも失われない（永続化漏れ防止）
      expect(r.reveal().peerPixels, pixels);
    });
  });

}
