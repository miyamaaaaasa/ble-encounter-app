import 'package:flutter/material.dart';

/// 「人と出会うことが楽しいコミュニティゲーム」デザインシステム。
///
/// コンセプト: レトロゲーム機の温かさ × パステルの柔らかさ × 手作り感。
/// Material Design から脱却し、全画面がこのパレットを参照する。
class Palette {
  Palette._();

  // ─── ベース（クリーム色の世界）──────────────────────────────
  static const cream      = Color(0xFFFBF3E4); // 画面の地：温かい紙
  static const creamDeep  = Color(0xFFF3E7D3); // 一段沈んだ面
  static const card       = Color(0xFFFFFDF8); // パネル面
  static const ink        = Color(0xFF4A3C31); // 文字：焦げ茶（黒を使わない）
  static const inkSoft    = Color(0xFF8A7A6B); // 補助文字
  static const inkFaint   = Color(0xFFBFB0A0); // 最弱文字・罫線

  // ─── アクセント（おもちゃ箱）────────────────────────────────
  static const coral      = Color(0xFFFF8A70); // メイン：出会いの温度
  static const coralDeep  = Color(0xFFE96D52);
  static const teal       = Color(0xFF5FC9B5); // サブ：電波・スキャン
  static const tealDeep   = Color(0xFF3FA894);
  static const sun        = Color(0xFFFFC85C); // 収集・報酬
  static const sunDeep    = Color(0xFFE8A93B);
  static const lavender   = Color(0xFFB89FE3); // バッジ・レア
  static const lavenderDeep = Color(0xFF9678CC);
  static const sky        = Color(0xFF7FB5EE); // 情報
  static const pinkSoft   = Color(0xFFFFB3C7);

  // ─── 夜（カケラ収集の世界だけは夜空のまま）─────────────────
  static const night      = Color(0xFF171B2E);
  static const nightCard  = Color(0xFF232A45);
  static const nightGlow  = Color(0xFF6FD8FF);

  // アバター用パステル 6色（従来のavatarColorsより柔らかく）
  static const pastelAvatars = [
    Color(0xFFF89A8C), Color(0xFF7CC7A8), Color(0xFFF3B562),
    Color(0xFF92A8E8), Color(0xFFC79BE0), Color(0xFFEE95B7),
  ];

  /// パネルの「置いてある」影（手作りおもちゃの厚み）
  static List<BoxShadow> lift([Color? tint]) => [
        BoxShadow(
          color: (tint ?? ink).withValues(alpha: 0.10),
          offset: const Offset(0, 4),
          blurRadius: 0, // にじまない影＝ゲーム機らしさ
        ),
      ];

  static List<BoxShadow> liftBig([Color? tint]) => [
        BoxShadow(
          color: (tint ?? ink).withValues(alpha: 0.14),
          offset: const Offset(0, 6),
          blurRadius: 0,
        ),
      ];
}

/// テキストスタイル（丸ゴシック的な太さ設計）
class Ts {
  Ts._();
  static const heading = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w800, color: Palette.ink, height: 1.2);
  static const title = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w700, color: Palette.ink);
  static const body = TextStyle(fontSize: 13.5, color: Palette.ink, height: 1.45);
  static const caption = TextStyle(fontSize: 11.5, color: Palette.inkSoft);
  static const tiny = TextStyle(fontSize: 10, color: Palette.inkFaint);
}
