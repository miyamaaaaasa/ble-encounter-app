import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/encounter_record.dart';
import '../theme/palette.dart';
import 'ui_kit.dart';
import 'user_icon.dart';

/// 広場レベル: 出会った人数で広場が発展していく。
class PlazaLevel {
  final int level;
  final String name;
  final int threshold; // このレベルの開始人数
  const PlazaLevel(this.level, this.name, this.threshold);

  static const levels = [
    PlazaLevel(1, 'はじまりの広場', 0),
    PlazaLevel(2, 'ちいさな広場', 5),
    PlazaLevel(3, 'にぎやかな広場', 15),
    PlazaLevel(4, 'みんなの公園', 50),
    PlazaLevel(5, '思い出の街', 100),
    PlazaLevel(6, 'お祭り広場', 250),
  ];

  static PlazaLevel of(int total) =>
      levels.lastWhere((l) => total >= l.threshold);

  static PlazaLevel? next(int total) {
    final cur = of(total);
    final idx = levels.indexOf(cur);
    return idx + 1 < levels.length ? levels[idx + 1] : null;
  }
}

/// 「今まで出会った人たちが集まる空間」— 広場シーン。
/// 住民（出会った人）がぷるぷる待機し、ときどきおしゃべりする。
class PlazaScene extends StatefulWidget {
  final List<EncounterRecord> residents; // 最近の住民（表示は最大8人）
  final int totalCount;
  final void Function(EncounterRecord) onTapResident;

  const PlazaScene({
    super.key,
    required this.residents,
    required this.totalCount,
    required this.onTapResident,
  });

  @override
  State<PlazaScene> createState() => _PlazaSceneState();
}

