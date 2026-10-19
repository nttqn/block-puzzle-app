import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps AdMob banner + interstitial ads, both real unit IDs from this
/// project's own AdMob account. The ADMOB_APP_ID / ADMOB_APP_ID_IOS GitHub
/// secrets (see README.md) are separate values — the manifest-level
/// Application IDs, not either ad unit ID here.
///
/// `google_mobile_ads` only supports Android/iOS, so every entry point here
/// is a no-op on web/desktop — that keeps `flutter run -d chrome` usable for
/// previewing gameplay without a phone.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  /// AdMob registers each platform as a separate "app", so Android and iOS
  /// have distinct ad unit IDs under the same `pub-9078637596840810`
  /// account even though it's the same Block Puzzle Plus listing.
  static String get bannerAdUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-9078637596840810/1523374736'
      : 'ca-app-pub-9078637596840810/7978938616';

  static String get interstitialAdUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-9078637596840810/9210293061'
      : 'ca-app-pub-9078637596840810/4039693603';

  // TODO: these are Google's public TEST rewarded unit IDs. Replace with real
  // "Rewarded" ad units from the AdMob console before a store release.
  static String get rewardedAdUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  InterstitialAd? _interstitialAd;
  int _gamesSinceInterstitial = 0;
  RewardedAd? _rewardedAd;

  Future<void> initialize() async {
    if (kIsWeb) return;
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  void _loadRewarded() {
    if (kIsWeb) return;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (_) => _rewardedAd = null,
      ),
    );
  }

  /// Shows a rewarded ad and resolves true only if the user earned the
  /// reward. On web (no ads) it resolves true so power-ups stay testable in
  /// `flutter run -d chrome`.
  Future<bool> showRewarded() {
    if (kIsWeb) return Future.value(true);
    final ad = _rewardedAd;
    if (ad == null) {
      _loadRewarded();
      return Future.value(false);
    }
    _rewardedAd = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return completer.future;
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
