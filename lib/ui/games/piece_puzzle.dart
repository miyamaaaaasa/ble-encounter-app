import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/encounter_record.dart';
import '../../models/game_data.dart';
import '../../services/game_storage.dart';
import '../../ui/encounter_helpers.dart';

// ─── ① ピース集めの旅 ────────────────────────────────────────────────────────

class PiecePuzzleScreen extends StatefulWidget {
  final List<EncounterRecord> todayRevealed;
  const PiecePuzzleScreen({super.key, required this.todayRevealed});

  @override
  State<PiecePuzzleScreen> createState() => _PiecePuzzleScreenState();
}

class _PiecePuzzleScreenState extends State<PiecePuzzleScreen> {
  PieceState? _puzzle;
  Set<String> _todayPiece = {};
  bool _loading = true;
  List<String> _newPieces = []; // 今回贈られたpeerIds

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data   = await GameStorage.load();
    final today  = await GameStorage.loadTodayPiece();
    if (!mounted) return;
    setState(() {
      _puzzle     = data.puzzle;
      _todayPiece = today;
      _loading    = false;
    });
  }

  Future<void> _collectAll() async {
    var puzzle = _puzzle!;
    final newIds = <String>[];

    for (final e in widget.todayRevealed) {
      if (_todayPiece.contains(e.peerId)) continue;
      final rarity = cardRarityOf(e.meetCount);
      // ホログラム → 30%でゴールドピース
      final gold = rarity == CardRarity.hologram &&
          (e.peerId.hashCode.abs() % 10) < 3;
      puzzle = puzzle.addPiece(e.peerId, gold);
      _todayPiece.add(e.peerId);
      newIds.add(e.peerId);
    }

    if (!mounted) return;
    setState(() { _puzzle = puzzle; _newPieces = newIds; });

    final data = await GameStorage.load();
    await GameStorage.save(data.copyWith(puzzle: puzzle));
    await GameStorage.saveTodayPiece(_todayPiece);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final puzzle = _puzzle!;
    final pendingPeers = widget.todayRevealed
        .where((e) => !_todayPiece.contains(e.peerId))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('ピース集めの旅')),
      body: CustomScrollView(
        slivers: [
          // ─── パズルグリッド ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  _ProgressHeader(puzzle: puzzle),
                  const SizedBox(height: 16),
                  _PuzzleGrid(puzzle: puzzle),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ─── 今日の取得候補 ─────────────────────────────────────────────
          if (pendingPeers.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton.icon(
                  onPressed: puzzle.isComplete ? null : _collectAll,
                  icon: const Text('✨', style: TextStyle(fontSize: 18)),
                  label: Text('今日の出会いから ${pendingPeers.length} 枚もらう'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                ),
              ),
            ),

          if (pendingPeers.isEmpty && widget.todayRevealed.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Text('✅', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text('今日分は全員からもらいました',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondaryContainer)),
                  ]),
                ),
              ),
            ),

          if (widget.todayRevealed.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: '🧩',
                title: 'まだ出会いがありません',
                subtitle: '今日タブで出会いを確認してからピースをもらえます',
              ),
            ),

          // ─── もらったピース一覧 ──────────────────────────────────────────
          if (_newPieces.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('さっきもらったピース',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 4,
                      children: _newPieces.map((pid) {
                        final e = widget.todayRevealed
                            .firstWhere((r) => r.peerId == pid);
                        final gold = cardRarityOf(e.meetCount) == CardRarity.hologram &&
                            (e.peerId.hashCode.abs() % 10) < 3;
                        return Chip(
                          avatar: Text(gold ? '⭐' : '🧩'),
                          label: Text(e.name,
                              style: const TextStyle(fontSize: 12)),
                          backgroundColor: gold
                              ? const Color(0xFFFFF8E1)
                              : null,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final PieceState puzzle;
  const _ProgressHeader({required this.puzzle});

  @override
  Widget build(BuildContext context) {
    final pct = puzzle.count / PieceState.total;
    final goldCount = puzzle.isGold.where((g) => g).length;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${puzzle.count} / ${PieceState.total} ピース',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (goldCount > 0)
              Text('⭐ ゴールド ×$goldCount',
                  style: const TextStyle(color: Color(0xFFFFB300), fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        if (puzzle.isComplete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('🎉 パズル完成！',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
      ],
    );
  }
}

// CustomPainterでジグゾーピース描画
class _PuzzleGrid extends StatelessWidget {
  final PieceState puzzle;
  const _PuzzleGrid({required this.puzzle});

  @override
  Widget build(BuildContext context) {
    const cols = 5;
    const cell = 56.0;
    const gap  = 3.0;
    final size  = cols * cell + (cols - 1) * gap;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PuzzlePainter(puzzle: puzzle),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PuzzlePainter extends CustomPainter {
  final PieceState puzzle;
  _PuzzlePainter({required this.puzzle});

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 5;
    final cellW = size.width / cols;
    final cellH = size.height / cols;
    const gap = 3.0;

    final emptyPaint  = Paint()..color = const Color(0xFFE0E0E0);
    final normalPaint = Paint()..color = const Color(0xFF4DD0E1);
    final goldPaint   = Paint()..color = const Color(0xFFFFCC02);
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < PieceState.total; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      final left = col * cellW + (col == 0 ? 0 : gap / 2);
      final top  = row * cellH + (row == 0 ? 0 : gap / 2);
      final rect = Rect.fromLTWH(left, top, cellW - gap, cellH - gap);
      final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

      if (!puzzle.collected[i]) {
        canvas.drawRRect(rRect, emptyPaint);
        // 点線風のアウトライン
        canvas.drawRRect(rRect, Paint()
          ..color = const Color(0xFFBDBDBD)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
      } else if (puzzle.isGold[i]) {
        canvas.drawRRect(rRect, goldPaint);
        // 星マーク
        _drawStar(canvas, rect.center, rect.shortestSide * 0.3);
        canvas.drawRRect(rRect, borderPaint);
      } else {
        canvas.drawRRect(rRect, normalPaint);
        // 小さい○
        canvas.drawCircle(rect.center, rect.shortestSide * 0.2,
            Paint()..color = Colors.white54);
        canvas.drawRRect(rRect, borderPaint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r) {
    final path = Path();
    const n = 5;
    final innerR = r * 0.4;
    for (int i = 0; i < n * 2; i++) {
      final angle = (i * math.pi / n) - math.pi / 2;
      final radius = i.isEven ? r : innerR;
      final pt = Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle));
      if (i == 0) path.moveTo(pt.dx, pt.dy); else path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(_PuzzlePainter old) =>
      old.puzzle.count != puzzle.count;
}

// ─── 共通空状態 ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(icon, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}
