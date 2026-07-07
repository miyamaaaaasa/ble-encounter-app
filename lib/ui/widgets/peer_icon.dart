import 'package:flutter/material.dart';
import '../../models/dot_avatar.dart';
import '../../models/encounter_record.dart';
import '../theme/palette.dart';

/// 相手ユーザーのアイコン共通コンポーネント。
///
/// 表示優先順位（本アプリ最大のUGC=ドット絵を主役にする）:
///  1. 相手が描いたドット絵（peerPixels・サーバー同期済みキャッシュ）
///  2. アバター画像URL（旧方式の互換）
///  3. パステル色サークル＋イニシャル
class PeerIcon extends StatelessWidget {
  final EncounterRecord encounter;
  final double size;

  /// true: 円形（リスト向け） / false: 角丸四角（ドット絵が映える）
  final bool circle;
  final double radius;
  final Border? border;

  /// 向き変更（広場の住民用）。ドット絵/画像のみ反転し、
  /// イニシャル文字は鏡文字にしない。
  final bool flipX;

  const PeerIcon({
    super.key,
    required this.encounter,
    this.size = 44,
    this.circle = true,
    this.radius = 12,
    this.border,
    this.flipX = false,
  });

  bool get hasDotArt =>
      encounter.peerPixels != null && encounter.peerPixels!.length == 256;

  @override
  Widget build(BuildContext context) {
    final color = Palette
        .pastelAvatars[encounter.colorIndex % Palette.pastelAvatars.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';

    Widget flip(Widget w) =>
        flipX ? Transform.flip(flipX: true, child: w) : w;

    Widget child;
    if (hasDotArt) {
      // ドット絵はにじませない・枠は白でレトロ感
      child = flip(DotAvatarView(
        avatar: DotAvatar(size: 16, pixels: encounter.peerPixels),
        sizePx: size,
        radius: circle ? size / 2 : radius,
        background: Palette.night
            ? const Color(0xFF3A415F)
            : const Color(0xFFF3E7D3),
      ));
    } else if (encounter.avatarUrl != null) {
      child = flip(ClipRRect(
        borderRadius: BorderRadius.circular(circle ? size / 2 : radius),
        child: Image.network(encounter.avatarUrl!,
            width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _initialCircle(color, initial)),
      ));
    } else {
      child = _initialCircle(color, initial);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(circle ? size / 2 : radius),
        border: border,
      ),
      child: child,
    );
  }

  Widget _initialCircle(Color color, String initial) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(circle ? size / 2 : radius),
        ),
        child: Center(
          child: Text(initial,
              style: TextStyle(
                  fontSize: size * 0.42,
                  color: Colors.white,
                  fontWeight: FontWeight.w800)),
        ),
      );
}
