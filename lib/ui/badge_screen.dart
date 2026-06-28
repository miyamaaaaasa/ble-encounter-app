import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_badge.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';

class BadgeScreen extends ConsumerWidget {
  const BadgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges  = ref.watch(appProvider.select((s) => s.badges));
    // 新しく取得した順（降順）
    final sorted  = [...badges]..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));
    final total   = sorted.length;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('バッジ'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: const Text('🏅', style: TextStyle(fontSize: 14)),
                label: Text('$total 個'),
              ),
            ),
          ],
        ),

        if (sorted.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🏅', style: TextStyle(
                    fontSize: 72,
                    color: Theme.of(context).colorScheme.outlineVariant)),
                const SizedBox(height: 20),
                Text('まだバッジがありません',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text('プロフィールを設定するとスタートバッジが届きます',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        fontSize: 13)),
              ],
            ),
          )
        else ...[
          // 獲得バッジ
          SliverList.builder(
            itemCount: sorted.length,
            itemBuilder: (ctx, i) => _BadgeTile(badge: sorted[i]),
          ),

          // 地域制覇バッジ（スタブ：coming soon）
          const SliverToBoxAdapter(
            child: _RegionBadgesSection(),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final AppBadge badge;
  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: Text(badge.emoji,
              style: const TextStyle(fontSize: 36)),
          title: Text(badge.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(badge.description),
          trailing: Text(
            fmtDate(badge.earnedAt),
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}

class _RegionBadgesSection extends StatelessWidget {
  const _RegionBadgesSection();

  static const _regions = [
    ('北海道', '🗾'), ('東北', '🌲'), ('関東', '🗼'), ('中部', '🗻'),
    ('近畿', '⛩️'), ('中国', '🌊'), ('四国', '🍊'), ('九州・沖縄', '🌺'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Row(
            children: [
              Text('地域制覇バッジ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Coming Soon',
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onTertiaryContainer)),
              ),
            ],
          ),
        ),
        ...(_regions.map((r) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Text(r.$2, style: const TextStyle(fontSize: 28)),
              title: Text(r.$1),
              subtitle: const Text('全県制覇で解放'),
              trailing: Icon(Icons.lock_outline,
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Card(
            elevation: 0,
            color: const Color(0xFFFFF8E1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const ListTile(
              leading: Text('👑', style: TextStyle(fontSize: 36)),
              title: Text('全国制覇バッジ', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('日本全47都道府県を制覇すると獲得'),
              trailing: Icon(Icons.lock_outline, color: Color(0xFFFFB300)),
            ),
          ),
        ),
      ],
    );
  }
}
