import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/models/piece.dart';

PieceInstance _singleCell() {
  final shape = kAllShapes.firstWhere((s) => s.cells.length == 1);
  return PieceInstance(cells: shape.cells, width: shape.width, height: shape.height, color: kPieceColors.first);
}

PieceInstance _horizontalLineOf(int length) {
  final shape = kAllShapes.firstWhere((s) => s.height == 1 && s.width == length && s.cells.length == length);
  return PieceInstance(cells: shape.cells, width: shape.width, height: shape.height, color: kPieceColors.first);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('canPlacePieceAt', () {
    test('rejects placements outside the board', () {
      final engine = GameEngine();
      final piece = _singleCell();
      expect(engine.canPlacePieceAt(piece, -1, 0), isFalse);
      expect(engine.canPlacePieceAt(piece, 0, GameEngine.boardSize), isFalse);
    });

    test('rejects placements overlapping an occupied cell', () {
      final engine = GameEngine();
      engine.board[3][3] = kPieceColors.first;
      expect(engine.canPlacePieceAt(_singleCell(), 3, 3), isFalse);
      expect(engine.canPlacePieceAt(_singleCell(), 3, 4), isTrue);
    });
  });

  group('placePiece', () {
    test('fills the board and awards one point per cell', () async {
      final engine = GameEngine();
      // Keep slots 1-2 occupied so placing slot 0 doesn't empty the whole
      // tray and trigger an auto-refill (which would repopulate slot 0).
      engine.tray[0] = _horizontalLineOf(3);
      engine.tray[1] = _singleCell();
      engine.tray[2] = _singleCell();
      await engine.placePiece(0, 0, 0);

      expect(engine.board[0][0], isNotNull);
      expect(engine.board[0][1], isNotNull);
      expect(engine.board[0][2], isNotNull);
      expect(engine.score, 3);
      expect(engine.tray[0], isNull);
    });

    test('completing a full row clears it and awards bonus points', () async {
      final engine = GameEngine();
      // Fill the first row except the last cell with a real placement so
      // completing it goes through the normal placePiece path.
      for (var c = 0; c < GameEngine.boardSize - 1; c++) {
        engine.board[0][c] = kPieceColors.first;
      }
      engine.tray[0] = _singleCell();
      final scoreBefore = engine.score;

      await engine.placePiece(0, 0, GameEngine.boardSize - 1);

      // Row 0 should be cleared back to empty.
      expect(engine.board[0].every((cell) => cell == null), isTrue);
      // 1 point for the placed cell, plus a 10-point line-clear bonus.
      expect(engine.score, scoreBefore + 1 + 10);
      expect(engine.combo, 1);
    });

    test('a placement that clears nothing resets the combo streak', () async {
      final engine = GameEngine();
      engine.combo = 3;
      engine.tray[0] = _singleCell();
      await engine.placePiece(0, 0, 0);
      expect(engine.combo, 0);
    });
  });

  group('game over detection', () {
    // Fills the whole board, then punches a diagonal of single-cell gaps
    // (r,r) plus two extras at (6,2)/(3,6). No row or column is ever fully
    // filled by this setup (each has its own gap) so nothing spuriously
    // clears, and no two empty cells share a row with adjacent columns —
    // a horizontal domino can never bridge any pair of them.
    GameEngine buildNearFullBoard() {
      final engine = GameEngine();
      for (var r = 0; r < GameEngine.boardSize; r++) {
        for (var c = 0; c < GameEngine.boardSize; c++) {
          engine.board[r][c] = kPieceColors.first;
        }
      }
      for (var i = 0; i < GameEngine.boardSize; i++) {
        engine.board[i][i] = null;
      }
      engine.board[6][2] = null;
      engine.board[3][6] = null;
      return engine;
    }

    test('domino cannot fit anywhere on the near-full board', () {
      final engine = buildNearFullBoard();
      final domino = _horizontalLineOf(2);
      for (var r = 0; r < GameEngine.boardSize; r++) {
        for (var c = 0; c < GameEngine.boardSize; c++) {
          expect(engine.canPlacePieceAt(domino, r, c), isFalse, reason: 'at ($r,$c)');
        }
      }
    });

    test('flags game over once no tray piece fits anywhere', () async {
      final engine = buildNearFullBoard();
      // Placing the single cell at the (6,6) diagonal gap leaves row 6
      // still open at (6,2) and column 6 still open at (3,6) — no clear.
      engine.tray[0] = _singleCell();
      engine.tray[1] = _horizontalLineOf(2);
      engine.tray[2] = null;

      await engine.placePiece(0, 6, 6);

      expect(engine.board[0].contains(null), isTrue, reason: 'row 0 should not have been cleared');
      expect(engine.gameOver, isTrue);
    });
  });
}
