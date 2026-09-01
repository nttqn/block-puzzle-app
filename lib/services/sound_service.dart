import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundEffect { place, pickupBack, clear, confirm, back }

/// Short one-shot sound effects, played via `flame_audio`'s `AudioPool`
/// (same pattern as the rest of this game series). `init()` must be fired
/// unawaited from `main()`, not awaited before `runApp()` — a missing or
/// broken asset can leave `AudioPool.create()`'s Future never resolving on
/// web, which would otherwise hang the entire app before its first frame
/// (see [[project_number_master_app]] in memory for the incident this
/// mirrors). Every play call is a safe no-op if the pool never finished
/// loading, or if sound is toggled off.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const _enabledKey = 'sound_enabled';

  static const Map<SoundEffect, String> _files = {
    SoundEffect.place: 'sfx_paint.wav',
    SoundEffect.pickupBack: 'sfx_stick.wav',
    SoundEffect.clear: 'sfx_explosive.wav',
    SoundEffect.confirm: 'sfx_menu_confirm.wav',
    SoundEffect.back: 'sfx_menu_back.wav',
  };

  final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(true);
  final Map<SoundEffect, AudioPool> _pools = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabledNotifier.value = prefs.getBool(_enabledKey) ?? true;

    for (final entry in _files.entries) {
      try {
        final pool = await FlameAudio.createPool(entry.value, minPlayers: 1, maxPlayers: 3)
            .timeout(const Duration(seconds: 5));
        _pools[entry.key] = pool;
      } catch (_) {
        // Missing/broken asset for this one effect shouldn't block the
        // rest — that effect just stays silent (play() below no-ops since
        // _pools has no entry for it).
      }
    }
  }

  void play(SoundEffect effect) {
    if (!enabledNotifier.value) return;
    _pools[effect]?.start();
  }

  Future<void> toggle() async {
    enabledNotifier.value = !enabledNotifier.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabledNotifier.value);
  }
}
