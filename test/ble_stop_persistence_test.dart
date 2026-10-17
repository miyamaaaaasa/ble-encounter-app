import 'package:flutter/services.dart';
// Test-only registration of FlutterBluePlus's existing Android implementation.
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_android/flutter_blue_plus_android.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/core/peer_id.dart';
import 'package:ble_encounter/models/own_profile.dart';
import 'package:ble_encounter/providers/ble_providers.dart';
import 'package:ble_encounter/services/account_snapshot.dart';
import 'package:ble_encounter/services/api_service.dart';

class _RestartApp extends AppNotifier {
  int permissionRequests = 0;
  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'own_profile_v1': const OwnProfile(name: 'Test').toStorageJson(),
    });
    await PeerId.init();
    ApiService.accountBlocked.value = true;
    AccountSnapshot.locked = true;
    FlutterBluePlusAndroid.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_blue_plus/methods'), (call) async {
      if (call.method == 'getAdapterState') return {'adapter_state': 6};
      return true;
    });
  });
  tearDown(() {
    ApiService.accountBlocked.value = false;
    AccountSnapshot.locked = false;
  });

  Future<(_RestartApp, ProviderContainer)> reload() async {
    final app = _RestartApp();
    final container =
        ProviderContainer(overrides: [appProvider.overrideWith(() => app)]);
    container.read(appProvider);
    addTearDown(() {
      app.dispose();
      container.dispose();
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(container.read(appProvider).isLoading, isFalse);
    return (app, container);
  }

  test('manual stop survives provider recreation without asking permissions',
      () async {
    final (first, _) = await reload();
    await first.stop();
    first.dispose();
    final (restarted, container) = await reload();
    expect(restarted.userStopped, isTrue);
    expect(restarted.permissionRequests, 0);
    expect(container.read(appProvider).isRunning, isFalse);
  });

  test('explicit start clears remembered stop even while Bluetooth is off',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ble_user_stopped_v1', true);
    final (app, _) = await reload();
    expect(app.userStopped, isTrue);
    await app.start();
    expect(prefs.getBool('ble_user_stopped_v1'), isFalse);
    app.dispose();
    final (restarted, _) = await reload();
    expect(restarted.userStopped, isFalse);
    expect(restarted.permissionRequests, 1);
  });
}
