import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ble_config.dart';
import '../models/encounter_record.dart';
import '../providers/ble_providers.dart';
import '../providers/broadcast_provider.dart';
import 'encounter_helpers.dart';
import 'encounter_detail_sheet.dart';
import 'gate_reveal_screen.dart';
import 'theme/palette.dart';
import 'widgets/peer_icon.dart';
import 'widgets/pixel_world.dart';
import 'widgets/ui_kit.dart';
import 'widgets/sorapi.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});
  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _clockTimer, _bannerTimer;
  bool _showBanner = false;
  double _scroll = 0;
  final _opened = <DateTime>{};
  // ponytail: session-only playback receipts; persist UI receipts separately
  // if suppressing replay across process/theme reconstruction is required.
  final _celebrated = <String>{};
  late final AnimationController _celebration;
  int _celebrationCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _celebration =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _celebrateOnOpen());
  }

  void _celebrateOnOpen() {
    if (!mounted) return;
    final now = DateTime.now();
    final list = ref
        .read(appProvider)
        .encounters
        .where((e) =>
            e.isRevealed &&
            AppNotifier.gatesToShow(now)
                .contains(AppNotifier.gateTimeFor(e.lastMet)))
        .toList();
    if (list.isNotEmpty) {
      _opened.addAll(AppNotifier.gatesToShow(now).where((g) =>
          !now.isBefore(g) &&
          !ref.read(appProvider).encounters.any((e) =>
              !e.isRevealed && AppNotifier.gateTimeFor(e.lastMet) == g)));
    }
    final fresh = list
        .where((e) =>
            !_celebrated.contains('${e.peerId}:${e.lastMet.toIso8601String()}'))
        .toList();
    if (fresh.isEmpty) return;
    _celebrated
        .addAll(fresh.map((e) => '${e.peerId}:${e.lastMet.toIso8601String()}'));
    setState(() => _celebrationCount = list.length);
    if (!MediaQuery.disableAnimationsOf(context)) _celebration.forward(from: 0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _celebrateOnOpen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _bannerTimer?.cancel();
    _celebration.dispose();
    super.dispose();
  }

  Future<void> _open(DateTime gate, List<EncounterRecord> people) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GateRevealScreen(
                encounters: people,
                date: DateTime.now(),
                onReveal: () async {
                  await ref.read(appProvider.notifier).revealToday();
                  if (!mounted) return;
                  _bannerTimer?.cancel();
                  _bannerTimer = null;
                  setState(() {
                    _showBanner = false;
                    _opened.addAll(AppNotifier.gatesToShow(DateTime.now())
                        .where((g) => !DateTime.now().isBefore(g)));
                  });
                  _celebrated.addAll(people.map(
                      (e) => '${e.peerId}:${e.lastMet.toIso8601String()}'));
                })));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final broadcast = ref.watch(broadcastProvider);
    ref.listen<AppState>(appProvider, (prev, next) {
      if (next.hasNewEncounter &&
          !(prev?.hasNewEncounter ?? false) &&
          _bannerTimer == null) {
        _bannerTimer = Timer(Duration(minutes: 10 + Random().nextInt(21)), () {
          if (mounted) setState(() => _showBanner = true);
        });
      }
      if ((prev?.isLoading ?? true) && !next.isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _celebrateOnOpen());
      }
    });
    final now = DateTime.now();
    final gates = AppNotifier.gatesToShow(now);
    final today = state.encounters
        .where((e) =>
            e.isRevealed && gates.contains(AppNotifier.gateTimeFor(e.lastMet)))
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));
    final available = gates
        .where((g) =>
            (kGateAlwaysOpen || !now.isBefore(g)) &&
            (!_opened.contains(g) ||
                state.encounters.any((e) =>
                    !e.isRevealed && AppNotifier.gateTimeFor(e.lastMet) == g)))
        .toList();
    // UI chooses the oldest pending gate first; provider's gate calculation and
    // revealToday remain the source of truth, including tomorrow's 09:00 gate.
    final pendingGates = available
        .where((g) => state.encounters.any(
            (e) => !e.isRevealed && AppNotifier.gateTimeFor(e.lastMet) == g))
        .toList();
    final gate = pendingGates.isNotEmpty
        ? pendingGates.first
        : available.isNotEmpty
            ? available.last
            : gates.firstWhere((g) => now.isBefore(g),
                orElse: () => DateTime(now.year, now.month, now.day + 1, 9));
    final canOpen = kGateAlwaysOpen || !now.isBefore(gate);
    final pending = state.encounters
        .where((e) =>
            (e.isRevealed &&
                gates.contains(AppNotifier.gateTimeFor(e.lastMet))) ||
            (!e.isRevealed &&
                (kGateAlwaysOpen ||
                    !now.isBefore(AppNotifier.gateTimeFor(e.lastMet)))))
        .toList();
    final start = DateTime(now.year, now.month, now.day);
    final history = state.encounters
        .where((e) =>
            e.isRevealed &&
            e.lastMet.isBefore(start) &&
            e.lastMet.isAfter(start.subtract(const Duration(days: 30))))
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));
    String two(int n) => n.toString().padLeft(2, '0');
    final tomorrow =
        gate.day != now.day || gate.month != now.month || gate.year != now.year;
    final gateLabel =
        '${tomorrow ? 'あしたの' : ''}${gate.hour == 9 ? '朝' : gate.hour == 12 ? '昼' : '夜'}の開門';

    return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0) setState(() => _scroll = n.metrics.pixels);
          return false;
        },
        child: Stack(children: [
          Positioned.fill(
              child: PixelWorld(
                  offset: _scroll,
                  strength: 1,
                  child: const SizedBox.expand())),
          CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: ColoredBox(
                    color: Palette.cream.withValues(alpha: .94),
                    child: ScreenHeader(
                        title: 'きょうの広場',
                        asset: 'assets/icons/nav_today.png',
                        trailing: state.isRunning
                            ? null
                            : PixelPanel(
                                padding: const EdgeInsets.all(8),
                                child: Text('停止中', style: Ts.caption))))),
            if (broadcast.banner != null)
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: PixelPanel(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(broadcast.banner!.title,
                                      style: Ts.title),
                                  Text(broadcast.banner!.body, style: Ts.body)
                                ])),
                            IconButton(
                                tooltip: 'お知らせを閉じる',
                                icon: Icon(Icons.close, color: Palette.ink),
                                onPressed: () => ref
                                    .read(broadcastProvider.notifier)
                                    .dismissBanner()),
                          ])))),
            if (_showBanner)
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: PixelPanel(
                          child: Row(children: [
                        Icon(Icons.people_outline, color: Palette.ink),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text('だれかの気配が届いているよ\n次の開門で会えるよ',
                                style: Ts.body))
                      ])))),
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(36, 40, 36, 24),
                    child: Column(children: [
                      SizedBox(
                          height: 180,
                          child: Stack(alignment: Alignment.center, children: [
                            const PixelDoor(),
                            Positioned(
                                right: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                    child: Sorapi(
                                        size: 68,
                                        mood: !state.isRunning
                                            ? SorapiMood.trouble
                                            : !canOpen &&
                                                    gate
                                                            .difference(now)
                                                            .inMinutes <=
                                                        5
                                                ? SorapiMood.think
                                                : SorapiMood.wait))),
                          ])),
                      const SizedBox(height: 24),
                      PixelPanel(
                          child: Column(children: [
                        Text(gateLabel, style: Ts.caption),
                        Text('${two(gate.hour)}:00',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Palette.ink)),
                        if (!canOpen)
                          _GateCountdown(
                              gate: gate,
                              onDone: () {
                                if (mounted) setState(() {});
                              })
                      ])),
                      if (canOpen) ...[
                        const SizedBox(height: 12),
                        WorldButton(
                            label: '門をあける', onTap: () => _open(gate, pending))
                      ],
                    ]))),
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: PixelPanel(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('きょうの出会い', style: Ts.title),
                          const SizedBox(height: 12),
                          if (today.isEmpty) ...[
                            Row(
                                children: List.generate(
                                    4,
                                    (_) => Expanded(
                                        child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: AspectRatio(
                                                aspectRatio: 1,
                                                child: ColoredBox(
                                                    color: Palette.cream,
                                                    child: Center(
                                                        child: Text('?',
                                                            style: TextStyle(
                                                                fontSize: 28,
                                                                color: Palette
                                                                    .inkSoft))))))))),
                            const SizedBox(height: 8),
                            Text('門がひらくと、きょうすれ違った\nみんなに会えるよ！',
                                style: Ts.caption),
                          ] else ...[
                            Text('${today.length}人 と出会いました！',
                                style: Ts.heading),
                            const SizedBox(height: 16),
                            SpeechBubble(
                                color: Palette.card,
                                text: today.first.template.phraseText,
                                pixelated: true),
                            const SizedBox(height: 16),
                            Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: today
                                    .map((e) => Semantics(
                                        button: true,
                                        label: e.name,
                                        child: GestureDetector(
                                            onTap: () =>
                                                EncounterDetailSheet.show(
                                                    context, e),
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  PeerIcon(
                                                      encounter: e,
                                                      size: today.length == 1
                                                          ? 104
                                                          : 64,
                                                      circle: false,
                                                      radius: 4),
                                                  SizedBox(
                                                      width: 80,
                                                      child: Text(e.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: Ts.caption)),
                                                ]))))
                                    .toList()),
                            const SizedBox(height: 16),
                            WorldButton(
                                label: 'みんなを見る',
                                secondary: true,
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => EncounterPeopleScreen(
                                            people: today)))),
                            const SizedBox(height: 12),
                            WorldButton(
                                label: '結果を見る・シェア',
                                secondary: true,
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => GateRevealScreen(
                                            encounters: today,
                                            date: now,
                                            resultOnly: true,
                                            onReveal: () async {})))),
                          ],
                        ])))),
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: PixelPanel(
                        child: Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            children: gates
                                .map((g) => Text(
                                    '${g.hour == 9 ? '朝' : g.hour == 12 ? '昼' : '夜'} ${two(g.hour)}:00',
                                    style: Ts.caption))
                                .toList())))),
            if (history.isNotEmpty) ...[
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: PixelPanel(
                          child: Text('さいきんの出会い', style: Ts.title)))),
              SliverList.builder(
                  itemCount: history.length,
                  itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: GestureDetector(
                          onTap: () =>
                              EncounterDetailSheet.show(context, history[i]),
                          child: PixelPanel(
                              child: Row(children: [
                            PeerIcon(
                                encounter: history[i], size: 40, circle: false),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(history[i].name, style: Ts.title),
                                  Text(
                                      '${fmtDate(history[i].lastMet)} · ${encounterLabel(history[i].meetCount)}',
                                      style: Ts.caption)
                                ])),
                          ]))))),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ]),
          Positioned.fill(
              child: IgnorePointer(
                  child: AnimatedBuilder(
                      animation: _celebration,
                      builder: (context, child) => CustomPaint(
                          painter: Celebration(
                              _celebrationCount, _celebration.value))))),
        ]));
  }
}

class _GateCountdown extends StatefulWidget {
  final DateTime gate;
  final VoidCallback onDone;
  const _GateCountdown({required this.gate, required this.onDone});
  @override
  State<_GateCountdown> createState() => _GateCountdownState();
}

class _GateCountdownState extends State<_GateCountdown> {
  late final Timer _timer;
  bool _notified = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!DateTime.now().isBefore(widget.gate) && !_notified) {
        _notified = true;
        widget.onDone();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(_GateCountdown old) {
    super.didUpdateWidget(old);
    if (old.gate != widget.gate) _notified = false;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = max(0, widget.gate.difference(DateTime.now()).inSeconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return Text(
        'あと ${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}',
        style: Ts.body);
  }
}
