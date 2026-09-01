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
      // Anchors the feedback's own top-left corner exactly at the pointer,
      // regardless of *where within the piece* the user grabbed it — unlike
      // the default childDragAnchorStrategy, which preserves the grabbed
      // point's fractional position and therefore introduces a grab-point-
      // dependent offset of up to half a cell either way. That was enough,
      // on a tight-fit gap exactly the piece's size (zero margin for
      // error), to tip the computed drop cell over by one and make a
      // genuinely-fitting placement register as invalid. With a fixed
      // anchor, the drop math (in BoardWidget, which reads this feedback's
      // tracked position) becomes a direct, grab-point-independent mapping
      // of pointer position to board cell.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // feedbackOffset is deliberately left at zero for the same reason:
      // BoardWidget derives the drop cell from this feedback's tracked
      // position (see its doc comment), so any nonzero feedbackOffset here
      // would shift *where a piece actually lands* away from where it's
      // drawn. The lift-above-the-finger visual is instead done with a
      // plain Transform inside the feedback itself, which only shifts
      // paint, not the tracked layout position.
      feedback: Transform.translate(
        offset: Offset(0, -boardCellSize * 1.5),
        child: PieceView(piece: piece, cellSize: boardCellSize),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: display),
      child: display,
    );
  }
}
