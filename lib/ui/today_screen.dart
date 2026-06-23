import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';
import 'result_card_screen.dart';
import 'radar_widget.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final all   = state.encounters;

    final revealedToday   = all.where((e) => e.metToday && e.isRevealed).toList();
    final unrevealedToday = all.where((e) => e.metToday && !e.isRevealed).toList();
    final totalRevealed   = all.where((e) => e.isRevealed).length;

    final now       = DateTime.now();
    final dateLabel = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

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
                    width: 7, height: 7,
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

        // ─── レーダーアニメーション ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 28, 0, 8),
            child: Column(
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(fontSize: 13,
                      color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 20),
                const RadarAnimation(size: 200),
                const SizedBox(height: 20),
                Text(
                  'すれ違い通信稼働中…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '累計 $totalRevealed 人とすれ違いました',
                  style: TextStyle(fontSize: 13,
                      color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
        ),

        // ─── 結果確認ボタン（未開封あり・件数は表示しない）──────────────────
        if (unrevealedToday.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultCardScreen(
                        encounters: unrevealedToday,
                        onReveal: () =>
                            ref.read(appProvider.notifier).revealToday(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('今日の結果を確認する'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ),

        // ─── 開封済みリスト ──────────────────────────────────────────────────
        if (revealedToday.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    '今日出会った人',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${revealedToday.length}人',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: revealedToday.length,
            itemBuilder: (ctx, i) => _TodayTile(encounter: revealedToday[i]),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ],
    );
  }
}

class _TodayTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _TodayTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color   = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial = encounter.name.isNotEmpty
        ? encounter.name.characters.first : '?';
    final label      = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);
    final tmpl       = encounter.template;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => EncounterDetailSheet.show(context, encounter),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color,
                  child: Text(initial,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(encounter.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(
                        '${tmpl.statusText} · ${tmpl.hobbyCategoryText}',
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: labelColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label,
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600, color: labelColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
