import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/game/game_mode.dart';
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

    test('clearing 2 lines at once applies a x2 multi-clear bonus and fires the combo banner', () async {
      final engine = GameEngine();
      // Fill row 0 and column 0 entirely except their shared corner (0,0),
      // so a single-cell placement there completes both at once.
      for (var c = 1; c < GameEngine.boardSize; c++) {
        engine.board[0][c] = kPieceColors.first;
      }
      for (var r = 1; r < GameEngine.boardSize; r++) {
        engine.board[r][0] = kPieceColors.first;
      }
      engine.tray[0] = _singleCell();
      final scoreBefore = engine.score;
      final bannerSeqBefore = engine.comboBannerSeq;

      await engine.placePiece(0, 0, 0);

      expect(engine.board[0].every((cell) => cell == null), isTrue);
      expect(engine.board.every((row) => row[0] == null), isTrue);
      // 1 point for the placed cell, plus (2 lines * 10 base points) * x2
      // multi-clear multiplier = 40.
      expect(engine.score, scoreBefore + 1 + 40);
      expect(engine.comboBannerMultiplier, 2);
      expect(engine.comboBannerSeq, bannerSeqBefore + 1);
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

  group('survival mode bomb', () {
    test('classic mode never spawns a bomb', () async {
      final engine = GameEngine();
      await engine.start();
      expect(engine.bomb, isNull);
      engine.dispose();
    });

    test('starting survival mode spawns a bomb that occupies its cell', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.survival);

      expect(engine.bomb, isNotNull);
      final bomb = engine.bomb!;
      expect(engine.board[bomb.row][bomb.col], kBombColor);
      // The tray's random pieces are chosen to always be placeable
      // somewhere, so the bomb's own cell must never be requested for one.
      expect(engine.canPlacePieceAt(_singleCell(), bomb.row, bomb.col), isFalse);

      engine.dispose();
    });

    test('completing the bomb\'s row defuses it', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.survival);
      final bomb = engine.bomb!;

      // Fill the rest of the bomb's row with a real placement; the bomb
      // cell itself already counts as "filled" toward the row being full.
      for (var c = 0; c < GameEngine.boardSize; c++) {
        if (c != bomb.col) engine.board[bomb.row][c] = kPieceColors.first;
      }
      engine.tray[0] = _singleCell();
      // Place a harmless single cell elsewhere just to drive placePiece's
      // full-board rescan — the row is already complete before this call.
      final targetRow = (bomb.row + 1) % GameEngine.boardSize;
      final targetCol = engine.board[targetRow].indexWhere((cell) => cell == null);
      await engine.placePiece(0, targetRow, targetCol);

      // The old bomb's cell is cleared along with the rest of the row.
      expect(engine.board[bomb.row][bomb.col], isNull);
      // A fresh bomb spawns immediately to keep survival mode's pressure
      // continuous — confirm it isn't still sitting at the old position
      // (which would mean the defuse never actually happened).
      if (engine.bomb != null) {
        expect(engine.bomb!.row != bomb.row || engine.bomb!.col != bomb.col, isTrue);
      }

      engine.dispose();
    });

    testWidgets('bomb timeout ends the run even if pieces could still be placed', (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final engine = GameEngine();
      await engine.start(mode: GameMode.survival);
      expect(engine.bomb, isNotNull);
      engine.bomb!.secondsLeft = 1;

      await tester.pump(const Duration(seconds: 1, milliseconds: 100));

      expect(engine.gameOver, isTrue);
      engine.dispose();
    });
  });
}
