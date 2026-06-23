import 'dart:convert';
import 'dart:typed_data';
import 'template_message.dart';

class OwnProfile {
  final String name;
  final int colorIndex;
  final TemplateMessage template;
  final DateTime? registeredAt;

  const OwnProfile({
    required this.name,
    this.colorIndex = 0,
    this.template = const TemplateMessage(),
    this.registeredAt,
  });

  /// BLE スキャン応答ペイロード。
  /// フォーマット: [0xBF][colorIdx][name ASCII ≤10][0x00][status][hobby][detail][phrase]
  /// 合計最大 17 bytes（27 byte 制限内）
  Uint8List toScanPayload() {
    const nameMax = 10;
    final nameBytes = _trimAscii(utf8.encode(name), nameMax);
    final out = BytesBuilder();
    out.addByte(0xBF);
    out.addByte(colorIndex & 0xFF);
    out.add(nameBytes);
    out.addByte(0x00);
    out.addByte(template.statusIndex & 0xFF);
    out.addByte(template.hobbyCategory & 0xFF);
    out.addByte(template.hobbyDetail & 0xFF);
    out.addByte(template.phraseIndex & 0xFF);
    return out.takeBytes();
  }

  static List<int> _trimAscii(List<int> bytes, int maxLen) {
    if (bytes.length <= maxLen) return bytes;
    return bytes.sublist(0, maxLen);
  }

  Map<String, dynamic> toMap() => {
        'n': name,
        'c': colorIndex,
        'ts': template.statusIndex,
        'th': template.hobbyCategory,
        'td': template.hobbyDetail,
        'tp': template.phraseIndex,
        if (registeredAt != null) 'r': registeredAt!.toIso8601String(),
      };

  String toStorageJson() => jsonEncode(toMap());

  static OwnProfile fromStorageJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return OwnProfile(
      name: m['n'] as String? ?? '',
      colorIndex: m['c'] as int? ?? 0,
      template: TemplateMessage(
        statusIndex: m['ts'] as int? ?? 0,
        hobbyCategory: m['th'] as int? ?? 0,
        hobbyDetail: m['td'] as int? ?? 0,
        phraseIndex: m['tp'] as int? ?? 0,
      ),
      registeredAt:
          m['r'] != null ? DateTime.tryParse(m['r'] as String) : null,
    );
  }

  OwnProfile copyWith({
    String? name,
    int? colorIndex,
    TemplateMessage? template,
    DateTime? registeredAt,
  }) =>
      OwnProfile(
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        template: template ?? this.template,
        registeredAt: registeredAt ?? this.registeredAt,
      );
}
