import 'package:flutter/material.dart';
import '../models/encounter_record.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';

class ResultCardScreen extends StatefulWidget {
  final List<EncounterRecord> encounters;
  const ResultCardScreen({super.key, required this.encounters});

  @override
  State<ResultCardScreen> createState() => _ResultCardScreenState();
}

class _ResultCardScreenState extends State<ResultCardScreen> {
  int _index = 0;

  bool get _isDone => _index >= widget.encounters.length;

  void _next() => setState(() => _index++);
  void _skipAll() => setState(() => _index = widget.encounters.length);

  @override
  Widget build(BuildContext context) {
    if (widget.encounters.isEmpty || _isDone) {
      return _ResultScreen(total: widget.encounters.length);
    }

    return _EncounterCard(
      encounter: widget.encounters[_index],
      current: _index + 1,
      total: widget.encounters.length,
      onNext: _next,
      onSkip: _skipAll,
    );
  }
}

// ─── 1枚ずつ表示するカード ────────────────────────────────────────────────────

class _EncounterCard extends StatelessWidget {
  final EncounterRecord encounter;
  final int current;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _EncounterCard({
    required this.encounter,
    required this.current,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final color = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final label = encounterLabel(encounter.meetCount);
    final labelColor = encounterLabelColor(encounter.meetCount, context);
    final tmpl = encounter.template;

    return Scaffold(
      backgroundColor:
          Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('$current / $total',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 14)),
        actions: [
          TextButton(
            onPressed: onSkip,
            child: Text('スキップ',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              // プログレスバー
              LinearProgressIndicator(
                value: current / total,
                borderRadius: BorderRadius.circular(4),
              ),
              const Spacer(),
              // アバター
              CircleAvatar(
                radius: 68,
                backgroundColor: color,
                child: Text(
                  initial,
                  style: const TextStyle(
                      fontSize: 56,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                encounter.name,
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: labelColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: labelColor.withOpacity(0.5)),
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
              // メッセージカード
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      '💬  ${tmpl.statusText}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${tmpl.hobbyCategoryText} の ${tmpl.hobbyDetailText}',
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tmpl.phraseText,
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // ボタン
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        EncounterDetailSheet.show(context, encounter),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(100, 48)),
                    child: const Text('詳細'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onNext,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                      child: Text(
                          current < total ? '次の人 →' : '結果を見る'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 最終リザルト画面 ─────────────────────────────────────────────────────────

class _ResultScreen extends StatelessWidget {
  final int total;
  const _ResultScreen({required this.total});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 24),
              Text(
                '今日は',
                style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                      text: '$total',
                      style: TextStyle(
                        fontSize: 88,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                        height: 1,
                      ),
                    ),
                    const TextSpan(
                      text: ' 人',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'とすれ違いました！',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.home_outlined),
                label: const Text('ホームへ戻る'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 52)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
