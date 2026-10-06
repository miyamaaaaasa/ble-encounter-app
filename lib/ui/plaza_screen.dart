import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'badge_screen.dart';
import 'community_tabs.dart';
import 'puzzle/puzzle_board_screen.dart';
import 'widgets/pixel_world.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import '../providers/puzzle_providers.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';
import 'theme/palette.dart';
import 'widgets/peer_icon.dart';
import 'widgets/plaza_scene.dart';
import 'widgets/ui_kit.dart';

// BGM トラック定義（音声ファイルは assets/bgm/ に配置してください）
String bgmTrackFor(int total) {
  if (total >= 10000) return 'bgm_10000.mp3';
  if (total >= 3000) return 'bgm_3000.mp3';
  if (total >= 1500) return 'bgm_1500.mp3';
  if (total >= 1000) return 'bgm_1000.mp3';
  if (total >= 500) return 'bgm_500.mp3';
  if (total >= 250) return 'bgm_250.mp3';
  if (total >= 100) return 'bgm_100.mp3';
  if (total >= 50) return 'bgm_50.mp3';
  return 'bgm_default.mp3';
}

/// 広場 = みんなが集まるメイン画面。
/// 出会った人・バッジ・カケラ・活動が一望できるコミュニティダッシュボード。
class PlazaScreen extends ConsumerStatefulWidget {
  const PlazaScreen({super.key});

  @override
  ConsumerState<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends ConsumerState<PlazaScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final puzzle = ref.watch(puzzleProvider);
    final revealed = state.encounters.where((e) => e.isRevealed).toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));
    return WorldPage(
        strength: .65,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
              child: ScreenHeader(
                  title: '広場', asset: 'assets/icons/nav_plaza.png')),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: PixelPanel(
                      child: Text('いろんな場所で\nすれ違いの気配が届いているよ',
                          style: Ts.body, textAlign: TextAlign.center)))),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: PlazaScene(
                      residents: revealed,
                      totalCount: revealed.length,
                      onTapResident: (e) =>
                          EncounterDetailSheet.show(context, e)))),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    TextButton.icon(
                        onPressed: () =>
                            openCommunityScreen(context, const BadgeScreen()),
                        icon: Image.asset('assets/icons/nav_badge.png',
                            width: 24),
                        label: Text('バッジ ${state.badges.length}個')),
                    TextButton.icon(
                        onPressed: () => openCommunityScreen(
                            context, const PuzzleBoardScreen()),
                        icon: Image.asset('assets/icons/nav_kakera.png',
                            width: 24),
                        label: Text('カケラ ${puzzle.pieces.length}枚')),
                  ]))),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('であった人ぜんいん', style: Ts.title))),
          if (revealed.isEmpty)
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: PixelPanel(
                        child: Text('まだ誰も来ていません\nすれ違って、門をあけてみよう。',
                            style: Ts.body))))
          else
            SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                    itemCount: revealed.length,
                    itemBuilder: (_, i) =>
                        _ResidentTile(encounter: revealed[i]))),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ]));
  }
}

// ─── 住民タイル ──────────────────────────────────────────────────────────────
class _ResidentTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _ResidentTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final rarity = cardRarityOf(encounter.meetCount);
    final border = rarityBorderColor(rarity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftPanel(
        onTap: () => EncounterDetailSheet.show(context, encounter),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // レアリティ枠の中にドット絵（主役）
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: rarity == CardRarity.hologram
                    ? const LinearGradient(colors: [
                        Color(0xFFFF6B6B),
                        Color(0xFFFFE66D),
                        Color(0xFF6BCB77),
                        Color(0xFF4D96FF)
                      ])
                    : null,
                color: rarity != CardRarity.hologram ? border : null,
              ),
              child: PeerIcon(
                  encounter: encounter, size: 42, circle: false, radius: 11),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(encounter.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Palette.ink)),
                      ),
                      if (encounter.peerBadgeLevel > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.workspace_premium,
                            size: 18, color: Palette.sun),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(fmtDate(encounter.lastMet), style: Ts.tiny),
                      const SizedBox(width: 8),
                      // 再遭遇回数は抽象ラベルで表示（数字非公開）
                      Text(encounterLabel(encounter.meetCount),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Palette.tealDeep)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: border.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border.withValues(alpha: 0.4)),
              ),
              child: Text(
                rarityLabel(rarity),
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