class _PlazaSceneState extends State<PlazaScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob;
  int _talkerIdx = -1; // いまおしゃべり中の住民
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _scheduleTalk();
  }

  void _scheduleTalk() {
    Future.delayed(Duration(milliseconds: 3500 + _rng.nextInt(2500)), () {
      if (!mounted) return;
      setState(() {
        _talkerIdx = widget.residents.isEmpty
            ? -1
            : _rng.nextInt(min(widget.residents.length, 8));
      });
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _talkerIdx = -1);
        if (mounted) _scheduleTalk();
      });
    });
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = PlazaLevel.of(widget.totalCount);
    final next = PlazaLevel.next(widget.totalCount);
    final progress = next == null
        ? 1.0
        : (widget.totalCount - level.threshold) /
            (next.threshold - level.threshold);
    final shown = widget.residents.take(8).toList();

    return Column(
      children: [
        // ─── 広場シーン ───────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 230,
            width: double.infinity,
            child: Stack(
              children: [
                // 背景（レベルで発展）
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PlazaBgPainter(
                        level: level.level, night: Palette.night),
                  ),
                ),

                // 住民たち（後列4人・前列4人）
                ...List.generate(shown.length, (i) {
                  final backRow = i >= 4;
                  final col = i % 4;
                  final seed = shown[i].peerId.hashCode;
                  final jitter = (seed % 17) / 17.0 * 0.08 - 0.04;
                  final xFrac =
                      0.13 + col * 0.24 + (backRow ? 0.10 : 0) + jitter;
                  final bottom = backRow ? 92.0 : 40.0;
                  final size = backRow ? 40.0 : 52.0;
                  // 向き変更: seedで左右どちらを向くか（ゆらぎで時々反転）
                  final faceLeft = seed % 2 == 0;

                  return AnimatedBuilder(
                    animation: _bob,
                    builder: (_, child) {
                      final dy =
                          sin(_bob.value * 2 * pi + i * 0.9) * 2.2;
                      return Positioned(
                        left: xFrac * (MediaQuery.of(context).size.width - 40),
                        bottom: bottom - dy,
                        child: child!,
                      );
                    },
                    child: _Resident(
                      encounter: shown[i],
                      size: size,
                      faceLeft: faceLeft,
                      talking: i == _talkerIdx,
                      onTap: () => widget.onTapResident(shown[i]),
                    ),
                  );
                }),

                // じぶん（中央手前）
                AnimatedBuilder(
                  animation: _bob,
                  builder: (_, child) {
                    final dy = sin(_bob.value * 2 * pi) * 2.0;
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14 - dy,
                      child: child!,
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const UserIcon(size: 44, radius: 12),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('じぶん',
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),

                // レベル名（左上）
                Positioned(
                  top: 10,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Lv.${level.level} ${level.name}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ─── 発展プログレス ───────────────────────────────────
        if (next != null)
          Row(
            children: [
              Expanded(child: CandyProgress(value: progress, height: 10)),
              const SizedBox(width: 10),
              Text('つぎ: ${next.name}', style: Ts.tiny),
            ],
          )
        else
          Text('🎆 広場は最高レベルです！', style: Ts.caption),
      ],
    );
  }
}

// ─── 住民1人 ─────────────────────────────────────────────────────────────────
class _Resident extends StatelessWidget {
  final EncounterRecord encounter;
  final double size;
  final bool faceLeft;
  final bool talking;
  final VoidCallback onTap;

  const _Resident({
    required this.encounter,
    required this.size,
    required this.faceLeft,
    required this.talking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        Palette.pastelAvatars[encounter.colorIndex % Palette.pastelAvatars.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // おしゃべり吹き出し
          AnimatedOpacity(
            opacity: talking ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              constraints: const BoxConstraints(maxWidth: 110),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Text(
                encounter.template.phraseText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A3C31)),
              ),
            ),
          ),
          // 体（向き変更は画像アバターのみ反転。文字は鏡文字にしない）
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: encounter.avatarUrl != null
                ? Transform.flip(
                    flipX: faceLeft,
                    child: Image.network(encounter.avatarUrl!,
                        fit: BoxFit.cover),
                  )
                : Center(
                    child: Text(initial,
                        style: TextStyle(
                            fontSize: size * 0.42,
                            color: Colors.white,
                            fontWeight: FontWeight.w800))),
          ),
          // 足元の影
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: size * 0.55,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 広場背景（レベルで発展）──────────────────────────────────────────────────
class _PlazaBgPainter extends CustomPainter {
  final int level;
  final bool night;
  _PlazaBgPainter({required this.level, required this.night});

  @override
  void paint(Canvas canvas, Size size) {
    // 空
    final skyColors = night
        ? [const Color(0xFF232B52), const Color(0xFF171B2E)]
        : switch (level) {
            <= 2 => [const Color(0xFFBFE3F5), const Color(0xFFE8F4E4)],
            <= 4 => [const Color(0xFFA9DBF2), const Color(0xFFDFF2D8)],
            _ => [const Color(0xFFFFD9A0), const Color(0xFFFFEFD5)], // 祭りの夕焼け
          };
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
                colors: skyColors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter)
            .createShader(Offset.zero & size),
    );

    // 地面
    final groundY = size.height * 0.55;
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      Paint()
        ..color =
            night ? const Color(0xFF2A3352) : const Color(0xFFA8D08A),
    );
    // 地面の道
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.85),
          width: size.width * 0.7,
          height: size.height * 0.35),
      Paint()
        ..color =
            night ? const Color(0xFF3A4368) : const Color(0xFFE8D5A8),
    );

    final deco = Paint();
    // 木（Lv2+で増える）
    final trees = (level - 1).clamp(0, 4);
    for (int i = 0; i < trees; i++) {
      final x = size.width * (0.08 + i * 0.28);
      deco.color = night ? const Color(0xFF1E2540) : const Color(0xFF6B9B4E);
      canvas.drawCircle(Offset(x, groundY - 14), 16, deco);
      deco.color = night ? const Color(0xFF161A30) : const Color(0xFF8B5E3C);
      canvas.drawRect(Rect.fromLTWH(x - 2.5, groundY - 6, 5, 12), deco);
    }
    // 花（Lv3+）
    if (level >= 3) {
      final rng = Random(7);
      deco.color = night ? const Color(0xFF8FA3E8) : const Color(0xFFF9A8C0);
      for (int i = 0; i < level * 3; i++) {
        canvas.drawCircle(
            Offset(rng.nextDouble() * size.width,
                groundY + 8 + rng.nextDouble() * (size.height - groundY - 16)),
            2.4,
            deco);
      }
    }
    // ベンチ（Lv4+）
    if (level >= 4) {
      deco.color = night ? const Color(0xFF4A3A2A) : const Color(0xFF9B6B43);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(size.width * 0.78, groundY + 6, 40, 8),
              const Radius.circular(2)),
          deco);
      canvas.drawRect(
          Rect.fromLTWH(size.width * 0.78 + 4, groundY + 14, 4, 8), deco);
      canvas.drawRect(
          Rect.fromLTWH(size.width * 0.78 + 32, groundY + 14, 4, 8), deco);
    }
    // 提灯（Lv6 お祭り or 夜）
    if (level >= 6 || night) {
      final lanternColors = [
        const Color(0xFFFF8A70),
        const Color(0xFFFFC85C),
        const Color(0xFF5FC9B5),
        const Color(0xFFB89FE3),
      ];
      final ropeP = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(0, 18);
      path.quadraticBezierTo(size.width / 2, 44, size.width, 14);
      canvas.drawPath(path, ropeP);
      for (int i = 0; i < 6; i++) {
        final t = 0.08 + i * 0.17;
        final x = size.width * t;
        final y = 18 + (44 - 18) * 4 * t * (1 - t) + 6;
        deco.color = lanternColors[i % lanternColors.length];
        canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: 10, height: 13),
            deco);
      }
    }
    // 星（夜のみ）
    if (night) {
      final rng = Random(3);
      deco.color = Colors.white.withValues(alpha: 0.8);
      for (int i = 0; i < 18; i++) {
        canvas.drawCircle(
            Offset(rng.nextDouble() * size.width,
                rng.nextDouble() * groundY * 0.8),
            rng.nextDouble() * 1.3 + 0.4,
            deco);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PlazaBgPainter old) =>
      old.level != level || old.night != night;
}
