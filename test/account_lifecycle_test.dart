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
    String? serverRecovery;
    var loseReconnectResponse = true;
    var loseEnrollmentResponse = true;
    ApiService.client = MockClient((request) async {
      if (request.method == 'DELETE') return http.Response('{}', 200);
      if (request.url.path.endsWith('/auth/anon')) {
        signups++;
        return http.Response(
            jsonEncode({'api_key': 'a' * 64, 'user_id': 'b' * 32}), 200);
      }
      if (request.url.path.endsWith('/account/session')) {
        final m = jsonDecode(request.body) as Map;
        capturedRecovery = m['recovery_key'] as String;
        serverRecovery = capturedRecovery;
        if (loseEnrollmentResponse) {
          loseEnrollmentResponse = false;
          throw http.ClientException('Enrollment reply lost after commit');
        }
        return http.Response(deleted ? ' {"error":"account_inactive"}' : '{}',
            deleted ? 403 : 200);
      }
      if (request.url.path.endsWith('/profile')) {
        return http.Response('{"error":"name_unavailable"}', 422);
      }
      if (request.url.path.endsWith('/auth/reconnect')) {
        reconnects++;
        final body = jsonDecode(request.body) as Map;
        final replacement = body['new_recovery_key'];
        expect(replacement, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(replacement, isNot(body['recovery_key']));
        if (body['recovery_key'] != serverRecovery) {
          return http.Response('{"error":"reconnection unavailable"}', 401);
        }
        serverRecovery = replacement as String;
        if (loseReconnectResponse) {
          loseReconnectResponse = false;
          throw http.ClientException('Response lost after server commit');
        }
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
    expect(secure['account_recovery_v1'], capturedRecovery,
        reason: 'Enrollment proof must survive a lost server reply');
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
    await expectLater(
        ApiService.reconnectAccount(), throwsA(isA<http.ClientException>()));
    expect(secure['account_recovery_pending_v1'], serverRecovery);
    expect(ApiService.accountBlocked.value, isTrue);
    final attempts = await Future.wait(
        [ApiService.reconnectAccount(), ApiService.reconnectAccount()]);
    expect(attempts, everyElement(isTrue));
    expect(reconnects, 3);
    expect(secure['account_recovery_v1'], serverRecovery);
    expect(secure['account_recovery_pending_v1'], isNull);
    expect(secure['api_key_v1'], 'c' * 64);
    expect(secure['api_key_v1'], isNot('a' * 64));
    expect((await SharedPreferences.getInstance()).getString('own_profile_v1'),
        'saved profile');
    expect((await SharedPreferences.getInstance()).getString('encounters_v1'),
        'saved history');
    // Self-deletion must not recreate a user on the next timer/API request.
    await ApiService.deleteAccount();
    expect(ApiService.accountBlocked.value, isTrue);
    await ApiService.issueToken();
    expect(signups, 1);
    expect(
        (await SharedPreferences.getInstance()).getBool(ApiService.deletedKey),
        isTrue);
    await ApiService.releaseBlockedAccount();
    await AccountSnapshot.clear();
    expect(secure['account_recovery_v1'], isNull);
    expect(secure['account_quarantine_v1'], isNull);
    expect((await SharedPreferences.getInstance()).getString('own_profile_v1'),
        isNull);
    await ApiService.beginNewAccount();
    await ApiService.init();
    expect(ApiService.accountBlocked.value, isFalse);
    expect(signups, 2);
    AccountSnapshot.locked = false;
  });
}
