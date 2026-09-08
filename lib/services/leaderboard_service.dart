import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

import '../game/game_mode.dart';

/// Google Play Games Services (Android) / Game Center (iOS) leaderboard
/// wiring — one leaderboard per [GameMode] per platform, since Classic and
/// Survival scores aren't comparable (see `ScoreService`, which already
/// tracks "best" per mode for the same reason) and Play Games/Game Center
/// use entirely separate leaderboard ID spaces for the same game.
///
/// All four leaderboard IDs are real now: Android's from Play Console
/// (opaque generated IDs), iOS's (`classical`/`survival`) chosen by the
/// user directly when creating the two Game Center leaderboards in App
/// Store Connect (unlike Play Console, App Store Connect lets you pick the
/// ID string yourself).
///
/// **This class was iOS-blind for a while after the iOS build itself was
/// added** — `_isSupported` originally checked Android only, and every
/// call only ever passed `androidLeaderboardID`, leaving `iOSLeaderboardID`
/// at the `games_services` package's empty-string default. That silently
/// made every leaderboard call a no-op on iOS specifically (not a Game
/// Center setup problem — the code never even tried), caught when the user
/// reported "chưa có leaderboard" ("no leaderboard yet") on the first real
/// iOS test after the signed build started working. **If iOS support is
/// ever added for a new games_services-backed feature on this class,
/// double-check both platforms are actually wired, not just the one
/// that shipped first.**
///
/// Every call here is wrapped in a try/catch: without full Play
/// Console/App Store Connect setup, sign-in/submit/show calls fail, and
/// that must never crash or block gameplay, the same way a failed ad load
/// never blocks gameplay in `AdsService`.
///
/// **Every platform call below is also wrapped in a `.timeout(...)`** — this
/// is not defensive-for-its-own-sake padding. `GameAuth.signIn()` calls a
/// plain `MethodChannel.invokeMethod`, and with no native handler attached
/// (confirmed via a throwaway `testWidgets` probe: a bare `await
/// GameAuth.signIn()` inside a widget test hangs forever, never throwing
/// `MissingPluginException` the way an unregistered channel is commonly
/// assumed to behave) the returned Future simply never completes — the
/// message sits in Flutter's channel buffer waiting for a handler that
/// will never attach under `flutter_test`, rather than being rejected. This
/// is the exact same failure class as the `flame_audio`/`AudioPool` hang
/// documented in [[project_number_master_app]] (see the Sound section
/// below): an unguarded platform-channel Future that can hang the caller
/// forever. Without the timeout here, both this project's own tests and a
/// real device with no network/Play Services could hang indefinitely on
/// sign-in instead of degrading gracefully. `Future.timeout` uses a real
/// `Timer` under the hood, so `flutter_test`'s fake async clock resolves it
/// deterministically via `tester.pump(duration)` — no real wall-clock wait
/// needed in tests.
class LeaderboardService {
  static const Map<GameMode, String> _androidLeaderboardIds = {
    GameMode.classic: 'CgkIje_cuZ8REAIQAQ',
    GameMode.survival: 'CgkIje_cuZ8REAIQAg',
  };

  static const Map<GameMode, String> _iosLeaderboardIds = {
    GameMode.classic: 'classical',
    GameMode.survival: 'survival',
  };

  static const _timeout = Duration(seconds: 5);

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || _isIOS);

  static String? _leaderboardIdForCurrentPlatform(GameMode mode) =>
      _isIOS ? _iosLeaderboardIds[mode] : _androidLeaderboardIds[mode];

  static bool _isConfigured(GameMode mode) =>
      !(_leaderboardIdForCurrentPlatform(mode)?.startsWith('REPLACE_') ?? true);

  /// Silent sign-in, best attempted once at app/game startup. Play Games
  /// Services v2 also auto-prompts sign-in on its own, but the plugin docs
  /// say this must still be called before submitScore/showLeaderboards.
  static Future<void> signIn() async {
    if (!_isSupported) return;
    try {
      await GameAuth.signIn().timeout(_timeout);
    } catch (_) {
      // No Google account signed in, Play Games not set up yet, no network,
      // a hung platform channel (see class doc), etc. — the game must stay
      // fully playable without a leaderboard.
    }
  }

  static Future<void> submitScore(GameMode mode, int score) async {
    if (!_isSupported || !_isConfigured(mode)) return;
    try {
      await Leaderboards.submitScore(
        score: Score(
          androidLeaderboardID: _androidLeaderboardIds[mode]!,
          iOSLeaderboardID: _iosLeaderboardIds[mode]!,
          value: score,
        ),
      ).timeout(_timeout);
    } catch (_) {
      // Fire-and-forget — a failed submit must never interrupt the
      // game-over flow the player is looking at.
    }
  }

  /// Opens Play Games'/Game Center's own leaderboard UI for [mode].
  /// Returns whether it could — the caller can use this to show a "not
  /// available" message instead of silently doing nothing when the user
  /// explicitly tapped a button for it.
  static Future<bool> showLeaderboard(GameMode mode) async {
    if (!_isSupported || !_isConfigured(mode)) return false;
    try {
      await GameAuth.signIn().timeout(_timeout);
      await Leaderboards.showLeaderboards(
        androidLeaderboardID: _androidLeaderboardIds[mode]!,
        iOSLeaderboardID: _iosLeaderboardIds[mode]!,
      ).timeout(_timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
