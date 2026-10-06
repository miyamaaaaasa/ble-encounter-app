import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/encounter_record.dart';
import 'encounter_detail_sheet.dart';
import 'encounter_helpers.dart';
import 'theme/palette.dart';
import 'widgets/peer_icon.dart';
import 'widgets/pixel_world.dart';

class GateRevealScreen extends StatefulWidget {
  final List<EncounterRecord> encounters;
  final Future<void> Function() onReveal;
  final DateTime date;
  final bool resultOnly;
  const GateRevealScreen(
      {super.key,
      required this.encounters,
      required this.onReveal,
      required this.date,
      this.resultOnly = false});
  @override
  State<GateRevealScreen> createState() => _GateRevealScreenState();
}

class _GateRevealScreenState extends State<GateRevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  final _shareKey = GlobalKey();
  bool _done = false, _saving = false, _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // ponytail: first eight arrive individually, larger groups join at results;
    // max 14 seconds avoids an unbounded ceremony for festival crowds.
    _animation = AnimationController(
        vsync: this,
        duration: Duration(
            milliseconds: 1800 + min(widget.encounters.length, 8) * 1400))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
    if (widget.resultOnly) {
      _done = true;
      _animation.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_done && !_saving && !_animation.isAnimating) {
      if (MediaQuery.disableAnimationsOf(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _finish();
        });
      } else {
        _animation.forward();
      }
    }
  }

  Future<void> _finish() async {
    if (_saving || _done) return;
    _animation.stop();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onReveal();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _done = true;
      });
      _animation.duration = const Duration(seconds: 3);
      if (!MediaQuery.disableAnimationsOf(context)) {
        _animation.forward(from: 0);
      } else {
        _animation.value = 1;
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = '保存できませんでした。もう一度お試しください。';
        });
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    ui.Image? image;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _shareKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/today-share.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      final box = context.findRenderObject()! as RenderBox;
      await Share.shareXFiles([XFile(file.path)],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size);
    } catch (_) {
      if (mounted) setState(() => _error = '画像を共有できませんでした。もう一度お試しください。');
    } finally {
      image?.dispose();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.encounters;
    return PopScope(
        canPop: _done || _error != null,
        child: Scaffold(
          backgroundColor: Palette.cream,
          body: SafeArea(
              child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, _) {
                    final ms =
                        _animation.value * _animation.duration!.inMilliseconds;
                    final opening = !_done && ms < 1800;
                    final index = ((ms - 1800) / 1400)
                        .floor()
                        .clamp(0, max(0, people.length - 1))
                        .toInt();
                    return Stack(fit: StackFit.expand, children: [
                      Positioned.fill(
                          child: PixelWorld(child: const SizedBox.expand())),
                      if (_done)
                        Positioned.fill(
                            child: IgnorePointer(
                                child: CustomPaint(
                                    painter: Celebration(
                                        people.length, _animation.value)))),
                      SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: Palette.card,
                                        foregroundColor: Palette.ink),
                                    onPressed: _saving
                                        ? null
                                        : _done || _error != null
                                            ? () => Navigator.pop(context)
                                            : _finish,
                                    child: Text(
                                        _done || _error != null
                                            ? '閉じる'
                                            : 'スキップ',
                                        style: Ts.title))),
                            if (!_done) ...[
                              const SizedBox(height: 40),
                              if (opening) ...[
                                PixelDoor(open: (ms / 1800).clamp(0, 1)),
                                const SizedBox(height: 28),
                                PixelPanel(
                                    child: Text('門がひらきます…', style: Ts.title)),
                              ] else if (people.isNotEmpty) ...[
                                PixelPanel(
                                    child: Text(
                                        people[index].meetCount > 1
                                            ? 'また会えた！'
                                            : 'はじめまして！',
                                        style: Ts.heading)),
                                const SizedBox(height: 24),
                                Transform.translate(
                                    offset: Offset(
                                        0,
                                        -sin(((ms - 1800) % 1400) / 1400 * pi) *
                                            10),
                                    child: PeerIcon(
                                        encounter: people[index],
                                        size: 132,
                                        circle: false,
                                        radius: 4)),
                                const SizedBox(height: 24),
                                PixelPanel(
                                    child: Column(children: [
                                  Text(people[index].name,
                                      style: Ts.heading,
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 8),
                                  Text(encounterLabel(people[index].meetCount),
                                      style: Ts.caption),
                                  const SizedBox(height: 8),
                                  Text(people[index].template.phraseText,
                                      style: Ts.body,
                                      textAlign: TextAlign.center),
                                ])),
                              ],
                            ] else ...[
                              RepaintBoundary(
                                  key: _shareKey,
                                  child: EncounterResultCard(
                                      people: people, date: widget.date)),
                              const SizedBox(height: 16),
                              if (people.isNotEmpty)
                                WorldButton(
                                    label: 'みんなを見る',
                                    onTap: () {
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  EncounterPeopleScreen(
                                                      people: people)));
                                    }),
                              const SizedBox(height: 12),
                              WorldButton(
                                  label: _sharing ? '画像を準備中…' : 'シェアする',
                                  onTap: _sharing ? null : _share,
                                  secondary: true),
                            ],
                            if (_saving)
                              PixelPanel(
                                  child: Text('出会いを保存中…', style: Ts.body)),
                            if (_error != null)
                              PixelPanel(
                                  child: Column(children: [
                                Text(_error!, style: Ts.body),
                                if (!_done)
                                  TextButton(
                                      onPressed: _finish,
                                      child: const Text('もう一度保存する')),
                              ])),
                          ])),
                    ]);
                  })),
        ));
  }
}

