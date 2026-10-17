import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/encounter_record.dart';
import '../encounter_detail_sheet.dart';
import '../theme/palette.dart';
import 'peer_icon.dart';

/// One person and their own message at a time; hidden encounters never enter it.
class EncounterHighlights extends StatefulWidget {
  final List<EncounterRecord> people;
  const EncounterHighlights({super.key, required this.people});
  @override
  State<EncounterHighlights> createState() => _EncounterHighlightsState();
}

class _EncounterHighlightsState extends State<EncounterHighlights> {
  final _pages = PageController(viewportFraction: .92);
  int _selected = 0;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EncounterHighlights oldWidget) {
    super.didUpdateWidget(oldWidget);
    final length = widget.people.where((e) => e.isRevealed).length;
    if (_selected >= length) {
      _selected = max(0, length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_selected);
      });
    }
  }

  void _go(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(index,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.people.where((e) => e.isRevealed).toList();
    if (people.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, bounds) {
      final width = max(1.0, bounds.maxWidth * .92 - 26);
      double textHeight(String text, TextStyle style, {int? lines}) {
        final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: lines)
          ..layout(maxWidth: width);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      final nameStyle = Ts.title.copyWith(height: 1.3);
      final hintStyle = Ts.caption.copyWith(height: 1.4);
      final height = people
          .map((e) =>
              170 +
              textHeight(e.template.phraseText, Ts.body) +
              textHeight(e.name, nameStyle, lines: 2) +
              textHeight('タップでプロフィール', hintStyle))
          .reduce(max);
      return Column(children: [
        SizedBox(
            height: height,
            child: PageView.builder(
                controller: _pages,
                itemCount: people.length,
                onPageChanged: (i) => setState(() => _selected = i),
                itemBuilder: (context, i) {
                  final person = people[i];
                  return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Palette.ink,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 12)),
                          onPressed: () =>
                              EncounterDetailSheet.show(context, person),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(person.template.phraseText,
                                    textAlign: TextAlign.center,
                                    style: Ts.body),
                                const SizedBox(height: 18),
                                PeerIcon(
                                    encounter: person,
                                    size: 100,
                                    circle: false,
                                    radius: 4),
                                const SizedBox(height: 14),
                                Text(person.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: nameStyle),
                                const SizedBox(height: 6),
                                Text('タップでプロフィール', style: hintStyle),
                              ])));
                })),
        if (people.length > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: '前の人',
                icon: const Icon(Icons.chevron_left),
                color: Palette.ink,
                onPressed: _selected > 0 ? () => _go(_selected - 1) : null),
            Text('${_selected + 1} / ${people.length}', style: Ts.caption),
            IconButton(
                tooltip: '次の人',
                icon: const Icon(Icons.chevron_right),
                color: Palette.ink,
                onPressed: _selected < people.length - 1
                    ? () => _go(_selected + 1)
                    : null),
          ]),
      ]);
    });
  }
}
