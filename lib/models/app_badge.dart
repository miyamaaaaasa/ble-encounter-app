import 'dart:convert';

enum BadgeCategory { count, region, special }

class AppBadge {
  final String id;
  final String title;
  final String emoji;
  final String description;
  final DateTime earnedAt;
  final BadgeCategory category;

  const AppBadge({
    required this.id,
    required this.title,
    required this.emoji,
    required this.description,
    required this.earnedAt,
    required this.category,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'desc': description,
        'at': earnedAt.toIso8601String(),
        'cat': category.index,
      };

  static AppBadge fromMap(Map<String, dynamic> m) => AppBadge(
        id: m['id'] as String,
        title: m['title'] as String,
        emoji: m['emoji'] as String? ?? '🏅',
        description: m['desc'] as String? ?? '',
        earnedAt: DateTime.parse(m['at'] as String),
        category: BadgeCategory.values[m['cat'] as int? ?? 0],
      );

  static String encodeList(List<AppBadge> list) =>
      jsonEncode(list.map((b) => b.toMap()).toList());

  static List<AppBadge> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => AppBadge.fromMap(e as Map<String, dynamic>)).toList();
  }

  // Count badge definition（100単位）
  static AppBadge forCount(int n) => AppBadge(
        id: 'count_$n',
        title: '${n}人達成',
        emoji: _countEmoji(n),
        description: '累計 $n 人とすれ違いました',
        earnedAt: DateTime.now(),
        category: BadgeCategory.count,
      );

  static String _countEmoji(int n) {
    if (n >= 1000) return '💎';
    if (n >= 500)  return '👑';
    if (n >= 300)  return '🥇';
    if (n >= 200)  return '🥈';
    return '🥉';
  }
}
