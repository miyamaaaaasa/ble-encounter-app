import 'package:flutter/material.dart';
import '../../models/dot_avatar.dart';

/// アプリ全体で使う「じぶんアイコン」共通コンポーネント。
///
/// 表示優先順位:
///  1. ユーザー作成ドット絵（DotAvatarStorage）
///  2. デフォルトドット絵（ニコちゃん）
///
/// DotAvatarStorage.save() で保存すると全 UserIcon が即時更新される。
class UserIcon extends StatelessWidget {
  final double size;
  final double radius;
  final Color background;

  const UserIcon({
    super.key,
    this.size = 32,
    this.radius = 8,
    this.background = const Color(0xFFF3E7D3),
  });

  @override
  Widget build(BuildContext context) {
    OwnAvatarNotifier.ensureLoaded();
    return ValueListenableBuilder<DotAvatar?>(
      valueListenable: OwnAvatarNotifier.instance,
      builder: (_, avatar, __) {
        final a = (avatar != null && !avatar.isEmpty)
            ? avatar
            : OwnAvatarNotifier.defaultFace;
        return DotAvatarView(
            avatar: a, sizePx: size, radius: radius, background: background);
      },
    );
  }
}

/// 自分のドット絵アイコンをアプリ全体へ配信する ValueNotifier。
class OwnAvatarNotifier {
  OwnAvatarNotifier._();

  static final instance = ValueNotifier<DotAvatar?>(null);
  static bool _loaded = false;

  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    DotAvatarStorage.load().then((a) => instance.value = a);
  }

  /// 保存時に呼ぶ（AvatarEditorScreen から）
  static void update(DotAvatar avatar) => instance.value = avatar;

  /// デフォルトのドット絵ニコちゃん（絵文字ではなくドット絵文化に沿う）
  static final DotAvatar defaultFace = _buildDefaultFace();

  static DotAvatar _buildDefaultFace() {
    // 16x16 シンプルなスマイル。6=黄, 14=黒, 15=透明
    const t = 15, y = 6, k = 14;
    const rows = <List<int>>[
      [t, t, t, t, t, y, y, y, y, y, y, t, t, t, t, t],
      [t, t, t, y, y, y, y, y, y, y, y, y, y, t, t, t],
      [t, t, y, y, y, y, y, y, y, y, y, y, y, y, t, t],
      [t, y, y, y, y, y, y, y, y, y, y, y, y, y, y, t],
      [t, y, y, y, y, y, y, y, y, y, y, y, y, y, y, t],
      [y, y, y, y, k, k, y, y, y, y, k, k, y, y, y, y],
      [y, y, y, y, k, k, y, y, y, y, k, k, y, y, y, y],
      [y, y, y, y, y, y, y, y, y, y, y, y, y, y, y, y],
      [y, y, y, y, y, y, y, y, y, y, y, y, y, y, y, y],
      [y, y, y, k, y, y, y, y, y, y, y, y, k, y, y, y],
      [t, y, y, y, k, y, y, y, y, y, y, k, y, y, y, t],
      [t, y, y, y, y, k, k, k, k, k, k, y, y, y, y, t],
      [t, t, y, y, y, y, y, y, y, y, y, y, y, y, t, t],
      [t, t, t, y, y, y, y, y, y, y, y, y, y, t, t, t],
      [t, t, t, t, t, y, y, y, y, y, y, t, t, t, t, t],
      [t, t, t, t, t, t, t, t, t, t, t, t, t, t, t, t],
    ];
    return DotAvatar(
        size: 16, pixels: [for (final r in rows) ...r]);
  }
}
