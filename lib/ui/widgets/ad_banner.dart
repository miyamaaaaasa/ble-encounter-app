import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/ads_config.dart';
import '../../services/ad_service.dart';
import '../theme/palette.dart';

/// Its own layout area, separated from both content and navigation hit targets.
class PlazaAdBanner extends StatefulWidget {
  const PlazaAdBanner({super.key});
  @override
  State<PlazaAdBanner> createState() => _PlazaAdBannerState();
}

class _PlazaAdBannerState extends State<PlazaAdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    AdService.instance.addListener(_update);
    _update();
  }

  void _update() {
    if (!AdService.instance.ready || !AdsConfig.configured) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      if (mounted) setState(() {});
      return;
    }
    if (_ad != null) return;
    final ad = BannerAd(
        adUnitId: AdsConfig.bannerId,
        size: AdSize.banner,
        request: AdService.request,
        listener: BannerAdListener(onAdLoaded: (ad) {
          if (!mounted || ad != _ad) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        }, onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted && ad == _ad)
            setState(() {
              _ad = null;
              _loaded = false;
            });
        }));
    _ad = ad;
    unawaited(ad.load().catchError((Object _) {
      ad.dispose();
      if (mounted && ad == _ad)
        setState(() {
          _ad = null;
          _loaded = false;
        });
    }));
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_update);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null || MediaQuery.sizeOf(context).width < 320) {
      return const SizedBox.shrink();
    }
    return ColoredBox(
        color: Palette.cream,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(AdsConfig.testMode ? '広告（テスト）' : '広告', style: Ts.caption),
              const SizedBox(height: 4),
              SizedBox(
                  width: _ad!.size.width.toDouble(),
                  height: _ad!.size.height.toDouble(),
                  child: AdWidget(ad: _ad!)),
            ])));
  }
}
