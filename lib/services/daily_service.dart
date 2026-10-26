import 'package:shared_preferences/shared_preferences.dart';

/// Local-time calendar day as `yyyymmdd`, e.g. `20261026`. Doubles as the
/// daily challenge's piece-sequence seed, and compares correctly as a
/// plain string.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

String todayKey() => dateKey(DateTime.now());

String previousDayKey(String key) {
  final d = DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(4, 6)), int.parse(key.substring(6, 8)));
  return dateKey(DateTime(d.year, d.month, d.day - 1));
}

class DailyStatus {
  /// Consecutive days with a finished daily game, still alive only if the
  /// last one was today or yesterday.
  final int streak;
  final int todayBest;
  final bool playedToday;
  const DailyStatus({required this.streak, required this.todayBest, required this.playedToday});
}

/// The daily challenge's bookkeeping: today's best score and the day streak.
/// Replaying the same day is allowed; only the best result counts.
class DailyService {
  DailyService._();
  static final DailyService instance = DailyService._();

  static const _bestDateKey = 'daily_best_date';
  static const _bestScoreKey = 'daily_best_score';
  static const _streakKey = 'daily_streak';
  static const _lastDateKey = 'daily_last_date';

  Future<int> bestFor(String date) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_bestDateKey) == date ? prefs.getInt(_bestScoreKey) ?? 0 : 0;
  }

  /// Records a finished daily game played on [date]. Safe to call more than
  /// once for the same game (e.g. again after "x2 score"): the best is a max
  /// and the streak only moves when the day changes.
  Future<void> record(String date, int score) async {
    final prefs = await SharedPreferences.getInstance();
    final bestDate = prefs.getString(_bestDateKey);
    if (bestDate == null || date.compareTo(bestDate) > 0) {
      await prefs.setString(_bestDateKey, date);
      await prefs.setInt(_bestScoreKey, score);
    } else if (date == bestDate && score > (prefs.getInt(_bestScoreKey) ?? 0)) {
      await prefs.setInt(_bestScoreKey, score);
    }

    final last = prefs.getString(_lastDateKey);
    if (last != null && date.compareTo(last) <= 0) return;
    final streak = last == previousDayKey(date) ? (prefs.getInt(_streakKey) ?? 0) + 1 : 1;
    await prefs.setInt(_streakKey, streak);
    await prefs.setString(_lastDateKey, date);
  }

  Future<DailyStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    final today = todayKey();
    final last = prefs.getString(_lastDateKey);
    final alive = last == today || last == previousDayKey(today);
    return DailyStatus(
      streak: alive ? prefs.getInt(_streakKey) ?? 0 : 0,
      todayBest: await bestFor(today),
      playedToday: last == today,
    );
  }
}
