import 'dart:convert';

class EncounterRecord {
  final String peerId;
  final String name;
  final String message;
  final int colorIndex;
  final DateTime firstMet;
  final DateTime lastMet;
  final int meetCount;
  final int rssi;

  const EncounterRecord({
    required this.peerId,
    required this.name,
    required this.message,
    required this.colorIndex,
    required this.firstMet,
    required this.lastMet,
    required this.meetCount,
    required this.rssi,
  });

  EncounterRecord updatedWith({
    required DateTime lastMet,
    required int rssi,
    String? name,
    String? message,
  }) =>
      EncounterRecord(
        peerId: peerId,
        name: name ?? this.name,
        message: message ?? this.message,
        colorIndex: colorIndex,
        firstMet: firstMet,
        lastMet: lastMet,
        meetCount: meetCount + 1,
        rssi: rssi,
      );

  Map<String, dynamic> toMap() => {
        'peerId': peerId,
        'name': name,
        'message': message,
        'colorIndex': colorIndex,
        'firstMet': firstMet.toIso8601String(),
        'lastMet': lastMet.toIso8601String(),
        'meetCount': meetCount,
        'rssi': rssi,
      };

  static EncounterRecord fromMap(Map<String, dynamic> m) => EncounterRecord(
        peerId: m['peerId'] as String,
        name: m['name'] as String? ?? '????',
        message: m['message'] as String? ?? '',
        colorIndex: m['colorIndex'] as int? ?? 0,
        firstMet: DateTime.parse(m['firstMet'] as String),
        lastMet: DateTime.parse(m['lastMet'] as String),
        meetCount: m['meetCount'] as int? ?? 1,
        rssi: m['rssi'] as int? ?? -99,
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
