import 'dart:math' show Random;

/// Number of Adventure levels. Levels are generated from their number (see
/// [adventureLevel]), so raising this just adds more, harder levels.
const int kAdventureLevels = 60;

enum LevelGoal { score, lines, gems }

/// One Adventure level: reach [target] (points, lines, or every gem cleared)
/// within [moves] placements. [gems] and [clutter] are pre-placed cells;
/// clutter is (row, col, kPieceColors index).
class AdventureLevel {
  final int number;
  final LevelGoal goal;
  final int target;
  final int moves;
  final List<(int, int)> gems;
  final List<(int, int, int)> clutter;

  const AdventureLevel({
    required this.number,
    required this.goal,
    required this.target,
    required this.moves,
    required this.gems,
    required this.clutter,
  });

  /// Seed for this level's piece sequence, so a level always deals the same
  /// opening tray.
  int get pieceSeed => number * 7919;

  /// 3 stars with at least 30% of the moves left, 2 with 15%, else 1.
  int starsFor(int movesLeft) {
    final f = movesLeft / moves;
    return f >= 0.3 ? 3 : (f >= 0.15 ? 2 : 1);
  }
}

/// Goals rotate score → lines → gems; every 3 levels is one difficulty tier
/// with bigger targets, a few more moves and more starting clutter.
AdventureLevel adventureLevel(int number, {int boardSize = 12}) {
  final tier = (number - 1) ~/ 3;
  final goal = LevelGoal.values[(number - 1) % 3];
  final rng = Random(number * 104729);

  final taken = <(int, int)>{};
  final rowCount = List<int>.filled(boardSize, 0);
  final colCount = List<int>.filled(boardSize, 0);
  // Never pre-fill a row/column past 9 cells, so the opening board has no
  // near-complete line handed out for free.
  (int, int)? freeCell() {
    for (var attempt = 0; attempt < 200; attempt++) {
      final r = rng.nextInt(boardSize);
      final c = rng.nextInt(boardSize);
      if (taken.contains((r, c)) || rowCount[r] >= 9 || colCount[c] >= 9) continue;
      taken.add((r, c));
      rowCount[r]++;
      colCount[c]++;
      return (r, c);
    }
    return null;
  }

  final gems = <(int, int)>[];
  if (goal == LevelGoal.gems) {
    final count = 3 + tier ~/ 3;
    for (var i = 0; i < count; i++) {
      final cell = freeCell();
      if (cell != null) gems.add(cell);
    }
  }
  final clutter = <(int, int, int)>[];
  for (var i = 0; i < (tier * 2).clamp(0, 36); i++) {
    final cell = freeCell();
    if (cell != null) clutter.add((cell.$1, cell.$2, rng.nextInt(8)));
  }

  final (target, moves) = switch (goal) {
    LevelGoal.score => (120 + tier * 30, 20 + tier),
    LevelGoal.lines => (4 + tier ~/ 2, 18 + tier),
    LevelGoal.gems => (gems.length, 20 + tier),
  };
  return AdventureLevel(number: number, goal: goal, target: target, moves: moves, gems: gems, clutter: clutter);
}
