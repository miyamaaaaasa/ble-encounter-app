import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Server stores ciphertext only. The separate key never leaves SecureStorage.
class AccountCipher {
  static final _aes = AesGcm.with256bits();
  static Future<String> newKey() async =>
      base64Encode(await (await _aes.newSecretKey()).extractBytes());
  static Future<String> encrypt(
      String compressed, String key, String userId) async {
    final box = await _aes.encrypt(base64Decode(compressed),
        secretKey: SecretKey(base64Decode(key)), aad: utf8.encode(userId));
    return base64Encode(
        [97, 49, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String> decrypt(
      String encrypted, String key, String userId) async {
    final data = base64Decode(encrypted);
    if (data.length < 30 || data[0] != 97 || data[1] != 49) {
      throw const FormatException('Unknown archive format');
    }
    final box = SecretBox(data.sublist(14, data.length - 16),
        nonce: data.sublist(2, 14), mac: Mac(data.sublist(data.length - 16)));
    final compressed = await _aes.decrypt(box,
        secretKey: SecretKey(base64Decode(key)), aad: utf8.encode(userId));
    return base64Encode(compressed);
  }
}
