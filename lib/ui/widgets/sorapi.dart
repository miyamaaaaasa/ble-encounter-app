import 'dart:async';
import 'package:flutter/material.dart';

enum SorapiMood {
  idle,
  walk,
  wait,
  wave,
  happy,
  jump,
  sit,
  sleep,
  trouble,
  think,
  book,
  discover
}

/// A world guide, never an EncounterRecord or a countable resident.
class Sorapi extends StatefulWidget {
  final SorapiMood mood;
  final double size;
  final bool animate;
  const Sorapi(
      {super.key,
      this.mood = SorapiMood.idle,
      this.size = 72,
      this.animate = true});
  @override
  State<Sorapi> createState() => _SorapiState();
}

class _SorapiState extends State<Sorapi> with WidgetsBindingObserver {
  Timer? _timer;
  ScrollPosition? _scroll;
  int _frame = 0;
  bool _foreground = true;
  List<String> get _frames => switch (widget.mood) {
        SorapiMood.walk => ['walk_0', 'walk_1', 'walk_2', 'walk_3', 'walk_4'],
        SorapiMood.idle => [
            'idle',
            'idle',
            'idle',
            'blink',
            'idle',
            'look',
            'idle'
          ],
        _ => [widget.mood.name],
      };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll?.removeListener(_sync);
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  @override
  void didUpdateWidget(Sorapi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _frame = 0;
    _sync();
  }

  bool get _visible {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final y = box.localToGlobal(Offset.zero).dy;
    return y + box.size.height > 0 && y < MediaQuery.sizeOf(context).height;
  }

  void _sync() {
    final active = _foreground &&
        widget.animate &&
        (_frames.length > 1 ||
            const {SorapiMood.wave, SorapiMood.happy, SorapiMood.jump}
                .contains(widget.mood)) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        _visible;
    if (!active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted) return;
      if (!_visible) {
        _sync();
        return;
      }
      setState(() => _frame++);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll?.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = !widget.animate || MediaQuery.disableAnimationsOf(context);
    final phase = reduced ? 0 : _frame % 8;
    final dy = switch (widget.mood) {
      SorapiMood.jump => phase < 4 ? -phase * 2.0 : -(7 - phase) * 2.0,
      SorapiMood.walk ||
      SorapiMood.happy ||
      SorapiMood.wave =>
        phase.isEven ? -1.0 : 0.0,
      _ => 0.0,
    };
    return Semantics(
      label: 'そらぴ、広場の案内役',
      image: true,
      child: RepaintBoundary(
          child: SizedBox(
              width: widget.size,
              height: widget.size * 1.125,
              child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Image.asset(
                      'assets/mascot/sorapi/${_frames[_frame % _frames.length]}.png',
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true)))),
    );
  }
}
