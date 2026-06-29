import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class SupabaseService {
  static SupabaseClient get _c => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnon);
    await _ensureAuth();
  }

  static Future<void> _ensureAuth() async {
    if (_c.auth.currentUser != null) return;
    try {
      await _c.auth.signInAnonymously();
      debugPrint('[Supabase] anonymous auth OK uid=${userId?.substring(0, 8)}');
    } catch (e) {
      debugPrint('[Supabase] auth error: $e');
    }
  }

  static String? get userId => _c.auth.currentUser?.id;
  static bool get isReady   => userId != null;

  // ─── Token ───────────────────────────────────────────────────────

  // サーバーで新トークンを発行（24時間有効）
  static Future<String?> issueToken() async {
    if (!isReady) return null;
    try {
      final res = await _c.rpc('issue_token');
      return res as String?;
    } catch (e) {
      debugPrint('[Supabase] issueToken: $e');
      return null;
    }
  }

  // 収集したトークンリストをユーザー情報に解析
  static Future<List<Map<String, dynamic>>> resolveTokens(List<String> tokens) async {
    if (!isReady || tokens.isEmpty) return [];
    try {
      final res = await _c.rpc('resolve_tokens', params: {'token_list': tokens});
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Supabase] resolveTokens: $e');
      return [];
    }
  }

  // ─── Profile ─────────────────────────────────────────────────────

  // 自分のプロフィール（表示名・色・ピース）をサーバーに同期
  static Future<void> syncProfile({
    required String displayName,
    required int colorIndex,
    List<int>? piecePixels,
  }) async {
    if (!isReady) return;
    try {
      await _c.from('users').upsert({
        'id':           userId,
        'display_name': displayName,
        'color_index':  colorIndex,
        if (piecePixels != null) 'piece_data': piecePixels,
      });
    } catch (e) {
      debugPrint('[Supabase] syncProfile: $e');
    }
  }

  // ─── Piece ───────────────────────────────────────────────────────

  // ピースデータを保存
  static Future<bool> savePieceData(List<int> pixels) async {
    if (!isReady) return false;
    try {
      await _c.from('users').upsert({'id': userId, 'piece_data': pixels});
      return true;
    } catch (e) {
      debugPrint('[Supabase] savePieceData: $e');
      return false;
    }
  }

  // 収集したピースをサーバーに記録（二重記録防止は UNIQUE 制約側で処理）
  static Future<void> recordCollectedPiece({
    required String ownerId,
    required DateTime metAt,
    required List<int> pieceSnapshot,
  }) async {
    if (!isReady) return;
    try {
      await _c.from('collected_pieces').upsert(
        {
          'collector_id':  userId,
          'owner_id':      ownerId,
          'last_met_at':   metAt.toIso8601String(),
          'meet_count':    1,
          'piece_snapshot': pieceSnapshot,
        },
        onConflict: 'collector_id,owner_id',
        ignoreDuplicates: false,
      );
    } catch (e) {
      debugPrint('[Supabase] recordCollectedPiece: $e');
    }
  }
}
