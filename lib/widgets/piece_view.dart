import 'package:flutter/material.dart';

import '../models/piece.dart';

/// Renders a [PieceInstance] as its own little grid of block cells, sized
/// by [cellSize]. Used both for the tray display and as a Draggable's
/// feedback — the two must be built from the same widget so a tray piece's
/// on-screen shape exactly matches what gets dragged.
class PieceView extends StatelessWidget {
  final PieceInstance piece;
  final double cellSize;
  final double opacity;

  const PieceView({super.key, required this.piece, required this.cellSize, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: piece.width * cellSize,
        height: piece.height * cellSize,
        child: Stack(
          children: [
            for (final cell in piece.cells)
              Positioned(
                left: cell.col * cellSize,
                top: cell.row * cellSize,
                width: cellSize,
                height: cellSize,
                child: BlockCell(color: piece.color, inset: cellSize * 0.06),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single glossy block cube — the shared visual unit for both placed
/// board cells and piece previews.
class BlockCell extends StatelessWidget {
  final Color color;
  final double inset;
  final bool bright;

  const BlockCell({super.key, required this.color, this.inset = 2, this.bright = false});

  @override
  Widget build(BuildContext context) {
    final base = bright ? Color.lerp(color, Colors.white, 0.55)! : color;
    return Padding(
      padding: EdgeInsets.all(inset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(base, Colors.white, 0.35)!, base, Color.lerp(base, Colors.black, 0.15)!],
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2, offset: const Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

/// A survival-mode bomb tile: a dark, glowing disc with its remaining
/// seconds — visually distinct from a normal placed [BlockCell] so it reads
/// as "something you must act on," not just another color.
class BombCell extends StatelessWidget {
  final int secondsLeft;

  const BombCell({super.key, required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 5;
    final glow = urgent ? Colors.redAccent : Colors.orangeAccent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Padding(
          padding: EdgeInsets.all(size * 0.05),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color.lerp(glow, Colors.black, 0.35)!, const Color(0xFF0B0D10)],
              ),
              border: Border.all(color: glow, width: size * 0.05),
              boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.6), blurRadius: size * 0.25)],
            ),
            child: Center(
              child: Text(
                '$secondsLeft',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.5,
                  shadows: [Shadow(color: glow, blurRadius: size * 0.15)],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
