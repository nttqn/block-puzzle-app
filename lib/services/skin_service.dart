import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adventure_service.dart';
import 'stats_service.dart';

/// How placed blocks are drawn (`BlockCell`). Candy is the original sprite
/// art; the rest are drawn in code, so they need no extra assets.
enum BlockSkin { candy, flat, neon, crystal }

extension BlockSkinInfo on BlockSkin {
  String get label => switch (this) {
        BlockSkin.candy => 'Candy',
        BlockSkin.flat => 'Flat',
        BlockSkin.neon => 'Neon',
        BlockSkin.crystal => 'Crystal',
      };

  String get unlockHint => switch (this) {
        BlockSkin.candy => 'Unlocked',
        BlockSkin.flat => 'Play 5 games',
        BlockSkin.neon => 'Clear 200 lines',
        BlockSkin.crystal => 'Earn 30 Adventure stars',
      };

  bool get isUnlocked => switch (this) {
        BlockSkin.candy => true,
        BlockSkin.flat => StatsService.instance.gamesPlayed >= 5,
        BlockSkin.neon => StatsService.instance.linesCleared >= 200,
        BlockSkin.crystal => AdventureService.instance.totalStars >= 30,
      };
}

class SkinService {
  SkinService._();
  static final SkinService instance = SkinService._();

  static const _key = 'block_skin';
  final ValueNotifier<BlockSkin> skin = ValueNotifier(BlockSkin.candy);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    skin.value = BlockSkin.values.firstWhere((s) => s.name == name, orElse: () => BlockSkin.candy);
  }

  Future<void> select(BlockSkin s) async {
    if (!s.isUnlocked) return;
    skin.value = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, s.name);
  }
}
