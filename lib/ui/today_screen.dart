import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ble_config.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart' show appProvider, AppState, notifHourProvider;
import '../services/notification_service.dart';
import 'encounter_helpers.dart';
import 'radar_widget.dart'; // WaveAnimation

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int      _notifHour = 18;
  Timer?   _countdownTimer;
  Duration _remaining         = Duration.zero;
  Duration _tomorrowRemaining = Duration.zero; // 0:00設定時の翌日カウントダウン
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

  // 通知時刻に応じた「今日公開するバッチの日付」
  DateTime get _revealDate {
    final now = DateTime.now();
    if (_notifHour == 0) {
      final y = now.subtract(const Duration(days: 1));
      return DateTime(y.year, y.month, y.day);
    }
    return DateTime(now.year, now.month, now.day);
  }

  bool _isRevealBatch(EncounterRecord e) {
    if (kGateAlwaysOpen) {
      // デバッグ: 今日の出会いを全て表示対象に
      final now = DateTime.now();
      return e.lastMet.year == now.year &&
             e.lastMet.month == now.month &&
             e.lastMet.day == now.day;
    }
    final d = _revealDate;
    return e.lastMet.year == d.year &&
           e.lastMet.month == d.month &&
           e.lastMet.day == d.day;
  }

  void _updateGate() {
    if (kGateAlwaysOpen) {
      // デバッグ: ゲート常時開放
      setState(() {
        _gateOpen          = true;
        _remaining         = Duration.zero;
        _tomorrowRemaining = Duration.zero;
      });
      _countdownTimer?.cancel();
      return;
    }

    final now = DateTime.now();

    if (_notifHour == 0) {
      // 0:00 設定: ゲートは常時オープン（昨日の出会いが表示対象）
      // 今日の出会いは翌日 00:00 から → 翌日カウントダウンを継続表示
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      setState(() {
        _gateOpen          = true;
        _remaining         = Duration.zero;
        _tomorrowRemaining = tomorrow.difference(now);
      });
      // タイマーは継続（カウントダウン更新のため）
      return;
    }

    final open = now.hour >= _notifHour;
    if (open) {
      setState(() {
        _gateOpen          = true;
        _remaining         = Duration.zero;
        _tomorrowRemaining = Duration.zero;
      });
      _countdownTimer?.cancel();
    } else {
      final target = DateTime(now.year, now.month, now.day, _notifHour);
      setState(() {
        _gateOpen          = false;
        _remaining         = target.difference(now);
        _tomorrowRemaining = Duration.zero;
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

    // プロフィール初回設定後に通知時刻を再読込
    ref.listen<AppState>(appProvider, (prev, next) {
      if ((prev?.ownProfile == null) && next.ownProfile != null) {
        _init();
      }
    });

    // 設定画面で時刻が変更されたら即座に反映
    ref.listen<int>(notifHourProvider, (_, newHour) {
      if (mounted && _notifHour != newHour) {
        setState(() => _notifHour = newHour);
        _startCountdown();
      }
    });

    final todayUnrev  = state.encounters.where((e) => _isRevealBatch(e) && !e.isRevealed).toList();
    final todayRev    = state.encounters.where((e) => _isRevealBatch(e) && e.isRevealed).toList();
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

        // ─── サイン波（間欠スキャン中を静かに表示）─────────────────────────
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
                  state.isRunning ? '約2分に1回 定期スキャン中' : '停止中',
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

        // ─── 開封前（ゲートロック）──────────────────────────────────────────
        if (!_gateOpen && !alreadyDone)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _GateLocked(
              remaining: _remaining,
              notifHour: _notifHour,
            ),
          ),

        // ─── 0:00 設定: 今日の出会いは翌日 00:00 まで閉鎖 ─────────────────
        if (_gateOpen && _notifHour == 0 && todayUnrev.isEmpty && !alreadyDone)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ZeroHourWaiting(remaining: _tomorrowRemaining),
          ),

        // ─── 開封可能（まだ未確認がある）───────────────────────────────────
        if (_gateOpen && !alreadyDone && (_notifHour != 0 || todayUnrev.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                children: [
                  if (_notifHour != 0) ...[
                    Text(
                      '${_notifHour.toString().padLeft(2, '0')}:00 になりました',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 16),
                  ],
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

    // レアリティに応じたカード背景装飾
    final cardBg = _rarityCardBackground(rarity, context);

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
                      // レアリティラベル（枠のみ、回数は非表示）
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: rarityBorderColor(rarity).withOpacity(0.7)),
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

                      // アバター
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

                      // 名前
                      Text(
                        encounter.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: rarity == CardRarity.common ? null : Colors.white,
                            ),
                      ),
                      const SizedBox(height: 20),

                      Divider(
                        color: rarity == CardRarity.common
                            ? null
                            : Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),

                      // 詳細（回数は非表示 → 初めて出会った日のみ）
                      _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: '初めて出会った日',
                          value: fmtDate(encounter.firstMet),
                          light: rarity != CardRarity.common),
                      _InfoRow(
                          icon: Icons.workspace_premium_outlined,
                          label: 'バッジ',
                          value: '---',
                          light: rarity != CardRarity.common),

                      const SizedBox(height: 12),
                      Divider(
                        color: rarity == CardRarity.common
                            ? null
                            : Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(height: 12),

                      // 定型文
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: rarity == CardRarity.common
                              ? Theme.of(context).colorScheme.surfaceContainerLow
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
                                  color: rarity == CardRarity.common
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
                                      ? Theme.of(context).colorScheme.outline
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
            style: TextStyle(fontSize: 11,
                color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// レアリティに応じたカード背景
BoxDecoration _rarityCardBackground(CardRarity r, BuildContext context) {
  switch (r) {
    case CardRarity.hologram:
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFB721FF), Color(0xFF21D4FD),
                   Color(0xFFFF6B6B), Color(0xFFFFE66D)],
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
            color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
      );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool light; // レアリティカード上では白テキスト
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
            Icon(icon, size: 16,
                color: light ? Colors.white70
                    : Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: light ? Colors.white70
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

// ─── 0:00 設定: 翌日 00:00 まで待機 ─────────────────────────────────────────

class _ZeroHourWaiting extends StatelessWidget {
  final Duration remaining;
  const _ZeroHourWaiting({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final h  = remaining.inHours.toString().padLeft(2, '0');
    final mm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.schedule_outlined, size: 64,
            color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 20),
        Text('今日の出会いは',
            style: TextStyle(fontSize: 14,
                color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 4),
        Text('明日 00:00 から確認できます',
            style: TextStyle(fontSize: 14,
                color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 20),
        Text('$h:$mm:$ss',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w300,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 4,
            )),
      ],
    );
  }
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
          trailing: Text(
              encounterLabel(encounter.meetCount),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: encounterLabelColor(encounter.meetCount, context))),
        ),
      ),
    );
  }
}
