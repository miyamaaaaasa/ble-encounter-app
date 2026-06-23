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

  // 100単位バッジを付与（未付与のマイルストーンだけ追加）
  static Future<List<AppBadge>> checkCountBadges({
    required int totalRevealed,
    required List<AppBadge> existing,
  }) async {
    final newBadges = <AppBadge>[];
    for (int milestone = 100; milestone <= totalRevealed; milestone += 100) {
      final id = 'count_$milestone';
      if (!existing.any((b) => b.id == id)) {
        newBadges.add(AppBadge.forCount(milestone));
      }
    }
    if (newBadges.isEmpty) return existing;
    final updated = [...existing, ...newBadges];
    await save(updated);
    return updated;
  }
}
