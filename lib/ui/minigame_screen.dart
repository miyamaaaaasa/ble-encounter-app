import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../models/encounter_record.dart';
import '../core/ble_config.dart';
import 'games/piece_puzzle.dart';
import 'games/tower_rpg.dart';
import 'games/aquarium.dart';

// ─── ミニゲーム ハブ ──────────────────────────────────────────────────────────

class MinigameScreen extends ConsumerWidget {
  const MinigameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    // 今日開封済みのすれ違いのみ（プライバシー保護: isRevealed必須）
    final todayRev = state.encounters
        .where((e) => e.isRevealed && e.metToday)
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));

    // デバッグ時: 今日の遭遇がなければ全revealedの直近10件をテスト用に使用
    final List<EncounterRecord> gameEncounters;
    if (kDebugBle && todayRev.isEmpty) {
      gameEncounters = state.encounters
          .where((e) => e.isRevealed)
          .take(10)
          .toList();
    } else {
      gameEncounters = todayRev;
    }

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('ミニゲーム')),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(children: [
            if (gameEncounters.isEmpty) ...[
              const SizedBox(height: 48),
              const Center(child: Text('🎮', style: TextStyle(fontSize: 72))),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '今日の出会いを確認してから遊べます',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '「今日」タブで出会いを確認してね',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ] else ...[
              _SectionHeader('今日の仲間', '${gameEncounters.length} 人と出会いました'),
              const SizedBox(height: 8),
              // 仲間サムネ
              SizedBox(
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: gameEncounters.length,
                  itemBuilder: (ctx, i) {
                    final e = gameEncounters[i];
                    final initial = e.name.isNotEmpty ? e.name.characters.first : '?';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: _avatarColor(e.peerId),
                        child: Text(initial,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ─── ゲームカード3枚 ─────────────────────────────────────────
            _GameCard(
              emoji: '🧩',
              title: 'ピース集めの旅',
              description: '出会った人からパズルのピースをもらおう。ホログラムの相手からはゴールドピースが手に入るかも！',
              tag: gameEncounters.isEmpty ? null : '${gameEncounters.length} 枚もらえる',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PiecePuzzleScreen(todayRevealed: gameEncounters))),
            ),
            const SizedBox(height: 12),

            _GameCard(
              emoji: '⚔️',
              title: 'はじめましてタワーRPG',
              description: '今日出会った人が勇者として参戦！紙質に応じてスキルが変わるタワー突破バトル。',
              tag: gameEncounters.isEmpty ? null : '勇者 ${gameEncounters.length} 人',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TowerRpgScreen(todayRevealed: gameEncounters))),
            ),
            const SizedBox(height: 12),

            _GameCard(
              emoji: '🐟',
              title: 'すれちがい水族館',
              description: 'すれ違った人の地域の魚が池に放流される！タップして釣り上げ、図鑑を埋めよう。',
              tag: gameEncounters.isEmpty ? null : '今日 ${gameEncounters.length} 匹放流',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AquariumScreen(todayRevealed: gameEncounters))),
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ],
    );
  }

  Color _avatarColor(String peerId) {
    const colors = [
      Color(0xFF378ADD), Color(0xFF1D9E75), Color(0xFFD85A30),
      Color(0xFFBA7517), Color(0xFF534AB7), Color(0xFFD4537E),
    ];
    return colors[peerId.hashCode.abs() % colors.length];
  }
}

// ─── ゲームカード ─────────────────────────────────────────────────────────────
class _GameCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final String? tag;
  final VoidCallback onTap;
  const _GameCard({
    required this.emoji, required this.title, required this.description,
    this.tag, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  if (tag != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(tag!,
                          style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ]),
        ),
      ),
    );
  }
}

// ─── セクションヘッダー ───────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.outline)),
    ]);
  }
}
