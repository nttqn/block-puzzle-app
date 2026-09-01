import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/piece.dart';
import '../services/score_service.dart';
import '../services/sound_service.dart';
import 'game_mode.dart';

/// The board color a bomb tile is drawn with. Occupies its cell like any
/// placed block (so `canPlacePieceAt` naturally refuses to place on it, and
/// a row/column counts it as "filled" toward completing a line) but is
/// rendered distinctly by the UI and carries its own countdown.
const Color kBombColor = Color(0xFF14181D);

/// Core Block Puzzle game state: a board, a 3-slot tray of pieces to place,
/// score/combo tracking, game-over detection, and (in [GameMode.survival])
/// a bomb tile racing a countdown. Pure Dart, no Flutter widget
/// dependencies, so it can be unit-tested independently of the
/// drag-and-drop UI.
class GameEngine extends ChangeNotifier {
  static const int boardSize = 12;
  static const int trayCount = 3;
  static const int bombSeconds = 25;

  List<List<Color?>> board = List.generate(boardSize, (_) => List<Color?>.filled(boardSize, null));
  List<PieceInstance?> tray = List<PieceInstance?>.filled(trayCount, null);

  GameMode mode = GameMode.classic;
  int score = 0;
  int best = 0;
  int combo = 0;
  bool gameOver = false;
  bool paused = false;

  /// The single active bomb tile in survival mode, or null in classic mode
  /// / between one being defused and the next spawning.
  BombTile? bomb;
  Timer? _bombTimer;

  final Random _rng = Random();

  /// Cells mid line-clear flash, purely for the UI to render brighter before
  /// they actually disappear. Empty outside of that brief window.
  Set<Point> clearingCells = {};

  /// The most recent line-clear score popup (points + where to show it),
  /// paired with a sequence number the UI bumps-detects to know a *new*
  /// popup fired vs. re-reading the same one on an unrelated rebuild.
  ScorePopup? popup;
  int popupSeq = 0;

  /// The most recent line-clear explosion (which cells burst, and their
  /// color at the moment they cleared), paired with a sequence number the
  /// same way [popup]/[popupSeq] are — so the UI can tell "a new clear
  /// just happened" apart from re-reading a stale value on an unrelated
  /// rebuild.
  ExplosionEvent? explosion;
  int explosionSeq = 0;

