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

  // 収集したトークンリストをユーザー情報に解析。
  // 通信エラー時は null を返す（[] と区別し、呼び出し側でトークンを保持させる）
  static Future<List<Map<String, dynamic>>?> resolveTokens(List<String> tokens) async {
    if (!isReady || tokens.isEmpty) return isReady ? [] : null;
    try {
      final res = await _c.rpc('resolve_tokens', params: {'token_list': tokens});
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Supabase] resolveTokens: $e');
      return null;
    }
  }

  // ─── Profile ─────────────────────────────────────────────────────

  // 自分のプロフィール（表示名・色・ピース・バッジレベル）をサーバーに同期
  static Future<void> syncProfile({
    required String displayName,
    required int colorIndex,
    List<int>? piecePixels,
    int? badgeLevel,
  }) async {
    if (!isReady) return;
    try {
      await _c.from('users').upsert({
        'id':           userId,
        'display_name': displayName,
        'color_index':  colorIndex,
        if (piecePixels != null) 'piece_data': piecePixels,
        if (badgeLevel != null) 'badge_level': badgeLevel,
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

}
