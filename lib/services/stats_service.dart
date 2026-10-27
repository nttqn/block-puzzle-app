import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lifetime totals for the Stats screen, which also gate skin unlocks (see
/// `SkinService`). Kept in memory after [load] and written through on each
/// change, the same way `PowerUpInventory` works.
class StatsService extends ChangeNotifier {
  StatsService._();
  static final StatsService instance = StatsService._();

  static const _keys = ['games', 'lines', 'blocks', 'bestStreak', 'biggestClear', 'totalScore'];
  final Map<String, int> _v = {for (final k in _keys) k: 0};

  int get gamesPlayed => _v['games']!;
  int get linesCleared => _v['lines']!;
  int get blocksPlaced => _v['blocks']!;

  /// Longest run of consecutive placements that each cleared a line.
  int get bestStreak => _v['bestStreak']!;

  /// Most lines cleared by a single placement.
  int get biggestClear => _v['biggestClear']!;
  int get totalScore => _v['totalScore']!;
  int get averageScore => gamesPlayed == 0 ? 0 : totalScore ~/ gamesPlayed;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _keys) {
      _v[k] = prefs.getInt('stat_$k') ?? 0;
    }
    notifyListeners();
  }

  void onPlacement({required int blocks, required int lines, required int streak}) {
    _add('blocks', blocks);
    if (lines > 0) _add('lines', lines);
    _max('bestStreak', streak);
    _max('biggestClear', lines);
  }

  void onGameEnded(int score) {
    _add('games', 1);
    _add('totalScore', score);
  }

  void _add(String k, int n) => _set(k, _v[k]! + n);

  void _max(String k, int n) {
    if (n > _v[k]!) _set(k, n);
  }

  void _set(String k, int value) {
    _v[k] = value;
    unawaited(SharedPreferences.getInstance().then((p) => p.setInt('stat_$k', value)));
    notifyListeners();
  }
}
