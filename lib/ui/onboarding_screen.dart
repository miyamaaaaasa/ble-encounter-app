import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dot_avatar.dart';
import '../services/notification_service.dart';
import 'theme/palette.dart';
import 'widgets/pixel_world.dart';
import 'widgets/user_icon.dart';

/// UI only. The caller still owns initial setup and OS permissions.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  static const _prefKey = 'onboarding_done_v1';
  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_prefKey) ?? false;
  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_prefKey, true)) {
      throw StateError('Tutorial completion could not be saved');
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final AnimationController _life =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat(reverse: true);
  int _page = 0;
  bool _saving = false;
  String? _error;
  static const _titles = [
    'ようこそ\nきょうの広場へ',
    'すれ違うと、\n気配が届く',
    '時間になったら\n門をあける',
    'はじめまして と\nまた会えた！',
    'さあ、広場を\nはじめましょう',
  ];
  static const _stories = [
    'ここは、日常ですれ違った\n誰かの気配が集まる、小さな広場です。',
    '日常の中ですれ違うと、\nその人の気配が きょうの広場に届きます。',
    '1日に3回、門がひらきます。\nその時間までに届いた気配と出会えます。',
    '門をあけると、\nいろいろな出会いが待っています。',
    '近くにいる誰かの気配を受け取るために、\nBluetoothを使います。',
  ];
  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await OnboardingScreen.markDone();
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存できませんでした。もう一度お試しください。';
        });
      }
    }
  }

  void _go(int page) => _pages.animateToPage(page,
      duration: Duration(
          milliseconds: MediaQuery.of(context).disableAnimations ? 1 : 450),
      curve: Curves.easeInOutCubic);
  @override
  void dispose() {
    _pages.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced && _life.isAnimating) _life.stop();
    if (!reduced && !_life.isAnimating) _life.repeat(reverse: true);
    return Scaffold(
        backgroundColor: Palette.nightSky,
        body: AnimatedBuilder(
            animation: _pages,
            builder: (context, _) {
              final progress = _pages.hasClients ? (_pages.page ?? 0.0) : 0.0;
              final dusk = ((progress - 1) / 3).clamp(0.0, 1.0);
              return Stack(fit: StackFit.expand, children: [
                PixelWorld(
                    night: false,
                    offset: reduced ? 0 : progress * 9,
                    child: const SizedBox.expand()),
                Opacity(
                    opacity: dusk,
                    child: PixelWorld(
                        night: true,
                        offset: reduced ? 0 : progress * 12,
                        child: const SizedBox.expand())),
                if (progress > 1 && progress < 3)
                  IgnorePointer(
                      child: ColoredBox(
                          color: Palette.coralDeep.withValues(
                              alpha: .12 * (1 - (progress - 2).abs())))),
                SafeArea(
                    child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                      child: Row(children: [
                        const Expanded(
                            child: Text('きょうの広場 / はじめての散歩',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(color: Colors.black, blurRadius: 5)
                                    ]))),
                        if (_page < 4)
                          TextButton(
                              onPressed: _saving ? null : () => _go(4),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor:
                                      Palette.nightSky.withValues(alpha: .8)),
                              child: const Text('スキップ')),
                      ])),
                  Expanded(
                      child: PageView.builder(
                          controller: _pages,
                          itemCount: 5,
                          onPageChanged: (p) => setState(() => _page = p),
                          itemBuilder: (context, page) =>
                              _story(page, reduced))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
                      child: Column(children: [
                        if (_error != null)
                          _paper(Text(_error!, style: Ts.body)),
                        SizedBox(
                            width: double.infinity,
                            child: TextButton(
                                key: const ValueKey('tutorial-next'),
                                onPressed: _saving
                                    ? null
                                    : () =>
                                        _page == 4 ? _finish() : _go(_page + 1),
                                style: TextButton.styleFrom(
                                    backgroundColor: Palette.coralDeep,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                            color: Colors.white, width: 1.5))),
                                child: Text(
                                    _saving
                                        ? '保存中…'
                                        : _page == 4
                                            ? '広場をはじめる'
                                            : 'つぎへ',
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800)))),
                        Semantics(
                            label: '全5ページ中、${_page + 1}ページ',
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                    5,
                                    (i) => SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: Center(
                                            child: Container(
                                                width: i == _page ? 12 : 7,
                                                height: i == _page ? 12 : 7,
                                                decoration: BoxDecoration(
                                                    color: i == _page
                                                        ? Colors.white
                                                        : Palette.nightSky,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: Colors
                                                            .white)))))))),
                      ])),
                ])),
              ]);
            }));
  }

  Widget _story(int page, bool reduced) => LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
          key: ValueKey('tutorial-page-$page'),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 24)),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _paper(Column(
                        crossAxisAlignment: page == 0
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          Text(_titles[page],
                              style: Ts.heading,
                              textAlign: page == 0
                                  ? TextAlign.center
                                  : TextAlign.left),
                          const SizedBox(height: 10),
                          Text(_stories[page],
                              style: Ts.body.copyWith(fontSize: 14),
                              textAlign: page == 0
                                  ? TextAlign.center
                                  : TextAlign.left),
                        ])),
                    const SizedBox(height: 12),
                    _scene(page, reduced),
                    const SizedBox(height: 12),
                    if (page == 1)
                      _paper(_fact(Icons.bluetooth, 'Bluetoothですれ違いを検知',
                          '位置情報（GPS）は使用しません。')),
                    if (page == 2)
                      _paper(Text(
                          '門をあけるまでは、だれと出会えたかは、まだわかりません。\nどんな出会いが待っているか、おたのしみに！',
                          style: Ts.body)),
                    if (page == 3)
                      _paper(Text(
                          '出会った人は図鑑に残ります。\n同じ人とまたすれ違うと「また会えた！」に。\nじぶんのドット絵やひとことも設定できます。',
                          style: Ts.body)),
                    if (page == 4)
                      _paper(Column(children: [
                        _fact(Icons.bluetooth, 'Bluetoothの使用',
                            'すれ違いの気配を受け取るために使用します。'),
                        const SizedBox(height: 14),
                        _fact(Icons.location_off_outlined, '位置情報は使用しません',
                            'GPS・現在地の取得は行いません。'),
                        const SizedBox(height: 14),
                        _fact(Icons.lock_outline, '本名・連絡先は不要です',
                            'ドット絵や選んだ自己紹介で出会います。'),
                      ])),
                  ]))));
  Widget _paper(Widget child) => PixelPanel(child: child);
  Widget _fact(IconData icon, String title, String body) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 25, color: Palette.sky),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Ts.title),
          const SizedBox(height: 3),
          Text(body, style: Ts.body)
        ])),
      ]);
  Widget _scene(int page, bool reduced) {
    if (page == 3) {
      return Column(children: [
        Row(children: [
          Expanded(
              child: Column(children: [
            _paper(Text('はじめまして！', style: Ts.body)),
            const SizedBox(height: 16),
            _resident(false, reduced)
          ])),
          const SizedBox(width: 16),
          Expanded(
              child: Column(children: [
            _paper(Text('また会えた！', style: Ts.body)),
            const SizedBox(height: 16),
            _resident(true, reduced)
          ])),
        ]),
        const SizedBox(height: 24),
        _paper(Column(children: [
          Row(children: [
            Icon(Icons.menu_book_outlined, color: Palette.ink),
            const SizedBox(width: 8),
            Text('図鑑', style: Ts.title)
          ]),
          const SizedBox(height: 14),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_demo(46), _demo(46), _silhouette(46)]),
        ])),
      ]);
    }
    final extra = page == 2
        ? math.max(0.0, MediaQuery.textScalerOf(context).scale(13.5) - 13.5) * 6
        : 0.0;
    return SizedBox(
        height: page == 4 ? 190 : 260 + extra,
        child: Stack(alignment: Alignment.center, children: [
          if (page == 2)
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                        3,
                        (i) => Flexible(
                                child: _paper(Column(children: [
                              Image.asset(
                                  const [
                                    'assets/gate/gate_morning.png',
                                    'assets/gate/gate_noon.png',
                                    'assets/gate/gate_night.png'
                                  ][i],
                                  width: 28,
                                  height: 28,
                                  filterQuality: FilterQuality.none),
                              Text(
                                  '${const [
                                    'あさ',
                                    'ひる',
                                    'よる'
                                  ][i]}\n${NotificationService.gateHours[i]}:00',
                                  style: Ts.body,
                                  textAlign: TextAlign.center),
                            ])))))),
          if (page != 1)
            Positioned(
                top: page == 2 ? 115 + extra : 10,
                child: const SizedBox(
                    width: 110, height: 125, child: PixelDoor(open: .15))),
          if (page == 1 || page == 2) ...[
            Positioned(
                left: 12,
                top: page == 2 ? 155 + extra : 35,
                child: _silhouette(50)),
            Positioned(
                right: 10,
                top: page == 2 ? 155 + extra : 75,
                child: _silhouette(60)),
            if (page == 1) Positioned(left: 30, bottom: 16, child: _demo(52)),
          ],
          Positioned(
              bottom: 0,
              child: AnimatedBuilder(
                  animation: _life,
                  builder: (context, child) => Transform.translate(
                      offset: Offset(
                          reduced ? 0 : math.sin(_life.value * math.pi) * 5,
                          reduced ? 0 : -_life.value * 3),
                      child: child),
                  child: const UserIcon(
                      size: 76, background: Colors.transparent))),
        ]));
  }

  // ponytail: default faces stand in for approved tutorial sprites;
  // demo residents never read real unrevealed encounters.
  Widget _demo(double size) => DotAvatarView(
      avatar: OwnAvatarNotifier.defaultFace,
      sizePx: size,
      background: Colors.transparent);
  Widget _silhouette(double size) => Semantics(
      label: 'まだ正体のわからない気配',
      child: SizedBox(
          width: size,
          height: size * 1.2,
          child: CustomPaint(painter: _Presence())));
  Widget _resident(bool reunion, bool reduced) => AnimatedBuilder(
      animation: _life,
      builder: (context, _) => Transform.translate(
          offset: Offset(
              0,
              reduced
                  ? 0
                  : -math.sin(_life.value * math.pi) * (reunion ? 5 : 2)),
          child: Column(children: [
            if (reunion) Icon(Icons.favorite, color: Palette.coral, size: 18),
            _demo(64),
          ])));
}

class _Presence extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 10;
    final paint = Paint()..color = Palette.nightSky.withValues(alpha: .88);
    for (final r in [
      const Rect.fromLTWH(3, 0, 4, 1),
      const Rect.fromLTWH(2, 1, 6, 5),
      const Rect.fromLTWH(1, 6, 8, 4),
      const Rect.fromLTWH(2, 10, 2, 2),
      const Rect.fromLTWH(6, 10, 2, 2)
    ]) {
      canvas.drawRect(
          Rect.fromLTWH(
              r.left * unit, r.top * unit, r.width * unit, r.height * unit),
          paint);
    }
  }

  @override
  bool shouldRepaint(_Presence oldDelegate) => false;
}
