import 'package:flutter/material.dart';
import '../theme/palette.dart';

/// Material Card/AppBar/FAB を使わない独自UIキット。
/// 全画面がここの部品だけで組み立てられる。

// ─── パネル（厚みのある紙）────────────────────────────────────────────────
class SoftPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? shadowTint;
  final VoidCallback? onTap;
  final double radius;

  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.shadowTint,
    this.onTap,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Palette.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Palette.lift(shadowTint),
      ),
      child: child,
    );
    if (onTap == null) return panel;
    return _Pressable(onTap: onTap!, child: panel);
  }
}

// タップで沈み込む（ゲーム機ボタンの押し心地）
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: AnimatedSlide(
          offset: _down ? const Offset(0, 0.015) : Offset.zero,
          duration: const Duration(milliseconds: 80),
          child: widget.child,
        ),
      ),
    );
  }
}

// ─── ぽってりボタン ──────────────────────────────────────────────────────────
class ChunkyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? emoji;
  final Color? color;
  final Color? deepColor;
  final Color labelColor;
  final VoidCallback? onTap;
  final bool expand;

  const ChunkyButton({
    super.key,
    required this.label,
    this.icon,
    this.emoji,
    this.color,
    this.deepColor,
    this.labelColor = Colors.white,
    this.onTap,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final btn = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: enabled ? (color ?? Palette.coral) : Palette.inkFaint,
        borderRadius: BorderRadius.circular(26),
        boxShadow: enabled
            ? [
                BoxShadow(
                    color: deepColor ?? Palette.coralDeep,
                    offset: const Offset(0, 4))
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            Icon(icon, color: labelColor, size: 20),
            const SizedBox(width: 8),
          ],
          Text(label,
              style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.5)),
        ],
      ),
    );
    if (!enabled) return btn;
    return _Pressable(onTap: onTap!, child: btn);
  }
}

// ─── 丸アイコンボタン（ヘッダー右上など）────────────────────────────────────
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color ?? Palette.card,
          shape: BoxShape.circle,
          boxShadow: Palette.lift(),
        ),
        child: Icon(icon, size: 21, color: Palette.ink),
      ),
    );
  }
}

// ─── 画面ヘッダー（TopAppBarの代替）─────────────────────────────────────────
class ScreenHeader extends StatelessWidget {
  final String title;
  final String? emoji;
  final String? asset; // 正式ピクセルアイコン優先
  final Widget? trailing;
  final Widget? below;

  const ScreenHeader({
    super.key,
    required this.title,
    this.emoji,
    this.asset,
    this.trailing,
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (asset != null) ...[
                  Image.asset(asset!, width: 30, height: 30,
                      filterQuality: FilterQuality.medium),
                  const SizedBox(width: 8),
                ] else if (emoji != null) ...[
                  Text(emoji!, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(title, style: Ts.heading)),
                if (trailing != null) trailing!,
              ],
            ),
            if (below != null) ...[const SizedBox(height: 8), below!],
          ],
        ),
      ),
    );
  }
}

// ─── 吹き出し（しっぽ付き・CustomPainter）───────────────────────────────────
class SpeechBubble extends StatelessWidget {
  final String text;
  final Color color;
  final double maxWidth;

  const SpeechBubble({
    super.key,
    required this.text,
    this.color = Colors.white,
    this.maxWidth = 230,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(color: color, ink: Palette.ink),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Palette.ink),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  final Color color;
  final Color ink;
  _BubblePainter({required this.color, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    const tail = 8.0;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - tail),
      const Radius.circular(16),
    );
    final path = Path()
      ..addRRect(body)
      ..moveTo(size.width / 2 - 8, size.height - tail)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 8, size.height - tail)
      ..close();

    canvas.drawPath(
        path.shift(const Offset(0, 3)),
        Paint()..color = ink.withValues(alpha: 0.10));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.color != color;
}

// ─── 統計チップ ──────────────────────────────────────────────────────────────
class StatChip extends StatelessWidget {
  final String emoji;
  final String label;
  final Color? color;
  const StatChip({
    super.key,
    required this.emoji,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? Palette.creamDeep,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Palette.ink)),
        ],
      ),
    );
  }
}

// ─── セクション見出し ───────────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String emoji;
  final String text;
  final Widget? trailing;
  const SectionLabel(this.emoji, this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(text, style: Ts.title),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─── ゲーム機ドック（NavigationBarの代替）───────────────────────────────────
class DockItem {
  final String? asset;   // 正式ピクセルアイコン（assets/icons/）
  final Widget? custom;  // カスタムウィジェット（じぶんタブのドット絵など）
  final String label;
  const DockItem({this.asset, this.custom, required this.label})
      : assert(asset != null || custom != null);
}

class GameDock extends StatelessWidget {
  final List<DockItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const GameDock({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.circular(30),
          boxShadow: Palette.liftBig(),
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final sel = i == selected;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? Palette.coral.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: sel ? 1.22 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: items[i].custom ??
                              Image.asset(
                                items[i].asset!,
                                filterQuality: FilterQuality.medium,
                                // 非選択時は少し沈んだ色味に
                                color: sel
                                    ? null
                                    : Palette.inkSoft.withValues(alpha: 0.55),
                                colorBlendMode:
                                    sel ? null : BlendMode.srcATop,
                              ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                          color: sel ? Palette.coralDeep : Palette.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── 進捗バー（丸っこい）────────────────────────────────────────────────────
class CandyProgress extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final double height;
  const CandyProgress({
    super.key,
    required this.value,
    this.color,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: Palette.creamDeep,
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            widthFactor: value.clamp(0.0, 1.0),
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: color ?? Palette.sun,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