  Future<void> start({GameMode mode = GameMode.classic}) async {
    this.mode = mode;
    best = await ScoreService.instance.loadBest(mode);
    board = List.generate(boardSize, (_) => List<Color?>.filled(boardSize, null));
    score = 0;
    combo = 0;
    gameOver = false;
    paused = false;
    clearingCells = {};
    bomb = null;
    tray = List<PieceInstance?>.filled(trayCount, null);
    _refillTray();

    _bombTimer?.cancel();
    _bombTimer = null;
    if (mode == GameMode.survival) {
      _maybeSpawnBomb();
      _bombTimer = Timer.periodic(const Duration(seconds: 1), _tickBomb);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _bombTimer?.cancel();
    super.dispose();
  }

  void _tickBomb(Timer timer) {
    if (paused || gameOver || bomb == null) return;
    bomb!.secondsLeft--;
    if (bomb!.secondsLeft <= 0) {
      gameOver = true;
      unawaited(ScoreService.instance.saveBest(mode, score));
      timer.cancel();
    }
    notifyListeners();
  }

  /// Picks a random empty cell to plant a bomb on, if none is currently
  /// active. A no-op once the board has no empty cells left (an already
  /// near-unwinnable state regardless).
  void _maybeSpawnBomb() {
    if (mode != GameMode.survival || bomb != null) return;
    final emptyCells = <Point>[];
    for (var r = 0; r < boardSize; r++) {
      for (var c = 0; c < boardSize; c++) {
        if (board[r][c] == null) emptyCells.add(Point(r, c));
      }
    }
    if (emptyCells.isEmpty) return;
    final chosen = emptyCells[_rng.nextInt(emptyCells.length)];
    board[chosen.x][chosen.y] = kBombColor;
    bomb = BombTile(row: chosen.x, col: chosen.y, secondsLeft: bombSeconds);
  }

  void togglePause() {
    if (gameOver) return;
    paused = !paused;
    notifyListeners();
  }

  bool canPlacePieceAt(PieceInstance piece, int originRow, int originCol) {
    for (final cell in piece.cells) {
      final r = originRow + cell.row;
      final c = originCol + cell.col;
      if (r < 0 || c < 0 || r >= boardSize || c >= boardSize) return false;
      if (board[r][c] != null) return false;
    }
    return true;
  }

  bool _canPlaceAnywhere(PieceInstance piece) {
    for (var r = 0; r < boardSize; r++) {
      for (var c = 0; c < boardSize; c++) {
        if (canPlacePieceAt(piece, r, c)) return true;
      }
    }
    return false;
  }

  /// Places tray[trayIndex] at the given board origin. Caller must have
  /// already verified [canPlacePieceAt] — this does not re-check.
  Future<void> placePiece(int trayIndex, int originRow, int originCol) async {
    if (paused || gameOver) return;
    final piece = tray[trayIndex];
    if (piece == null) return;

    for (final cell in piece.cells) {
      board[originRow + cell.row][originCol + cell.col] = piece.color;
    }
    final pointsGained = piece.cells.length;
    score += pointsGained;
    var totalGainedThisMove = pointsGained;
    final pieceCentroidRow =
        originRow + piece.cells.map((c) => c.row).reduce((a, b) => a + b) / piece.cells.length;
    final pieceCentroidCol =
        originCol + piece.cells.map((c) => c.col).reduce((a, b) => a + b) / piece.cells.length;
    tray[trayIndex] = null;
    HapticFeedback.selectionClick();
    SoundService.instance.play(SoundEffect.place);

    final fullRows = <int>[];
    final fullCols = <int>[];
    for (var r = 0; r < boardSize; r++) {
      if (board[r].every((cell) => cell != null)) fullRows.add(r);
    }
    for (var c = 0; c < boardSize; c++) {
      if (board.every((row) => row[c] != null)) fullCols.add(c);
    }

    if (fullRows.isNotEmpty || fullCols.isNotEmpty) {
      final flashed = <Point>{};
      for (final r in fullRows) {
        for (var c = 0; c < boardSize; c++) {
          flashed.add(Point(r, c));
        }
      }
      for (final c in fullCols) {
        for (var r = 0; r < boardSize; r++) {
          flashed.add(Point(r, c));
        }
      }
      if (bomb != null && (fullRows.contains(bomb!.row) || fullCols.contains(bomb!.col))) {
        bomb = null;
      }

      // Capture each cell's color before it's nulled below, for the
      // explosion particle effect — the board itself no longer has this
      // information once the clear actually happens.
      explosion = ExplosionEvent(
        flashed.map((p) => ExplosionCell(row: p.x, col: p.y, color: board[p.x][p.y] ?? kBombColor)).toList(),
      );
      explosionSeq++;

      clearingCells = flashed;
      notifyListeners();
      HapticFeedback.mediumImpact();
      SoundService.instance.play(SoundEffect.clear);
      await Future.delayed(const Duration(milliseconds: 160));

      for (final r in fullRows) {
        for (var c = 0; c < boardSize; c++) {
          board[r][c] = null;
        }
      }
      for (final c in fullCols) {
        for (var r = 0; r < boardSize; r++) {
          board[r][c] = null;
        }
      }
      clearingCells = {};

      combo++;
      final totalLines = fullRows.length + fullCols.length;
      var linePoints = totalLines * 10;
      if (totalLines > 1) linePoints += (totalLines - 1) * 10;
      final comboMultiplier = 1 + (combo - 1) * 0.5;
      final bonus = (linePoints * comboMultiplier).round();
      score += bonus;
      totalGainedThisMove += bonus;
    } else {
      combo = 0;
    }

    // Every successful placement earns at least the base per-cell points,
    // so the "+N" popup fires every move, not just on a line clear — shown
    // at the piece's own landing spot (which is always defined, unlike a
    // cleared-line centroid that only exists when a clear happens).
    popup = ScorePopup(points: totalGainedThisMove, row: pieceCentroidRow, col: pieceCentroidCol);
    popupSeq++;

    if (tray.every((p) => p == null)) {
      _refillTray();
    }

    _maybeSpawnBomb();

    if (score > best) {
      best = score;
    }

    _checkGameOver();
    if (gameOver) {
      unawaited(ScoreService.instance.saveBest(mode, score));
    }
    notifyListeners();
  }

  void _checkGameOver() {
    for (final piece in tray) {
      if (piece != null && _canPlaceAnywhere(piece)) return;
    }
    gameOver = true;
  }

  void _refillTray() {
    for (var i = 0; i < trayCount; i++) {
      tray[i] = _pickFairPiece();
    }
  }

  /// Picks a random piece, retrying a few times if the board is nearly full
  /// so a fresh tray doesn't hand the player an immediately-unplaceable
  /// piece more often than necessary. Not a hard guarantee (the genre's
  /// classic "unlucky board" game-over is still possible by design).
  PieceInstance _pickFairPiece() {
    PieceInstance candidate = randomPiece();
    for (var attempt = 0; attempt < 20; attempt++) {
      if (_canPlaceAnywhere(candidate)) return candidate;
      candidate = randomPiece();
    }
    return candidate;
  }
}

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);

  @override
  bool operator ==(Object other) => other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// A one-shot "+N" floating score popup, centered on the cleared cells'
/// centroid (in board row/col units, fractional so it can land between
/// cells for a multi-line clear).
class ScorePopup {
  final int points;
  final double row;
  final double col;
  const ScorePopup({required this.points, required this.row, required this.col});
}

/// A single line-clear event: every cell that burst, and the color it was
/// showing at the moment it cleared (the board cell itself is nulled right
/// after this is captured, so this is the only record of what color
/// belongs at each exploding position).
class ExplosionEvent {
  final List<ExplosionCell> cells;
  const ExplosionEvent(this.cells);
}

class ExplosionCell {
  final int row;
  final int col;
  final Color color;
  const ExplosionCell({required this.row, required this.col, required this.color});
}

/// A survival-mode bomb sitting on the board at (row, col), counting down.
/// Defused by completing its row or column (a normal line clear); reaching
/// zero seconds ends the run regardless of whether pieces could still fit.
class BombTile {
  final int row;
  final int col;
  int secondsLeft;
  BombTile({required this.row, required this.col, required this.secondsLeft});
}
