import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import 'profile_screen.dart' show avatarColors;

class EncounterListScreen extends ConsumerWidget {
  const EncounterListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final encounters = state.encounters;

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
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.isRunning
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 6),
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
        ),
        if (encounters.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else
          SliverList.builder(
            itemCount: encounters.length,
            itemBuilder: (ctx, i) => _EncounterTile(encounter: encounters[i]),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}

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
                color: Theme.of(context).colorScheme.outline, fontSize: 16)),
        const SizedBox(height: 8),
        Text('外出して、誰かとすれ違ってみよう！',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outlineVariant,
                fontSize: 13)),
      ],
    );
  }
}

// ─── ヘルパー ─────────────────────────────────────────────────────────────────

String formatEncounterTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inHours < 1) return '1時間以内に出会いました';
  if (diff.inHours < 24) return '今日出会いました';
  final y = dt.year;
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}

String encounterLabel(int meetCount) {
  if (meetCount >= 50) return '伝説';
  if (meetCount >= 10) return '常連';
  if (meetCount >= 5) return 'よく見る';
  return '見かけた';
}

Color encounterLabelColor(int meetCount, BuildContext context) {
  if (meetCount >= 50) return const Color(0xFFFFB300);
  if (meetCount >= 10) return const Color(0xFFBA68C8);
  if (meetCount >= 5) return Theme.of(context).colorScheme.tertiary;
  return Theme.of(context).colorScheme.primary;
}

int rssiToStars(int rssi) {
  if (rssi >= -60) return 5;
  if (rssi >= -70) return 4;
  if (rssi >= -80) return 3;
  if (rssi >= -90) return 2;
  return 1;
}

final _urlRegex = RegExp(r'https?://\S+', caseSensitive: false);

List<TextSpan> buildUrlSpans(
    String text, TextStyle base, TextStyle link) {
  final spans = <TextSpan>[];
  int last = 0;
  for (final m in _urlRegex.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    final url = m.group(0)!;
    spans.add(TextSpan(
      text: url,
      style: link,
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        },
    ));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}

// ─── タイル ──────────────────────────────────────────────────────────────────

class _EncounterTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _EncounterTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final stars = rssiToStars(encounter.rssi);
    final label = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);

    return InkWell(
      onTap: () => _showDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(encounter.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      Text(
                        '${'★' * stars}${'☆' * (5 - stars)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: stars >= 4
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  if (encounter.message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      encounter.message,
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        formatEncounterTime(encounter.lastMet),
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline),
                      ),
                      const SizedBox(width: 8),
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

  void _showDetail(BuildContext context) {
    final color = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final stars = rssiToStars(encounter.rssi);
    final label = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final baseStyle = TextStyle(
            fontSize: 15,
            color: Theme.of(ctx).colorScheme.onSurface);
        final linkStyle = TextStyle(
            fontSize: 15,
            color: Theme.of(ctx).colorScheme.primary,
            decoration: TextDecoration.underline);

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 40,
                backgroundColor: color,
                child: Text(initial,
                    style: const TextStyle(
                        fontSize: 34,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              Text(encounter.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: labelColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: labelColor)),
              ),
              if (encounter.message.isNotEmpty) ...[
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                      children: buildUrlSpans(
                          encounter.message, baseStyle, linkStyle)),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _DetailItem(
                    label: '電波強度',
                    value: '${'★' * stars}${'☆' * (5 - stars)}',
                  ),
                  _DetailItem(
                    label: '初めて',
                    value: formatEncounterTime(encounter.firstMet),
                  ),
                  _DetailItem(
                    label: '最近',
                    value: formatEncounterTime(encounter.lastMet),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _DetailItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 4),
        Text(value,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
