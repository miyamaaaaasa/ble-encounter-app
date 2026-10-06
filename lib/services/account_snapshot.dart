import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// A compact, allow-listed account snapshot; never contains API/recovery keys.
class AccountSnapshot {
  static const keys = {
    'own_profile_v1',
    'encounters_v1',
    'dot_avatar_v1',
    'own_piece_v1',
    'puzzle_pieces_v1',
    'pending_scans_v1',
    'app_badges_v1',
    'game_data_v1',
    'game_today_date',
    'game_today_piece',
    'game_today_fish',
  };
  static bool locked = false;
  static Future<void> Function()? onChanged;
  static Timer? _timer;
  static void changed() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () async {
      try {
        await onChanged?.call();
      } catch (_) {/* retry at next status check */}
    });
  }

  static Future<String> capture() async {
    final prefs = await SharedPreferences.getInstance();
    final fields = <String, String>{};
    for (final key in keys) {
      final value = prefs.getString(key);
      if (value != null) fields[key] = value;
    }
    return base64Encode(gzip.encode(utf8.encode(jsonEncode(fields))));
  }

  static Future<void> clear() async {
    _timer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    for (final key in keys) {
      await prefs.remove(key);
    }
    for (final key in [
      'onboarding_done_v1',
      'broadcast_last_id_v1',
      'broadcast_cached_v1',
      'broadcast_dismissed_id_v1'
    ]) {
      await prefs.remove(key);
    }
  }

  static Future<void> restore(String archive) async {
    if (archive.isEmpty) return;
    final fields = jsonDecode(utf8.decode(gzip.decode(base64Decode(archive))))
        as Map<String, dynamic>;
    if (fields.keys.any((k) => !keys.contains(k)) ||
        fields.values.any((v) => v is! String)) {
      throw const FormatException('Invalid account archive');
    }
    final prefs = await SharedPreferences.getInstance();
    for (final entry in fields.entries) {
      await prefs.setString(entry.key, entry.value as String);
    }
  }
}
