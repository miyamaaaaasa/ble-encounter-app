import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/piece_data.dart';

/// 自分のドット絵ピースをローカルに保存
class OwnPieceStorage {
  static const _key = 'own_piece_v1';

  static Future<PieceData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json  = prefs.getString(_key);
    if (json == null) return null;
    try {
      return PieceData.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(PieceData piece) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(piece.toJson()));
  }
}

/// 収集した他ユーザーのピースをローカルに保存
class PuzzlePieceStorage {
  static const _key = 'puzzle_pieces_v1';

  static Future<List<PuzzlePiece>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json  = prefs.getString(_key);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => PuzzlePiece.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<PuzzlePiece> pieces) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(pieces.map((p) => p.toMap()).toList()));
  }
}

/// ゲート解析前の「収集したが未解析のトークン」をローカルに保存
class PendingScanStorage {
  static const _key = 'pending_scans_v1';

  static Future<List<_PendingScan>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json  = prefs.getString(_key);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => _PendingScan.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(String token, DateTime at) async {
    final existing = await load();
    if (existing.any((s) => s.token == token)) return; // 重複スキップ
    // 仕様: ユーザーが開門して確認するまで時間経過では削除しない。
    // （削除はサーバー解析成功時の removeTokens のみ。容量保護の上限だけ設ける）
    final all = [...existing, _PendingScan(token: token, at: at)];
    final trimmed = all.length > 2000 ? all.sublist(all.length - 2000) : all;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(trimmed.map((s) => s.toMap()).toList()));
  }

  static Future<List<String>> getAllTokens() async {
    final list = await load();
    return list.map((s) => s.token).toList();
  }

  static Future<DateTime?> scannedAtFor(String token) async {
    final list = await load();
    final s = list.where((s) => s.token == token).firstOrNull;
    return s?.at;
  }

  static Future<void> removeTokens(List<String> tokens) async {
    final existing = await load();
    final updated  = existing.where((s) => !tokens.contains(s.token)).toList();
    final prefs    = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(updated.map((s) => s.toMap()).toList()));
  }

  static Future<int> get pendingCount async => (await load()).length;
}

class _PendingScan {
  final String   token;
  final DateTime at;
  const _PendingScan({required this.token, required this.at});
  Map<String, dynamic> toMap()          => {'t': token, 'at': at.toIso8601String()};
  static _PendingScan fromMap(Map<String, dynamic> m) =>
      _PendingScan(token: m['t'] as String, at: DateTime.parse(m['at'] as String));
}
