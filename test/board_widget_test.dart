import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/models/piece.dart';
import 'package:block_puzzle/widgets/board_widget.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a line clear shows a floating +points popup', (tester) async {
    final engine = GameEngine();
    for (var c = 0; c < GameEngine.boardSize - 1; c++) {
      engine.board[0][c] = kPieceColors.first;
    }
    final singleCellShape = kAllShapes.firstWhere((s) => s.cells.length == 1);
    engine.tray[0] = PieceInstance(
      cells: singleCellShape.cells,
      width: singleCellShape.width,
      height: singleCellShape.height,
      color: kPieceColors.first,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 360,
            child: AnimatedBuilder(
              animation: engine,
              builder: (context, _) => BoardWidget(engine: engine),
            ),
          ),
        ),
      ),
    );

    // Deliberately not awaited: placePiece suspends on an internal
    // Future.delayed (the clear-flash pause), which only resolves once the
    // test's fake clock is advanced via pump(duration) below — awaiting it
    // directly here would deadlock.
    unawaited(engine.placePiece(0, 0, GameEngine.boardSize - 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // past the clear-flash delay
    await tester.pump(); // render the frame with the popup now present

    expect(find.textContaining('+'), findsOneWidget);

    // The popup animation runs for 900ms and removes itself when done.
    await tester.pump(const Duration(milliseconds: 950));
    expect(find.textContaining('+'), findsNothing);
  });
}
