import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/palette.dart';

/// Scenery follows local day/night, independently of the user's UI theme.
/// The landscape is a provisional flattened middle layer; sky and flowers
/// are separate Canvas layers, ready for replacement by approved pixel assets.
class PixelWorld extends StatelessWidget {
  final Widget child;
  final double offset;
  final double strength;
  final bool? night;
  final int richness;
  const PixelWorld(
      {super.key,
      required this.child,
      this.offset = 0,
      this.strength = 1,
      this.night,
      this.richness = 1});

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final dark = night ?? (h < 6 || h >= 18);
    final delta = (offset * strength).clamp(-50.0, 50.0);
    return ClipRect(
        child: Stack(children: [
      Positioned.fill(
          child: Transform.translate(
              offset: Offset(0, delta * .08),
              child: CustomPaint(painter: _Sky(dark)))),
      Positioned.fill(
          child: Transform.translate(
              offset: Offset(0, delta * .24),
              child: Image.asset(
                  dark
                      ? 'assets/today/plaza_dark.png'
                      : 'assets/today/plaza_light.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none))),
      Positioned.fill(
          child: Transform.translate(
              offset: Offset(0, delta * .55),
              child: IgnorePointer(
                  child: CustomPaint(painter: _Flowers(dark, richness))))),
      child,
    ]));
  }
}

class WorldPage extends StatefulWidget {
  final Widget child;
  final double strength;
  const WorldPage({super.key, required this.child, this.strength = .3});
  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  double _offset = 0;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
            setState(() => _offset = n.metrics.pixels);
          }
          return false;
        },
        child: PixelWorld(
            offset: _offset,
            strength: widget.strength,
            child: ColoredBox(
                color: Palette.cream.withValues(alpha: .88),
                child: widget.child)),
      );
}

class PixelPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PixelPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: Palette.card,
            border: Border.all(color: Palette.inkFaint, width: 2),
            borderRadius: BorderRadius.circular(8)),
        child: child,
      );
}

class _Sky extends CustomPainter {
  final bool night;
  _Sky(this.night);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(
        Offset.zero & s,
        Paint()
          ..color = night ? const Color(0xff152943) : const Color(0xff9bdff1));
    if (night) {
      final p = Paint()..color = const Color(0xffffe6a1);
      for (var i = 0; i < 24; i++) {
        c.drawRect(
            Rect.fromLTWH((i * 67 % 97) / 97 * s.width,
                (i * 31 % 53) / 150 * s.height, 2, 2),
            p);
      }
    }
  }

  @override
  bool shouldRepaint(_Sky old) => old.night != night;
}

class _Flowers extends CustomPainter {
  final bool night;
  final int richness;
  _Flowers(this.night, this.richness);
  @override
  void paint(Canvas c, Size s) {
    final count = 12 + richness * 6;
    for (var i = 0; i < count; i++) {
      final x = i.isEven ? 6.0 + i % 4 * 7 : s.width - 12 - i % 4 * 7;
      final y = s.height * .65 + i / count * s.height * .34;
      final p = Paint()
        ..color = [Palette.sun, Palette.coral, Palette.lavender][i % 3]
            .withValues(alpha: night ? .7 : .9);
      c.drawRect(Rect.fromLTWH(x, y, 4, 12), p);
      c.drawRect(Rect.fromLTWH(x - 4, y + 4, 12, 4), p);
    }
    if (richness >= 3) {
      for (final x in [16.0, s.width - 20]) {
        c.drawRect(Rect.fromLTWH(x, s.height * .52, 4, 20),
            Paint()..color = Palette.sun);
      }
    }
    if (richness >= 5) {
      for (var i = 0; i < 9; i++) {
        c.drawRect(
            Rect.fromLTWH(
                s.width * .12 + s.width * .085 * i, s.height * .12, 8, 12),
            Paint()..color = [Palette.coral, Palette.sun, Palette.sky][i % 3]);
      }
    }
  }

  @override
  bool shouldRepaint(_Flowers old) =>
      old.night != night || old.richness != richness;
}

