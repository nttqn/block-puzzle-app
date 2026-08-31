import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps AdMob banner + interstitial ads behind Google's official TEST ad
/// unit IDs. Swap these for real AdMob IDs before publishing (and set the
/// ADMOB_APP_ID GitHub secret — see README.md).
///
/// `google_mobile_ads` only supports Android/iOS, so every entry point here
/// is a no-op on web/desktop — that keeps `flutter run -d chrome` usable for
/// previewing gameplay without a phone.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  static const String bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';

  InterstitialAd? _interstitialAd;
  int _gamesSinceInterstitial = 0;

  Future<void> initialize() async {
    if (kIsWeb) return;
    await MobileAds.instance.initialize();
    _loadInterstitial();
  }

  BannerAd? createBannerAd({required void Function() onLoaded}) {
    if (kIsWeb) return null;
    final banner = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    banner.load();
    return banner;
  }

  void _loadInterstitial() {
    if (kIsWeb) return;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }

  /// Shows an interstitial roughly every other finished game so ads never
  /// interrupt active play — call this once when a game ends.
  void maybeShowInterstitialAfterGame() {
    if (kIsWeb) return;
    _gamesSinceInterstitial++;
    if (_gamesSinceInterstitial < 2 || _interstitialAd == null) {
      if (_interstitialAd == null) _loadInterstitial();
      return;
    }
    _gamesSinceInterstitial = 0;
    final ad = _interstitialAd!;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitial();
      },
    );
    ad.show();
  }
}
