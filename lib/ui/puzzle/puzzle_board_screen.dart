import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/piece_data.dart';
import '../../services/piece_storage.dart';
import '../piece_editor/piece_editor_screen.dart';
import 'decrypt_screen.dart';

/// 収集したカケラ（ピース）を並べるパズルボード画面
class PuzzleBoardScreen extends StatefulWidget {
  final List<PuzzlePiece> highlightPieces; // 今回新たに入手したピース（演出対象）

  const PuzzleBoardScreen({super.key, this.highlightPieces = const []});

  @override
  State<PuzzleBoardScreen> createState() => _PuzzleBoardScreenState();
}

class _PuzzleBoardScreenState extends State<PuzzleBoardScreen>
    with TickerProviderStateMixin {
  List<PuzzlePiece> _pieces = [];
  Set<String>       _newIds = {};

  late AnimationController _revealCtrl;
  int _revealingIdx = -1;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _newIds = widget.highlightPieces.map((p) => p.ownerId).toSet();
    _load();
  }

  @override
  void dispose() {
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await PuzzlePieceStorage.load();
    setState(() => _pieces = list);
    if (_newIds.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 400));
      _revealNext(0);
    }
  }

  void _revealNext(int idx) {
    final newPieces = _pieces.where((p) => _newIds.contains(p.ownerId) && !p.isRevealed).toList();
    if (idx >= newPieces.length) {
      _saveRevealedState();
      return;
    }
    setState(() => _revealingIdx = _pieces.indexWhere((p) => p.ownerId == newPieces[idx].ownerId));
    HapticFeedback.mediumImpact();
    _revealCtrl.forward(from: 0).then((_) {
      setState(() {
        final i = _revealingIdx;
        if (i >= 0) _pieces[i] = _pieces[i].copyWith(isRevealed: true);
        _revealingIdx = -1;
      });
      Future.delayed(const Duration(milliseconds: 300), () => _revealNext(idx + 1));
    });
  }

  Future<void> _saveRevealedState() async {
    await PuzzlePieceStorage.save(_pieces);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('カケラコレクション', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00AAFF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00AAFF).withValues(alpha: 0.5)),
              ),
              child: Text('${_pieces.length}枚',
                  style: const TextStyle(color: Color(0xFF00AAFF), fontSize: 12)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.brush_outlined),
            tooltip: 'マイピースを描く',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PieceEditorScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DecryptScreen(), fullscreenDialog: true),
        ),
        icon: const Icon(Icons.radar),
        label: const Text('電波解析'),
        backgroundColor: const Color(0xFF001122),
        foregroundColor: const Color(0xFF00AAFF),
      ),
      body: _pieces.isEmpty
          ? _emptyState()
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:    3,
                crossAxisSpacing:  8,
                mainAxisSpacing:   8,
              ),
              itemCount: _pieces.length,
              itemBuilder: (ctx, i) => _PieceCell(
                piece:       _pieces[i],
                isRevealing: i == _revealingIdx,
                revealAnim:  _revealCtrl,
                onTap:       () => _showDetail(_pieces[i]),
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_view_outlined, size: 72, color: Colors.white12),
          const SizedBox(height: 16),
          const Text('まだカケラがありません', style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 8),
          const Text('誰かとすれ違うとカケラを集められます',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  void _showDetail(PuzzlePiece piece) {
    showModalBottomSheet(
      context:       context,
      backgroundColor: const Color(0xFF111122),
      shape:         const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PieceDetail(piece: piece),
    );
  }
}

// ─── グリッドセル ─────────────────────────────────────────────────────────────

class _PieceCell extends StatelessWidget {
  final PuzzlePiece         piece;
  final bool                isRevealing;
  final AnimationController revealAnim;
  final VoidCallback        onTap;

  const _PieceCell({
    required this.piece,
    required this.isRevealing,
    required this.revealAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isRevealing) {
      return AnimatedBuilder(
        animation: revealAnim,
        builder: (_, __) {
          final t = Curves.elasticOut.transform(revealAnim.value);
          return Transform.scale(
            scale:  0.5 + t * 0.5,
            child:  Opacity(opacity: revealAnim.value, child: _cell(revealed: true)),
          );
        },
      );
    }
    return GestureDetector(onTap: onTap, child: _cell(revealed: piece.isRevealed));
  }

  Widget _cell({required bool revealed}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111122),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: revealed ? const Color(0xFF00AAFF).withValues(alpha: 0.4) : Colors.white10,
        ),
        boxShadow: revealed
            ? [BoxShadow(color: const Color(0xFF00AAFF).withValues(alpha: 0.15), blurRadius: 8)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            if (!revealed)
              const Center(child: Icon(Icons.lock_outline, color: Colors.white24, size: 28))
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
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          if (piece.isRevealed) ...[
            PieceThumbnailWidget(piece: piece.piece, size: 128),
            const SizedBox(height: 16),
            Text(piece.ownerName,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
