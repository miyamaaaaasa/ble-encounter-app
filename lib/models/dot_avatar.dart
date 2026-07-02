import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'piece_data.dart';

/// ドット絵アバター（16x16 / 32x32）。
/// 画像アイコンに代わる自作アイコン。パレットは PieceData と共通。
class DotAvatar {
  final int size; // 16 or 32
  final List<int> pixels; // size*size, 0-15 (15=透明)

  DotAvatar({this.size = 16, List<int>? pixels})
      : pixels = (pixels != null && pixels.length == size * size)
            ? List<int>.from(pixels)
            : List.filled(size * size, PieceData.transparent);

  DotAvatar.clone(DotAvatar src)
      : size = src.size,
        pixels = List<int>.from(src.pixels);

  int getPixel(int x, int y) => pixels[y * size + x];
  void setPixel(int x, int y, int c) => pixels[y * size + x] = c.clamp(0, 15);

  bool get isEmpty => pixels.every((p) => p == PieceData.transparent);

  /// 塗りつぶし（同色領域をflood fill）
  void fill(int x, int y, int color) {
    final target = getPixel(x, y);
    if (target == color) return;
    final stack = <(int, int)>[(x, y)];
    while (stack.isNotEmpty) {
      final (cx, cy) = stack.removeLast();
      if (cx < 0 || cx >= size || cy < 0 || cy >= size) continue;
      if (getPixel(cx, cy) != target) continue;
      setPixel(cx, cy, color);
      stack.addAll([(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]);
    }
  }

  Map<String, dynamic> toMap() => {'s': size, 'p': pixels};

  static DotAvatar fromMap(Map<String, dynamic> m) {
    final s = (m['s'] as num?)?.toInt() ?? 16;
    final p = (m['p'] as List?)?.map((e) => (e as num).toInt()).toList();
    return DotAvatar(size: s, pixels: p);
  }
}

/// ドット絵アバターのローカル永続化
class DotAvatarStorage {
  static const _key = 'dot_avatar_v1';

  static Future<DotAvatar?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json == null) return null;
      return DotAvatar.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(DotAvatar avatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(avatar.toMap()));
  }
}

/// ドット絵アバターの表示ウィジェット（全画面共通で使う）
class DotAvatarView extends StatelessWidget {
  final DotAvatar avatar;
  final double sizePx;
  final Color background;
  final double radius;

  const DotAvatarView({
    super.key,
    required this.avatar,
    this.sizePx = 48,
    this.background = const Color(0xFFF3E7D3),
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        size: Size.square(sizePx),
        painter: _DotPainter(avatar: avatar, bg: background),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  final DotAvatar avatar;
  final Color bg;
  _DotPainter({required this.avatar, required this.bg});

  @override
  void paint(Canvas canvas, Size size) {
    final n = avatar.size;
    final cell = size.width / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final paint = Paint();
    for (int y = 0; y < n; y++) {
      for (int x = 0; x < n; x++) {
        final idx = avatar.getPixel(x, y);
        if (idx == PieceData.transparent) continue;
        paint.color = PieceData.paletteColor(idx);
        // わずかに重ねて描き、セル間の隙間線を防ぐ
        canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) =>
      old.avatar != avatar || old.bg != bg;
}