/// Provisional door art. Motion is real geometry, not text or a sound imitation.
class PixelDoor extends StatelessWidget {
  final double open;
  const PixelDoor({super.key, this.open = 0});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _Door(open), size: const Size(140, 170));
}

class _Door extends CustomPainter {
  final double open;
  _Door(this.open);
  @override
  void paint(Canvas c, Size s) {
    final frame = Paint()..color = const Color(0xffbfa67a);
    final door = Paint()..color = const Color(0xff345b5d);
    final light = Paint()
      ..color = const Color(0xffffefad).withValues(alpha: open);
    c.drawRect(Rect.fromLTWH(12, 18, s.width - 24, s.height - 18), light);
    c.drawRect(Rect.fromLTWH(0, 12, 12, s.height - 12), frame);
    c.drawRect(Rect.fromLTWH(s.width - 12, 12, 12, s.height - 12), frame);
    c.drawRect(Rect.fromLTWH(12, 0, s.width - 24, 18), frame);
    final w = (s.width / 2 - 12) * (1 - open);
    c.drawRect(Rect.fromLTWH(12, 18, w, s.height - 18), door);
    c.drawRect(Rect.fromLTWH(s.width - 12 - w, 18, w, s.height - 18), door);
    final grain = Paint()..color = const Color(0xff446d66);
    for (var plank = 0; plank < 4; plank++) {
      final x = 12 + plank * w / 4;
      c.drawRect(Rect.fromLTWH(x, 22, w / 8, s.height - 26), grain);
      c.drawRect(
          Rect.fromLTWH(s.width - x - w / 8, 22, w / 8, s.height - 26), grain);
    }
    if (w > 8) {
      c.drawRect(Rect.fromLTWH(12 + w - 4, 18, 2, s.height - 18), frame);
      c.drawRect(
          Rect.fromLTWH(s.width - 12 - w + 2, 18, 2, s.height - 18), frame);
      c.drawRect(Rect.fromLTWH(12 + w - 10, 94, 6, 6), frame);
      c.drawRect(Rect.fromLTWH(s.width - 12 - w + 4, 94, 6, 6), frame);
    }
    for (var j = 1; j < 4; j++) {
      c.drawRect(Rect.fromLTWH(12, j * 36.0, w, 4), frame);
      c.drawRect(Rect.fromLTWH(s.width - 12 - w, j * 36.0, w, 4), frame);
    }
  }

  @override
  bool shouldRepaint(_Door old) => old.open != open;
}

class Celebration extends CustomPainter {
  final int count;
  final double progress;
  Celebration(this.count, this.progress);
  @override
  void paint(Canvas c, Size s) {
    if (count == 0 || progress >= 1) return;
    final p = Paint();
    final colors = [Palette.sun, Palette.coral, Palette.sky, Palette.lavender];
    final n = count >= 20
        ? 72
        : count >= 10
            ? 40
            : count >= 5
                ? 24
                : 12;
    for (var i = 0; i < n; i++) {
      p.color = colors[i % 4].withValues(alpha: 1 - progress);
      final angle = i * 2 * pi / n;
      final fireworks = count >= 20;
      final crackers = count >= 5 && count < 10;
      final x = fireworks
          ? s.width * (i.isEven ? .25 : .75) + cos(angle) * progress * 120
          : crackers
              ? s.width * (i.isEven ? .1 : .9) + cos(angle) * progress * 90
              : (i * 37 % 100) / 100 * s.width;
      final y = fireworks
          ? s.height * .2 + sin(angle) * progress * 120
          : crackers
              ? s.height * .3 - sin(angle).abs() * progress * 100
              : s.height * progress * .65 + i % 5 * 12;
      c.drawRect(Rect.fromLTWH(x, y, count < 5 ? 4 : 5, count < 5 ? 4 : 9), p);
      if (count < 5) c.drawRect(Rect.fromLTWH(x - 3, y + 1, 10, 2), p);
    }
  }

  @override
  bool shouldRepaint(Celebration old) =>
      old.progress != progress || old.count != count;
}