/// Sharing captures only this card: no names, UID, status, precise encounter
/// timestamps, location or profile fields are exported.
class EncounterResultCard extends StatelessWidget {
  final List<EncounterRecord> people;
  final DateTime date;
  const EncounterResultCard(
      {super.key, required this.people, required this.date});
  @override
  Widget build(BuildContext context) {
    final first = people.where((e) => e.meetCount <= 1).length;
    return PixelWorld(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              PixelPanel(
                  child: Column(children: [
                Text('きょう', style: Ts.title),
                if (people.isEmpty)
                  Text('今回はだれもいなかったみたい',
                      style: Ts.title, textAlign: TextAlign.center)
                else ...[
                  Text('${people.length}人',
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: Palette.coralDeep)),
                  Text('と出会いました！', style: Ts.title),
                ],
              ])),
              const SizedBox(height: 24),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 12,
                  children: people
                      .take(20)
                      .map((e) => PeerIcon(
                          encounter: e,
                          size: people.length == 1
                              ? 120
                              : people.length > 9
                                  ? 40
                                  : 56,
                          circle: false,
                          radius: 3))
                      .toList()),
              if (people.length > 20)
                PixelPanel(
                    child:
                        Text('ほか ${people.length - 20}人', style: Ts.caption)),
              const SizedBox(height: 24),
              if (people.isNotEmpty)
                PixelPanel(
                    child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                      Text('はじめまして $first人', style: Ts.body),
                      Text('また会えた！ ${people.length - first}人', style: Ts.body),
                    ]))
              else
                PixelPanel(
                    child: Text('また、どこかで\nだれかの気配を探してみよう！',
                        style: Ts.body, textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              PixelPanel(
                  padding: const EdgeInsets.all(8),
                  child: Text('${fmtDate(date)}\nはじめましてこんにちは',
                      style: Ts.caption, textAlign: TextAlign.center)),
            ])));
  }
}

class WorldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool secondary;
  const WorldButton(
      {super.key, required this.label, this.onTap, this.secondary = false});
  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
          onTap: onTap,
          child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  color: secondary ? Palette.card : Palette.coralDeep,
                  border: Border.all(
                      color: secondary ? Palette.inkFaint : Palette.coral,
                      width: 2),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: secondary ? Palette.ink : Colors.white)))));
}

class EncounterPeopleScreen extends StatelessWidget {
  final List<EncounterRecord> people;
  const EncounterPeopleScreen({super.key, required this.people});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Palette.cream,
      body: SafeArea(
          child: Column(children: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('広場に戻る')),
        Expanded(
            child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: people.length,
                itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                        onTap: () =>
                            EncounterDetailSheet.show(context, people[i]),
                        child: PixelPanel(
                            child: Row(children: [
                          PeerIcon(
                              encounter: people[i],
                              size: 56,
                              circle: false,
                              radius: 4),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(people[i].name, style: Ts.title),
                                Text(people[i].template.phraseText,
                                    style: Ts.body),
                                Text(encounterLabel(people[i].meetCount),
                                    style: Ts.caption),
                              ])),
                        ])))))),
      ])));
}
