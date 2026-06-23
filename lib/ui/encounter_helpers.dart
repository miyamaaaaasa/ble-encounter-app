import 'package:flutter/material.dart';

// ─── レアリティ ───────────────────────────────────────────────────────────────
enum CardRarity { common, craft, gradient, hologram }

CardRarity cardRarityOf(int meetCount) {
  if (meetCount >= 25) return CardRarity.hologram;
  if (meetCount >= 10) return CardRarity.gradient;
  if (meetCount >= 5)  return CardRarity.craft;
  return CardRarity.common;
}

String rarityLabel(CardRarity r) => switch (r) {
  CardRarity.common   => '白',
  CardRarity.craft    => 'クラフト',
  CardRarity.gradient => 'グラデ',
  CardRarity.hologram => 'ホログラム',
};

Color rarityBorderColor(CardRarity r) => switch (r) {
  CardRarity.common   => const Color(0xFFBDBDBD),
  CardRarity.craft    => const Color(0xFFA1887F),
  CardRarity.gradient => const Color(0xFF7E57C2),
  CardRarity.hologram => const Color(0xFFFFB300),
};

BoxDecoration rarityDecoration(CardRarity r, BuildContext context) {
  switch (r) {
    case CardRarity.hologram:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D), Color(0xFF6BCB77), Color(0xFF4D96FF)],
          stops: [0.0, 0.33, 0.66, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    case CardRarity.gradient:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF7E57C2), Color(0xFF2196F3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    case CardRarity.craft:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFA1887F),
      );
    case CardRarity.common:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: const Color(0xFFBDBDBD), width: 1.5),
      );
  }
}

// アバターカラー（全画面共通）
const avatarColors = [
  Color(0xFF378ADD),
  Color(0xFF1D9E75),
  Color(0xFFD85A30),
  Color(0xFFBA7517),
  Color(0xFF534AB7),
  Color(0xFFD4537E),
];

String encounterLabel(int meetCount) {
  if (meetCount >= 50) return '伝説';
  if (meetCount >= 10) return '常連';
  if (meetCount >= 5)  return 'よく見る';
  return '見かけた';
}

Color encounterLabelColor(int meetCount, BuildContext context) {
  if (meetCount >= 50) return const Color(0xFFFFB300);
  if (meetCount >= 10) return const Color(0xFFBA68C8);
  if (meetCount >= 5)  return Theme.of(context).colorScheme.tertiary;
  return Theme.of(context).colorScheme.primary;
}

int rssiToStars(int rssi) {
  if (rssi >= -60) return 5;
  if (rssi >= -70) return 4;
  if (rssi >= -80) return 3;
  if (rssi >= -90) return 2;
  return 1;
}

String formatDateOnly(DateTime dt) {
  final now = DateTime.now();
  final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (isToday) return '今日出会った';
  final y = dt.year;
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y/$m/$d に出会った';
}

String fmtDate(DateTime dt) {
  final y = dt.year;
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}
