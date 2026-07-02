import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_badge.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import '../providers/puzzle_providers.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';
import 'theme/palette.dart';
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
    final total = revealed.length;
    final badges = state.badges;
    final recentBadges = [...badges]
      ..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));

    return Container(
      color: Palette.cream,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'みんなの広場',
              emoji: '🏡',
              trailing: StatChip(
                emoji: '👥',
                label: 'のべ $total人',
                color: Palette.coral.withValues(alpha: 0.18),
              ),
            ),
          ),

          // ─── ここ最近の仲間（横スクロール）─────────────────────
          if (revealed.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: SectionLabel('👋', 'さいきん来た人'),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 92,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: revealed.take(12).length,
                  itemBuilder: (ctx, i) {
                    final e = revealed[i];
                    return _RecentFace(
                      encounter: e,
                      onTap: () => EncounterDetailSheet.show(context, e),
                    );
                  },
                ),
              ),
            ),
          ],

          // ─── コレクション状況（バッジ＆カケラ）────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SoftPanel(
                      color: Palette.lavender.withValues(alpha: 0.16),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('🏅', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 6),
                              Text('バッジ', style: Ts.title),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('${badges.length}個',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Palette.lavenderDeep)),
                          if (recentBadges.isNotEmpty)
                            Text(
                              '最新: ${recentBadges.first.emoji} ${recentBadges.first.title}',
                              style: Ts.tiny,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SoftPanel(
                      color: Palette.sky.withValues(alpha: 0.16),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('💎', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 6),
                              Text('カケラ', style: Ts.title),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('${puzzle.pieces.length}枚',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Palette.tealDeep)),
                          Text('すれ違いで集まる', style: Ts.tiny),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── 住民名簿 ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: SectionLabel('📛', 'であった人ぜんいん',
                  trailing: Text('$total人', style: Ts.caption)),
            ),
          ),

          if (revealed.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: SoftPanel(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: const [
                      Text('🌱', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('まだ誰も来ていません', style: Ts.title),
                      SizedBox(height: 6),
                      Text('外に出て、誰かとすれ違ってみよう！', style: Ts.caption),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverList.builder(
                itemCount: revealed.length,
                itemBuilder: (ctx, i) => _ResidentTile(encounter: revealed[i]),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

// ─── 最近の顔（横スクロール）──────────────────────────────────────────────────
class _RecentFace extends StatelessWidget {
  final EncounterRecord encounter;
  final VoidCallback onTap;
  const _RecentFace({required this.encounter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        Palette.pastelAvatars[encounter.colorIndex % Palette.pastelAvatars.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: Palette.lift(),
                image: encounter.avatarUrl != null
                    ? DecorationImage(
                        image: NetworkImage(encounter.avatarUrl!),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: encounter.avatarUrl == null
                  ? Center(
                      child: Text(initial,
                          style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.w800)))
                  : null,
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 60,
              child: Text(
                encounter.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Palette.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 住民タイル ──────────────────────────────────────────────────────────────
class _ResidentTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _ResidentTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color =
        Palette.pastelAvatars[encounter.colorIndex % Palette.pastelAvatars.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final rarity = cardRarityOf(encounter.meetCount);
    final border = rarityBorderColor(rarity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftPanel(
        onTap: () => EncounterDetailSheet.show(context, encounter),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
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
              child: CircleAvatar(
                radius: 21,
                backgroundColor: color,
                backgroundImage: encounter.avatarUrl != null
                    ? NetworkImage(encounter.avatarUrl!)
                    : null,
                child: encounter.avatarUrl == null
                    ? Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15))
                    : null,
              ),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Palette.ink)),
                      ),
                      if (encounter.peerBadgeLevel > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          AppBadge.badgeLevelLabel(encounter.peerBadgeLevel)
                              .split(' ')
                              .first,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(fmtDate(encounter.lastMet), style: Ts.tiny),
                      const SizedBox(width: 8),
                      // 再遭遇回数は抽象ラベルで表示（数字非公開）
                      Text(encounterLabel(encounter.meetCount),
                          style: const TextStyle(
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

