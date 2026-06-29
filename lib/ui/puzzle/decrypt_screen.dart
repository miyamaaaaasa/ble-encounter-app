import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/piece_data.dart';
import '../../services/encounter_resolver.dart';
import '../../services/piece_storage.dart';
import 'puzzle_board_screen.dart';

/// ゲートの「電波解析」演出画面
class DecryptScreen extends StatefulWidget {
  const DecryptScreen({super.key});

  @override
  State<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends State<DecryptScreen>
    with TickerProviderStateMixin {
  late AnimationController _scanCtrl;
  late AnimationController _glitchCtrl;

  int    _progress    = 0;
  int    _total       = 0;
  int    _pieceCount  = 0;
  bool   _done        = false;
  String _statusText  = '初期化中...';

  static final _rng = Random();

  @override
  void initState() {
    super.initState();
    _scanCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _glitchCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100))..repeat();
    _startResolve();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _glitchCtrl.dispose();
    super.dispose();
  }

  Future<void> _startResolve() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _statusText = 'スキャンデータを読み込み中...');

    final pendingTokens = await PendingScanStorage.getAllTokens();
    if (!mounted) return;

    if (pendingTokens.isEmpty) {
      setState(() { _statusText = '未解析データなし'; _done = true; });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _navigateToBoard([]);
      return;
    }

    setState(() {
      _total      = pendingTokens.length;
      _statusText = 'サーバーに接続中... (${pendingTokens.length} 件)';
    });
    await Future.delayed(const Duration(milliseconds: 800));

    final results = await EncounterResolver.resolveAndCollect(
      onProgress: (current, total) {
        if (!mounted) return;
        setState(() {
          _progress  = current;
          _total     = total;
          _statusText = '解析中 [$current/$total]';
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _pieceCount = results.length;
      _done       = true;
      _statusText = _pieceCount > 0
          ? '解析完了！ ${_pieceCount}枚のカケラを入手'
          : '解析完了（新規カケラなし）';
    });

    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) _navigateToBoard(results);
  }

  void _navigateToBoard(List<PuzzlePiece> newPieces) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:      (_, __, ___) => PuzzleBoardScreen(highlightPieces: newPieces),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? _progress / _total : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF000811),
      body: Stack(
        children: [
          // 背景：流れるバイナリ
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glitchCtrl,
              builder: (_, __) => CustomPaint(painter: _GlitchBgPainter(_rng)),
            ),
          ),
          // スキャンライン
          AnimatedBuilder(
            animation: _scanCtrl,
            builder: (_, __) {
              final h = MediaQuery.of(context).size.height;
              return Positioned(
                top:   _scanCtrl.value * h,
                left:  0, right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      const Color(0xFF00FF88).withValues(alpha: 0.7),
                      Colors.transparent,
                    ]),
                  ),
                ),
              );
            },
          ),
          // メインUI
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // アイコン
                  AnimatedBuilder(
                    animation: _scanCtrl,
                    builder: (_, __) => Transform.rotate(
                      angle: _done ? 0 : _scanCtrl.value * 2 * pi,
                      child: Icon(
                        _done ? Icons.check_circle_outline : Icons.radar,
                        size: 72,
                        color: _done ? const Color(0xFF00FF88) : const Color(0xFF00AAFF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _glowText('電波解析', 24, const Color(0xFF00AAFF), letterSpacing: 8),
                  const SizedBox(height: 24),

                  // プログレス
                  if (_total > 0) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:           progress,
                        minHeight:       8,
                        backgroundColor: const Color(0xFF003322),
                        valueColor:      const AlwaysStoppedAnimation(Color(0xFF00FF88)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(color: Color(0xFF00FF88), fontSize: 14,
                          fontFamily: 'monospace', letterSpacing: 2),
                    ),
                  ] else
                    const SizedBox(width: 48, height: 48,
                        child: CircularProgressIndicator(color: Color(0xFF00AAFF), strokeWidth: 2)),

                  const SizedBox(height: 20),
                  Text(_statusText,
                    style: const TextStyle(color: Color(0xFF88CCFF), fontSize: 13, letterSpacing: 1),
                    textAlign: TextAlign.center),

                  if (_done && _pieceCount > 0) ...[
                    const SizedBox(height: 24),
                    _glowText('✨ ${_pieceCount}枚のカケラを入手 ✨', 16, const Color(0xFFFFD700)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowText(String text, double size, Color color, {double letterSpacing = 0}) {
    return Text(text, textAlign: TextAlign.center,
      style: TextStyle(
        color: color, fontSize: size, fontWeight: FontWeight.bold,
        letterSpacing: letterSpacing,
        shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 14)],
      ));
  }
}

class _GlitchBgPainter extends CustomPainter {
  final Random rng;
  _GlitchBgPainter(this.rng);

  @override
  void paint(Canvas canvas, Size size) {
    const chars = '01';
    final tp     = TextPainter(textDirection: TextDirection.ltr);
    const style  = TextStyle(color: Color(0x1100FF44), fontSize: 11, fontFamily: 'monospace');
    for (double y = 0; y < size.height; y += 16) {
      for (double x = 0; x < size.width; x += 10) {
        if (rng.nextDouble() > 0.25) continue;
        tp.text = TextSpan(text: chars[rng.nextInt(chars.length)], style: style);
        tp.layout();
        tp.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(_) => true;
}
