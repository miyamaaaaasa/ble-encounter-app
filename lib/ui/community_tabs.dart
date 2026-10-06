import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ble_config.dart';
import '../providers/ble_providers.dart';
import '../providers/puzzle_providers.dart';
import 'badge_screen.dart';
import 'encounter_detail_sheet.dart';
import 'encounter_helpers.dart';
import 'gate_reveal_screen.dart';
import 'minigame_screen.dart';
import 'profile_screen.dart';
import 'puzzle/puzzle_board_screen.dart';
import 'settings_screen.dart';
import 'theme/palette.dart';
import 'widgets/peer_icon.dart';
import 'widgets/pixel_world.dart';
import 'widgets/ui_kit.dart';
import 'widgets/user_icon.dart';

/// Existing full screens remain reachable with their original state/actions.
void openCommunityScreen(BuildContext context, Widget screen) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
                backgroundColor: Palette.cream,
                body: SafeArea(
                    child: Column(children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('戻る'))),
                  Expanded(child: screen),
                ])),
              )));
}

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  int _filter = 0;
  @override
  Widget build(BuildContext context) {
    final encounters = ref
        .watch(appProvider)
        .encounters
        .where((e) => e.isRevealed)
        .toList()
      ..sort((a, b) => b.lastMet.compareTo(a.lastMet));
    final shown = encounters
        .where((e) =>
            _filter == 0 || (_filter == 1 ? e.meetCount <= 1 : e.meetCount > 1))
        .toList();
    return WorldPage(
        child: CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: ScreenHeader(
              title: '図鑑',
              asset: 'assets/icons/nav_badge.png',
              trailing: TextButton(
                  onPressed: () =>
                      openCommunityScreen(context, const BadgeScreen()),
                  child: const Text('バッジ')))),
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('発見した人数 ${encounters.length}人', style: Ts.title),
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: List.generate(
                            3,
                            (i) => ChoiceChip(
                                label: Text(['すべて', 'はじめまして', '再会'][i]),
                                selected: _filter == i,
                                onSelected: (_) =>
                                    setState(() => _filter = i)))),
                  ]))),
      if (shown.isEmpty)
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: PixelPanel(
                    child: Text('まだ空いているページです。\n開門して出会った人を集めよう。',
                        style: Ts.body))))
      else
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10),
                itemCount: shown.length,
                itemBuilder: (_, i) => Semantics(
                    button: true,
                    label: '${shown[i].name}のプロフィール',
                    child: GestureDetector(
                        onTap: () =>
                            EncounterDetailSheet.show(context, shown[i]),
                        child: PixelPanel(
                            padding: const EdgeInsets.all(8),
                            child: Column(children: [
                              Expanded(
                                  child: Center(
                                      child: PeerIcon(
                                          encounter: shown[i],
                                          size: 56,
                                          circle: false,
                                          radius: 4))),
                              Text(shown[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Ts.caption),
                            ])))))),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ]));
  }
}

class GameCollectionScreen extends ConsumerWidget {
  const GameCollectionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzle = ref.watch(puzzleProvider);
    return WorldPage(
        strength: .2,
        child: ListView(children: [
          ScreenHeader(title: 'ゲーム', asset: 'assets/icons/nav_game.png'),
          Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Image.asset('assets/icons/nav_kakera.png',
                          width: 28, height: 28),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('カケラ ${puzzle.pieces.length}枚',
                              style: Ts.title))
                    ]),
                    const SizedBox(height: 20),
                    GestureDetector(
                        onTap: () => openCommunityScreen(
                            context, const PuzzleBoardScreen()),
                        child: PixelPanel(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              SizedBox(
                                  height: 170,
                                  width: double.infinity,
                                  child: PixelWorld(
                                      child: Center(
                                          child: Image.asset(
                                              'assets/icons/nav_kakera.png',
                                              width: 72,
                                              height: 72)))),
                              const SizedBox(height: 12),
                              Text('カケラのよぞら', style: Ts.heading),
                              Text('集めたカケラをならべよう', style: Ts.body),
                            ]))),
                    const SizedBox(height: 20),
                    PixelPanel(
                        child: Column(children: [
                      Image.asset('assets/icons/nav_game.png',
                          width: 64, height: 64),
                      const SizedBox(height: 12),
                      Text('ゲームセンター', style: Ts.title),
                      const SizedBox(height: 8),
                      if (kGameTabEnabled)
                        WorldButton(
                            label: 'あそぶ',
                            onTap: () => openCommunityScreen(
                                context, const MinigameScreen()))
                      else
                        Text('近日公開予定', style: Ts.body),
                    ])),
                  ])),
        ]));
  }
}

class SelfOverviewScreen extends ConsumerWidget {
  const SelfOverviewScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final profile = state.ownProfile;
    final revealed = state.encounters.where((e) => e.isRevealed).toList();
    return WorldPage(
        strength: .08,
        child: ListView(children: [
          ScreenHeader(
              title: 'じぶん',
              asset: 'assets/icons/nav_today.png',
              trailing: IconButton(
                  tooltip: '設定',
                  onPressed: () =>
                      openCommunityScreen(context, const SettingsScreen()),
                  icon: Image.asset('assets/icons/nav_settings.png',
                      width: 30, height: 30))),
          Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const UserIcon(size: 112, radius: 4),
                const SizedBox(height: 16),
                Text(profile?.name ?? 'じぶん', style: Ts.heading),
                const SizedBox(height: 12),
                SpeechBubble(
                    color: Palette.card,
                    text: profile?.template.phraseText ?? 'よろしく！',
                    pixelated: true),
                const SizedBox(height: 20),
                WorldButton(
                    label: 'プロフィールを編集',
                    secondary: true,
                    onTap: () =>
                        openCommunityScreen(context, const ProfileScreen())),
                const SizedBox(height: 20),
                PixelPanel(
                    child: Column(children: [
                  if (profile != null) ...[
                    Text(profile.template.statusText, style: Ts.body),
                    Text(
                        '${profile.template.hobbyCategoryText} · ${profile.template.hobbyDetailText}',
                        style: Ts.caption),
                    if (profile.registeredAt != null)
                      Text('広場に来た日 ${fmtDate(profile.registeredAt!)}',
                          style: Ts.caption),
                  ],
                  const SizedBox(height: 12),
                  Text('出会った人 ${revealed.length}人', style: Ts.title),
                  Text('あつめたバッジ ${state.badges.length}個', style: Ts.body),
                ])),
                const SizedBox(height: 20),
                WorldButton(
                    label: 'バッジを見る',
                    secondary: true,
                    onTap: () =>
                        openCommunityScreen(context, const BadgeScreen())),
              ])),
        ]));
  }
}
