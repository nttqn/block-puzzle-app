import 'package:flutter/material.dart';

import '../services/music_service.dart';

/// Note icon that toggles [MusicService]'s on/off state — independent of
/// [SoundToggleButton], which only controls sound effects. Shared by
/// `HomeScreen`'s AppBar and `GameScreen`'s AppBar, same reasoning as that
/// button: one widget, not a per-screen copy, so both use the exact same
/// instance/behavior.
class MusicToggleButton extends StatelessWidget {
  const MusicToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MusicService.instance.enabledNotifier,
      builder: (context, enabled, _) {
        return IconButton(
          icon: Icon(enabled ? Icons.music_note : Icons.music_off),
          onPressed: () => MusicService.instance.toggle(),
          // Keep this as tight as SoundToggleButton — a real
          // "RenderFlex overflowed" was hit in the game screen's AppBar
          // before (see game_screen.dart's AppBar comment), and this adds
          // a second icon button to that same tight row.
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      },
    );
  }
}
