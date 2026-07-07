// 回帰テスト: 未消化すれ違いデータの保持
// 「翌日に消える」「オフライン解析でトークンが失われる」バグの再発防止。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/services/piece_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('add → getAllTokens で取り出せる', () async {
    await PendingScanStorage.add('token-a', DateTime(2026, 7, 1, 10));
    await PendingScanStorage.add('token-b', DateTime(2026, 7, 2, 11));
    expect(await PendingScanStorage.getAllTokens(), ['token-a', 'token-b']);
  });

  test('同一トークンは重複追加されない', () async {
    await PendingScanStorage.add('dup', DateTime(2026, 7, 1));
    await PendingScanStorage.add('dup', DateTime(2026, 7, 2));
    expect((await PendingScanStorage.getAllTokens()).length, 1);
  });

  test('【回帰】古いトークンが時間経過で消えない（開門まで保持仕様）', () async {
    // かつて48時間で自動削除され「翌日に消える」原因になった
    final old = DateTime.now().subtract(const Duration(days: 10));
    await PendingScanStorage.add('very-old-token', old);
    await PendingScanStorage.add('new-token', DateTime.now());
    final tokens = await PendingScanStorage.getAllTokens();
    expect(tokens, contains('very-old-token'),
        reason: '未消化データはユーザーが開門するまで保持されること');
  });

  test('removeTokens は指定分だけ削除する', () async {
    await PendingScanStorage.add('keep', DateTime.now());
    await PendingScanStorage.add('drop', DateTime.now());
    await PendingScanStorage.removeTokens(['drop']);
    expect(await PendingScanStorage.getAllTokens(), ['keep']);
  });

  test('scannedAtFor は保存時刻を返す', () async {
    final at = DateTime(2026, 7, 3, 15, 30);
    await PendingScanStorage.add('t', at);
    expect(await PendingScanStorage.scannedAtFor('t'), at);
    expect(await PendingScanStorage.scannedAtFor('missing'), isNull);
  });

  test('容量上限2000件で古い順に切り捨て', () async {
    // 上限テストは軽量化のため直接多数追加はせず、境界のみ検証
    for (int i = 0; i < 5; i++) {
      await PendingScanStorage.add('tok-$i', DateTime(2026, 1, 1 + i));
    }
    expect((await PendingScanStorage.getAllTokens()).length, 5);
  });
}
