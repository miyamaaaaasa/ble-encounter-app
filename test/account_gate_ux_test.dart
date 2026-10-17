import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/services/api_service.dart';
import 'package:ble_encounter/ui/account_access_gate.dart';

void main() {
  testWidgets('self-deleted account can begin again without waiting for poll',
      (t) async {
    SharedPreferences.setMockInitialValues({
      ApiService.deletedKey: true,
      ApiService.blockedKey: true,
    });
    final previousClient = ApiService.client;
    ApiService.client = MockClient((_) async => http.Response('{}', 503));
    addTearDown(() => ApiService.client = previousClient);
    await ApiService.init();
    await t.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: AccountAccessGate(child: Text('account ready')))));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('アカウントを削除しました。'), findsOneWidget);
    await t.tap(find.text('スキップ'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    await t.tap(find.text('広場をはじめる'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('account ready'), findsOneWidget);
    expect(find.text('保存中…'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
