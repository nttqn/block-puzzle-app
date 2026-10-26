import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_mode.dart';

/// One in-progress game per [GameMode], so closing the app (or a phone
/// call) mid-run doesn't lose it. The engine owns the JSON shape
/// (`GameEngine.toSave` / `restoreSave`); this only stores it.
class GameSaveService {
  GameSaveService._();
  static final GameSaveService instance = GameSaveService._();

  String _key(GameMode mode) => 'saved_game_${mode.name}';

  Future<void> save(GameMode mode, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(mode), jsonEncode(data));
  }

  Future<Map<String, dynamic>?> load(GameMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(mode));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // A save from an older/broken build is not worth crashing over.
      await prefs.remove(_key(mode));
      return null;
    }
  }

  Future<void> clear(GameMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(mode));
  }
}
