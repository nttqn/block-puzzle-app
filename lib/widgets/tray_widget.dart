import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../models/piece.dart';
import 'piece_view.dart';

/// Payload carried by a tray piece's Draggable — the board needs the tray
/// index (not just the piece) so it knows which slot to clear on drop.
class TrayDragData {
  final PieceInstance piece;
  final int trayIndex;
  const TrayDragData({required this.piece, required this.trayIndex});
}

/// The row of up to 3 pieces waiting to be placed. Each piece is rendered
/// at [traySlotCellSize] but drags as a feedback rendered at the larger
/// [boardCellSize] so it lines up 1:1 with the board while dragging — the
/// jump in size on pickup is a deliberate, common genre convention that
/// makes the piece easier to see under a finger.
class TrayWidget extends StatelessWidget {
  final GameEngine engine;
  final double traySlotCellSize;
  final double boardCellSize;

  const TrayWidget({
    super.key,
    required this.engine,
    required this.traySlotCellSize,
    required this.boardCellSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < engine.tray.length; i++) _buildSlot(context, i),
      ],
    );
  }

  Widget _buildSlot(BuildContext context, int index) {
    final piece = engine.tray[index];
    final slotSize = traySlotCellSize * 5;
    if (piece == null) {
      return SizedBox(width: slotSize, height: slotSize);
    }

    // The whole slot (not just the piece's drawn cubes) must be grabbable —
    // a shape's empty cells and the small gaps between adjacent cubes are
    // otherwise dead zones a real finger can easily land in, silently
    // failing to start a drag. A transparent full-slot Container hit-tests
    // across its entire area regardless of what the piece looks like.
    final display = Container(
      width: slotSize,
      height: slotSize,
      color: Colors.transparent,
      alignment: Alignment.center,
      child: PieceView(piece: piece, cellSize: traySlotCellSize),
    );

    return Draggable<TrayDragData>(
      data: TrayDragData(piece: piece, trayIndex: index),
      feedback: PieceView(piece: piece, cellSize: boardCellSize),
      feedbackOffset: Offset(0, -boardCellSize * 3),
      childWhenDragging: Opacity(opacity: 0.25, child: display),
      child: display,
    );
  }
}
