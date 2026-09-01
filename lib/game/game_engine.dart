import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/piece.dart';
import '../services/score_service.dart';

/// Core Block Puzzle game state: an 8x8 board, a 3-slot tray of pieces to
/// place, score/combo tracking, and game-over detection. Pure Dart, no
/// Flutter widget dependencies, so it can be unit-tested independently of
/// the drag-and-drop UI.
class GameEngine extends ChangeNotifier {
  static const int boardSize = 12;
  static const int trayCount = 3;

  List<List<Color?>> board = List.generate(boardSize, (_) => List<Color?>.filled(boardSize, null));
  List<PieceInstance?> tray = List<PieceInstance?>.filled(trayCount, null);

  int score = 0;
  int best = 0;
  int combo = 0;
  bool gameOver = false;
  bool paused = false;

  /// Cells mid line-clear flash, purely for the UI to render brighter before
  /// they actually disappear. Empty outside of that brief window.
  Set<Point> clearingCells = {};

  /// The most recent line-clear score popup (points + where to show it),
  /// paired with a sequence number the UI bumps-detects to know a *new*
  /// popup fired vs. re-reading the same one on an unrelated rebuild.
  ScorePopup? popup;
  int popupSeq = 0;

  Future<void> start() async {
    best = await ScoreService.instance.loadBest();
    board = List.generate(boardSize, (_) => List<Color?>.filled(boardSize, null));
    score = 0;
    combo = 0;
    gameOver = false;
    paused = false;
    clearingCells = {};
    tray = List<PieceInstance?>.filled(trayCount, null);
    _refillTray();
    notifyListeners();
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
    score += piece.cells.length;
    tray[trayIndex] = null;
    HapticFeedback.selectionClick();

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
      clearingCells = flashed;
      notifyListeners();
      HapticFeedback.mediumImpact();
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

      final centroidRow = flashed.map((p) => p.x).reduce((a, b) => a + b) / flashed.length;
      final centroidCol = flashed.map((p) => p.y).reduce((a, b) => a + b) / flashed.length;
      popup = ScorePopup(points: bonus, row: centroidRow, col: centroidCol);
      popupSeq++;
    } else {
      combo = 0;
    }

    if (tray.every((p) => p == null)) {
      _refillTray();
    }

    if (score > best) {
      best = score;
    }

    _checkGameOver();
    if (gameOver) {
      unawaited(ScoreService.instance.saveBest(best));
    }
    notifyListeners();
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

  void _checkGameOver() {
    for (final piece in tray) {
      if (piece != null && _canPlaceAnywhere(piece)) return;
    }
    gameOver = true;
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
