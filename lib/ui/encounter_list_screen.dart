import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';

enum _Sort { recent, count }

class EncounterListScreen extends ConsumerStatefulWidget {
  const EncounterListScreen({super.key});

  @override
  ConsumerState<EncounterListScreen> createState() =>
      _EncounterListScreenState();
}

class _EncounterListScreenState
    extends ConsumerState<EncounterListScreen> {
  _Sort _sort = _Sort.recent;

  List<EncounterRecord> _sorted(List<EncounterRecord> list) {
    final copy = List<EncounterRecord>.from(list);
    switch (_sort) {
      case _Sort.recent:
        copy.sort((a, b) => b.lastMet.compareTo(a.lastMet));
      case _Sort.count:
        copy.sort((a, b) => b.meetCount.compareTo(a.meetCount));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    // 図鑑は開封済みのみ表示（プライバシー保護）
    final encounters = _sorted(
        state.encounters.where((e) => e.isRevealed).toList());

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('図鑑'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: const Icon(Icons.people, size: 16),
                label: Text('累計 ${encounters.length} 人'),
              ),
            ),
          ],
        ),

        // ─── ソートボタン ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<_Sort>(
              segments: const [
                ButtonSegment(
                  value: _Sort.recent,
                  icon: Icon(Icons.access_time, size: 16),
                  label: Text('最近'),
                ),
                ButtonSegment(
                  value: _Sort.count,
                  icon: Icon(Icons.trending_up, size: 16),
                  label: Text('遭遇回数'),
                ),
              ],
              selected: {_sort},
              onSelectionChanged: (s) =>
                  setState(() => _sort = s.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
            ),
          ),
        ),

        if (state.errorMessage != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer),
                  ),
                ),
              ),
            ),
          ),

        if (encounters.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else
          SliverList.builder(
            itemCount: encounters.length,
            itemBuilder: (ctx, i) =>
                _ZukanTile(encounter: encounters[i]),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}

// ─── 空状態 ──────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.people_outline,
            size: 72,
            color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 20),
        Text('まだすれ違いがありません',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 16)),
        const SizedBox(height: 8),
        Text('外出して、誰かとすれ違ってみよう！',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outlineVariant,
                fontSize: 13)),
      ],
    );
  }
}

// ─── 図鑑タイル ───────────────────────────────────────────────────────────────

class _ZukanTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _ZukanTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final label = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);
    final stars = rssiToStars(encounter.rssi);

    return InkWell(
      onTap: () => EncounterDetailSheet.show(context, encounter),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Text(
                initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          encounter.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      // 電波強度
                      Text(
                        '${'★' * stars}${'☆' * (5 - stars)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: stars >= 4
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '初: ${fmtDate(encounter.firstMet)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '最終: ${fmtDate(encounter.lastMet)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: labelColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: labelColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
