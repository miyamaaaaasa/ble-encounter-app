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

  // スタートバッジ（初回プロフィール設定時）
  static AppBadge starter() => AppBadge(
        id: 'special_start',
        title: 'はじめましてこんにちは',
        emoji: '🌱',
        description: 'アプリを始めました！',
        earnedAt: DateTime.now(),
        category: BadgeCategory.special,
      );

  // 人数バッジ定義
  // 1人目・10人・50人・100人・以降100単位
  static AppBadge? forCountMilestone(int milestone) {
    return switch (milestone) {
      1   => AppBadge(id: 'count_1',   title: '初めてのすれ違い', emoji: '🤝',  description: '初めての出会い！', earnedAt: DateTime.now(), category: BadgeCategory.count),
      10  => AppBadge(id: 'count_10',  title: '広場の充実',      emoji: '👥',  description: '10人とすれ違いました', earnedAt: DateTime.now(), category: BadgeCategory.count),
      50  => AppBadge(id: 'count_50',  title: '50人突破',        emoji: '🎖️', description: '50人を超えました！', earnedAt: DateTime.now(), category: BadgeCategory.count),
      100 => AppBadge(id: 'count_100', title: '100人突破',       emoji: '🏅',  description: '100人を達成！', earnedAt: DateTime.now(), category: BadgeCategory.count),
      _   => milestone > 100 && milestone % 100 == 0
          ? AppBadge(id: 'count_$milestone', title: '${milestone}人突破', emoji: _countEmoji(milestone), description: '累計 $milestone 人とすれ違いました', earnedAt: DateTime.now(), category: BadgeCategory.count)
          : null,
    };
  }

  static String _countEmoji(int n) {
    if (n >= 1000) return '💎';
    if (n >= 500)  return '👑';
    if (n >= 300)  return '🥇';
    if (n >= 200)  return '🥈';
    return '🥉';
  }

  // BLE で相手に送るバッジレベル（0-255、1バイト）
  // 0: バッジなし
  // 1: スタートバッジ
  // 2: 1人達成
  // 3: 10人達成
  // 4: 50人達成
  // 5: 100人達成
  // 6+: n*100人達成 (n = badgeLevel - 4)
  static int badgeLevelFrom(List<AppBadge> badges) {
    if (badges.isEmpty) return 0;
    int level = 0;
    if (badges.any((b) => b.id == 'special_start')) level = 1;
    if (badges.any((b) => b.id == 'count_1'))   level = 2;
    if (badges.any((b) => b.id == 'count_10'))  level = 3;
    if (badges.any((b) => b.id == 'count_50'))  level = 4;
    if (badges.any((b) => b.id == 'count_100')) level = 5;
    // 100単位バッジを探す（最大値を使う）
    final countBadges = badges.where((b) => b.id.startsWith('count_')).toList();
    for (final b in countBadges) {
      final n = int.tryParse(b.id.replaceFirst('count_', '')) ?? 0;
      if (n > 100 && n % 100 == 0) {
        final l = 4 + n ~/ 100;
        if (l > level) level = l;
      }
    }
    return level.clamp(0, 255);
  }

  // バッジレベルから表示用テキストへ
  static String badgeLevelLabel(int level) {
    if (level == 0) return '';
    if (level == 1) return '🌱 スタート';
    if (level == 2) return '🤝 1人達成';
    if (level == 3) return '👥 10人達成';
    if (level == 4) return '🎖️ 50人達成';
    if (level == 5) return '🏅 100人達成';
    final n = (level - 4) * 100;
    return '${_countEmoji(n)} ${n}人達成';
  }
}
