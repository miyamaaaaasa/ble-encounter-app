import 'dart:convert';
import 'template_message.dart';

class EncounterRecord {
  final String peerId;
  final String name;
  final int colorIndex;
  final DateTime firstMet;
  final DateTime lastMet;
  final int meetCount;
  final int rssi;
  final TemplateMessage template;
  // プライバシー保護: 結果演出完了まで画面に表示しない
  final bool isRevealed;

  const EncounterRecord({
    required this.peerId,
    required this.name,
    required this.colorIndex,
    required this.firstMet,
    required this.lastMet,
    required this.meetCount,
    required this.rssi,
    this.template = const TemplateMessage(),
    this.isRevealed = false,
  });

  bool get metToday {
    final now = DateTime.now();
    return lastMet.year == now.year &&
        lastMet.month == now.month &&
        lastMet.day == now.day;
  }

  bool get firstMetToday {
    final now = DateTime.now();
    return firstMet.year == now.year &&
        firstMet.month == now.month &&
        firstMet.day == now.day;
  }

  EncounterRecord updatedWith({
    required DateTime lastMet,
    required int rssi,
    String? name,
    TemplateMessage? template,
  }) =>
      EncounterRecord(
        peerId: peerId,
        name: name ?? this.name,
        colorIndex: colorIndex,
        firstMet: firstMet,
        lastMet: lastMet,
        meetCount: meetCount + 1,
        rssi: rssi,
        template: template ?? this.template,
        // 今日すでに開封済みなら保持。昨日以前の revealed は今日の再遭遇でリセット
        isRevealed: isRevealed && metToday,
      );

  // 結果演出完了時に呼ぶ
  EncounterRecord reveal() => EncounterRecord(
        peerId: peerId,
        name: name,
        colorIndex: colorIndex,
        firstMet: firstMet,
        lastMet: lastMet,
        meetCount: meetCount,
        rssi: rssi,
        template: template,
        isRevealed: true,
      );

  Map<String, dynamic> toMap() => {
        'peerId': peerId,
        'name': name,
        'colorIndex': colorIndex,
        'firstMet': firstMet.toIso8601String(),
        'lastMet': lastMet.toIso8601String(),
        'meetCount': meetCount,
        'rssi': rssi,
        'ts': template.statusIndex,
        'th': template.hobbyCategory,
        'td': template.hobbyDetail,
        'tp': template.phraseIndex,
        'rv': isRevealed,
      };

  static EncounterRecord fromMap(Map<String, dynamic> m) => EncounterRecord(
        peerId: m['peerId'] as String,
        name: m['name'] as String? ?? '????',
        colorIndex: m['colorIndex'] as int? ?? 0,
        firstMet: DateTime.parse(m['firstMet'] as String),
        lastMet: DateTime.parse(m['lastMet'] as String),
        meetCount: m['meetCount'] as int? ?? 1,
        rssi: m['rssi'] as int? ?? -99,
        template: TemplateMessage(
          statusIndex: m['ts'] as int? ?? 0,
          hobbyCategory: m['th'] as int? ?? 0,
          hobbyDetail: m['td'] as int? ?? 0,
          phraseIndex: m['tp'] as int? ?? 0,
        ),
        isRevealed: m['rv'] as bool? ?? true, // 旧レコードは公開済み扱い
      );

  static String encodeList(List<EncounterRecord> list) =>
      jsonEncode(list.map((e) => e.toMap()).toList());

  static List<EncounterRecord> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => EncounterRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
