import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../models/piece.dart';
import 'piece_view.dart';
import 'tray_widget.dart';

/// The 8x8 board. Wrapped in a single `DragTarget<TrayDragData>` covering
/// the whole grid (rather than 64 individual targets) — dropped position is
/// derived from the feedback widget's global top-left corner
/// (`DragTargetDetails.offset` already accounts for feedbackOffset/anchor),
/// converted to board-local cell coordinates.
class BoardWidget extends StatefulWidget {
  final GameEngine engine;

  const BoardWidget({super.key, required this.engine});

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  final GlobalKey _boardKey = GlobalKey();
  int? _previewRow;
  int? _previewCol;
  PieceInstance? _previewPiece;
  bool _previewValid = false;

  void _updatePreview(DragTargetDetails<TrayDragData> details, double cellSize) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final row = (local.dy / cellSize).floor();
    final col = (local.dx / cellSize).floor();
    setState(() {
      _previewPiece = details.data.piece;
      _previewRow = row;
      _previewCol = col;
      _previewValid = widget.engine.canPlacePieceAt(details.data.piece, row, col);
    });
  }

  void _clearPreview() {
    setState(() {
      _previewPiece = null;
      _previewRow = null;
      _previewCol = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = GameEngine.boardSize;
        final cellSize = constraints.maxWidth / size;
        return DragTarget<TrayDragData>(
          onWillAcceptWithDetails: (details) {
            _updatePreview(details, cellSize);
            return true;
          },
          onMove: (details) => _updatePreview(details, cellSize),
          onLeave: (_) => _clearPreview(),
          onAcceptWithDetails: (details) {
            final row = _previewRow;
            final col = _previewCol;
            _clearPreview();
            if (row == null || col == null) return;
            if (widget.engine.canPlacePieceAt(details.data.piece, row, col)) {
              widget.engine.placePiece(details.data.trayIndex, row, col);
            }
          },
          builder: (context, candidateData, rejectedData) {
            return Container(
              key: _boardKey,
              width: constraints.maxWidth,
              height: constraints.maxWidth,
              decoration: BoxDecoration(
                color: const Color(0xFF1B2430),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0E141C), width: 3),
              ),
              child: Stack(
                children: [
                  for (var r = 0; r < size; r++)
                    for (var c = 0; c < size; c++)
                      Positioned(
                        left: c * cellSize,
                        top: r * cellSize,
                        width: cellSize,
                        height: cellSize,
                        child: _buildCell(r, c),
                      ),
                  if (_previewPiece != null && _previewRow != null && _previewCol != null)
                    for (final cell in _previewPiece!.cells)
                      if (_inBounds(_previewRow! + cell.row, _previewCol! + cell.col))
                        Positioned(
                          left: (_previewCol! + cell.col) * cellSize,
                          top: (_previewRow! + cell.row) * cellSize,
                          width: cellSize,
                          height: cellSize,
                          child: Padding(
                            padding: EdgeInsets.all(cellSize * 0.06),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: (_previewValid ? Colors.greenAccent : Colors.redAccent).withValues(
                                  alpha: 0.55,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _inBounds(int r, int c) => r >= 0 && c >= 0 && r < GameEngine.boardSize && c < GameEngine.boardSize;

  Widget _buildCell(int r, int c) {
    final color = widget.engine.board[r][c];
    final isClearing = widget.engine.clearingCells.contains(Point(r, c));
    return Padding(
      padding: const EdgeInsets.all(1),
      child: color == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF232E3D),
                borderRadius: BorderRadius.circular(3),
              ),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              child: BlockCell(color: color, inset: 1, bright: isClearing),
            ),
    );
  }
}
