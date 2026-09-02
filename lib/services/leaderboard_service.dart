import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

import '../game/game_mode.dart';

/// Google Play Games Services leaderboard wiring — one leaderboard per
/// [GameMode], since Classic and Survival scores aren't comparable (see
/// `ScoreService`, which already tracks "best" per mode for the same
/// reason).
///
/// The leaderboard IDs below are **placeholders** — each must be replaced
/// with the real ID created in Play Console (Play Games Services >
/// Leaderboards, one per mode) before this does anything useful. This also
/// requires a Play Console project for this app, Play Games Services
/// enabled on it, and the `com.google.android.gms.games.APP_ID` manifest
/// meta-data (see PLAY_GAMES_APP_ID in build-apk.yml) sourced from a real
/// release-signed build — Play Games ties sign-in to the app's signing
/// certificate, so this cannot be verified against the debug-signed builds
/// this project has used so far. Every call here is wrapped in a
/// try/catch: without all of the above, sign-in/submit/show calls fail, and
/// that must never crash or block gameplay, the same way a failed ad load
/// never blocks gameplay in `AdsService`.
///
/// Android-only: `games_services` also supports Game Center on iOS/macOS,
/// but this app has no iOS build target (see build-apk.yml,
/// --platforms=android only), so anything else no-ops.
class LeaderboardService {
  static const Map<GameMode, String> _leaderboardIds = {
    GameMode.classic: 'REPLACE_WITH_CLASSIC_LEADERBOARD_ID',
    GameMode.survival: 'REPLACE_WITH_SURVIVAL_LEADERBOARD_ID',
  };

  static bool get _isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _isConfigured(GameMode mode) => !(_leaderboardIds[mode]?.startsWith('REPLACE_') ?? true);

  /// Silent sign-in, best attempted once at app/game startup. Play Games
  /// Services v2 also auto-prompts sign-in on its own, but the plugin docs
  /// say this must still be called before submitScore/showLeaderboards.
  static Future<void> signIn() async {
    if (!_isSupported) return;
    try {
      await GameAuth.signIn();
    } catch (_) {
      // No Google account signed in, Play Games not set up yet, no network,
      // etc. — the game must stay fully playable without a leaderboard.
    }
  }

  static Future<void> submitScore(GameMode mode, int score) async {
    if (!_isSupported || !_isConfigured(mode)) return;
    try {
      await Leaderboards.submitScore(score: Score(androidLeaderboardID: _leaderboardIds[mode]!, value: score));
    } catch (_) {
      // Fire-and-forget — a failed submit must never interrupt the
      // game-over flow the player is looking at.
    }
  }

  /// Opens Play Games' own leaderboard UI for [mode]. Returns whether it
  /// could — the caller can use this to show a "not available" message
  /// instead of silently doing nothing when the user explicitly tapped a
  /// button for it.
  static Future<bool> showLeaderboard(GameMode mode) async {
    if (!_isSupported || !_isConfigured(mode)) return false;
    try {
      await GameAuth.signIn();
      await Leaderboards.showLeaderboards(androidLeaderboardID: _leaderboardIds[mode]!);
      return true;
    } catch (_) {
      return false;
    }
  }
}
