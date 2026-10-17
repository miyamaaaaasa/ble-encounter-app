import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resolve more than server limit; retain full queue on a failed batch',
      () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'read' ? 'a' * 32 : null);
    final tokens =
        List.generate(205, (i) => i.toRadixString(16).padLeft(32, '0'));
    var failLast = false;
    final batches = <int>[];
    ApiService.client = MockClient((request) async {
      final list = (jsonDecode(request.body) as Map)['tokens'] as List;
      batches.add(list.length);
      if (failLast && list.contains(tokens.last)) return http.Response('', 503);
      return http.Response(
          jsonEncode([
            for (final token in list.take(200)) {'token': token}
          ]),
          200);
    });
    await ApiService.init();
    expect((await ApiService.resolveTokens(tokens))!.length, 205);
    expect(batches, [200, 5]);
    failLast = true;
    expect(await ApiService.resolveTokens(tokens), isNull);
  });
}
