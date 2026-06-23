import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';
import 'result_card_screen.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  List<EncounterRecord> _todayEncounters(List<EncounterRecord> all) {
    final now = DateTime.now();
    return all.where((e) {
      return e.lastMet.year == now.year &&
          e.lastMet.month == now.month &&
          e.lastMet.day == now.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final today = _todayEncounters(state.encounters);
    final newCount = today.where((e) => e.firstMetToday).length;
    final returnCount = today.length - newCount;
    final now = DateTime.now();
    final dateLabel =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: const Text('今日'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isRunning
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    state.isRunning ? 'スキャン中' : '停止中',
                    style: TextStyle(
                      fontSize: 12,
                      color: state.isRunning
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ─── カウンター カード ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 28, horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      dateLabel,
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        '${today.length}',
                        key: ValueKey(today.length),
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '人とすれ違いました',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                    const SizedBox(height: 14),
                    // 新規 / 再遭遇 バッジ
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatChip(
                          label: '初めて',
                          count: newCount,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        const SizedBox(width: 10),
                        _StatChip(
                          label: '再会',
                          count: returnCount,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        const SizedBox(width: 10),
                        _StatChip(
                          label: '通算',
                          count: state.encounters.length,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ─── 結果演出ボタン ──────────────────────────────────────────────
        if (today.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ResultCardScreen(encounters: today),
                    ),
                  );
                },
                icon: const Icon(Icons.slideshow_outlined),
                label: const Text('今日の結果を1人ずつ見る'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
              ),
            ),
          ),

        // ─── 今日のリスト ────────────────────────────────────────────────
        if (today.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.explore_outlined,
                    size: 56,
                    color:
                        Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Text(
                  'まだ今日はすれ違いがありません',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  '外出してみましょう！',
                  style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.outlineVariant,
                      fontSize: 13),
                ),
              ],
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                '今日出会った人',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: today.length,
            itemBuilder: (ctx, i) =>
                _TodayTile(encounter: today[i]),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}

// ─── 統計チップ ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withOpacity(0.75)),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── タイル ──────────────────────────────────────────────────────────────────

class _TodayTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _TodayTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final label = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);
    final tmpl = encounter.template;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => EncounterDetailSheet.show(context, encounter),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color,
                  child: Text(
                    initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        encounter.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '${tmpl.statusText} · ${tmpl.hobbyCategoryText}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: labelColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: labelColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
