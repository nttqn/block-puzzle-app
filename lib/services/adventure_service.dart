import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/adventure.dart';

/// Best stars per Adventure level (0 = not beaten yet). A level is playable
/// once the one before it has been beaten.
class AdventureService extends ChangeNotifier {
  AdventureService._();
  static final AdventureService instance = AdventureService._();

  static const _key = 'adventure_stars';
  List<int> _stars = List<int>.filled(kAdventureLevels, 0);

  int starsFor(int level) => level >= 1 && level <= _stars.length ? _stars[level - 1] : 0;
  int get totalStars => _stars.fold(0, (a, b) => a + b);

  /// Highest level the player may start.
  int get unlocked {
    var n = 1;
    while (n <= kAdventureLevels && starsFor(n) > 0) {
      n++;
    }
    return n.clamp(1, kAdventureLevels);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key) ?? const [];
    _stars = [for (var i = 0; i < kAdventureLevels; i++) i < saved.length ? int.tryParse(saved[i]) ?? 0 : 0];
    notifyListeners();
  }

  Future<void> record(int level, int stars) async {
    if (stars <= starsFor(level)) return;
    _stars[level - 1] = stars;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final s in _stars) '$s']);
  }
}
