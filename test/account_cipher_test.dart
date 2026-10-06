import 'package:flutter_test/flutter_test.dart';
import 'package:ble_encounter/services/account_cipher.dart';
import 'dart:convert';

void main() {
  test(
      'encrypted archive round trip, random nonces, tampering and wrong owner rejected',
      () async {
    final key = await AccountCipher.newKey();
    final plain = base64Encode(utf8.encode('そら・履歴・カケラ・バッジ'));
    final a = await AccountCipher.encrypt(plain, key, 'owner');
    final b = await AccountCipher.encrypt(plain, key, 'owner');
    expect(a, isNot(b));
    expect(await AccountCipher.decrypt(a, key, 'owner'), plain);
    expect(
        () => AccountCipher.decrypt(a, key, 'someone-else'), throwsA(anything));
    final changed = base64Decode(a);
    changed[15] ^= 1;
    expect(() => AccountCipher.decrypt(base64Encode(changed), key, 'owner'),
        throwsA(anything));
    final wrong = await AccountCipher.newKey();
    expect(() => AccountCipher.decrypt(a, wrong, 'owner'), throwsA(anything));
  });
}
