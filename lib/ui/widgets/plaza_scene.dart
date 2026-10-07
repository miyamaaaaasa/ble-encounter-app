import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/encounter_record.dart';
import '../theme/palette.dart';
import 'peer_icon.dart';
import 'pixel_world.dart';
import 'sorapi.dart';
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
  // 新規住民フェードイン: 前回表示していた住民ID
  Set<String> _knownIds = {};
  final Set<String> _fadingIn = {};

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _knownIds = widget.residents.take(8).map((e) => e.peerId).toSet();
    _scheduleTalk();
  }

  @override
  void didUpdateWidget(PlazaScene old) {
    super.didUpdateWidget(old);
    // 新しく広場に来た住民をふわっと登場させる（過剰演出はしない）
    final current = widget.residents.take(8).map((e) => e.peerId).toSet();
    final newcomers = current.difference(_knownIds);
    if (newcomers.isNotEmpty && _knownIds.isNotEmpty) {
      setState(() => _fadingIn.addAll(newcomers));
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _fadingIn.removeAll(newcomers));
      });
    }
    _knownIds = current;
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
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 400,
            width: double.infinity,
            child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                      children: [
                        // 背景（レベルで発展）
                        Positioned.fill(
                          child: PixelWorld(
                              richness: level.level,
                              child: const SizedBox.expand()),
                        ),

                        // 住民たち（後列4人・前列4人）
                        ...List.generate(shown.length, (i) {
                          final backRow = i >= 4;
                          final col = i % 4;
                          final seed = shown[i].peerId.hashCode;
                          final jitter = (seed % 17) / 17.0 * 0.08 - 0.04;
                          final xFrac = (col / 3 + jitter).clamp(0.0, 1.0);
                          final bottom = backRow ? 180.0 : 100.0;
                          final size = backRow ? 48.0 : 60.0;
                          // 向き変更: seedで左右どちらを向くか（ゆらぎで時々反転）
                          final faceLeft = seed % 2 == 0;

                          return AnimatedBuilder(
                            animation: _bob,
                            builder: (_, child) {
                              final dy =
                                  sin(_bob.value * 2 * pi + i * 0.9) * 2.2;
                              return Positioned(
                                left:
                                    xFrac * max(0, constraints.maxWidth - 110),
                                bottom: bottom - dy,
                                child: child!,
                              );
                            },
                            child: AnimatedOpacity(
                              // 新規住民はふわっと現れる
                              opacity: _fadingIn.contains(shown[i].peerId)
                                  ? 0.15
                                  : 1.0,
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOut,
                              child: _Resident(
                                encounter: shown[i],
                                size: size,
                                faceLeft: faceLeft,
                                talking: i == _talkerIdx,
                                onTap: () => widget.onTapResident(shown[i]),
                              ),
                            ),
                          );
                        }),

                        const Positioned(
                            right: 6,
                            bottom: 16,
                            child: IgnorePointer(
                                child: Sorapi(size: 62, mood: SorapiMood.sit))),

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
                    )),
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
          Text('広場は最高レベルです！', style: Ts.caption),
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
    return Semantics(
        button: true,
        label: encounter.name,
        child: GestureDetector(
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
              // 体: ドット絵住民（白枠の角丸ドット絵。向きはPeerIcon側で安全に反転）
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(size * 0.28),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: PeerIcon(
                  encounter: encounter,
                  size: size - 4,
                  circle: false,
                  radius: size * 0.22,
                  flipX: faceLeft,
                ),
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
        ));
  }
}
