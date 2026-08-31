import 'dart:math';
import 'dart:ui';

/// A block cell offset relative to a piece's own top-left bounding box.
class Cell {
  final int row;
  final int col;
  const Cell(this.row, this.col);
}

/// One concrete piece: a fixed set of cells (already normalized so the
/// smallest row/col is 0) plus a display color. Instances are generated
/// fresh for the tray, not shared/mutated.
class PieceInstance {
  final List<Cell> cells;
  final int height;
  final int width;
  final Color color;

  PieceInstance({required this.cells, required this.height, required this.width, required this.color});
}

const List<Color> kPieceColors = [
  Color(0xFFE53935), // red
  Color(0xFFFB8C00), // orange
  Color(0xFFFDD835), // yellow
  Color(0xFF43A047), // green
  Color(0xFF00ACC1), // teal
  Color(0xFF1E88E5), // blue
  Color(0xFF5E35B1), // indigo
  Color(0xFFD81B60), // pink
];

/// Every distinct shape a piece can spawn as, expressed as a grid of rows
/// (each row a string; '#' = filled cell). Parsed once at startup into
/// normalized [Cell] lists.
const List<List<String>> _shapeGrids = [
  // Singles / lines
  ['#'],
  ['##'],
  ['#', '#'],
  ['###'],
  ['#', '#', '#'],
  ['####'],
  ['#', '#', '#', '#'],
  ['#####'],
  ['#', '#', '#', '#', '#'],

  // Squares
  ['##', '##'],
  ['###', '###', '###'],

  // L-tromino (2x2 minus a corner), 4 rotations
  ['##', '#.'],
  ['##', '.#'],
  ['.#', '##'],
  ['#.', '##'],

  // L-tetromino, 4 rotations
  ['#.', '#.', '##'],
  ['###', '#..'],
  ['##', '.#', '.#'],
  ['..#', '###'],

  // J-tetromino, 4 rotations
  ['.#', '.#', '##'],
  ['#..', '###'],
  ['##', '#.', '#.'],
  ['###', '..#'],

  // T-tetromino, 4 rotations
  ['###', '.#.'],
  ['.#', '##', '.#'],
  ['.#.', '###'],
  ['#.', '##', '#.'],

  // S-tetromino, 2 rotations
  ['.##', '##.'],
  ['#.', '##', '.#'],

  // Z-tetromino, 2 rotations
  ['##.', '.##'],
  ['.#', '##', '#.'],

  // Plus pentomino
  ['.#.', '###', '.#.'],

  // Big-L pentomino, 4 rotations
  ['#...', '####'],
  ['####', '#...'],
  ['##', '.#', '.#', '.#'],
  ['#.', '#.', '#.', '##'],

  // P-pentomino, 4 rotations
  ['##', '##', '#.'],
  ['##', '##', '.#'],
  ['.#', '##', '##'],
  ['#.', '##', '##'],
];

class BlockShape {
  final List<Cell> cells;
  final int height;
  final int width;
  const BlockShape({required this.cells, required this.height, required this.width});
}

final List<BlockShape> kAllShapes = _shapeGrids.map(_parseShape).toList(growable: false);

BlockShape _parseShape(List<String> grid) {
  final cells = <Cell>[];
  for (var r = 0; r < grid.length; r++) {
    final row = grid[r];
    for (var c = 0; c < row.length; c++) {
      if (row[c] == '#') cells.add(Cell(r, c));
    }
  }
  return BlockShape(cells: cells, height: grid.length, width: grid.map((r) => r.length).reduce(max));
}

final Random _rng = Random();

PieceInstance randomPiece() {
  final shape = kAllShapes[_rng.nextInt(kAllShapes.length)];
  final color = kPieceColors[_rng.nextInt(kPieceColors.length)];
  return PieceInstance(cells: shape.cells, height: shape.height, width: shape.width, color: color);
}
