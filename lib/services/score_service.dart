import 'package:shared_preferences/shared_preferences.dart';

/// Persists the player's best score locally via shared_preferences. No
/// backend/leaderboard for this game — see CLAUDE.md for why that was
/// deliberately left out for now.
class ScoreService {
  ScoreService._();
  static final ScoreService instance = ScoreService._();

  static const _bestScoreKey = 'best_score';

  Future<int> loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_bestScoreKey) ?? 0;
  }

  Future<void> saveBest(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_bestScoreKey) ?? 0;
    if (value > current) {
      await prefs.setInt(_bestScoreKey, value);
    }
  }
}
