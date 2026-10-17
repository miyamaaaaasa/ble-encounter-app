import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ads_config.dart';

/// Gate decisions stay in the encounter provider; only ad frequency lives here.
bool gateAdIsEligible(DateTime gate, DateTime now,
        {DateTime? previousGate, DateTime? lastAd}) =>
    !gate.isAfter(now) &&
    (previousGate == null || gate.isAfter(previousGate)) &&
    (lastAd == null || now.difference(lastAd) >= const Duration(minutes: 10));

class AdService extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = AdService();
  static const request = AdRequest(nonPersonalizedAds: true);
  static RequestConfiguration get familyConfiguration => RequestConfiguration(
      ageRestrictedTreatment: AgeRestrictedTreatment.child,
      maxAdContentRating: MaxAdContentRating.g);

  Future<void>? _initializing;
  InterstitialAd? _interstitial;
  DateTime? _loadedAt;
  int _foregroundEpoch = 0;
  bool _loading = false, _presenting = false;
  bool ready = false, privacyOptionsRequired = false;

  Future<void> initialize() {
    debugPrint(
        '[Ads] enabled=${AdsConfig.enabled} configured=${AdsConfig.configured} test=${AdsConfig.testMode}');
    if (!AdsConfig.configured) return Future.value();
    if (_initializing == null) WidgetsBinding.instance.addObserver(this);
    return _initializing ??= _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _foregroundEpoch++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interstitial?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      // Set child treatment before initializing or requesting any ads.
      await MobileAds.instance
          .updateRequestConfiguration(familyConfiguration)
          .timeout(const Duration(seconds: 10));
      await MobileAds.instance.setSameAppKeyEnabled(false);
      debugPrint('[Ads] child treatment applied');
      if (!AdsConfig.testMode) {
        final consent = Completer<void>();
        ConsentInformation.instance.requestConsentInfoUpdate(
            ConsentRequestParameters(tagForUnderAgeOfConsent: true), () {
          if (!consent.isCompleted) consent.complete();
        }, (_) {
          if (!consent.isCompleted)
            consent.completeError(StateError('Consent unavailable'));
        });
        await consent.future.timeout(const Duration(seconds: 30));
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        privacyOptionsRequired = await ConsentInformation.instance
                .getPrivacyOptionsRequirementStatus() ==
            PrivacyOptionsRequirementStatus.required;
        if (!await ConsentInformation.instance.canRequestAds()) {
          notifyListeners();
          return;
        }
      }
      // Sample ad units have no publisher UMP message; never use this bypass
      // for production units (AdsConfig chooses sample IDs in testMode).
      await MobileAds.instance
          .initialize()
          .timeout(const Duration(seconds: 35));
      await MobileAds.instance.setAppMuted(true);
      ready = true;
      debugPrint('[Ads] ready');
      notifyListeners();
      prepareGateAd();
    } catch (error) {
      // Ads must never prevent opening the plaza or viewing encounters.
      debugPrint(
          '[Ads] initialization unavailable (${error.runtimeType}); continuing without ads');
    }
  }

  void prepareGateAd() {
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) >= const Duration(minutes: 55)) {
      _interstitial?.dispose();
      _interstitial = null;
      _loadedAt = null;
    }
    if (!ready || _loading || _interstitial != null || _presenting) return;
    _loading = true;
    unawaited(InterstitialAd.load(
        adUnitId: AdsConfig.interstitialId,
        request: request,
        adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (ad) {
          _loading = false;
          if (!ready) {
            ad.dispose();
            return;
          }
          _interstitial = ad;
          _loadedAt = DateTime.now();
          debugPrint('[Ads] gate ad loaded');
        }, onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('[Ads] gate load unavailable (${error.code})');
        })).catchError((Object _) {
      _loading = false;
    }));
  }

  /// Called only after a successfully saved gate result has been closed.
  /// Unavailable ads are skipped immediately, never displayed later on resume.
  Future<void> showAfterGate(DateTime gate,
      {required bool Function() canShow}) async {
    prepareGateAd();
    if (!ready || _presenting || _interstitial == null) {
      debugPrint('[Ads] gate skipped: no ready ad');
      return;
    }
    final epoch = _foregroundEpoch;
    _presenting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      if (!gateAdIsEligible(gate, now,
              previousGate:
                  DateTime.tryParse(prefs.getString('ad_last_gate_v1') ?? ''),
              lastAd: DateTime.tryParse(
                  prefs.getString('ad_last_shown_v1') ?? '')) ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          epoch != _foregroundEpoch ||
          !canShow()) {
        debugPrint('[Ads] gate skipped: frequency or view changed');
        return;
      }
      // Save before showing so crashes/reconstruction cannot repeat this gate.
      if (!await prefs.setString('ad_last_gate_v1', gate.toIso8601String()) ||
          !await prefs.setString('ad_last_shown_v1', now.toIso8601String()))
        return;
      if (!ready ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          epoch != _foregroundEpoch ||
          !canShow()) {
        return;
      }
      final ad = _interstitial;
      if (ad == null) return;
      _interstitial = null;
      final closed = Completer<void>();
      ad.fullScreenContentCallback =
          FullScreenContentCallback(onAdDismissedFullScreenContent: (_) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      }, onAdFailedToShowFullScreenContent: (_, __) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      });
      try {
        debugPrint('[Ads] showing gate ad');
        await ad.show();
        await closed.future;
      } catch (_) {
        ad.dispose();
      }
    } catch (_) {
      debugPrint('[Ads] gate ad skipped');
    } finally {
      _presenting = false;
      prepareGateAd();
    }
  }

  Future<void> showPrivacyOptions() async {
    if (!privacyOptionsRequired) return;
    FormError? error;
    await ConsentForm.showPrivacyOptionsForm((value) => error = value);
    if (error != null) throw StateError('Privacy options unavailable');
    ready = await ConsentInformation.instance.canRequestAds();
    if (!ready) {
      _interstitial?.dispose();
      _interstitial = null;
    }
    notifyListeners();
  }
}
