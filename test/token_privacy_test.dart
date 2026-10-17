import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ble_encounter/core/peer_id.dart';
import 'package:ble_encounter/services/api_service.dart';
import 'package:ble_encounter/services/token_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'offline never advertises permanent ID or expired token; refresh is single flight',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
    final secure = <String, String>{
      'api_key_v1': 'a' * 64,
      'api_user_id_v1': 'b' * 32
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
      final a = call.arguments as Map;
      if (call.method == 'read') return secure[a['key']];
      if (call.method == 'write') secure[a['key']] = a['value'];
      if (call.method == 'delete') secure.remove(a['key']);
      return null;
    });
    var online = false, requests = 0;
    ApiService.client = MockClient((request) async {
      requests++;
      return http.Response(
          online ? jsonEncode({'token': 'c' * 32}) : '', online ? 200 : 503);
    });
    await ApiService.init();
    await TokenService.init();
    expect(TokenService.hexToken, isEmpty);
    secure['ble_token_v1'] = 'd' * 32;
    secure['ble_token_expiry_v1'] =
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
    await TokenService.init();
    expect(TokenService.hexToken, isEmpty);
    online = true;
    requests = 0;
    await Future.wait(List.generate(5, (_) => TokenService.refresh()));
    expect(requests, 1);
    expect(TokenService.hexToken, 'c' * 32);
    expect(TokenService.tokenBytes, List.filled(16, 0xcc));
    final response = Completer<http.Response>();
    ApiService.client = MockClient((_) => response.future);
    final refreshing = TokenService.refresh();
    await Future<void>.delayed(Duration.zero);
    final clearing = TokenService.clear();
    response.complete(http.Response(jsonEncode({'token': 'e' * 32}), 200));
    await Future.wait([refreshing, clearing]);
    expect(secure['ble_token_v1'], isNull);
    expect(TokenService.hexToken, isEmpty);
    await TokenService.clear();
    expect(TokenService.hexToken, isEmpty);
  });
}
