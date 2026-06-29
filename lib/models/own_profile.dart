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

  /// BLE スキャン応答ペイロード（サーバーファースト版）。
  /// プライバシー保護のため個人情報は一切送信しない。
  /// BLEでは暗号化されたトークンのみを交換し、プロフィールはサーバーから取得する。
  Uint8List toScanPayload({int badgeLevel = 0}) {
    return Uint8List(0);
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

  static OwnProfile fromMap(Map<String, dynamic> m) => OwnProfile(
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

  static OwnProfile fromStorageJson(String json) =>
      fromMap(jsonDecode(json) as Map<String, dynamic>);

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
