import 'dart:math' show cos, pi, sin;

import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../models/piece.dart';
import '../services/sound_service.dart';
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

  int _lastExplosionSeq = 0;
  final List<_ActiveExplosion> _activeExplosions = [];

  int _lastComboBannerSeq = 0;
  final List<_ActiveComboBanner> _activeComboBanners = [];

  @override
  void initState() {
    super.initState();
    _lastPopupSeq = widget.engine.popupSeq;
    _lastExplosionSeq = widget.engine.explosionSeq;
    _lastComboBannerSeq = widget.engine.comboBannerSeq;
  }

  @override
  void didUpdateWidget(covariant BoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final popup = widget.engine.popup;
    if (widget.engine.popupSeq != _lastPopupSeq && popup != null) {
      _lastPopupSeq = widget.engine.popupSeq;
      _addPopup(popup);
    }
    final explosion = widget.engine.explosion;
    if (widget.engine.explosionSeq != _lastExplosionSeq && explosion != null) {
      _lastExplosionSeq = widget.engine.explosionSeq;
      _addExplosion(explosion);
    }
    final comboMultiplier = widget.engine.comboBannerMultiplier;
    if (widget.engine.comboBannerSeq != _lastComboBannerSeq && comboMultiplier != null) {
      _lastComboBannerSeq = widget.engine.comboBannerSeq;
      _addComboBanner(comboMultiplier);
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

  void _addExplosion(ExplosionEvent explosion) {
    final controller = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    final entry = _ActiveExplosion(explosion: explosion, controller: controller);
    controller.addListener(() => setState(() {}));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _activeExplosions.remove(entry));
        controller.dispose();
      }
    });
    setState(() => _activeExplosions.add(entry));
    controller.forward();
  }

  void _addComboBanner(int multiplier) {
    final controller = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    final entry = _ActiveComboBanner(multiplier: multiplier, controller: controller);
    controller.addListener(() => setState(() {}));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _activeComboBanners.remove(entry));
        controller.dispose();
      }
    });
    setState(() => _activeComboBanners.add(entry));
    controller.forward();
  }

  @override
  void dispose() {
    for (final entry in _activePopups) {
      entry.controller.dispose();
    }
    for (final entry in _activeExplosions) {
      entry.controller.dispose();
    }
    for (final entry in _activeComboBanners) {
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
            } else {
              SoundService.instance.play(SoundEffect.pickupBack);
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
                  for (final entry in _activeExplosions) ..._buildExplosion(entry, cellSize),
                  for (final entry in _activePopups) _buildPopup(entry, cellSize),
                  for (final entry in _activeComboBanners) _buildComboBanner(entry, cellSize),
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

  /// A big "COMBO xN!" banner for a multi-line clear — punches in with a
  /// slight overshoot (`easeOutBack`) over the first third of the
  /// animation, holds, then fades over the last third. Centered on the
  /// board horizontally and pinned above its vertical middle (rather than
  /// following the clear's centroid like `_buildPopup`) since a multi-line
  /// clear can span rows and columns at once with no single natural anchor
  /// point, and a fixed "title card" position reads more like a genre-
  /// standard callout than a per-cell effect anyway.
  Widget _buildComboBanner(_ActiveComboBanner entry, double cellSize) {
    final t = entry.controller.value;
    final scale = t < 0.35 ? Curves.easeOutBack.transform((t / 0.35).clamp(0.0, 1.0)) : 1.0;
    final opacity = t < 0.7
        ? 1.0
        : (1.0 - Curves.easeIn.transform(((t - 0.7) / 0.3).clamp(0.0, 1.0))).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      top: cellSize * GameEngine.boardSize * 0.32,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: Text(
                'COMBO x${entry.multiplier}!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: cellSize * 1.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 10),
                    Shadow(color: Colors.deepOrange, blurRadius: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const int _particlesPerCell = 6;

  /// A cleared cell bursts into [_particlesPerCell] small shards flying
  /// outward at evenly-spaced angles, shrinking and fading as they go — the
  /// underlying cell itself already flashes bright white and vanishes via
  /// `clearingCells`/`BlockCell(bright: true)` on its own faster timeline
  /// (see `_buildCell`); this runs concurrently on a longer timeline so the
  /// shards keep flying after the cell underneath has already gone empty.
  List<Widget> _buildExplosion(_ActiveExplosion entry, double cellSize) {
    final t = entry.controller.value;
    final travel = cellSize * 1.5 * Curves.easeOut.transform(t);
    final scale = 1 - t * 0.7;
    final opacity = (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);
    final particleSize = cellSize * 0.32;

    final widgets = <Widget>[];
    for (final cell in entry.explosion.cells) {
      final centerX = (cell.col + 0.5) * cellSize;
      final centerY = (cell.row + 0.5) * cellSize;
      for (var k = 0; k < _particlesPerCell; k++) {
        final angle = (k / _particlesPerCell) * 2 * pi;
        final dx = cos(angle) * travel;
        final dy = sin(angle) * travel;
        widgets.add(
          Positioned(
            left: centerX + dx - particleSize / 2,
            top: centerY + dy - particleSize / 2,
            width: particleSize,
            height: particleSize,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: cell.color, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
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
                  // inset: 0 here, not the usual small gap — the outer
                  // Padding(1) above already separates this cell from its
                  // neighbors, so adding another inset on top of that
                  // doubled the visible gap between adjacent placed blocks.
                  child: BlockCell(color: color, inset: 0, bright: isClearing),
                ),
    );
  }
}

class _ActivePopup {
  final ScorePopup popup;
  final AnimationController controller;
  const _ActivePopup({required this.popup, required this.controller});
}

class _ActiveExplosion {
  final ExplosionEvent explosion;
  final AnimationController controller;
  const _ActiveExplosion({required this.explosion, required this.controller});
}

class _ActiveComboBanner {
  final int multiplier;
  final AnimationController controller;
  const _ActiveComboBanner({required this.multiplier, required this.controller});
}
