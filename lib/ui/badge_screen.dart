import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_badge.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';
import 'theme/palette.dart';
import 'widgets/ui_kit.dart';

/// バッジ = コレクション棚。
/// 獲得済みが並ぶだけでなく「次の目標」への進捗を見せて収集欲を刺激する。
class BadgeScreen extends ConsumerWidget {
  const BadgeScreen({super.key});

  // 次の人数マイルストーンを返す
  static (int next, int prev) _nextMilestone(int count) {
    const fixed = [1, 10, 50, 100];
    for (final m in fixed) {
      if (count < m) {
        final prevIdx = fixed.indexOf(m) - 1;
        return (m, prevIdx >= 0 ? fixed[prevIdx] : 0);
      }
    }
    final next = ((count ~/ 100) + 1) * 100;
    return (next, next - 100);
  }

  static Color _rarityColor(AppBadge b) {
    if (b.id.startsWith('count_')) {
      final n = int.tryParse(b.id.replaceFirst('count_', '')) ?? 0;
      if (n >= 500) return Palette.lavenderDeep;
      if (n >= 100) return Palette.sunDeep;
      if (n >= 50) return Palette.tealDeep;
      return Palette.sky;
    }
    return Palette.coral;
  }

  static String _rarityLabel(AppBadge b) {
    if (b.id.startsWith('count_')) {
      final n = int.tryParse(b.id.replaceFirst('count_', '')) ?? 0;
      if (n >= 500) return 'レジェンド';
      if (n >= 100) return 'ゴールド';
      if (n >= 50) return 'シルバー';
      return 'ブロンズ';
    }
    return 'スペシャル';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final badges = state.badges;
    final sorted = [...badges]..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));
    final revealedCount =
        state.encounters.where((e) => e.isRevealed).length;
    final (next, prev) = _nextMilestone(revealedCount);
    final progress =
        next == prev ? 1.0 : (revealedCount - prev) / (next - prev);

    return Container(
      color: Palette.cream,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'バッジずかん',
              emoji: '🏅',
              trailing: StatChip(
                emoji: '✨',
                label: '${sorted.length}個',
                color: Palette.lavender.withValues(alpha: 0.22),
              ),
            ),
          ),

          // ─── 次の目標 ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: SoftPanel(
                color: Palette.sun.withValues(alpha: 0.18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🎯', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        const Text('つぎの目標', style: Ts.title),
                        const Spacer(),
                        Text('${next}人とすれ違う',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Palette.sunDeep)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CandyProgress(value: progress, color: Palette.sun),
                    const SizedBox(height: 6),
                    Text(
                      'あと少し！マイルストーンに近づいています',
                      style: Ts.tiny,
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (sorted.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: SoftPanel(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: const [
                      Text('🏅', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('まだバッジがありません', style: Ts.title),
                      SizedBox(height: 6),
                      Text('プロフィールを設定するとスタートバッジが届きます',
                          style: Ts.caption),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: SectionLabel('🗃️', 'コレクション'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _BadgeCell(badge: sorted[i]),
                  childCount: sorted.length,
                ),
              ),
            ),
          ],

          // ─── 地域制覇（coming soon）───────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: SectionLabel('🗾', 'ちいき制覇（じゅんびちゅう）'),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 88,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: const [
                  _RegionChip('北海道', '🗾'),
                  _RegionChip('東北', '🌲'),
                  _RegionChip('関東', '🗼'),
                  _RegionChip('中部', '🗻'),
                  _RegionChip('近畿', '⛩️'),
                  _RegionChip('中国', '🌊'),
                  _RegionChip('四国', '🍊'),
                  _RegionChip('九州・沖縄', '🌺'),
                ],
              ),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

// ─── バッジセル ──────────────────────────────────────────────────────────────
class _BadgeCell extends StatelessWidget {
  final AppBadge badge;
  const _BadgeCell({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = BadgeScreen._rarityColor(badge);
    final rarity = BadgeScreen._rarityLabel(badge);

    return SoftPanel(
      padding: const EdgeInsets.all(14),
      shadowTint: color,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
            ),
            child: Center(
              child: Text(badge.emoji, style: const TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(height: 10),
          Text(badge.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: Palette.ink)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(rarity,
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(height: 4),
          Text(fmtDate(badge.earnedAt), style: Ts.tiny),
        ],
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  final String name;
  final String emoji;
  const _RegionChip(this.name, this.emoji);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Opacity(
        opacity: 0.55,
        child: SoftPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Palette.creamDeep,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(name,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Palette.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}
