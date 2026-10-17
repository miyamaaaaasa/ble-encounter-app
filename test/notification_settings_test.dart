import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'gate notifications respect disabled preference and cancel existing alarms',
      () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    var initialized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        initialized = true;
        return true;
      }
      if (call.method == 'zonedSchedule') expect(initialized, isTrue);
      return null;
    });
    await Future.wait([
      NotificationService.init(),
      NotificationService.scheduleGateNotifications()
    ]);
    expect(calls.where((c) => c.method == 'zonedSchedule').length, 3);
    calls.clear();
    await NotificationService.setPref(
        NotificationService.prefEncounterEnabled, false);
    await NotificationService.scheduleGateNotifications();
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    expect(calls.where((c) => c.method == 'cancel').length, 3);
  });
}
