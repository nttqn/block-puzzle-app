import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../game/game_mode.dart';
import '../models/adventure.dart';
import '../models/piece.dart';

/// Preset game states for store screenshots (`tool/store_shots.js`), picked
/// with `?shot=<name>`. Web-only: always null on Android/iOS builds.
String? get screenshotScenario => kIsWeb ? Uri.base.queryParameters['shot'] : null;

GameMode scenarioMode(String name) => _scenarios[name]?.mode ?? GameMode.classic;

int scenarioLevel(String name) => _scenarios[name]?.level?.number ?? 1;

void applyScenario(String name, GameEngine e) {
  final s = _scenarios[name];
  if (s == null) return;
  e.board = s.board();
  e.tray = [for (final (grid, color) in s.tray) _piece(grid, color)];
  e.score = s.score;
  e.combo = 0;
  if (e.score > e.best) e.best = e.score;
  e.bomb = null;
  final level = s.level;
  if (level != null) {
    e.level = level;
    e.movesLeft = s.movesLeft;
    e.linesThisGame = s.linesDone;
    e.gemsLeft = [for (final row in e.board) ...row].where((c) => c == kGemColor).length;
  }
  final bomb = s.bomb;
  if (bomb != null) {
    e.board[bomb.$1][bomb.$2] = kBombColor;
    e.bomb = BombTile(row: bomb.$1, col: bomb.$2, secondsLeft: bomb.$3);
  }
}

const _colorIndex = {'r': 0, 'o': 1, 'y': 2, 'g': 3, 'c': 4, 'b': 5, 'p': 6, 'k': 7};

List<List<Color?>> _grid(List<String> rows) => [
      for (final row in rows)
        [
          for (final ch in row.split(''))
            ch == 'd' ? kGemColor : (_colorIndex.containsKey(ch) ? kPieceColors[_colorIndex[ch]!] : null),
        ],
    ];

PieceInstance _piece(List<String> grid, String letter) {
  final cells = <Cell>[];
  for (var r = 0; r < grid.length; r++) {
    for (var c = 0; c < grid[r].length; c++) {
      if (grid[r][c] == '#') cells.add(Cell(r, c));
    }
  }
  return PieceInstance(
    cells: cells,
    height: grid.length,
    width: grid.map((r) => r.length).reduce((a, b) => a > b ? a : b),
    color: kPieceColors[_colorIndex[letter]!],
  );
}

class _Scenario {
  final GameMode mode;
  final int score;
  final List<List<Color?>> Function() board;
  final List<(List<String>, String)> tray;
  final (int, int, int)? bomb;
  final AdventureLevel? level;
  final int movesLeft;
  final int linesDone;
  const _Scenario({
    required this.mode,
    required this.score,
    required this.board,
    required this.tray,
    this.bomb,
    this.level,
    this.movesLeft = 0,
    this.linesDone = 0,
  });
}

// Full board in color blocks, with no two holes adjacent in a row: a single
// cell fits, then nothing in the rest of the tray does -> game over.
List<List<Color?>> _nearFullBoard() {
  final b = List.generate(12, (r) => List<Color?>.generate(12, (c) => kPieceColors[((r ~/ 2) * 3 + c ~/ 3) % 8]));
  for (var i = 0; i < 12; i++) {
    b[i][i] = null;
  }
  b[6][2] = null;
  b[3][6] = null;
  return b;
}

