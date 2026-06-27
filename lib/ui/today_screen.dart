import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ble_config.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart'
    show appProvider, AppState, AppNotifier, scanIntervalProvider;
import 'encounter_helpers.dart';
import 'radar_widget.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Timer? _clockTimer;
  Timer? _bannerTimer;
  bool   _showBanner = false;
  final  _rng = Random();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  static DateTime _gateFor(DateTime t) => AppNotifier.gateTimeFor(t);

  List<DateTime> _todayGates() {
    final now = DateTime.now();
    return [
      DateTime(now.year, now.month, now.day,  9),
      DateTime(now.year, now.month, now.day, 12),
      DateTime(now.year, now.month, now.day, 21),
    ];
  }

  List<EncounterRecord> _forGate(
          List<EncounterRecord> enc, DateTime gate) =>
      enc.where((e) => _gateFor(e.lastMet) == gate).toList();

  void _onEncounterDetected() {
    if (_bannerTimer != null) return;
    final delay = Duration(minutes: _rng.nextInt(21) + 10);
    _bannerTimer = Timer(delay, () {
      if (mounted) setState(() => _showBanner = true);
    });
  }

  void _onGateRevealed() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    setState(() => _showBanner = false);
    ref.read(appProvider.notifier).revealToday();
  }

  String _gateLabel(int hour) {
    if (hour == 9)  return '朝 🌅';
    if (hour == 12) return '昼 ☀️';
    if (hour == 21) return '夜 🌙';
    return '$hour:00';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);

    ref.listen<AppState>(appProvider, (prev, next) {
      if (next.hasNewEncounter && !(prev?.hasNewEncounter ?? false)) {
        _onEncounterDetected();
      }
    });

    final gates = _todayGates();
    final now   = DateTime.now();
    final si    = ref.watch(scanIntervalProvider);

    final todayRevealed = state.encounters
        .where((e) =>
            e.isRevealed && gates.any((g) => _gateFor(e.lastMet) == g))
        .toList();

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

        // ─── 波アニメ ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 32, 0, 8),
            child: Column(
              children: [
                AnimatedOpacity(
                  opacity: state.isRunning ? 1.0 : 0.35,
                  duration: const Duration(milliseconds: 600),
                  child: const WaveAnimation(),
                ),
                const SizedBox(height: 14),
                Text(
                  state.isRunning ? _scanLabel(si) : '停止中',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: state.isRunning
                        ? const Color(0xFF4ECDC4)
                        : Theme.of(context).colorScheme.outlineVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── すれ違いバナー ────────────────────────────────────────────────
        if (_showBanner)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.people_outline,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '誰かとすれ違えています！\n次のゲート時刻に確認できます',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ─── 3ゲートカード ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: gates.map((gate) {
                final enc       = _forGate(state.encounters, gate);
                final isOpen    = kGateAlwaysOpen || now.isAfter(gate);
                final hasUnrev  = enc.any((e) => !e.isRevealed);
                final revCount  = enc.where((e) => e.isRevealed).length;
                final unrevCount = enc.where((e) => !e.isRevealed).length;
                final remaining = isOpen
                    ? Duration.zero
                    : gate.difference(now);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _GateCard(
                    gateTime:   gate,
                    label:      _gateLabel(gate.hour),
                    isOpen:     isOpen,
                    remaining:  remaining,
                    revCount:   revCount,
                    unrevCount: unrevCount,
                    hasUnrev:   hasUnrev,
                    onReveal: () {
                      final unrev =
                          enc.where((e) => !e.isRevealed).toList();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _SwipeCardScreen(
                            encounters: unrev,
                            onReveal: _onGateRevealed,
                          ),
                          fullscreenDialog: true,
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ─── 今日 開封済みリスト ───────────────────────────────────────────
        if (todayRevealed.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Text(
                    '今日出会った人',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary),
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
                      '${todayRevealed.length}人',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: todayRevealed.length,
            itemBuilder: (ctx, i) =>
                _RevealedTile(encounter: todayRevealed[i]),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ],
    );
  }
}

String _scanLabel(ScanInterval si) {
  switch (si) {
    case ScanInterval.always: return '常時スキャン中';
    case ScanInterval.one:    return '1分に1回 スキャン中';
    case ScanInterval.two:    return '2分に1回 スキャン中';
    case ScanInterval.three:  return '3分に1回 スキャン中';
    case ScanInterval.five:   return '5分に1回 スキャン中';
    case ScanInterval.ten:    return '10分に1回 スキャン中';
  }
}

// ─── ゲートカード ─────────────────────────────────────────────────────────────

class _GateCard extends StatelessWidget {
  final DateTime gateTime;
  final String label;
  final bool isOpen;
  final Duration remaining;
  final int revCount;
  final int unrevCount;
  final bool hasUnrev;
  final VoidCallback onReveal;

  const _GateCard({
    required this.gateTime,
    required this.label,
    required this.isOpen,
    required this.remaining,
    required this.revCount,
    required this.unrevCount,
    required this.hasUnrev,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final hh = gateTime.hour.toString().padLeft(2, '0');
    final rh = remaining.inHours.toString().padLeft(2, '0');
    final rm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final rs = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOpen
              ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
              : Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isOpen
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    )),
                Text('$hh:00',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: isOpen
                  ? _openContent(context)
                  : _closedContent(context, rh, rm, rs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _openContent(BuildContext ctx) {
    if (hasUnrev) {
      return FilledButton.icon(
        onPressed: onReveal,
        icon: const Icon(Icons.lock_open_outlined, size: 18),
        label: Text('$unrevCount人 確認する'),
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      );
    }
    if (revCount > 0) {
      return Row(children: [
        Icon(Icons.check_circle_outline,
            size: 18, color: Theme.of(ctx).colorScheme.primary),
        const SizedBox(width: 6),
        Text('$revCount人 確認済み',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.primary,
                fontWeight: FontWeight.w600)),
      ]);
    }
    return Text('出会いなし',
        style: TextStyle(
            fontSize: 13, color: Theme.of(ctx).colorScheme.outline));
  }

  Widget _closedContent(BuildContext ctx, String rh, String rm, String rs) {
    return Row(children: [
      Icon(Icons.lock_clock_outlined,
          size: 18, color: Theme.of(ctx).colorScheme.outlineVariant),
      const SizedBox(width: 8),
      Text('$rh:$rm:$rs',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w300,
              color: Theme.of(ctx).colorScheme.outline)),
    ]);
  }
}

// ─── スワイプカード画面 ────────────────────────────────────────────────────────

class _SwipeCardScreen extends StatefulWidget {
  final List<EncounterRecord> encounters;
  final VoidCallback onReveal;
  const _SwipeCardScreen(
      {required this.encounters, required this.onReveal});

  @override
  State<_SwipeCardScreen> createState() => _SwipeCardScreenState();
}

class _SwipeCardScreenState extends State<_SwipeCardScreen> {
  final _ctrl = PageController();
  int  _page  = 0;
  bool _done  = false;

  void _next() {
    if (_page < widget.encounters.length - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
    } else {
      _complete();
    }
  }

  void _skipAll() => _complete();

  void _complete() {
    if (_done) return;
    setState(() => _done = true);
    widget.onReveal();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.encounters.length;

    if (_done) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 24),
                Text(
                  '今日は $total 人と出会いました！',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text('広場に追加されました',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    total,
                    (i) => Container(
                          margin:
                              const EdgeInsets.symmetric(horizontal: 3),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                          ),
                        )),
              ),
            ),
            Positioned.fill(
              top: 36,
              child: PageView.builder(
                controller: _ctrl,
                itemCount: total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) => _EncounterCard(
                  encounter: widget.encounters[i],
                  onNext: _next,
                  isLast: i == total - 1,
                ),
              ),
            ),
            Positioned(
              top: 8, right: 16,
              child: TextButton.icon(
                onPressed: _skipAll,
                icon: const Icon(Icons.fast_forward, size: 16),
                label: const Text('スキップ'),
                style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 出会いカード ──────────────────────────────────────────────────────────────

class _EncounterCard extends StatelessWidget {
  final EncounterRecord encounter;
  final VoidCallback onNext;
  final bool isLast;
  const _EncounterCard(
      {required this.encounter,
      required this.onNext,
      required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color   = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial =
        encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final rarity  = cardRarityOf(encounter.meetCount);
    final tmpl    = encounter.template;
    final cardBg  = _rarityCardBackground(rarity, context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: rarityBorderColor(rarity).withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: cardBg,
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: rarityBorderColor(rarity)
                                  .withOpacity(0.7)),
                        ),
                        child: Text(
                          rarityLabel(rarity),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: rarity == CardRarity.common
                                  ? rarityBorderColor(rarity)
                                  : Colors.white),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 24,
                                spreadRadius: 6),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: color,
                          child: Text(
                            initial,
                            style: const TextStyle(
                                fontSize: 48,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        encounter.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: rarity == CardRarity.common
                                  ? null
                                  : Colors.white,
                            ),
                      ),
                      const SizedBox(height: 20),
                      Divider(
                        color: rarity == CardRarity.common
                            ? null
                            : Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: '初めて出会った日',
                          value: fmtDate(encounter.firstMet),
                          light: rarity != CardRarity.common),
                      if (encounter.prefecture >= 0)
                        _InfoRow(
                            icon: Icons.place_outlined,
                            label: '出身地',
                            value: _prefName(encounter.prefecture),
                            light: rarity != CardRarity.common),
                      const SizedBox(height: 12),
                      Divider(
                        color: rarity == CardRarity.common
                            ? null
                            : Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: rarity == CardRarity.common
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '💬 "${tmpl.phraseText}"',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic,
                                  color:
                                      rarity == CardRarity.common
                                          ? null
                                          : Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${tmpl.statusText}  ·  ${tmpl.hobbyCategoryText}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: rarity == CardRarity.common
                                      ? Theme.of(context)
                                          .colorScheme
                                          .outline
                                      : Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onNext,
            icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
            label: Text(isLast ? '完了' : '次へ'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          Text(
            '← スワイプでも操作できます →',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

String _prefName(int code) {
  const names = [
    '北海道', '青森', '岩手', '宮城', '秋田', '山形', '福島',
    '茨城', '栃木', '群馬', '埼玉', '千葉', '東京', '神奈川',
    '新潟', '富山', '石川', '福井', '山梨', '長野',
    '岐阜', '静岡', '愛知', '三重',
    '滋賀', '京都', '大阪', '兵庫', '奈良', '和歌山',
    '鳥取', '島根', '岡山', '広島', '山口',
    '徳島', '香川', '愛媛', '高知',
    '福岡', '佐賀', '長崎', '熊本', '大分', '宮崎', '鹿児島', '沖縄',
  ];
  if (code < 0 || code >= names.length) return '不明';
  return names[code];
}

BoxDecoration _rarityCardBackground(CardRarity r, BuildContext context) {
  switch (r) {
    case CardRarity.hologram:
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFB721FF),
            Color(0xFF21D4FD),
            Color(0xFFFF6B6B),
            Color(0xFFFFE66D)
          ],
          stops: [0.0, 0.33, 0.66, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    case CardRarity.gradient:
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    case CardRarity.craft:
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD4A574), Color(0xFFA07850)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    case CardRarity.common:
      return BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1.5),
      );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool light;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: light
                    ? Colors.white70
                    : Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: light
                        ? Colors.white70
                        : Theme.of(context).colorScheme.outline)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: light ? Colors.white : null)),
          ],
        ),
      );
}

class _RevealedTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _RevealedTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color =
        avatarColors[encounter.colorIndex % avatarColors.length];
    final initial = encounter.name.isNotEmpty
        ? encounter.name.characters.first
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: color,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Text(encounter.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${encounter.template.statusText} · ${encounter.template.hobbyCategoryText}'),
          trailing: Text(encounterLabel(encounter.meetCount),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: encounterLabelColor(
                      encounter.meetCount, context))),
        ),
      ),
    );
  }
}
