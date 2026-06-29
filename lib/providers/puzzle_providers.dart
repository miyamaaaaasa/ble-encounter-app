import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piece_data.dart';
import '../services/encounter_resolver.dart';
import '../services/piece_storage.dart';

class PuzzleState {
  final List<PuzzlePiece> pieces;
  final bool   isResolving;
  final int    progress;
  final int    progressTotal;
  final List<PuzzlePiece> lastNewPieces; // 直近の解析で新規取得したピース（演出用）

  const PuzzleState({
    this.pieces = const [],
    this.isResolving = false,
    this.progress = 0,
    this.progressTotal = 0,
    this.lastNewPieces = const [],
  });

  PuzzleState copyWith({
    List<PuzzlePiece>? pieces,
    bool? isResolving,
    int? progress,
    int? progressTotal,
    List<PuzzlePiece>? lastNewPieces,
  }) =>
      PuzzleState(
        pieces:        pieces ?? this.pieces,
        isResolving:   isResolving ?? this.isResolving,
        progress:      progress ?? this.progress,
        progressTotal: progressTotal ?? this.progressTotal,
        lastNewPieces: lastNewPieces ?? this.lastNewPieces,
      );

  int get revealedCount => pieces.where((p) => p.isRevealed).length;
}

class PuzzleNotifier extends Notifier<PuzzleState> {
  @override
  PuzzleState build() {
    _load();
    return const PuzzleState();
  }

  Future<void> _load() async {
    final list = await PuzzlePieceStorage.load();
    state = state.copyWith(pieces: list);
  }

  /// 保留トークンをサーバーで解析してピースを収集。
  /// 自動・手動どちらからも呼べる（多重実行ガード付き）。
  Future<List<PuzzlePiece>> resolvePending({
    void Function(int current, int total)? onProgress,
  }) async {
    if (state.isResolving) return const [];
    state = state.copyWith(isResolving: true, progress: 0, progressTotal: 0);
    try {
      final newlyPending = await EncounterResolver.resolveAndCollect(
        onProgress: (c, t) {
          state = state.copyWith(progress: c, progressTotal: t);
          onProgress?.call(c, t);
        },
      );
      final all = await PuzzlePieceStorage.load();
      state = state.copyWith(
        pieces:        all,
        isResolving:   false,
        lastNewPieces: newlyPending,
      );
      debugPrint('[Puzzle] resolved: ${newlyPending.length} new / ${all.length} total');
      return newlyPending;
    } catch (e) {
      debugPrint('[Puzzle] resolve error: $e');
      state = state.copyWith(isResolving: false);
      return const [];
    }
  }

  /// 演出完了後に未公開ピースを公開済みにする。
  Future<void> markRevealed(Iterable<String> ownerIds) async {
    final ids = ownerIds.toSet();
    final updated = state.pieces
        .map((p) => ids.contains(p.ownerId) ? p.copyWith(isRevealed: true) : p)
        .toList();
    state = state.copyWith(pieces: updated, lastNewPieces: const []);
    await PuzzlePieceStorage.save(updated);
  }

  /// 全ピースを公開済みにする（演出スキップ用）。
  Future<void> markAllRevealed() async {
    final updated = state.pieces.map((p) => p.copyWith(isRevealed: true)).toList();
    state = state.copyWith(pieces: updated, lastNewPieces: const []);
    await PuzzlePieceStorage.save(updated);
  }

  Future<void> refresh() => _load();
}

final puzzleProvider =
    NotifierProvider<PuzzleNotifier, PuzzleState>(PuzzleNotifier.new);
