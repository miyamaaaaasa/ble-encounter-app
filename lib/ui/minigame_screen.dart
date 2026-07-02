import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../models/encounter_record.dart';
import '../core/ble_config.dart';
import 'games/piece_puzzle.dart';
import 'games/tower_rpg.dart';
import 'games/aquarium.dart';
import 'theme/palette.dart';
import 'widgets/ui_kit.dart';

/// ミニゲーム = ゲーム機のメニュー画面。
/// 大きなカートリッジ風カードの横カルーセルで選ぶ。
class MinigameScreen extends ConsumerStatefulWidget {
  const MinigameScreen({super.key});

  @override
  ConsumerState<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends ConsumerState<MinigameScreen> {
  late final PageController _ctrl;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(viewportFraction: 0.78)
      ..addListener(() {
        if (mounted) setState(() => _page = _ctrl.page ?? 0);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    // 今日開封済みのすれ違いのみ（プライバシー保護: isRevealed必須）
    final todayRev = state.encounters
        .where((e) => e.isRevealed && e.metToday)
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));

    final List<EncounterRecord> gameEncounters;
    if (kDebugBle && todayRev.isEmpty) {
      gameEncounters =
          state.encounters.where((e) => e.isRevealed).take(10).toList();
    } else {
      gameEncounters = todayRev;
    }

    final games = [
      _GameDef(
        emoji: '🧩',
        title: 'ピース集めの旅',
        description: '出会った人からパズルのピースをもらおう。ホログラムの相手からはゴールドピースが手に入るかも！',
        colors: const [Color(0xFFFFB88C), Color(0xFFFF8A70)],
        tag: gameEncounters.isEmpty ? null : '${gameEncounters.length} 枚もらえる',
        builder: () => PiecePuzzleScreen(todayRevealed: gameEncounters),
      ),
      _GameDef(
        emoji: '⚔️',
        title: 'はじめましてタワーRPG',
        description: '今日出会った人が勇者として参戦！紙質に応じてスキルが変わるタワー突破バトル。',
        colors: const [Color(0xFFA88FE0), Color(0xFF8368C9)],
        tag: gameEncounters.isEmpty ? null : '勇者 ${gameEncounters.length} 人',
        builder: () => TowerRpgScreen(todayRevealed: gameEncounters),
      ),
      _GameDef(
        emoji: '🐟',
        title: 'すれちがい水族館',
        description: 'すれ違った人の地域の魚が池に放流される！タップして釣り上げ、図鑑を埋めよう。',
        colors: const [Color(0xFF80CFEE), Color(0xFF5FA8DC)],
        tag: gameEncounters.isEmpty ? null : '今日 ${gameEncounters.length} 匹放流',
        builder: () => AquariumScreen(todayRevealed: gameEncounters),
      ),
    ];

    return Container(
      color: Palette.cream,
      child: Column(
        children: [
          ScreenHeader(
            title: 'ゲームセンター',
            asset: 'assets/icons/tab_game.png',
            trailing: gameEncounters.isNotEmpty
                ? StatChip(
                    emoji: '🧑‍🤝‍🧑',
                    label: '今日の仲間 ${gameEncounters.length}人',
                    color: Palette.sun.withValues(alpha: 0.3))
                : null,
          ),

          // 仲間の顔ぶれ
          if (gameEncounters.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: gameEncounters.length,
                itemBuilder: (ctx, i) {
                  final e = gameEncounters[i];
                  final initial =
                      e.name.isNotEmpty ? e.name.characters.first : '?';
                  final color = Palette.pastelAvatars[
                      e.colorIndex % Palette.pastelAvatars.length];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: color,
                      backgroundImage: e.avatarUrl != null
                          ? NetworkImage(e.avatarUrl!)
                          : null,
                      child: e.avatarUrl == null
                          ? Text(initial,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold))
                          : null,
                    ),
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SoftPanel(
                color: Palette.creamDeep,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text('💡', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '「今日」タブで出会いを確認すると、その人たちと一緒に遊べるよ',
                        style: TextStyle(fontSize: 12, color: Palette.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── カートリッジカルーセル ─────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              itemCount: games.length,
              itemBuilder: (ctx, i) {
                final dist = (i - _page).abs();
                final scale = (1.0 - dist * 0.08).clamp(0.85, 1.0);
                return Transform.scale(
                  scale: scale,
                  child: _GameCartridge(
                    def: games[i],
                    onPlay: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => games[i].builder()),
                    ),
                  ),
                );
              },
            ),
          ),

          // ページドット
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(games.length, (i) {
                final sel = _page.round() == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: sel ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: sel ? Palette.coral : Palette.inkFaint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameDef {
  final String emoji;
  final String title;
  final String description;
  final List<Color> colors;
  final String? tag;
  final Widget Function() builder;
  const _GameDef({
    required this.emoji,
    required this.title,
    required this.description,
    required this.colors,
    this.tag,
    required this.builder,
  });
}

// ─── ゲームカートリッジ ──────────────────────────────────────────────────────
class _GameCartridge extends StatelessWidget {
  final _GameDef def;
  final VoidCallback onPlay;
  const _GameCartridge({required this.def, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: def.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: def.colors.last.withValues(alpha: 0.45),
              offset: const Offset(0, 6),
              blurRadius: 14,
            ),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // カートリッジの持ち手風ライン
            Container(
              width: 60,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const Spacer(),
            Text(def.emoji, style: const TextStyle(fontSize: 84)),
            const SizedBox(height: 16),
            Text(
              def.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              def.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.9)),
            ),
            if (def.tag != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(def.tag!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ChunkyButton(
                label: 'あそぶ！',
                emoji: '▶️',
                color: Colors.white,
                deepColor: Colors.black.withValues(alpha: 0.15),
                labelColor: def.colors.last,
                onTap: onPlay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
