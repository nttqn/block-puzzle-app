import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/models/piece.dart';
import 'package:block_puzzle/widgets/board_widget.dart';
import 'package:block_puzzle/widgets/tray_widget.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dragging a 5-piece onto a genuinely empty 5-cell run in the last row shows a valid preview', (
    tester,
  ) async {
    final engine = GameEngine();
    // Fill the whole board solid, then punch a clean run of 5 empty cells
    // in the very last row (mirrors the user's screenshot: a near-full
    // board with a horizontal gap along the bottom edge).
    for (var r = 0; r < GameEngine.boardSize; r++) {
      for (var c = 0; c < GameEngine.boardSize; c++) {
        engine.board[r][c] = kPieceColors.first;
      }
    }
    const lastRow = GameEngine.boardSize - 1;
    const gapStart = 5;
    for (var c = gapStart; c < gapStart + 5; c++) {
      engine.board[lastRow][c] = null;
    }

    final fiveLineShape = kAllShapes.firstWhere((s) => s.height == 1 && s.width == 5 && s.cells.length == 5);
    final piece = PieceInstance(
      cells: fiveLineShape.cells,
      width: fiveLineShape.width,
      height: fiveLineShape.height,
      color: kPieceColors[1],
    );
    engine.tray[0] = piece;
    engine.tray[1] = null;
    engine.tray[2] = null;

    const boardSize = 360.0;
    const cellSize = boardSize / GameEngine.boardSize;
    const traySlotCellSize = cellSize * 0.55;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: boardSize,
                height: boardSize,
                child: AnimatedBuilder(animation: engine, builder: (context, _) => BoardWidget(engine: engine)),
              ),
              TrayWidget(engine: engine, traySlotCellSize: traySlotCellSize, boardCellSize: cellSize),
            ],
          ),
        ),
      ),
    );

    // Grab the piece at its ordinary center — with pointerDragAnchorStrategy
    // this should no longer matter for where the piece actually lands.
    final trayFinder = find.byType(Draggable<TrayDragData>).first;
    final trayCenter = tester.getCenter(trayFinder);
    final gesture = await tester.startGesture(trayCenter);
    await tester.pump(const Duration(milliseconds: 50));

    final boardFinder = find.byType(BoardWidget);
    final boardTopLeft = tester.getTopLeft(boardFinder);
    // Aim for the exact top-left corner of the intended origin cell (the
    // tightest possible margin) since the anchor is now pointer-fixed —
    // this should land exactly on (lastRow, gapStart) regardless of grab
    // point.
    final targetLocal = Offset(gapStart * cellSize + 3, lastRow * cellSize + 3);
    await gesture.moveTo(boardTopLeft + targetLocal);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Diagnostic: report whatever preview state exists (green, red, or
    // none) rather than assuming which one to expect.
    final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    var greenCount = 0;
    var redCount = 0;
    for (final box in decoratedBoxes) {
      final decoration = box.decoration;
      if (decoration is! BoxDecoration) continue;
      final color = decoration.color;
      if (color == null || color.a == 0) continue;
      if (color.g > color.r && color.g > color.b) greenCount++;
      if (color.r > color.g && color.b < color.r * 0.5) redCount++;
    }
    // ignore: avoid_print
    print('greenCount=$greenCount redCount=$redCount boardTopLeft=$boardTopLeft trayCenter=$trayCenter '
        'targetGlobal=${boardTopLeft + targetLocal}');

    expect(greenCount, 5, reason: 'the piece exactly fits the gap, so all 5 preview cells should be green');
    expect(redCount, 0);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 1000));

    // Filling the gap completes the last row entirely (it was the only
    // gap), so it immediately clears — check score increased instead of
    // checking the board cell directly, since that cell is null again by
    // now either way.
    expect(engine.score, greaterThan(0), reason: 'the piece should have actually been placed and scored');
  });
}
