import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:ble_encounter/services/api_service.dart';
import 'package:ble_encounter/services/account_snapshot.dart';
import 'package:ble_encounter/services/profile_storage.dart';
import 'package:ble_encounter/models/own_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('snapshot round trip excludes credentials and settings, validates keys',
      () async {
    SharedPreferences.setMockInitialValues({
      'own_profile_v1': 'そら',
      'encounters_v1': 'history',
      'puzzle_pieces_v1': 'pieces',
      'app_badges_v1': 'badges',
      'theme_mode_v1': 'dark',
      'api_key_v1': 'secret'
    });
    final archive = await AccountSnapshot.capture();
    await AccountSnapshot.clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('own_profile_v1'), isNull);
    expect(prefs.getString('theme_mode_v1'), 'dark');
    await AccountSnapshot.restore(archive);
    expect(prefs.getString('own_profile_v1'), 'そら');
    expect(prefs.getString('encounters_v1'), 'history');
    expect(prefs.getString('puzzle_pieces_v1'), 'pieces');
    expect(prefs.getString('app_badges_v1'), 'badges');
  });
  test(
      'revocation stops automatic signup; explicit reconnect gets a fresh key and restores data',
      () async {
    SharedPreferences.setMockInitialValues(
        {'own_profile_v1': 'saved profile', 'encounters_v1': 'saved history'});
    final secure = <String, String>{};
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final a = call.arguments as Map? ?? {};
      final k = a['key'] as String?;
      switch (call.method) {
        case 'read':
          return secure[k];
        case 'write':
          secure[k!] = a['value'] as String;
          return null;
        case 'delete':
          secure.remove(k);
          return null;
        default:
          return null;
      }
    });
    var signups = 0;
    String? capturedRecovery;
    var deleted = false;
    var reconnects = 0;
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/anon')) {
        signups++;
        return http.Response(
            jsonEncode({'api_key': 'a' * 64, 'user_id': 'b' * 32}), 200);
      }
      if (request.url.path.endsWith('/account/session')) {
        final m = jsonDecode(request.body) as Map;
        capturedRecovery = m['recovery_key'] as String;
        return http.Response(deleted ? ' {"error":"account_inactive"}' : '{}',
            deleted ? 403 : 200);
      }
      if (request.url.path.endsWith('/profile')) {
        return http.Response('{"error":"name_unavailable"}', 422);
      }
      if (request.url.path.endsWith('/auth/reconnect')) {
        reconnects++;
        return http.Response(
            jsonEncode(
                {'api_key': 'c' * 64, 'user_id': 'b' * 32, 'archive': ''}),
            200);
      }
      return http.Response('{"error":"account_inactive"}', 403);
    });
    await ApiService.checkAccount();
    expect(signups, 1);
    expect(capturedRecovery, isNotNull);
    expect(await ApiService.syncProfile(displayName: '禁止語123', colorIndex: 0),
        isFalse);
    expect(ApiService.profileError, 'この名前は使用できません');
    deleted = true;
    await ApiService.checkAccount();
    expect(ApiService.accountBlocked.value, isTrue);
    await ApiService.releaseBlockedAccount();
    await AccountSnapshot.clear();
    expect(secure['api_key_v1'], isNull);
    expect(ApiService.isReady, isFalse);
    await ApiService.issueToken();
    expect(signups, 1);
    expect(reconnects, 0);
    // A delayed storage callback must not repopulate the cleared account.
    await ProfileStorage()
        .saveOwnProfile(const OwnProfile(name: 'stale', colorIndex: 0));
    expect((await SharedPreferences.getInstance()).getString('own_profile_v1'),
        isNull);
    expect(await ApiService.reconnectAccount(), isTrue);
    expect(reconnects, 1);
    expect(secure['api_key_v1'], 'c' * 64);
    expect(secure['api_key_v1'], isNot('a' * 64));
    expect((await SharedPreferences.getInstance()).getString('own_profile_v1'),
        'saved profile');
    expect((await SharedPreferences.getInstance()).getString('encounters_v1'),
        'saved history');
    AccountSnapshot.locked = false;
  });
}
