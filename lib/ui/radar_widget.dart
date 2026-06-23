import 'dart:math';
import 'package:flutter/material.dart';

// ミントグリーンのサイン波アニメーション（旧円形レーダー廃止・完全置き換え）
class WaveAnimation extends StatefulWidget {
  final double width;
  final double height;
  const WaveAnimation({super.key, this.width = 260, this.height = 56});

  @override
  State<WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<WaveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _WavePainter(_ctrl.value),
        size: Size(widget.width, widget.height),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  static const _mint = Color(0xFF4ECDC4);

  const _WavePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final amp  = size.height * 0.36;

    // 背面の薄い波（位相ずらし）
    _drawWave(
      canvas, size, midY, amp * 0.60, 2.5, progress + 0.28,
      Paint()
        ..color = _mint.withOpacity(0.20)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // メインの波（ミントグリーン）
    _drawWave(
      canvas, size, midY, amp, 2.0, progress,
      Paint()
        ..color = _mint
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawWave(Canvas canvas, Size size, double midY, double amplitude,
      double freq, double phase, Paint paint) {
    final path = Path();
    final w = size.width;
    bool first = true;
    for (double x = 0; x <= w; x += 1.5) {
      final y = midY + amplitude * sin(2 * pi * (freq * (x / w) - phase));
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}
