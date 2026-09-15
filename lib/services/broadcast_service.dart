import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// 管理者からのお知らせ1件。
class Broadcast {
  final int id;
  final String title;
  final String body;
  final DateTime createdAt;

  const Broadcast({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory Broadcast.fromJson(Map<String, dynamic> j) => Broadcast(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            ((j['created_at'] as num?)?.toInt() ?? 0) * 1000),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      };
}

/// 管理者お知らせの取得と、未読状態の永続化。
///
/// サーバーからのプッシュではなくアプリ起動中のポーリングで受け取る。
/// 「どこまで読んだか」を端末に保存し、それより新しいものだけを取得する。
class BroadcastService {
  BroadcastService._();

  static const _keyLastId = 'broadcast_last_id_v1';
  static const _keyCached = 'broadcast_cached_v1';
  static const _keyDismissed = 'broadcast_dismissed_id_v1';

  /// 受信済みで未表示のお知らせを取得する。
  ///
  /// 通信できなかった場合は空リストを返し、既読位置も進めない
  /// （次回の起動・ポーリングで改めて取りに行く）。
  static Future<List<Broadcast>> fetchNew() async {
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getInt(_keyLastId) ?? 0;

    final raw = await ApiService.fetchBroadcasts(lastId);
    if (raw == null || raw.isEmpty) return [];

    final list = raw.map(Broadcast.fromJson).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    // 既読位置を進める。ここで進めるため、同じお知らせが繰り返し出ることはない。
    await prefs.setInt(_keyLastId, list.last.id);

    // 直近分はキャッシュしておき、再起動後も一覧で見返せるようにする
    final cached = await loadCached();
    final merged = [...cached, ...list];
    // 新しい順に最大20件だけ保持（ストレージを無限に太らせない）
    merged.sort((a, b) => b.id.compareTo(a.id));
    final trimmed = merged.take(20).toList();
    await prefs.setString(
        _keyCached, jsonEncode(trimmed.map((b) => b.toJson()).toList()));

    debugPrint('[Broadcast] ${list.length} new (lastId -> ${list.last.id})');
    return list;
  }

  /// バナーを閉じた位置を記録する。これ以下のIDはバナー表示しない。
  /// 一覧（loadCached）には残るため、閉じても後から読み返せる。
  static Future<void> dismissUpTo(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getInt(_keyDismissed) ?? 0;
    if (id > cur) await prefs.setInt(_keyDismissed, id);
  }

  static Future<int> dismissedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDismissed) ?? 0;
  }

  /// バナー表示すべきお知らせ（未dismissのうち最新1件）。無ければ null。
  static Future<Broadcast?> bannerTarget() async {
    final dismissed = await dismissedId();
    final cached = await loadCached(); // 新しい順
    for (final b in cached) {
      if (b.id > dismissed) return b;
    }
    return null;
  }

  /// 保存済みのお知らせ一覧（新しい順）
  static Future<List<Broadcast>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyCached);
    if (s == null || s.isEmpty) return [];
    try {
      final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return list.map(Broadcast.fromJson).toList();
    } catch (e) {
      debugPrint('[Broadcast] cache parse error: $e');
      return [];
    }
  }
}
