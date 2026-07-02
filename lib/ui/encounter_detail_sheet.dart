import 'package:flutter/material.dart';
import '../models/app_badge.dart';
import '../models/encounter_record.dart';
import 'encounter_helpers.dart';

class EncounterDetailSheet extends StatelessWidget {
  final EncounterRecord encounter;
  const EncounterDetailSheet({super.key, required this.encounter});

  static void show(BuildContext context, EncounterRecord encounter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EncounterDetailSheet(encounter: encounter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final label = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);
    final tmpl = encounter.template;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: color,
                    backgroundImage: encounter.avatarUrl != null
                        ? NetworkImage(encounter.avatarUrl!)
                        : null,
                    child: encounter.avatarUrl == null
                        ? Text(
                            initial,
                            style: const TextStyle(
                                fontSize: 44,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    encounter.name,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: labelColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: labelColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      '【$label】',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                          fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // メッセージ吹き出し
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('💬',
                                style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              'ひとこと',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Row(label: '状態', value: tmpl.statusText),
                        _Row(
                          label: '趣味',
                          value:
                              '${tmpl.hobbyCategoryText} / ${tmpl.hobbyDetailText}',
                        ),
                        _Row(label: 'メッセージ', value: tmpl.phraseText),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  _DateRow(
                    label: '初めて会った日',
                    date: fmtDate(encounter.firstMet),
                  ),
                  const SizedBox(height: 6),
                  _DateRow(
                    label: '最後に会った日',
                    date: fmtDate(encounter.lastMet),
                  ),
                  if (encounter.peerBadgeLevel > 0) ...[
                    const SizedBox(height: 6),
                    _DateRow(
                      label: '相手のバッジ',
                      date: AppBadge.badgeLevelLabel(encounter.peerBadgeLevel),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String date;
  const _DateRow({required this.label, required this.date});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline),
        ),
        Text(
          date,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
