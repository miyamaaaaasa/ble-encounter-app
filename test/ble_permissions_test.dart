import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/core/peer_id.dart';
import 'package:ble_encounter/providers/ble_providers.dart';

class _PermissionsApp extends AppNotifier {
  @override
  AppState build() => const AppState(isLoading: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'legacy Android reports disabled OS location without pretending BLE is ready',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/device_info'),
            (_) async => {
                  for (final field in [
                    'board',
                    'bootloader',
                    'brand',
                    'device',
                    'display',
                    'fingerprint',
                    'hardware',
                    'host',
                    'id',
                    'manufacturer',
                    'model',
                    'product',
                    'tags',
                    'type',
                    'serialNumber'
                  ])
                    field: 'test',
                  'isPhysicalDevice': true,
                  'isLowRamDevice': false,
                  'version': {
                    'codename': 'REL',
                    'incremental': '1',
                    'previewSdkInt': 0,
                    'release': '7',
                    'sdkInt': 24
                  },
                });
    var locationOn = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async {
      if (call.method == 'requestPermissions') {
        return {for (final id in call.arguments as List) id: 1};
      }
      if (call.method == 'checkServiceStatus') return locationOn ? 1 : 0;
      return null;
    });
    final container = ProviderContainer(
        overrides: [appProvider.overrideWith(_PermissionsApp.new)]);
    addTearDown(container.dispose);
    final app = container.read(appProvider.notifier);
    expect(await app.requestPermissions(), isFalse);
    expect(container.read(appProvider).errorMessage, contains('端末全体'));
    expect(container.read(appProvider).errorMessage, contains('GPS'));
    locationOn = true;
    expect(await app.requestPermissions(), isTrue);
    app.dispose();
  });
  test('notification refusal does not disable permitted BLE; BLE refusal does',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var denyBle = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async {
      if (call.method == 'requestPermissions') {
        return {
          for (final id in call.arguments as List)
            id: id == Permission.notification.value ||
                    (denyBle && id == Permission.bluetoothScan.value)
                ? 0
                : 1,
        };
      }
      return null;
    });
    final container = ProviderContainer(
        overrides: [appProvider.overrideWith(_PermissionsApp.new)]);
    addTearDown(container.dispose);
    final app = container.read(appProvider.notifier);
    expect(await app.requestPermissions(), isTrue);
    denyBle = true;
    expect(await app.requestPermissions(), isFalse);
    app.dispose();
  });
}
