import 'package:flutter/material.dart';

/// 「人と出会うことが楽しいコミュニティゲーム」デザインシステム。
///
/// ライト = 昼の広場（クリーム色の紙の世界）
/// ダーク = 夜の広場（提灯が灯る夜のお祭り。単純な黒にしない）
///
/// [Palette.night] を切り替えると全getterが夜の広場パレットを返す。
/// テーマ変更時はアプリルートから再ビルドされる。
class Palette {
  Palette._();

  /// 現在夜モードかどうか（ThemeControllerが設定する）
  static bool night = false;

  // ─── ベース ──────────────────────────────────────────────
  static const _creamL = Color(0xFFFBF3E4);
  static const _creamN = Color(0xFF1B2035); // 夜の広場の空
  static Color get cream => night ? _creamN : _creamL;

  static const _creamDeepL = Color(0xFFF3E7D3);
  static const _creamDeepN = Color(0xFF262D4A);
  static Color get creamDeep => night ? _creamDeepN : _creamDeepL;

  static const _cardL = Color(0xFFFFFDF8);
  static const _cardN = Color(0xFF272E4E); // 夜店の屋台
  static Color get card => night ? _cardN : _cardL;

  static const _inkL = Color(0xFF4A3C31);
  static const _inkN = Color(0xFFF2EADA); // 提灯に照らされた温かい白
  static Color get ink => night ? _inkN : _inkL;

  static const _inkSoftL = Color(0xFF8A7A6B);
  static const _inkSoftN = Color(0xFFB1A995);
  static Color get inkSoft => night ? _inkSoftN : _inkSoftL;

  static const _inkFaintL = Color(0xFFBFB0A0);
  static const _inkFaintN = Color(0xFF5C6076);
  static Color get inkFaint => night ? _inkFaintN : _inkFaintL;

  // ─── アクセント（夜は提灯のように少し明るく）─────────────
  static Color get coral => night ? const Color(0xFFFF9C84) : const Color(0xFFFF8A70);
  static Color get coralDeep => night ? const Color(0xFFD86A50) : const Color(0xFFE96D52);
  static Color get teal => night ? const Color(0xFF6FDCC7) : const Color(0xFF5FC9B5);
  static Color get tealDeep => night ? const Color(0xFF4FB8A2) : const Color(0xFF3FA894);
  static Color get sun => night ? const Color(0xFFFFD470) : const Color(0xFFFFC85C);
  static Color get sunDeep => night ? const Color(0xFFE8B14A) : const Color(0xFFE8A93B);
  static Color get lavender => night ? const Color(0xFFC6AFF0) : const Color(0xFFB89FE3);
  static Color get lavenderDeep => night ? const Color(0xFFA588DB) : const Color(0xFF9678CC);
  static Color get sky => night ? const Color(0xFF8FC2F5) : const Color(0xFF7FB5EE);
  static Color get pinkSoft => night ? const Color(0xFFFFC1D2) : const Color(0xFFFFB3C7);

  // ─── 夜（カケラの夜空。モード非依存の固定世界観）─────────
  static const nightSky = Color(0xFF171B2E);
  static const nightCard = Color(0xFF232A45);
  static const nightGlow = Color(0xFF6FD8FF);

  // アバター用パステル 6色（両モード共通）
  static const pastelAvatars = [
    Color(0xFFF89A8C), Color(0xFF7CC7A8), Color(0xFFF3B562),
    Color(0xFF92A8E8), Color(0xFFC79BE0), Color(0xFFEE95B7),
  ];

  /// パネルの「置いてある」影（夜は深く落とす）
  static List<BoxShadow> lift([Color? tint]) => [
        BoxShadow(
          color: (tint ?? (night ? Colors.black : _inkL))
              .withValues(alpha: night ? 0.35 : 0.10),
          offset: const Offset(0, 4),
          blurRadius: 0,
        ),
      ];

  static List<BoxShadow> liftBig([Color? tint]) => [
        BoxShadow(
          color: (tint ?? (night ? Colors.black : _inkL))
              .withValues(alpha: night ? 0.45 : 0.14),
          offset: const Offset(0, 6),
          blurRadius: 0,
        ),
      ];
}

/// テキストスタイル（Palette.nightに追従する動的スタイル）
class Ts {
  Ts._();
  static TextStyle get heading => TextStyle(
      fontSize: 22, fontWeight: FontWeight.w800, color: Palette.ink, height: 1.2);
  static TextStyle get title =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.ink);
  static TextStyle get body =>
      TextStyle(fontSize: 13.5, color: Palette.ink, height: 1.45);
  static TextStyle get caption => TextStyle(fontSize: 11.5, color: Palette.inkSoft);
  static TextStyle get tiny => TextStyle(fontSize: 10, color: Palette.inkFaint);
}
