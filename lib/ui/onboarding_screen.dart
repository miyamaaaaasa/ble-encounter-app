import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/palette.dart';
import 'widgets/ui_kit.dart';

/// 初回起動時のオンボーディング。
/// スワイプ形式・スキップ可能・設定から再閲覧可能。
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  static const _prefKey = 'onboarding_done_v1';

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  final String art; // 絵文字アート or アセットパス
  final bool isAsset;
  final String title;
  final String body;
  const _Page(this.art, this.title, this.body, {this.isAsset = false});
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  static const _pages = <_Page>[
    _Page('👋', 'ようこそ！',
        '「はじめましてこんにちは」は、\nBluetoothですれ違った人との\n出会いを楽しむコミュニティゲームです。\n\nGPSは使いません。あなたの場所は誰にも分かりません。'),
    _Page('🎨', 'じぶんのドット絵をつくろう',
        '「じぶん」タブで、あなただけの\nドット絵アイコンを描けます。\n\nこのアイコンがあなたの分身になります。'),
    _Page('💬', 'ひとことを設定しよう',
        'プロフィールで「ひとこと」を選ぶと、\nすれ違った相手にあなたの雰囲気が伝わります。\n\n本名も連絡先も必要ありません。'),
    _Page('📡', 'すれ違おう',
        'アプリを持って外に出るだけ。\n近くの誰かと電波がすれ違うと、\nこっそり記録されます。'),
    _Page('👻', '「気配」を感じよう',
        'すれ違った瞬間には相手は分かりません。\n「誰かとすれ違えています…！」\nという気配だけが届きます。\n\nお楽しみは開門まで取っておく仕組みです。'),
    _Page('assets/gate/gate_morning.png', '開門を待とう',
        '朝9時・昼12時・夜21時。\n1日3回の「開門」で、\nすれ違った人たちとやっと出会えます。',
        isAsset: true),
    _Page('assets/icons/tab_kakera.png', 'カケラを集めよう',
        '出会った人のドット絵は\n「カケラ」としてコレクションされます。\n\n夜空にカケラを集めていこう。',
        isAsset: true),
    _Page('⚔️', 'ミニゲームで遊ぼう',
        '今日出会った人たちは、\nRPGの勇者や水族館の魚になって\nゲームに登場します。'),
    _Page('🌞', 'さあ、はじめよう！',
        '外に出て、まだ見ぬ誰かと\n「はじめましてこんにちは」。'),
  ];

  Future<void> _finish() async {
    await OnboardingScreen.markDone();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: Palette.cream,
      body: SafeArea(
        child: Column(
          children: [
            // スキップ
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: Text('スキップ',
                      style: TextStyle(
                          color: Palette.inkSoft,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SoftPanel(
                          padding: const EdgeInsets.all(28),
                          radius: 32,
                          child: p.isAsset
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.asset(p.art,
                                      width: 96, height: 96,
                                      fit: BoxFit.cover),
                                )
                              : Text(p.art,
                                  style: const TextStyle(fontSize: 72)),
                        ),
                        const SizedBox(height: 36),
                        Text(p.title,
                            style: Ts.heading, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(p.body,
                            style: Ts.body.copyWith(height: 1.7),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ページドット
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final sel = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: sel ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: sel ? Palette.coral : Palette.inkFaint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // 次へ / はじめる
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: ChunkyButton(
                label: isLast ? 'はじめる！' : 'つぎへ',
                emoji: isLast ? '🌞' : null,
                onTap: () {
                  if (isLast) {
                    _finish();
                  } else {
                    _ctrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
