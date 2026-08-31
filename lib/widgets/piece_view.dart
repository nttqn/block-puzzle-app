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
