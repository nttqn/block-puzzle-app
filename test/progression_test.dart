import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/game/game_mode.dart';
import 'package:block_puzzle/models/piece.dart';
import 'package:block_puzzle/services/daily_service.dart';
import 'package:block_puzzle/services/game_save_service.dart';
import 'package:block_puzzle/services/power_up_inventory.dart';

PieceInstance _singleCell() {
  final shape = kAllShapes.firstWhere((s) => s.cells.length == 1);
  return PieceInstance(cells: shape.cells, width: shape.width, height: shape.height, color: kPieceColors[3]);
}

void _fillForGameOver(GameEngine engine) {
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
  engine.tray[0] = _singleCell();
  // A domino fits none of the diagonal holes, and keeping it in the tray
  // stops a refill from handing out pieces that would.
  final domino = kAllShapes.firstWhere((s) => s.height == 1 && s.width == 2);
  engine.tray[1] = PieceInstance(cells: domino.cells, width: 2, height: 1, color: kPieceColors.first);
  engine.tray[2] = null;
}

String _shapeOf(PieceInstance? p) =>
    p == null ? '-' : '${p.cells.map((c) => '${c.row}${c.col}').join()}/${p.color.toARGB32()}';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('save and resume', () {
    test('a placement is saved and a new engine resumes it exactly', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.classic);
      engine.tray[0] = _singleCell();
      engine.hammerCharges = 0;
      await engine.placePiece(0, 4, 7);
      await pumpEventQueue();

      final resumed = GameEngine();
      expect(await resumed.resume(GameMode.classic), isTrue);
      expect(resumed.board[4][7], kPieceColors[3]);
      expect(resumed.score, engine.score);
      expect(resumed.hammerCharges, 0);
      expect([for (final p in resumed.tray) _shapeOf(p)], [for (final p in engine.tray) _shapeOf(p)]);
    });

    test('nothing to resume after a fresh install', () async {
      expect(await GameEngine().resume(GameMode.classic), isFalse);
    });

    test('game over deletes the save', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.classic);
      engine.tray[0] = _singleCell();
      await engine.placePiece(0, 0, 0);
      await pumpEventQueue();
      expect(await GameSaveService.instance.load(GameMode.classic), isNotNull);

      _fillForGameOver(engine);
      await engine.placePiece(0, 6, 6);
      await pumpEventQueue();
      expect(engine.gameOver, isTrue);
      expect(await GameSaveService.instance.load(GameMode.classic), isNull);
    });

    test('a daily save from an earlier day is discarded', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.daily);
      final save = engine.toSave()..['daily'] = previousDayKey(todayKey());
      await GameSaveService.instance.save(GameMode.daily, save);

      expect(await GameEngine().resume(GameMode.daily), isFalse);
      expect(await GameSaveService.instance.load(GameMode.daily), isNull);
    });
  });

  group('daily challenge', () {
    test('two games on the same day get the same pieces', () async {
      final a = GameEngine();
      final b = GameEngine();
      await a.start(mode: GameMode.daily);
      await b.start(mode: GameMode.daily);
      expect([for (final p in a.tray) _shapeOf(p)], [for (final p in b.tray) _shapeOf(p)]);
      a.shuffleTray();
      b.shuffleTray();
      expect([for (final p in a.tray) _shapeOf(p)], [for (final p in b.tray) _shapeOf(p)]);
    });

    test('a resumed daily game continues the same piece sequence', () async {
      final a = GameEngine();
      await a.start(mode: GameMode.daily);
      final resumed = GameEngine()..restoreSave(a.toSave(), storedBest: 0);
      a.shuffleTray();
      resumed.shuffleTray();
      expect([for (final p in resumed.tray) _shapeOf(p)], [for (final p in a.tray) _shapeOf(p)]);
    });

    test('streak grows on consecutive days and today\'s best is a max', () async {
      final today = todayKey();
      await DailyService.instance.record(previousDayKey(today), 300);
      await DailyService.instance.record(today, 120);
      await DailyService.instance.record(today, 90);

      final status = await DailyService.instance.status();
      expect(status.streak, 2);
      expect(status.todayBest, 120);
      expect(status.playedToday, isTrue);
    });

    test('a missed day resets the streak', () async {
      final today = todayKey();
      await DailyService.instance.record(previousDayKey(previousDayKey(previousDayKey(today))), 50);
      await DailyService.instance.record(today, 70);
      expect((await DailyService.instance.status()).streak, 1);
    });

    test('previousDayKey crosses month and leap-year boundaries', () {
      expect(previousDayKey('20260301'), '20260228');
      expect(previousDayKey('20240301'), '20240229');
      expect(previousDayKey('20270101'), '20261231');
    });
  });

  group('new best and x2 score', () {
    test('passing the starting best fires the celebration exactly once', () async {
      SharedPreferences.setMockInitialValues({'best_score_classic': 3});
      final engine = GameEngine();
      await engine.start(mode: GameMode.classic);
      for (var i = 0; i < 6; i++) {
        engine.tray[0] = _singleCell();
        await engine.placePiece(0, 0, i);
      }
      expect(engine.score, greaterThan(3));
      expect(engine.newBestSeq, 1);
    });

    test('no celebration on the very first game (no best to beat)', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.classic);
      engine.tray[0] = _singleCell();
      await engine.placePiece(0, 0, 0);
      expect(engine.newBestSeq, 0);
    });

    test('x2 doubles the final score once and gives up the continue', () async {
      final engine = GameEngine();
      engine.score = 100;
      _fillForGameOver(engine);
      await engine.placePiece(0, 6, 6);
      expect(engine.gameOver, isTrue);
      expect(engine.canDoubleScore, isTrue);
      final before = engine.score;

      engine.doubleScore();
      engine.doubleScore();

      expect(engine.score, before * 2);
      expect(engine.best, before * 2);
      expect(engine.canDoubleScore, isFalse);
      expect(engine.canContinueAfterGameOver, isFalse);
    });
  });

  group('daily gift inventory', () {
    test('one free gift a day, one ad bonus after it, then nothing', () async {
      final inv = PowerUpInventory.instance;
      await inv.load();
      expect(inv.canClaimGift, isTrue);
      expect(inv.canClaimAdBonus, isFalse);

      final gift = await inv.claimGift();
      expect(gift, isNotNull);
      expect(inv.count(gift!), 1);
      expect(await inv.claimGift(), isNull);

      expect(inv.canClaimAdBonus, isTrue);
      await inv.claimAdBonus();
      expect(inv.canClaimAdBonus, isFalse);
      final total = PowerUp.values.fold<int>(0, (sum, p) => sum + inv.count(p));
      expect(total, 2);

      expect(inv.consume(gift), isTrue);
      await inv.load();
      expect(PowerUp.values.fold<int>(0, (sum, p) => sum + inv.count(p)), 1, reason: 'persisted');
    });
  });
}
