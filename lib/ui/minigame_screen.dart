import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encounter_record.dart';
import '../models/own_profile.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';

class MinigameScreen extends ConsumerStatefulWidget {
  const MinigameScreen({super.key});

  @override
  ConsumerState<MinigameScreen> createState() => _MinigameScreenState();
}

class _MinigameScreenState extends ConsumerState<MinigameScreen>
    with SingleTickerProviderStateMixin {
  EncounterRecord? _selected;
  int? _score;
  late AnimationController _scoreAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scoreAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnim = CurvedAnimation(parent: _scoreAnim, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _scoreAnim.dispose();
    super.dispose();
  }

  int _calcMatch(OwnProfile own, EncounterRecord other) {
    int score = 50;
    if (own.template.hobbyCategory == other.template.hobbyCategory) score += 25;
    if (own.template.hobbyDetail == other.template.hobbyDetail) score += 15;
    if (own.template.phraseIndex == other.template.phraseIndex) score += 10;
    // peerId ハッシュで 0-19 の揺らぎ
    final hash = other.peerId.hashCode.abs();
    score += (hash % 20) - 10;
    return score.clamp(0, 100);
  }

  void _match(OwnProfile own) {
    if (_selected == null) return;
    setState(() => _score = _calcMatch(own, _selected!));
    _scoreAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final state  = ref.watch(appProvider);
    final own    = state.ownProfile;
    // 今日新しく広場に加わった（= 今日lastMetで revealed）の未対戦
    final cards  = state.encounters
        .where((e) => e.isRevealed && e.metToday)
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('ミニゲーム')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'はじめましてマッチ',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '今日出会った人との相性をチェックしよう',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        if (cards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎮', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text('今日の出会いを確認してから遊べます',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 4),
                Text('まず「今日」タブを開いてみよう',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        fontSize: 12)),
              ],
            ),
          )
        else ...[
          // ─── 相手選択 ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text('相手を選ぶ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 130,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: cards.length,
                itemBuilder: (ctx, i) {
                  final e = cards[i];
                  final isSelected = _selected?.peerId == e.peerId;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selected = e;
                        _score    = null;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CardWidget(
                          encounter: e, selected: isSelected),
                    ),
                  );
                },
              ),
            ),
          ),

          // ─── マッチボタン & スコア ─────────────────────────────────────────
          if (_selected != null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    if (_score == null)
                      FilledButton.icon(
                        onPressed: own != null ? () => _match(own) : null,
                        icon: const Text('💘', style: TextStyle(fontSize: 20)),
                        label: const Text('相性チェック！'),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52)),
                      )
                    else ...[
                      ScaleTransition(
                        scale: _scaleAnim,
                        child: _ScoreDisplay(score: _score!),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            setState(() { _score = null; _selected = null; }),
                        child: const Text('もう一度選ぶ'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ],
    );
  }
}

// ─── カードウィジェット ────────────────────────────────────────────────────────

class _CardWidget extends StatelessWidget {
  final EncounterRecord encounter;
  final bool selected;
  const _CardWidget({required this.encounter, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color   = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial = encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final rarity  = cardRarityOf(encounter.meetCount);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : rarityBorderColor(rarity).withOpacity(0.4),
          width: selected ? 2.5 : 1.5,
        ),
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: _CardContent(
          encounter: encounter, color: color, initial: initial, rarity: rarity),
    );
  }
}

class _CardContent extends StatelessWidget {
  final EncounterRecord encounter;
  final Color color;
  final String initial;
  final CardRarity rarity;
  const _CardContent({
    required this.encounter,
    required this.color,
    required this.initial,
    required this.rarity,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rarityBorderColor(rarity),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: color,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            encounter.name,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            rarityLabel(rarity),
            style: TextStyle(
                fontSize: 9,
                color: rarityBorderColor(rarity)),
          ),
        ],
      ),
    );
  }
}

// ─── スコア表示 ───────────────────────────────────────────────────────────────

class _ScoreDisplay extends StatelessWidget {
  final int score;
  const _ScoreDisplay({required this.score});

  String get _emoji {
    if (score >= 90) return '💎';
    if (score >= 75) return '💕';
    if (score >= 60) return '😊';
    if (score >= 40) return '🙂';
    return '🤝';
  }

  String get _message {
    if (score >= 90) return '最高の相性！';
    if (score >= 75) return 'かなり相性いいかも！';
    if (score >= 60) return '良い相性です';
    if (score >= 40) return 'まずまずかな';
    return 'また会えるといいね';
  }

  Color _scoreColor(BuildContext context) {
    if (score >= 75) return const Color(0xFFE91E63);
    if (score >= 50) return Theme.of(context).colorScheme.primary;
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            '$score%',
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: _scoreColor(context),
            ),
          ),
          Text(_message,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
