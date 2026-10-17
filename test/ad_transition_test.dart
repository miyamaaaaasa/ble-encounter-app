import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The SDK's own codec is needed to simulate native ad callbacks, not an ad server.
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as sdk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/services/ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final background in [false, true]) {
    testWidgets(
        background
            ? 'background and resume cancels a pending gate ad'
            : 'navigation during persistence cancels a pending gate ad',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var shown = 0;
      int? id;
      messenger.setMockMethodCallHandler(sdk.instanceManager.channel,
          (call) async {
        if (call.method == 'loadInterstitialAd')
          id = call.arguments['adId'] as int;
        if (call.method == 'showAdWithoutView') shown++;
        return null;
      });
      final ads = AdService()..ready = true;
      ads.prepareGateAd();
      await t.pump();
      expect(id, isNotNull);
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
          sdk.instanceManager.channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('onAdEvent', {
            'adId': id,
            'eventName': 'onAdLoaded',
          })),
          (_) => delivered.complete());
      await delivered.future;
      var checks = 0;
      await ads.showAfterGate(
          DateTime.now().subtract(const Duration(minutes: 1)), canShow: () {
        checks++;
        if (background && checks == 1) {
          ads.didChangeAppLifecycleState(AppLifecycleState.paused);
          ads.didChangeAppLifecycleState(AppLifecycleState.resumed);
        }
        return background || checks == 1;
      });
      expect(checks, greaterThanOrEqualTo(1));
      expect(shown, 0);
      ads.dispose();
      await t.pump();
      messenger.setMockMethodCallHandler(sdk.instanceManager.channel, null);
    });
  }
}
