import 'dart:convert';
import 'dart:typed_data';
import 'template_message.dart';

class OwnProfile {
  final String name;
  final int colorIndex;
  final TemplateMessage template;
  final int prefecture; // 0-46 = 都道府県コード, -1 = 未設定
  final DateTime? registeredAt;

  const OwnProfile({
    required this.name,
    this.colorIndex = 0,
    this.template = const TemplateMessage(),
    this.prefecture = -1,
    this.registeredAt,
  });

  /// BLE スキャン応答ペイロード。
  /// フォーマット: [0xBF][colorIdx][prefecture+1 or 0xFF][name ASCII ≤9][0x00][status][hobby][detail][phrase]
  /// 合計最大 17 bytes（27 byte 制限内）
  Uint8List toScanPayload() {
    const nameMax = 9; // prefecture byte追加のため1減
    final nameBytes = _trimAscii(utf8.encode(name), nameMax);
    final out = BytesBuilder();
    out.addByte(0xBF);
    out.addByte(colorIndex & 0xFF);
    out.addByte(prefecture == -1 ? 0xFF : (prefecture & 0x3F)); // 0xFF=未設定, 0-46=都道府県
    out.add(nameBytes);
    out.addByte(0x00);
    out.addByte(template.statusIndex   == -1 ? 0xFF : template.statusIndex   & 0xFF);
    out.addByte(template.hobbyCategory == -1 ? 0xFF : template.hobbyCategory & 0xFF);
    out.addByte(template.hobbyDetail   == -1 ? 0xFF : template.hobbyDetail   & 0xFF);
    out.addByte(template.phraseIndex   == -1 ? 0xFF : template.phraseIndex   & 0xFF);
    return out.takeBytes();
  }

  static List<int> _trimAscii(List<int> bytes, int maxLen) {
    if (bytes.length <= maxLen) return bytes;
    return bytes.sublist(0, maxLen);
  }

  Map<String, dynamic> toMap() => {
        'n': name,
        'c': colorIndex,
        'pf': prefecture,
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
      prefecture: m['pf'] as int? ?? -1,
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
    int? prefecture,
    TemplateMessage? template,
    DateTime? registeredAt,
  }) =>
      OwnProfile(
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        prefecture: prefecture ?? this.prefecture,
        template: template ?? this.template,
        registeredAt: registeredAt ?? this.registeredAt,
      );
}
