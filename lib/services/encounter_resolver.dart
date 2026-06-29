import 'package:flutter/foundation.dart';
import '../models/piece_data.dart';
import 'piece_storage.dart';
import 'supabase_service.dart';

/// サーバーから解析されたユーザー情報
class ResolvedProfile {
  final String userId;
  final String displayName;
  final int colorIndex;
  final DateTime metAt;

  const ResolvedProfile({
    required this.userId,
    required this.displayName,
    required this.colorIndex,
    required this.metAt,
  });
}

/// ゲート時刻にローカルの保留トークンをサーバーで解析し、ピースを収集する。
class EncounterResolver {
  /// 解析を実行し、新規取得 or 更新されたピースを返す。
  /// onProfileResolved: サーバーで解析された各ユーザー情報のコールバック（EncounterRecord更新用）
  static Future<List<PuzzlePiece>> resolveAndCollect({
    void Function(int current, int total)? onProgress,
    void Function(ResolvedProfile profile)? onProfileResolved,
  }) async {
    final tokens = await PendingScanStorage.getAllTokens();
    if (tokens.isEmpty) return [];

    debugPrint('[Resolver] resolving ${tokens.length} pending tokens...');
    final resolved = await SupabaseService.resolveTokens(tokens);

    final existing   = await PuzzlePieceStorage.load();
    final updated    = List<PuzzlePiece>.from(existing);
    final newPieces  = <PuzzlePiece>[];
    final myUid      = SupabaseService.userId;

    for (int i = 0; i < resolved.length; i++) {
      final r = resolved[i];
      onProgress?.call(i + 1, resolved.length);
      await Future.delayed(const Duration(milliseconds: 150)); // 演出タイミング

      final ownerId   = r['user_id'] as String?;
      final token     = r['token']   as String?;
      if (ownerId == null || token == null) continue;
      if (ownerId == myUid) continue; // 自分は除外

      final piece     = PieceData.fromJson(r['piece_data']);
      final name      = r['display_name'] as String? ?? '???';
      final color     = (r['color_index'] as num?)?.toInt() ?? 0;
      final metAt     = await PendingScanStorage.scannedAtFor(token) ?? DateTime.now();

      // サーバーファースト: 解析結果をコールバックで通知（EncounterRecord更新用）
      onProfileResolved?.call(ResolvedProfile(
        userId: ownerId,
        displayName: name,
        colorIndex: color,
        metAt: metAt,
      ));

      final existIdx  = updated.indexWhere((p) => p.ownerId == ownerId);
      if (existIdx >= 0) {
        final prev = updated[existIdx];
        updated[existIdx] = prev.copyWith(
          lastMetAt:  metAt,
          meetCount:  prev.meetCount + 1,
          ownerName:  name,
          piece:      piece.isEmpty ? prev.piece : piece, // ピース更新されていれば反映
          isRevealed: false, // 再び演出対象にする
        );
      } else {
        final np = PuzzlePiece(
          ownerId:        ownerId,
          ownerName:      name,
          ownerColorIndex: color,
          piece:          piece,
          firstMetAt:     metAt,
          lastMetAt:      metAt,
          meetCount:      1,
          isRevealed:     false,
        );
        updated.add(np);
        newPieces.add(np);
      }

      // サーバー側にも収集記録（best-effort）
      SupabaseService.recordCollectedPiece(
        ownerId:       ownerId,
        metAt:         metAt,
        pieceSnapshot: piece.toJson(),
      );
    }

    await PuzzlePieceStorage.save(updated);
    await PendingScanStorage.removeTokens(tokens);

    debugPrint('[Resolver] done: ${newPieces.length} new, ${updated.length} total');
    return updated.where((p) => !p.isRevealed).toList(); // 演出待ちリストを返す
  }
}