final Map<String, _Scenario> _scenarios = {
  // Adventure gem level mid-way: 'd' cells are gems.
  'adventure': _Scenario(
    mode: GameMode.adventure,
    score: 320,
    level: const AdventureLevel(number: 9, goal: LevelGoal.gems, target: 5, moves: 22, gems: [], clutter: []),
    movesLeft: 14,
    board: () => _grid([
      '............',
      '..d.........',
      '.......kk...',
      '....d...k...',
      '.oo.........',
      '.o.....yy...',
      '.......yy..d',
      '..bbb.......',
      'gg..b..cc...',
      'g...r...c.pp',
      'rr.rrr..c..p',
      'r..ccc.oo.pp',
    ]),
    tray: [(['##', '##'], 'g'), (['###'], 'p'), (['#.', '##'], 'c')],
  ),
  // One line short of the goal; the store script's drag completes row 11.
  'advwin': _Scenario(
    mode: GameMode.adventure,
    score: 410,
    level: const AdventureLevel(number: 7, goal: LevelGoal.lines, target: 6, moves: 24, gems: [], clutter: []),
    movesLeft: 12,
    linesDone: 5,
    board: () => _grid([
      '............',
      '............',
      '............',
      '....pp......',
      '....pp...g..',
      '.cc.....gg..',
      '.c......g...',
      '.c...rrr....',
      'oo....r..bb.',
      'o..yy....bb.',
      'o..yy.kkk...',
      '...ggbbccrrp',
    ]),
    tray: [(['###'], 'y'), (['#', '#'], 'b'), (['##', '#.'], 'o')],
  ),
  'classic': _Scenario(
    mode: GameMode.classic,
    score: 1240,
    board: () => _grid([
      '............',
      '............',
      '............',
      '.......yy...',
      '.......yy...',
      '..cc.......p',
      '..c....oo..p',
      'gggc...o..pp',
      'g..bbb.o.rrr',
      '..kkb..ccc.r',
      'yykk..gg.c.r',
      'yy.bbbgg.c..',
    ]),
    tray: [(['#.', '#.', '##'], 'o'), (['###'], 'k'), (['##', '##'], 'b')],
  ),
  'combo': _Scenario(
    mode: GameMode.classic,
    score: 980,
    board: () => _grid([
      '............',
      '............',
      '............',
      '............',
      '.........pp.',
      '.....yy..pp.',
      '.cc..yy.....',
      '.c...o...gg.',
      '.c..oo.k.g..',
      'rr..o.kkkg..',
      'rrbb.gggccyy',
      'ookk.bbppcgg',
    ]),
    tray: [(['###'], 'y'), (['#', '#'], 'c'), (['.#', '##'], 'g')],
  ),
  'combo3': _Scenario(
    mode: GameMode.classic,
    score: 2210,
    board: () => _grid([
      '............',
      '............',
      '...pp.......',
      '...pp.......',
      '..........r.',
      '.kk......rr.',
      '.k...yyy..r.',
      '.k....y.....',
      'oo.....bbb..',
      'ggccbbr.yyoo',
      'ggcckkr.yypp',
      'rroobbp.kkpp',
    ]),
    tray: [(['#', '#', '#'], 'b'), (['##', '##'], 'y'), (['#.', '##'], 'k')],
  ),
  'hammer': _Scenario(
    mode: GameMode.classic,
    score: 1675,
    board: () => _grid([
      '............',
      '............',
      '....bb......',
      '....bb......',
      '............',
      '..r.........',
      '..rr....ggg.',
      '...r....g...',
      'kkk..oo.....',
      'k..yyoo..ppp',
      'cc.yy.c.pp.p',
      'ccbbbbccc.kk',
    ]),
    tray: [(['###', '###', '###'], 'g'), (['#####'], 'r'), (['##', '.#', '.#'], 'p')],
  ),
  'survival': _Scenario(
    mode: GameMode.survival,
    score: 640,
    board: () => _grid([
      '............',
      '............',
      '..........cc',
      '..ggg.....c.',
      '..g.........',
      '........ooo.',
      '.bb.....o...',
      '.bb..yy.....',
      '......yy..kk',
      'pp.r.....kk.',
      'p..rr..bbb..',
      'pp..r.cc.b..',
    ]),
    tray: [(['##.', '.##'], 'r'), (['#', '#', '#', '#'], 'y'), (['.#.', '###'], 'b')],
    bomb: (4, 8, 18),
  ),
  'urgent': _Scenario(
    mode: GameMode.survival,
    score: 1380,
    board: () => _grid([
      '............',
      '............',
      '............',
      '...yy.......',
      '...yy....cc.',
      '.........c..',
      '..kk.....c..',
      '..k....rr...',
      'ggbbooppy..c',
      'g..bb..pp..c',
      'rr..b.ooo..c',
      'rr.ccc.o..kk',
    ]),
    tray: [(['#'], 'g'), (['##', '##'], 'o'), (['###', '.#.'], 'p')],
    bomb: (8, 9, 7),
  ),
  'gameover': _Scenario(
    mode: GameMode.classic,
    score: 2980,
    board: _nearFullBoard,
    tray: [(['#'], 'y'), (['##'], 'c'), (['###', '###', '###'], 'k')],
  ),
  'dense': _Scenario(
    mode: GameMode.classic,
    score: 4350,
    board: () => _grid([
      '............',
      '..yy....kk..',
      '..yy....kk..',
      'pp...cc.....',
      'p...ccc..rr.',
      'pbb.....rr..',
      '.bb.ggg.....',
      'oo..g..yyy.c',
      'o..kk...y..c',
      'o.kk..bb...c',
      'rrr..bbppp.c',
      'r.ccgg..p.oo',
    ]),
    tray: [(['#', '#'], 'k'), (['###', '#..'], 'c'), (['.#', '##', '.#'], 'o')],
  ),
};
