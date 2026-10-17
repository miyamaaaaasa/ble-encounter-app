import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ble_encounter/core/ads_config.dart';
import 'package:ble_encounter/services/ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('disabled ads never call a native advertising method', () async {
    var calls = 0;
    const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final ads = AdService();
    await ads.initialize();
    await ads.showAfterGate(DateTime(2026, 10, 18), canShow: () => true);
    expect(calls, 0);
    expect(ads.ready, isFalse);
    ads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('family requests do not personalize or declare adult treatment', () {
    expect(AdService.familyConfiguration.ageRestrictedTreatment,
        AgeRestrictedTreatment.child);
    expect(
        AdService.familyConfiguration.maxAdContentRating, MaxAdContentRating.g);
    expect(AdService.request.nonPersonalizedAds, isTrue);
  });
  test('one gate cannot show twice, including older replay and future gates',
      () {
    final noon = DateTime(2026, 10, 18, 12);
    expect(gateAdIsEligible(noon, noon), isTrue);
    expect(
        gateAdIsEligible(noon, noon.add(const Duration(hours: 1)),
            previousGate: noon),
        isFalse);
    expect(
        gateAdIsEligible(noon.subtract(const Duration(hours: 3)), noon,
            previousGate: noon),
        isFalse);
    expect(gateAdIsEligible(noon.add(const Duration(hours: 9)), noon), isFalse);
    expect(
        gateAdIsEligible(noon, noon,
            lastAd: noon.subtract(const Duration(minutes: 5))),
        isFalse);
    expect(
        gateAdIsEligible(noon, noon,
            lastAd: noon.add(const Duration(minutes: 1))),
        isFalse);
  });
  test(
      'default builds never activate the SDK and test IDs are platform specific',
      () {
    expect(AdsConfig.enabled, isFalse);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(AdsConfig.bannerId, startsWith('ca-app-pub-3940256099942544/'));
      expect(
          AdsConfig.interstitialId, startsWith('ca-app-pub-3940256099942544/'));
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
