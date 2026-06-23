import 'package:flutter/material.dart';

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
