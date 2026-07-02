import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piece_data.dart';
import '../../providers/ble_providers.dart' show appProvider;
import '../../providers/puzzle_providers.dart';
import '../../services/encounter_resolver.dart';
import '../games/memory_game_screen.dart';
import '../piece_editor/piece_editor_screen.dart';
import 'decrypt_screen.dart';

/// 収集したカケラ（ピース）を並べるパズルボード画面。
/// プロバイダーで状態を保持するため、タブ移動しても消えない。
/// 開いた時点で保留トークンを自動解析し、電波解析を押さなくてもカケラが見える。
class PuzzleBoardScreen extends ConsumerStatefulWidget {
  const PuzzleBoardScreen({super.key});

  @override
  ConsumerState<PuzzleBoardScreen> createState() => _PuzzleBoardScreenState();
}

class _PuzzleBoardScreenState extends ConsumerState<PuzzleBoardScreen> {
  bool _autoResolved = false;

  @override
  void initState() {
    super.initState();
    // 初回表示時に自動でバックグラウンド解析（電波解析を押さなくてもカケラが揃う）
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoResolve());
  }

  Future<void> _autoResolve() async {
    if (_autoResolved) return;
    _autoResolved = true;
    final newPieces = await ref.read(puzzleProvider.notifier).resolvePending(
      onProfileResolved: (profile) {
        ref.read(appProvider.notifier).upsertFromServerProfile(
          peerId: profile.userId,
          name: profile.displayName,
          colorIndex: profile.colorIndex,
          metAt: profile.metAt,
        );
      },
    );
    if (newPieces.isNotEmpty) {
      // 自動取得分は静かに公開済みにする（演出は電波解析ボタンで）
      await ref.read(puzzleProvider.notifier)
          .markRevealed(newPieces.map((p) => p.ownerId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✨ ${newPieces.length}枚のカケラが届きました'),
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final puzzle = ref.watch(puzzleProvider);
    final pieces = puzzle.pieces;

    // 次のマイルストーン（10枚区切り）への進捗
    final nextGoal = ((pieces.length ~/ 10) + 1) * 10;
    final progress = (pieces.length / nextGoal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF171B2E),
      body: SafeArea(
        child: Column(
          children: [
            // ─── 夜空ヘッダー ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Image.asset('assets/icons/tab_kakera.png',
                      width: 30, height: 30,
                      filterQuality: FilterQuality.medium),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('カケラのよぞら',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  _NightIconButton(
                    icon: Icons.sports_esports_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MemoryGameScreen()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _NightIconButton(
                    icon: Icons.brush_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PieceEditorScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // ─── 収集進捗パネル ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF232A45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x226FD8FF)),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${pieces.length}',
                            style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF6FD8FF),
                                height: 1.0)),
                        const SizedBox(width: 4),
                        const Text('枚 あつめた',
                            style: TextStyle(
                                fontSize: 13, color: Colors.white70)),
                        const Spacer(),
                        Text('つぎの目標 $nextGoal枚',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white38)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: const Color(0xFF171B2E),
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFF6FD8FF)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── カケラグリッド ─────────────────────────────────
            Expanded(
              child: pieces.isEmpty
                  ? _emptyState()
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1, // 正方形セル
                      ),
                      itemCount: pieces.length,
                      itemBuilder: (ctx, i) => _PieceCell(
                        piece: pieces[i],
                        onTap: () => _showDetail(pieces[i]),
                      ),
                    ),
            ),

            // ─── 電波解析ボタン ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DecryptScreen(),
                      fullscreenDialog: true),
                ),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF232A45),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0x446FD8FF)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x336FD8FF),
                          blurRadius: 12,
                          spreadRadius: 1),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.radar, color: Color(0xFF6FD8FF), size: 20),
                      SizedBox(width: 8),
                      Text('電波解析',
                          style: TextStyle(
                              color: Color(0xFF6FD8FF),
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 2)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.grid_view_outlined, size: 72, color: Colors.white12),
          const SizedBox(height: 16),
          const Text('まだカケラがありません',
              style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 8),
          const Text('誰かとすれ違うとカケラを集められます',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  void _showDetail(PuzzlePiece piece) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111122),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PieceDetail(piece: piece),
    );
  }
}

// ─── 夜空用アイコンボタン ─────────────────────────────────────────────────────
class _NightIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NightIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF232A45),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x336FD8FF)),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF6FD8FF)),
      ),
    );
  }
}

// ─── グリッドセル ─────────────────────────────────────────────────────────────

class _PieceCell extends StatelessWidget {
  final PuzzlePiece  piece;
  final VoidCallback onTap;

  const _PieceCell({required this.piece, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final revealed = piece.isRevealed;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111122),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: revealed
                ? const Color(0xFF00AAFF).withValues(alpha: 0.4)
                : Colors.white10,
          ),
          boxShadow: revealed
              ? [BoxShadow(color: const Color(0xFF00AAFF).withValues(alpha: 0.15), blurRadius: 8)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!revealed)
                const Center(
                    child: Icon(Icons.lock_outline, color: Colors.white24, size: 28))
              else
                PieceThumbnailWidget(piece: piece.piece, size: double.infinity),
              if (revealed)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    color: Colors.black45,
                    child: Text(
                      piece.ownerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 詳細シート ───────────────────────────────────────────────────────────────

class _PieceDetail extends StatelessWidget {
  final PuzzlePiece piece;
  const _PieceDetail({required this.piece});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          if (piece.isRevealed) ...[
            PieceThumbnailWidget(piece: piece.piece, size: 128),
            const SizedBox(height: 16),
            Text(piece.ownerName,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${piece.meetCount}回すれ違い',
                style: const TextStyle(color: Color(0xFF00AAFF), fontSize: 13)),
            const SizedBox(height: 4),
            Text('初めて: ${_fmt(piece.firstMetAt)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text('最後: ${_fmt(piece.lastMetAt)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ] else
            const Text('まだ解析されていません',
                style: TextStyle(color: Colors.white38, fontSize: 15)),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
}
