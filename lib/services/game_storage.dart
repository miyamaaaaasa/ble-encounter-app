import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_data.dart';

class GameStorage {
  static const _keyData   = 'game_data_v1';
  static const _keyDate   = 'game_today_date';
  // 今日分の一時的な処理済みセット（日付リセット対象）
  static const _keyTodayPiece = 'game_today_piece';
  static const _keyTodayFish  = 'game_today_fish';

  static Future<GameData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyData);
    if (raw == null) return GameData.empty();
    try {
      return GameData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return GameData.empty();
    }
  }

  static Future<void> save(GameData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyData, jsonEncode(data.toJson()));
  }

  // 今日ピースを贈ったpeerIdセット（日跨ぎでリセット）
  static Future<Set<String>> loadTodayPiece() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString(_keyDate) != today) {
      await prefs.setString(_keyDate, today);
      await prefs.remove(_keyTodayPiece);
      await prefs.remove(_keyTodayFish);
      return {};
    }
    final raw = prefs.getString(_keyTodayPiece);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> saveTodayPiece(Set<String> peerIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTodayPiece, jsonEncode(peerIds.toList()));
  }

  static Future<Set<String>> loadTodayFish() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString(_keyDate) != today) {
      await prefs.setString(_keyDate, today);
      await prefs.remove(_keyTodayPiece);
      await prefs.remove(_keyTodayFish);
      return {};
    }
    final raw = prefs.getString(_keyTodayFish);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> saveTodayFish(Set<String> peerIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTodayFish, jsonEncode(peerIds.toList()));
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }
}
