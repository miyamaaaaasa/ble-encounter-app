import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

/// Advertise only a valid server-issued rotating token, never a permanent ID.
class TokenService {
  static const _store = FlutterSecureStorage();
  static const _keyToken = 'ble_token_v1';
  static const _keyExpiry = 'ble_token_expiry_v1';
  static String? _token;
  static DateTime? _expiry;
  static Future<void>? _refreshing;
  static int _generation = 0;

  static bool get canAdvertise =>
      !ApiService.accountBlocked.value &&
      _token != null &&
      RegExp(r'^[0-9a-f]{32}$').hasMatch(_token!) &&
      _expiry != null &&
      _expiry!.isAfter(DateTime.now());
  static String get hexToken => canAdvertise ? _token! : '';
  static List<int> get tokenBytes {
    if (!canAdvertise) throw StateError('No valid advertising token');
    final h = hexToken;
    return List.generate(
        16, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16));
  }

  static Future<void> init() async {
    final generation = _generation;
    final token = await _store.read(key: _keyToken);
    final expiry = DateTime.tryParse(await _store.read(key: _keyExpiry) ?? '');
    if (generation != _generation || ApiService.accountBlocked.value) return;
    _token = token;
    _expiry = expiry;
    await ensureFresh();
  }

  static Future<void> ensureFresh() async {
    if (!canAdvertise ||
        _expiry!.difference(DateTime.now()) < const Duration(hours: 2)) {
      await refresh();
    }
  }

  static Future<void> clear() async {
    _generation++;
    _token = null;
    _expiry = null;
    try {
      await _refreshing;
    } catch (_) {/* Still clear expired credentials. */}
    await _store.delete(key: _keyToken);
    await _store.delete(key: _keyExpiry);
  }

  static Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  static Future<void> _refresh() async {
    final generation = _generation;
    final next = await ApiService.issueToken();
    if (generation != _generation || ApiService.accountBlocked.value) return;
    if (next == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(next)) {
      debugPrint(
          '[Token] no replacement; only an unexpired token may advertise');
      return;
    }
    final expiry = DateTime.now().add(const Duration(hours: 24));
    await _store.write(key: _keyToken, value: next);
    await _store.write(key: _keyExpiry, value: expiry.toIso8601String());
    if (generation != _generation || ApiService.accountBlocked.value) return;
    _token = next;
    _expiry = expiry;
  }
}
