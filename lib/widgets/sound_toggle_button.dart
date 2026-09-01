import 'package:flutter/material.dart';

import '../services/sound_service.dart';

/// Speaker icon that toggles [SoundService]'s on/off state, reflecting the
/// current value via its `enabledNotifier` so every instance of this button
/// (home screen, in-game AppBar) stays in sync with the same shared state.
class SoundToggleButton extends StatelessWidget {
  const SoundToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SoundService.instance.enabledNotifier,
      builder: (context, enabled, _) {
        return IconButton(
          icon: Icon(enabled ? Icons.volume_up : Icons.volume_off),
          onPressed: () => SoundService.instance.toggle(),
        );
      },
    );
  }
}
