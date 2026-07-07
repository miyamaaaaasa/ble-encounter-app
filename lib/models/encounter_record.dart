import 'dart:convert';
import 'template_message.dart';

class EncounterRecord {
  final String peerId;
  final String name;
  final int colorIndex;
  final int prefecture; // 0-46 = 都道府県コード, -1 = 未設定
  final DateTime firstMet;
  final DateTime lastMet;
  final int meetCount;
  final int rssi;
  final TemplateMessage template;
  // プライバシー保護: 結果演出完了まで画面に表示しない
  final bool isRevealed;
  // 相手のバッジレベル（サーバー解析で取得）
  final int peerBadgeLevel;
  // 相手のアバター画像URL（サーバー解析で取得）
  final String? avatarUrl;
  // 相手のドット絵（16x16=256画素・サーバー解析で取得し端末にキャッシュ）
  // 本アプリ最大のUGC。表示優先度は peerPixels > avatarUrl > イニシャル
  final List<int>? peerPixels;

  const EncounterRecord({
    required this.peerId,
    required this.name,
    required this.colorIndex,
    required this.firstMet,
    required this.lastMet,
    required this.meetCount,
    required this.rssi,
    this.prefecture = -1,
    this.template = const TemplateMessage(),
    this.isRevealed = false,
    this.peerBadgeLevel = 0,
    this.avatarUrl,
    this.peerPixels,
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
    int? prefecture,
    TemplateMessage? template,
    int? peerBadgeLevel,
    String? avatarUrl,
  }) =>
      EncounterRecord(
        peerId: peerId,
        name: name ?? this.name,
        colorIndex: colorIndex,
        prefecture: prefecture ?? this.prefecture,
        firstMet: firstMet,
        lastMet: lastMet,
        meetCount: meetCount + 1,
        rssi: rssi,
        template: template ?? this.template,
        isRevealed: isRevealed && metToday,
        peerBadgeLevel: peerBadgeLevel ?? this.peerBadgeLevel,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        peerPixels: peerPixels,
      );

  // ドット絵キャッシュだけ差し替えた複製（カケラ→名簿の補完マイグレーション用）
  EncounterRecord withPixels(List<int> pixels) => EncounterRecord(
        peerId: peerId,
        name: name,
        colorIndex: colorIndex,
        prefecture: prefecture,
        firstMet: firstMet,
        lastMet: lastMet,
        meetCount: meetCount,
        rssi: rssi,
        template: template,
        isRevealed: isRevealed,
        peerBadgeLevel: peerBadgeLevel,
        avatarUrl: avatarUrl,
        peerPixels: pixels,
      );

  // 結果演出完了時に呼ぶ
  EncounterRecord reveal() => EncounterRecord(
        peerId: peerId,
        name: name,
        colorIndex: colorIndex,
        prefecture: prefecture,
        firstMet: firstMet,
        lastMet: lastMet,
        meetCount: meetCount,
        rssi: rssi,
        template: template,
        isRevealed: true,
        peerBadgeLevel: peerBadgeLevel,
        avatarUrl: avatarUrl,
        peerPixels: peerPixels,
      );

  Map<String, dynamic> toMap() => {
        'peerId': peerId,
        'name': name,
        'colorIndex': colorIndex,
        'pf': prefecture,
        'firstMet': firstMet.toIso8601String(),
        'lastMet': lastMet.toIso8601String(),
        'meetCount': meetCount,
        'rssi': rssi,
        'ts': template.statusIndex,
        'th': template.hobbyCategory,
        'td': template.hobbyDetail,
        'tp': template.phraseIndex,
        'rv': isRevealed,
        'bl': peerBadgeLevel,
        if (avatarUrl != null) 'av': avatarUrl,
        if (peerPixels != null) 'px': peerPixels,
      };

  static EncounterRecord fromMap(Map<String, dynamic> m) => EncounterRecord(
        peerId: m['peerId'] as String,
        name: m['name'] as String? ?? '????',
        colorIndex: m['colorIndex'] as int? ?? 0,
        prefecture: m['pf'] as int? ?? -1,
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
        peerBadgeLevel: m['bl'] as int? ?? 0,
        avatarUrl: m['av'] as String?,
        peerPixels: (m['px'] as List?)?.map((e) => (e as num).toInt()).toList(),
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
