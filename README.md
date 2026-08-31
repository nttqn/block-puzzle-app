# Block Puzzle

A Flutter Android block-puzzle game: drag wooden blocks from a 3-piece tray
onto an 8x8 grid, clear full rows/columns for points, chain clears for combo
bonuses. Genre clone of the classic "block blast" style puzzle games — own
art, own code, no assets or code copied from any existing app.

There is no Flutter/Android SDK installed by default in some dev
environments this project is developed in — see `CLAUDE.md` for the CI-only
Android build setup if that's the case for you. If Flutter *is* available
locally:

```
flutter pub get
flutter analyze
flutter test
flutter run -d chrome          # fastest way to iterate on gameplay/UI
flutter build apk --release    # debug-signed test APK
```

## Before publishing to the Play Store

1. **AdMob**: `lib/services/ads_service.dart` currently uses Google's public
   TEST ad unit IDs. Create a real AdMob app + banner/interstitial ad units
   and swap `bannerAdUnitId`/`interstitialAdUnitId`. Also set the
   `ADMOB_APP_ID` GitHub secret (the App ID is a separate value from the ad
   unit IDs — see AdMob console's app settings).
2. **Release signing**: generate a keystore and set the `KEYSTORE_BASE64`,
   `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` GitHub secrets — see
   `CLAUDE.md` for the exact CI wiring. Without these the build stays
   debug-signed (fine for sideloading, rejected by Play Console).
3. **App icon**: replace `assets/icon/icon.png` (512x512) — nothing else
   needs editing, `flutter_launcher_icons` regenerates every mipmap size in
   CI.
