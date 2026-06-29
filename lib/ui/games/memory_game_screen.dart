import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piece_data.dart';
import '../../providers/puzzle_providers.dart';
import '../piece_editor/piece_editor_screen.dart';

class MemoryGameScreen extends ConsumerStatefulWidget {
  const MemoryGameScreen({super.key});

  @override
  ConsumerState<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends ConsumerState<MemoryGameScreen> {
  List<_Card> _cards = [];
  int? _firstFlip;
  int? _secondFlip;
  bool _checking = false;
  int _moves = 0;
  int _matched = 0;
  int _totalPairs = 0;

  @override
  void initState() {
    super.initState();
    _setupGame();
  }

  void _setupGame() {
    final pieces = ref.read(puzzleProvider).pieces
        .where((p) => p.isRevealed)
        .toList();

    if (pieces.isEmpty) return;

    final rng = Random();
    final selected = List<PuzzlePiece>.from(pieces)..shuffle(rng);
    final pairCount = min(selected.length, 6);
    final pairs = selected.take(pairCount).toList();

    _totalPairs = pairCount;
    _cards = [];
    for (final p in pairs) {
      _cards.add(_Card(piece: p, pairId: p.ownerId));
      _cards.add(_Card(piece: p, pairId: p.ownerId));
    }
    _cards.shuffle(rng);
    _moves = 0;
    _matched = 0;
    _firstFlip = null;
    _secondFlip = null;
    _checking = false;
  }

  void _onCardTap(int index) {
    if (_checking) return;
    if (_cards[index].isMatched || _cards[index].isFlipped) return;

    setState(() {
      _cards[index].isFlipped = true;

      if (_firstFlip == null) {
        _firstFlip = index;
      } else {
        _secondFlip = index;
        _moves++;
        _checking = true;
        _checkMatch();
      }
    });
  }

  Future<void> _checkMatch() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      if (_cards[_firstFlip!].pairId == _cards[_secondFlip!].pairId) {
        _cards[_firstFlip!].isMatched = true;
        _cards[_secondFlip!].isMatched = true;
        _matched++;
      } else {
        _cards[_firstFlip!].isFlipped = false;
        _cards[_secondFlip!].isFlipped = false;
      }
      _firstFlip = null;
      _secondFlip = null;
      _checking = false;
    });

    if (_matched == _totalPairs && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _showResult();
    }
  }

  void _showResult() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111122),
        title: const Text('クリア！', style: TextStyle(color: Colors.white)),
        content: Text(
          '$_moves手でクリアしました！',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(_setupGame);
            },
            child: const Text('もう一度'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('戻る'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A1A),
          foregroundColor: Colors.white,
          title: const Text('神経衰弱', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Text('カケラを集めてから遊べます',
              style: TextStyle(color: Colors.white38, fontSize: 15)),
        ),
      );
    }

    final crossCount = _cards.length <= 8 ? 3 : 4;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        foregroundColor: Colors.white,
        title: const Text('神経衰弱', style: TextStyle(color: Colors.white)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('$_moves手 | $_matched/$_totalPairs',
                  style: const TextStyle(color: Color(0xFF00AAFF), fontSize: 14)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_setupGame),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _cards.length,
          itemBuilder: (ctx, i) => _CardWidget(
            card: _cards[i],
            onTap: () => _onCardTap(i),
          ),
        ),
      ),
    );
  }
}

class _Card {
  final PuzzlePiece piece;
  final String pairId;
  bool isFlipped;
  bool isMatched;

  _Card({
    required this.piece,
    required this.pairId,
    this.isFlipped = false,
    this.isMatched = false,
  });
}

class _CardWidget extends StatelessWidget {
  final _Card card;
  final VoidCallback onTap;

  const _CardWidget({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: card.isFlipped || card.isMatched
              ? const Color(0xFF111122)
              : const Color(0xFF1A1A3E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: card.isMatched
                ? const Color(0xFF00FF88)
                : card.isFlipped
                    ? const Color(0xFF00AAFF)
                    : Colors.white10,
            width: card.isMatched ? 2 : 1,
          ),
          boxShadow: card.isMatched
              ? [BoxShadow(color: const Color(0xFF00FF88).withValues(alpha: 0.3), blurRadius: 8)]
              : null,
        ),
        child: card.isFlipped || card.isMatched
            ? ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: PieceThumbnailWidget(
                  piece: card.piece.piece,
                  size: double.infinity,
                ),
              )
            : const Center(
                child: Icon(Icons.help_outline, color: Colors.white24, size: 32),
              ),
      ),
    );
  }
}
