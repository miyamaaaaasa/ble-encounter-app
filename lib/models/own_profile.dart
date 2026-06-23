import 'dart:convert';
import 'dart:typed_data';

class OwnProfile {
  final String name;
  final String message;
  final int colorIndex;
  final String? iconPath;       // ローカル JPEG パス
  final DateTime? registeredAt; // 初回登録日

  const OwnProfile({
    required this.name,
    this.message = '',
    this.colorIndex = 0,
    this.iconPath,
    this.registeredAt,
  });

  /// BLE スキャン応答ペイロード。
  /// フォーマット: [0xBF][colorIdx][name ASCII ≤10 bytes][0x00][message ASCII ≤13 bytes]
  /// 合計最大 25 bytes (scan response 27 byte 制限内)
  Uint8List toScanPayload() {
    // 27 byte 制限 - 2 byte ヘッダ (0xBF + colorIdx) - 1 byte セパレータ = 24 bytes
    const totalAvail = 24;
    const nameMax = 10; // ASCII 10 文字
    final nameBytes = _trimUtf8(utf8.encode(name), nameMax);
    final msgMax = (totalAvail - nameBytes.length).clamp(0, 14);
    final msgBytes = _trimUtf8(utf8.encode(message), msgMax);

    final out = BytesBuilder();
    out.addByte(0xBF);
    out.addByte(colorIndex & 0xFF);
    out.add(nameBytes);
    out.addByte(0x00); // セパレータ
    out.add(msgBytes);
    return out.takeBytes();
  }

  static List<int> _trimUtf8(List<int> bytes, int maxLen) {
    if (bytes.length <= maxLen) return bytes;
    int len = maxLen;
    // UTF-8 継続バイト (10xxxxxx) を超えないようにトリム
    while (len > 0 && (bytes[len] & 0xC0) == 0x80) len--;
    return bytes.sublist(0, len);
  }

  Map<String, dynamic> toMap() => {
        'n': name,
        'm': message,
        'c': colorIndex,
        if (iconPath != null) 'i': iconPath,
        if (registeredAt != null) 'r': registeredAt!.toIso8601String(),
      };

  String toStorageJson() => jsonEncode(toMap());

  static OwnProfile fromStorageJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return OwnProfile(
      name: m['n'] as String? ?? '',
      message: m['m'] as String? ?? '',
      colorIndex: m['c'] as int? ?? 0,
      iconPath: m['i'] as String?,
      registeredAt: m['r'] != null
          ? DateTime.tryParse(m['r'] as String)
          : null,
    );
  }

  OwnProfile copyWith({
    String? name,
    String? message,
    int? colorIndex,
    String? iconPath,
    DateTime? registeredAt,
    bool clearIcon = false,
  }) =>
      OwnProfile(
        name: name ?? this.name,
        message: message ?? this.message,
        colorIndex: colorIndex ?? this.colorIndex,
        iconPath: clearIcon ? null : (iconPath ?? this.iconPath),
        registeredAt: registeredAt ?? this.registeredAt,
      );
}
