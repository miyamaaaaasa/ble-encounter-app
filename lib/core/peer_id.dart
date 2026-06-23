import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// デバイス固有の永続 ID。
/// アプリ再起動・ユーザー名変更でも変わらない。
/// main() で await PeerId.init() を呼ぶこと。
class PeerId {
  PeerId._();

  static const _prefKey = 'device_uid_v1';

  static Uint8List? _bytes;
  static String? _hex;

  static Uint8List get bytes {
    assert(_bytes != null, 'PeerId.init() must be called before use');
    return _bytes!;
  }

  static String get hex {
    _hex ??= _bytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _hex!;
  }

  static String get shortHex => hex.substring(hex.length - 4);

  /// SharedPreferences から読み込み、なければ新規生成して保存する。
  static Future<void> init() async {
    if (_bytes != null) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null && stored.length == 32) {
      _hex = stored;
      _bytes = Uint8List.fromList(
        List.generate(
          16,
          (i) => int.parse(stored.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
    } else {
      const uuid = Uuid();
      _bytes = Uint8List.fromList(uuid.v4obj().toBytes());
      _hex = _bytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_prefKey, _hex!);
    }
  }
}
