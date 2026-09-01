import 'package:flutter/material.dart';

/// Full-bleed decorative background shared by the home screen and the game
/// screen, with a dark scrim between the image and [child] so text/buttons
/// stay readable over the busy bokeh art. Gameplay itself isn't affected by
/// how dark the scrim is — `BoardWidget`'s cells paint their own opaque
/// background, so this only shows through in the padding/HUD/tray areas
/// around the board.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/backgrounds/bg.png', fit: BoxFit.cover),
        Container(color: Colors.black.withValues(alpha: 0.45)),
        child,
      ],
    );
  }
}
