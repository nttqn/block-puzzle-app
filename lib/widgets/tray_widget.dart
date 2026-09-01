import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../models/piece.dart';
import '../services/sound_service.dart';
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
    // Each slot gets an equal, *bounded* third of the row via Expanded —
    // giving _buildSlot's FittedBox something concrete to shrink into.
    // Without a hard width bound here, 3 slots sized at their natural
    // traySlotCellSize could exceed the row's actual available width on
    // some window sizes (this shipped as a real "RenderFlex overflowed"
    // crash — traySlotCellSize is derived from the board's own layout,
    // which isn't guaranteed to leave exactly this much room for the tray
    // in every aspect ratio) and FittedBox alone does nothing without a
    // bounded parent to fit into.
    return Row(
      children: [
        for (var i = 0; i < engine.tray.length; i++) Expanded(child: Center(child: _buildSlot(context, i))),
      ],
    );
  }

  Widget _buildSlot(BuildContext context, int index) {
    final piece = engine.tray[index];
    final slotSize = traySlotCellSize * 5;
    if (piece == null) {
      return SizedBox(width: slotSize, height: slotSize);
    }
    // FittedBox shrinks the slot's fixed-size content (drawn at slotSize,
    // which is derived from the board's layout and can exceed what Expanded
    // actually allocates this slot in the Row) down to fit — Expanded alone
    // only guarantees the Row itself doesn't overflow; it doesn't stop an
    // oversized child from visually spilling past its slot into a neighbor.
    // Scoped to the in-place display only: the returned Draggable's `feedback`
    // is painted through the Overlay during a drag, entirely outside this
    // FittedBox, so it stays sized off boardCellSize untouched.
    return FittedBox(fit: BoxFit.scaleDown, child: _buildDraggable(piece, index, slotSize));
  }

  Widget _buildDraggable(PieceInstance piece, int index, double slotSize) {
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

    final feedbackWidth = piece.width * boardCellSize;
    final feedbackHeight = piece.height * boardCellSize;

    return Draggable<TrayDragData>(
      data: TrayDragData(piece: piece, trayIndex: index),
      // Anchors the feedback's *center* at the pointer, regardless of
      // where within the piece the user actually grabbed it. Two prior
      // designs were both worse:
      //  - childDragAnchorStrategy (the default) preserves the grabbed
      //    point's fractional position, which introduced a grab-point-
      //    dependent offset of up to half a cell — enough, on a tight-fit
      //    gap exactly the piece's size, to tip the computed drop cell
      //    over by one and reject a placement that actually fit.
      //  - pointerDragAnchorStrategy (anchors the top-left corner instead)
      //    fixed that, but meant the piece's top-left snapped to the
      //    finger regardless of where you grabbed it — combined with the
      //    visual lift below, this produced a confusing double jump users
      //    reported as "I have to drop it somewhere else entirely for it
      //    to match."
      // Center-anchoring is just as deterministic (no grab-point
      // dependency, so the tight-fit bug stays fixed) but reads far more
      // naturally: the piece moves as a rigid body centered on the finger,
      // the way people actually expect a dragged shape to behave.
      dragAnchorStrategy: (draggable, context, position) => Offset(feedbackWidth / 2, feedbackHeight / 2),
      // feedbackOffset is deliberately left at zero: BoardWidget derives
      // the drop cell from this feedback's tracked position (see its doc
      // comment), so any nonzero feedbackOffset here would shift *where a
      // piece actually lands* away from where it's drawn. The lift-above-
      // the-finger visual is instead done with a plain Transform inside
      // the feedback itself, which only shifts paint, not the tracked
      // layout position. Kept modest now that the piece is already
      // centered on the finger (rather than 1.5 cells, which — even
      // paint-only — visually separated the piece from the finger enough
      // to feel like it wasn't tracking correctly).
      feedback: Transform.translate(
        offset: Offset(0, -boardCellSize * 0.6),
        child: PieceView(piece: piece, cellSize: boardCellSize),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: display),
      // Fires when the piece is released somewhere that isn't any
      // DragTarget at all (e.g. off the board entirely) — the invalid-
      // placement-on-the-board case is handled separately in
      // BoardWidget.onAcceptWithDetails, since the board always technically
      // "accepts" the drag at the framework level and only our own check
      // decides whether to actually place it.
      onDraggableCanceled: (velocity, offset) => SoundService.instance.play(SoundEffect.pickupBack),
      child: display,
    );
  }
}
