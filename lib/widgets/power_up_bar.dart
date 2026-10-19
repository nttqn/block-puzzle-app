import 'package:flutter/material.dart';

/// Undo / Hammer / Shuffle buttons. Each shows its remaining free charges,
/// or a small "watch ad" badge once spent.
class PowerUpBar extends StatelessWidget {
  final int undoCharges;
  final int hammerCharges;
  final int shuffleCharges;
  final bool canUndo;
  final bool enabled;
  final bool hammerArmed;
  final VoidCallback onUndo;
  final VoidCallback onHammer;
  final VoidCallback onShuffle;

  const PowerUpBar({
    super.key,
    required this.undoCharges,
    required this.hammerCharges,
    required this.shuffleCharges,
    required this.canUndo,
    required this.enabled,
    required this.hammerArmed,
    required this.onUndo,
    required this.onHammer,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PowerUpButton(
          icon: Icons.undo,
          label: 'Undo',
          charges: undoCharges,
          enabled: enabled && canUndo,
          onTap: onUndo,
        ),
        const SizedBox(width: 28),
        _PowerUpButton(
          icon: Icons.gavel,
          label: 'Hammer',
          charges: hammerCharges,
          enabled: enabled,
          active: hammerArmed,
          onTap: onHammer,
        ),
        const SizedBox(width: 28),
        _PowerUpButton(
          icon: Icons.shuffle,
          label: 'Shuffle',
          charges: shuffleCharges,
          enabled: enabled,
          onTap: onShuffle,
        ),
      ],
    );
  }
}

class _PowerUpButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int charges;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  const _PowerUpButton({
    required this.icon,
    required this.label,
    required this.charges,
    required this.enabled,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = active ? Colors.amberAccent : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Colors.amber.withValues(alpha: 0.25) : const Color(0xFF232E3D),
                    border: Border.all(color: accent.withValues(alpha: active ? 1 : 0.35), width: 2),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: charges > 0 ? Colors.green : Colors.deepOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: charges > 0
                        ? Text(
                            '$charges',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          )
                        : const Icon(Icons.play_arrow, color: Colors.white, size: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: accent.withValues(alpha: 0.8), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
