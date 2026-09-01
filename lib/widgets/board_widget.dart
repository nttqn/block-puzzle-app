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

class _BoardWidgetState extends State<BoardWidget> with TickerProviderStateMixin {
  final GlobalKey _boardKey = GlobalKey();
  int? _previewRow;
  int? _previewCol;
  PieceInstance? _previewPiece;
  bool _previewValid = false;

  int _lastPopupSeq = 0;
  final List<_ActivePopup> _activePopups = [];

  @override
  void initState() {
    super.initState();
    _lastPopupSeq = widget.engine.popupSeq;
  }

  @override
  void didUpdateWidget(covariant BoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final popup = widget.engine.popup;
    if (widget.engine.popupSeq != _lastPopupSeq && popup != null) {
      _lastPopupSeq = widget.engine.popupSeq;
      _addPopup(popup);
    }
  }

  void _addPopup(ScorePopup popup) {
    final controller = AnimationController(duration: const Duration(milliseconds: 900), vsync: this);
    final entry = _ActivePopup(popup: popup, controller: controller);
    controller.addListener(() => setState(() {}));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _activePopups.remove(entry));
        controller.dispose();
      }
    });
    setState(() => _activePopups.add(entry));
    controller.forward();
  }

  @override
  void dispose() {
    for (final entry in _activePopups) {
      entry.controller.dispose();
    }
    super.dispose();
  }

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
                clipBehavior: Clip.none,
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
                  for (final entry in _activePopups) _buildPopup(entry, cellSize),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPopup(_ActivePopup entry, double cellSize) {
    final t = entry.controller.value;
    // Rises steadily for the whole animation, but only starts fading out
    // in the back half so the number reads clearly for a beat first.
    final rise = cellSize * 1.8 * Curves.easeOut.transform(t);
    final opacity = t < 0.5 ? 1.0 : 1.0 - Curves.easeIn.transform((t - 0.5) * 2);
    final centerX = (entry.popup.col + 0.5) * cellSize;
    final centerY = (entry.popup.row + 0.5) * cellSize;
    return Positioned(
      left: centerX - cellSize * 2,
      top: centerY - cellSize * 0.5 - rise,
      width: cellSize * 4,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Text(
            '+${entry.popup.points}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.amberAccent,
              fontSize: cellSize * 1.1,
              fontWeight: FontWeight.w900,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 6),
                Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _inBounds(int r, int c) => r >= 0 && c >= 0 && r < GameEngine.boardSize && c < GameEngine.boardSize;

  Widget _buildCell(int r, int c) {
    final color = widget.engine.board[r][c];
    final isClearing = widget.engine.clearingCells.contains(Point(r, c));
    final bomb = widget.engine.bomb;
    final isBomb = bomb != null && bomb.row == r && bomb.col == c;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: isBomb
          ? BombCell(secondsLeft: bomb.secondsLeft)
          : color == null
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

class _ActivePopup {
  final ScorePopup popup;
  final AnimationController controller;
  const _ActivePopup({required this.popup, required this.controller});
}
