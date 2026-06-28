import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_badge.dart';

class BadgeService {
  static const _key = 'app_badges_v1';

  static Future<List<AppBadge>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    try { return AppBadge.decodeList(json); } catch (_) { return []; }
  }

  static Future<void> save(List<AppBadge> badges) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, AppBadge.encodeList(badges));
  }

  // 初回プロフィール設定時のスタートバッジを付与
  static Future<List<AppBadge>> awardStartBadge(List<AppBadge> existing) async {
    if (existing.any((b) => b.id == 'special_start')) return existing;
    final updated = [...existing, AppBadge.starter()];
    await save(updated);
    return updated;
  }

  // 人数マイルストーンバッジを確認・付与
  // 基準: 1人, 10人, 50人, 100人, 以降100単位
  static Future<List<AppBadge>> checkCountBadges({
    required int totalRevealed,
    required List<AppBadge> existing,
  }) async {
    final milestones = _milestonesUpTo(totalRevealed);
    final newBadges = <AppBadge>[];
    for (final m in milestones) {
      final id = 'count_$m';
      if (!existing.any((b) => b.id == id)) {
        final badge = AppBadge.forCountMilestone(m);
        if (badge != null) newBadges.add(badge);
      }
    }
    if (newBadges.isEmpty) return existing;
    final updated = [...existing, ...newBadges];
    await save(updated);
    return updated;
  }

  // 達成済みマイルストーンの一覧を返す
  static List<int> _milestonesUpTo(int total) {
    final result = <int>[];
    if (total >= 1)  result.add(1);
    if (total >= 10) result.add(10);
    if (total >= 50) result.add(50);
    // 100単位
    for (int m = 100; m <= total; m += 100) {
      result.add(m);
    }
    return result;
  }
}
