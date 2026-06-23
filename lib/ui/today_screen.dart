import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import '../services/notification_service.dart';
import 'encounter_helpers.dart';
import 'radar_widget.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int      _notifHour = 18;
  Timer?   _countdownTimer;
  Duration _remaining = Duration.zero;
  bool     _gateOpen  = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await NotificationService.loadSettings();
    if (mounted) {
      setState(() => _notifHour = s.hour);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _updateGate();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateGate();
    });
  }

  void _updateGate() {
    final now  = DateTime.now();
    final open = now.hour >= _notifHour;
    if (open) {
      setState(() {
        _gateOpen  = true;
        _remaining = Duration.zero;
      });
      _countdownTimer?.cancel();
    } else {
      final target = DateTime(now.year, now.month, now.day, _notifHour);
      setState(() {
        _gateOpen  = false;
        _remaining = target.difference(now);
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state       = ref.watch(appProvider);
    final todayUnrev  = state.encounters.where((e) => e.metToday && !e.isRevealed).toList();
    final todayRev    = state.encounters.where((e) => e.metToday && e.isRevealed).toList();
    final alreadyDone = todayRev.isNotEmpty;

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

        // ─── レーダー（常時表示）────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 28, 0, 8),
            child: Column(
              children: [
                const RadarAnimation(size: 180),
                const SizedBox(height: 16),
                Text(
                  'すれ違い通信稼働中…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── 開封前（ゲートロック）──────────────────────────────────────────
        if (!_gateOpen && !alreadyDone)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _GateLocked(
              remaining: _remaining,
              notifHour: _notifHour,
            ),
          ),

        // ─── 開封可能（まだ未確認がある）───────────────────────────────────
        if (_gateOpen && !alreadyDone)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                children: [
                  Text(
                    '${_notifHour.toString().padLeft(2, '0')}:00 になりました',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: todayUnrev.isEmpty ? null : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _SwipeCardScreen(
                            encounters: todayUnrev,
                            onReveal: () =>
                                ref.read(appProvider.notifier).revealToday(),
                          ),
                          fullscreenDialog: true,
                        ),
                      );
                    },
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(
                      todayUnrev.isEmpty ? '今日はまだすれ違いがありません' : '今日の出会いを確認する',
                    ),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                  ),
                ],
              ),
            ),
          ),

        // ─── 開封済みリスト ──────────────────────────────────────────────────
        if (alreadyDone) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Text('今日出会った人',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${todayRev.length}人',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: todayRev.length,
            itemBuilder: (ctx, i) => _RevealedTile(encounter: todayRev[i]),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ],
    );
  }
}

// ─── ゲートロック画面 ──────────────────────────────────────────────────────────

class _GateLocked extends StatelessWidget {
  final Duration remaining;
  final int notifHour;
  const _GateLocked({required this.remaining, required this.notifHour});

  @override
  Widget build(BuildContext context) {
    final hh  = remaining.inHours.toString().padLeft(2, '0');
    final mm  = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final ss  = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    final revH = notifHour.toString().padLeft(2, '0');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_clock_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 20),
        Text(
          '開門まで',
          style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Text(
          '$hh:$mm:$ss',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$revH:00 に今日の出会いを確認できます',
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }
}

// ─── スワイプカード画面 ────────────────────────────────────────────────────────

class _SwipeCardScreen extends StatefulWidget {
  final List<EncounterRecord> encounters;
  final VoidCallback onReveal;
  const _SwipeCardScreen({required this.encounters, required this.onReveal});

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
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
            // ─── ページインジケーター ──────────────────────────────────────
            Positioned(
              top: 12, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                )),
              ),
            ),

            // ─── カード ────────────────────────────────────────────────────
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

            // ─── スキップボタン ────────────────────────────────────────────
            Positioned(
              top: 8, right: 16,
              child: TextButton.icon(
                onPressed: _skipAll,
                icon: const Icon(Icons.fast_forward, size: 16),
                label: const Text('スキップ'),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.outline),
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
  const _EncounterCard({
    required this.encounter,
    required this.onNext,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color   = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial = encounter.name.isNotEmpty ? encounter.name.characters.first : '?';
    final rarity  = cardRarityOf(encounter.meetCount);
    final tmpl    = encounter.template;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // レアリティバッジ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: rarityBorderColor(rarity).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: rarityBorderColor(rarity)),
                      ),
                      child: Text(
                        rarityLabel(rarity),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: rarityBorderColor(rarity)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // アバター
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 4),
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

                    // 名前
                    Text(
                      encounter.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),

                    const Divider(),
                    const SizedBox(height: 12),

                    // 詳細情報
                    _InfoRow(icon: Icons.handshake_outlined,
                        label: 'すれ違い回数', value: '${encounter.meetCount}回'),
                    _InfoRow(icon: Icons.calendar_today_outlined,
                        label: '初めて出会った日', value: fmtDate(encounter.firstMet)),
                    _InfoRow(icon: Icons.workspace_premium_outlined,
                        label: 'バッジ', value: '---'),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    // 定型文
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '💬 "${tmpl.phraseText}"',
                            style: const TextStyle(
                                fontSize: 15, fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${tmpl.statusText}  ·  ${tmpl.hobbyCategoryText}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ],
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
            style: TextStyle(fontSize: 11,
                color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ─── 開封済みタイル ───────────────────────────────────────────────────────────

class _RevealedTile extends StatelessWidget {
  final EncounterRecord encounter;
  const _RevealedTile({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final color   = avatarColors[encounter.colorIndex % avatarColors.length];
    final initial = encounter.name.isNotEmpty ? encounter.name.characters.first : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: color,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
          title: Text(encounter.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${encounter.template.statusText} · ${encounter.template.hobbyCategoryText}'),
          trailing: Text('${encounter.meetCount}回',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline)),
        ),
      ),
    );
  }
}
