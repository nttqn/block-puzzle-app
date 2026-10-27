import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/game/game_mode.dart';
import 'package:block_puzzle/models/adventure.dart';
import 'package:block_puzzle/models/piece.dart';
import 'package:block_puzzle/services/adventure_service.dart';
import 'package:block_puzzle/services/skin_service.dart';
import 'package:block_puzzle/services/stats_service.dart';

PieceInstance _line(int length) {
  final shape = kAllShapes.firstWhere((s) => s.height == 1 && s.width == length && s.cells.length == length);
  return PieceInstance(cells: shape.cells, width: shape.width, height: shape.height, color: kPieceColors.first);
}

/// A bare engine (no persistence) playing a hand-made level.
GameEngine _engineOn(AdventureLevel level) {
  final e = GameEngine()
    ..mode = GameMode.adventure
    ..level = level
    ..movesLeft = level.moves
    ..gemsLeft = level.gems.length;
  for (final (r, c) in level.gems) {
    e.board[r][c] = kGemColor;
  }
  e.tray[0] = _line(3);
  e.tray[1] = _line(1);
  e.tray[2] = _line(1);
  return e;
}

/// Row 0 filled except columns 0-2, so a 3-long line at (0, 0) clears it.
void _almostFullRow(GameEngine e) {
  for (var c = 3; c < GameEngine.boardSize; c++) {
    e.board[0][c] ??= kPieceColors[2];
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('level generation', () {
    test('is deterministic, rotates goals and never pre-fills a line', () {
      for (var n = 1; n <= kAdventureLevels; n++) {
        final a = adventureLevel(n);
        final b = adventureLevel(n);
        expect(a.goal, LevelGoal.values[(n - 1) % 3]);
        expect(a.gems, b.gems);
        expect(a.clutter, b.clutter);
        final cells = {...a.gems, for (final (r, c, _) in a.clutter) (r, c)};
        expect(cells.length, a.gems.length + a.clutter.length, reason: 'level $n overlaps');
        for (var i = 0; i < 12; i++) {
          expect(cells.where((p) => p.$1 == i).length, lessThanOrEqualTo(9));
          expect(cells.where((p) => p.$2 == i).length, lessThanOrEqualTo(9));
        }
        if (a.goal == LevelGoal.gems) expect(a.target, a.gems.length);
      }
    });

    test('later levels ask for more', () {
      expect(adventureLevel(58).target, greaterThan(adventureLevel(1).target));
      expect(adventureLevel(59).target, greaterThan(adventureLevel(2).target));
      expect(adventureLevel(60).gems.length, greaterThan(adventureLevel(3).gems.length));
    });

    test('starting a level lays out its gems and clutter and sets the moves', () async {
      final engine = GameEngine();
      await engine.start(mode: GameMode.adventure, levelNumber: 6);
      final level = adventureLevel(6);
      expect(engine.movesLeft, level.moves);
      expect(engine.gemsLeft, level.gems.length);
      for (final (r, c) in level.gems) {
        expect(engine.board[r][c], kGemColor);
      }
      expect(engine.best, 0);
    });
  });

  group('playing a level', () {
    test('reaching the goal wins with stars from the moves left', () async {
      const level = AdventureLevel(number: 1, goal: LevelGoal.lines, target: 1, moves: 10, gems: [], clutter: []);
      final e = _engineOn(level);
      _almostFullRow(e);

      await e.placePiece(0, 0, 0);

      expect(e.won, isTrue);
      expect(e.gameOver, isTrue);
      expect(e.movesLeft, 9);
      expect(e.stars, 3);
      expect(e.canContinueAfterGameOver, isFalse);
      expect(e.canDoubleScore, isFalse);
      await pumpEventQueue();
      expect(AdventureService.instance.starsFor(1), 3);
    });

    test('running out of moves loses, and continue gives the move back plus 5', () async {
      const level = AdventureLevel(number: 2, goal: LevelGoal.score, target: 500, moves: 1, gems: [], clutter: []);
      final e = _engineOn(level);

      await e.placePiece(1, 5, 5);

      expect(e.gameOver, isTrue);
      expect(e.won, isFalse);
      expect(e.canContinueAfterGameOver, isTrue);
      e.continueAfterGameOver();
      expect(e.gameOver, isFalse);
      expect(e.movesLeft, 6);
    });

    test('clearing a gem\'s line collects it; collecting all of them wins', () async {
      const level = AdventureLevel(number: 3, goal: LevelGoal.gems, target: 2, moves: 10, gems: [(0, 5), (7, 7)], clutter: []);
      final e = _engineOn(level);
      _almostFullRow(e);

      await e.placePiece(0, 0, 0);
      expect(e.gemsLeft, 1);
      expect(e.goalProgress, 1);
      expect(e.won, isFalse);

      e.hammerDestroy(7, 7);
      expect(e.gemsLeft, 0);
      expect(e.won, isTrue);
      expect(e.gameOver, isTrue);
    });

    test('fewer moves left means fewer stars', () {
      const level = AdventureLevel(number: 4, goal: LevelGoal.score, target: 1, moves: 20, gems: [], clutter: []);
      expect(level.starsFor(6), 3);
      expect(level.starsFor(3), 2);
      expect(level.starsFor(1), 1);
    });
  });

  group('progress, stats and skins', () {
    test('levels unlock one at a time and stars keep the best result', () async {
      final adv = AdventureService.instance;
      await adv.load();
      expect(adv.unlocked, 1);
      await adv.record(1, 2);
      await adv.record(1, 1);
      expect(adv.starsFor(1), 2);
      expect(adv.unlocked, 2);
      await adv.record(2, 3);
      expect(adv.totalStars, 5);
      await adv.load();
      expect(adv.totalStars, 5, reason: 'persisted');
    });

    test('a real game counts blocks, lines and games; a bare engine does not', () async {
      final stats = StatsService.instance;
      await stats.load();
      final bare = _engineOn(
        const AdventureLevel(number: 5, goal: LevelGoal.score, target: 999, moves: 9, gems: [], clutter: []),
      );
      await bare.placePiece(1, 3, 3);
      expect(stats.blocksPlaced, 0);

      final engine = GameEngine();
      await engine.start(mode: GameMode.classic);
      engine.tray[0] = _line(3);
      _almostFullRow(engine);
      await engine.placePiece(0, 0, 0);
      expect(stats.blocksPlaced, 3);
      expect(stats.linesCleared, 1);
      expect(stats.biggestClear, 1);
      expect(stats.bestStreak, 1);
    });

    test('skins unlock from stats and adventure stars', () async {
      await StatsService.instance.load();
      await AdventureService.instance.load();
      expect(BlockSkin.candy.isUnlocked, isTrue);
      expect(BlockSkin.flat.isUnlocked, isFalse);
      expect(BlockSkin.crystal.isUnlocked, isFalse);

      await SkinService.instance.select(BlockSkin.neon);
      expect(SkinService.instance.skin.value, BlockSkin.candy, reason: 'locked skins cannot be picked');

      for (var i = 1; i <= 10; i++) {
        await AdventureService.instance.record(i, 3);
      }
      expect(BlockSkin.crystal.isUnlocked, isTrue);
      await SkinService.instance.select(BlockSkin.crystal);
      expect(SkinService.instance.skin.value, BlockSkin.crystal);
    });
  });
}
