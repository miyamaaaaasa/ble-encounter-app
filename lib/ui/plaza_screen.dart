import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';

// BGM トラック定義（音声ファイルは assets/bgm/ に配置してください）
// 累計すれ違い数に応じて豪華なトラックに切り替わります
String bgmTrackFor(int total) {
  if (total >= 10000) return 'bgm_10000.mp3';
  if (total >= 3000)  return 'bgm_3000.mp3';
  if (total >= 1500)  return 'bgm_1500.mp3';
  if (total >= 1000)  return 'bgm_1000.mp3';
  if (total >= 500)   return 'bgm_500.mp3';
  if (total >= 250)   return 'bgm_250.mp3';
  if (total >= 100)   return 'bgm_100.mp3';
  if (total >= 50)    return 'bgm_50.mp3';
  return 'bgm_default.mp3';
}

class PlazaScreen extends ConsumerStatefulWidget {
  const PlazaScreen({super.key});

  @override
  ConsumerState<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends ConsumerState<PlazaScreen> {
  @override
  void initState() {
    super.initState();
    // TODO: 音声ファイルが揃ったら AudioPlayer を初期化してBGM再生
    // import 'package:audioplayers/audioplayers.dart';
    // _player.play(AssetSource(bgmTrackFor(total)));
  }

  @override
  Widget build(BuildContext context) {
    final state    = ref.watch(appProvider);
    // 広場には開封済みのみ表示（プライバシー保護）
    final revealed = state.encounters
        .where((e) => e.isRevealed)
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));
    final total = revealed.length;

    return CustomScrollView(
      slivers: [
        // ─── ヘッダー ─────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          expandedHeight: 140,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(Icons.people_outline, size: 28),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '累計すれ違い',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.outline),
                          ),
                          Text(
                            '$total 人',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            title: const Text('広場'),
          ),
        ),

        if (revealed.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline,
                    size: 72,
                    color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 20),
                Text('まだ誰とも出会っていません',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text('外出して、誰かとすれ違ってみよう！',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        fontSize: 13)),
              ],
            ),
          )
        else
          SliverList.builder(
            itemCount: revealed.length,
            itemBuilder: (ctx, i) => _PlazaTile(encounter: revealed[i]),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}

// ─── 広場リストタイル ──────────────────────────────────────────────────────────

class _PlazaTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _PlazaTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color   = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial = encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final rarity  = cardRarityOf(encounter.meetCount);
    final border  = rarityBorderColor(rarity);

    return InkWell(
      onTap: () => EncounterDetailSheet.show(context, encounter),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            // レアリティ枠付きアバター
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: rarity == CardRarity.hologram
                    ? const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D),
                                 Color(0xFF6BCB77), Color(0xFF4D96FF)],
                      )
                    : null,
                color: rarity != CardRarity.hologram ? border : null,
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: color,
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(encounter.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Row(
                    children: [
                      Text(fmtDate(encounter.lastMet),
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(width: 8),
                      Text(encounterLabel(encounter.meetCount),
                          style: TextStyle(
                              fontSize: 11,
                              color: encounterLabelColor(encounter.meetCount, context))),
                    ],
                  ),
                ],
              ),
            ),
            // レアリティラベル
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: border.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border.withOpacity(0.4)),
              ),
              child: Text(
                rarityLabel(rarity),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
