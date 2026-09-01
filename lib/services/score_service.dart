import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_mode.dart';

/// Persists the player's best score locally via shared_preferences, one key
/// per [GameMode] since Classic and Survival scores aren't comparable. No
/// backend/leaderboard for this game — see CLAUDE.md for why that was
/// deliberately left out for now.
class ScoreService {
  ScoreService._();
  static final ScoreService instance = ScoreService._();

  String _key(GameMode mode) => 'best_score_${mode.name}';

  Future<int> loadBest(GameMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(mode)) ?? 0;
  }

  Future<void> saveBest(GameMode mode, int value) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_key(mode)) ?? 0;
    if (value > current) {
      await prefs.setInt(_key(mode), value);
    }
  }
}
