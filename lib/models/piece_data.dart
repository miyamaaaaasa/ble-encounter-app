import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 16×16 ドット絵ピース
class PieceData {
  static const gridSize   = 16;
  static const pixelCount = gridSize * gridSize; // 256
  static const transparent = 15; // パレット15番 = 透明（背景色で表示）

  // 固定16色パレット
  static const palette = [
    Color(0xFF1A1A2E), //  0: 夜の紺
    Color(0xFF16213E), //  1: ディープブルー
    Color(0xFF0F3460), //  2: ロイヤルブルー
    Color(0xFF533483), //  3: パープル
    Color(0xFFE94560), //  4: 赤
    Color(0xFFFF8C42), //  5: オレンジ
    Color(0xFFFFD166), //  6: 黄
    Color(0xFF06D6A0), //  7: エメラルド
    Color(0xFF118AB2), //  8: シアン
    Color(0xFFFFFFFF), //  9: 白
    Color(0xFFAAAAAA), // 10: グレー
    Color(0xFF555555), // 11: 濃グレー
    Color(0xFF8B4513), // 12: 茶
    Color(0xFFFF69B4), // 13: ピンク
    Color(0xFF000000), // 14: 黒
    Color(0x00000000), // 15: 透明（背景色で表示）
  ];

  static Color paletteColor(int idx) => palette[idx.clamp(0, 15)];

  final List<int> pixels; // 256個 (0-15のインデックス)

  PieceData({List<int>? pixels})
      : pixels = pixels != null && pixels.length == pixelCount
            ? List<int>.from(pixels)
            : List.filled(pixelCount, transparent);

  PieceData.clone(PieceData src) : pixels = List<int>.from(src.pixels);

  int getPixel(int x, int y)          => pixels[y * gridSize + x];
  void setPixel(int x, int y, int c)  => pixels[y * gridSize + x] = c.clamp(0, 15);
  Color colorAt(int x, int y)         => paletteColor(getPixel(x, y));

  bool get isEmpty => pixels.every((p) => p == transparent);

  // JSON: List<int> として保存（Supabase JSONB対応）
  List<int> toJson() => List<int>.from(pixels);

  static PieceData fromJson(dynamic data) {
    if (data == null) return PieceData();
    try {
      final list = (data as List).map((e) => (e as num).toInt()).toList();
      return PieceData(pixels: list);
    } catch (_) {
      return PieceData();
    }
  }

  // ウィジェット描画用: ARGB Uint32List
  Uint32List toArgbList({Color? background}) {
    final bg = background?.value ?? 0xFF1A1A2E; // デフォルト: パレット0番
    final buf = Uint32List(pixelCount);
    for (int i = 0; i < pixelCount; i++) {
      final c = palette[pixels[i]];
      buf[i] = c.alpha == 0 ? bg : c.value;
    }
    return buf;
  }
}

/// 収集した他ユーザーのピース
class PuzzlePiece {
  final String   ownerId;
  final String   ownerName;
  final int      ownerColorIndex;
  final PieceData piece;
  final DateTime firstMetAt;
  final DateTime lastMetAt;
  final int      meetCount;
  final bool     isRevealed;

  const PuzzlePiece({
    required this.ownerId,
    required this.ownerName,
    required this.ownerColorIndex,
    required this.piece,
    required this.firstMetAt,
    required this.lastMetAt,
    required this.meetCount,
    required this.isRevealed,
  });

  PuzzlePiece copyWith({
    bool? isRevealed,
    DateTime? lastMetAt,
    int? meetCount,
    String? ownerName,
    PieceData? piece,
  }) => PuzzlePiece(
    ownerId:        ownerId,
    ownerName:      ownerName      ?? this.ownerName,
    ownerColorIndex: ownerColorIndex,
    piece:          piece          ?? this.piece,
    firstMetAt:     firstMetAt,
    lastMetAt:      lastMetAt      ?? this.lastMetAt,
    meetCount:      meetCount      ?? this.meetCount,
    isRevealed:     isRevealed     ?? this.isRevealed,
  );

  Map<String, dynamic> toMap() => {
    'oid':   ownerId,
    'onam':  ownerName,
    'ocol':  ownerColorIndex,
    'pix':   piece.toJson(),
    'fm':    firstMetAt.toIso8601String(),
    'lm':    lastMetAt.toIso8601String(),
    'mc':    meetCount,
    'rev':   isRevealed,
  };

  static PuzzlePiece fromMap(Map<String, dynamic> m) => PuzzlePiece(
    ownerId:        m['oid'] as String,
    ownerName:      m['onam'] as String? ?? '???',
    ownerColorIndex: (m['ocol'] as num?)?.toInt() ?? 0,
    piece:          PieceData.fromJson(m['pix']),
    firstMetAt:     DateTime.parse(m['fm'] as String),
    lastMetAt:      DateTime.parse(m['lm'] as String),
    meetCount:      (m['mc'] as num?)?.toInt() ?? 1,
    isRevealed:     m['rev'] as bool? ?? false,
  );
}
