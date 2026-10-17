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
