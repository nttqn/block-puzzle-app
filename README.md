# Block Puzzle Plus

A Flutter Android block-puzzle game: drag wooden blocks from a 3-piece tray
onto a grid, clear full rows/columns for points, chain clears for combo
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

1. ~~**AdMob**~~ — done. Real banner/interstitial ad unit IDs are set in
   `lib/services/ads_service.dart`; the `ADMOB_APP_ID` GitHub secret (a
   separate value from the ad unit IDs) is also set.
2. ~~**Release signing**~~ — done. The `KEYSTORE_BASE64`,
   `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` GitHub secrets are set;
   CI builds a real Play-Store-signable APK/AAB. See CLAUDE.md's
   "Leaderboard" section for this keystore's SHA-1, needed to register the
   Play Games OAuth client.
3. **App icon**: done — `assets/icon/icon.png` is the real launcher icon
   art; `flutter_launcher_icons` regenerates every mipmap size in CI.
4. **Privacy policy**: drafted at `docs/privacy.html` (covers the local
   score/settings storage, Play Games Services sign-in, and AdMob). Enable
   GitHub Pages for this repo (Settings → Pages → Source: "Deploy from a
   branch" → branch `main`, folder `/docs`) to get a public URL — Play
   Console requires one before a listing can go live. Once enabled, it's
   `https://nttqn.github.io/block-puzzle-app/privacy.html`.
