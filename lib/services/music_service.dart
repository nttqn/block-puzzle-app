import 'package:flame_audio/flame_audio.dart';

import 'sound_service.dart';

/// Looping background music, kept separate from [SoundService] (which only
/// ever deals in one-shot [AudioPool] effects) since `FlameAudio.bgm` is a
/// different mechanism — a single lifecycle-aware looping player, not a
/// pool.
///
/// Both tracks are procedurally synthesised (`tool/gen_music.js`), not
/// recorded — see that script for how/why, and regenerate from there if the
/// style ever needs changing rather than hand-editing the WAVs.
///
/// Respects the same [SoundService.enabledNotifier] toggle as the SFX —
/// deliberately not a second, separate music toggle, since the existing
/// single speaker icon already reads to a player as "all game audio" and a
/// second control nobody asked for would just be clutter.
class MusicService {
  MusicService._();
  static final MusicService instance = MusicService._();

  static const _menuTrack = 'bgm_menu.wav';
  static const _gameTrack = 'bgm_game.wav';
  static const _volume = 0.45;

  String? _wanted;
  bool _initialized = false;

  Future<void> init() async {
    try {
      // Registers the WidgetsBinding observer that auto-pauses/resumes this
      // track on app background/foreground — must happen once before the
      // first play() call. The audio-context param here is the same fix
      // SoundService.init() applies globally for its own AudioPool
      // players (audioFocus: none, so SFX don't steal focus and cut this
      // loop out) — passed explicitly rather than relying on that global
      // default, since main.dart fires both services' init() unawaited
      // with no guaranteed order, and FlameAudio.bgm otherwise falls back
      // to its own internal default (mixWithOthers) the instant it's
      // first referenced.
      await FlameAudio.bgm.initialize(
        audioContext: AudioContext(
          android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
      _initialized = true;
    } catch (_) {
      // No bgm this session (e.g. a broken/missing asset) — the game must
      // stay fully playable in silence, same contract as SoundService.
    }
    SoundService.instance.enabledNotifier.addListener(_onToggle);
  }

  void playMenu() => _play(_menuTrack);

  void playGame() => _play(_gameTrack);

  void _play(String track) {
    _wanted = track;
    if (!_initialized || !SoundService.instance.enabledNotifier.value) return;
    // Bgm.play() is documented as safe to call while another track is
    // already playing — it releases the old source first, so switching
    // menu <-> game music is just calling this again with the other file.
    FlameAudio.bgm.play(track, volume: _volume).catchError((_) {});
  }

  void _onToggle() {
    if (!_initialized || _wanted == null) return;
    if (SoundService.instance.enabledNotifier.value) {
      FlameAudio.bgm.play(_wanted!, volume: _volume).catchError((_) {});
    } else {
      FlameAudio.bgm.stop().catchError((_) {});
    }
  }
}
