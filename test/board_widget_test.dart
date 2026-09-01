import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/models/piece.dart';
import 'package:block_puzzle/widgets/board_widget.dart';

PieceInstance _singleCell() {
  final shape = kAllShapes.firstWhere((s) => s.cells.length == 1);
  return PieceInstance(cells: shape.cells, width: shape.width, height: shape.height, color: kPieceColors.first);
}

Widget _harness(GameEngine engine) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 360,
        child: AnimatedBuilder(animation: engine, builder: (context, _) => BoardWidget(engine: engine)),
      ),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('every successful placement shows a floating +points popup, not just line clears', (tester) async {
    final engine = GameEngine();
    engine.tray[0] = _singleCell();
    engine.tray[1] = _singleCell();
    engine.tray[2] = _singleCell();

    await tester.pumpWidget(_harness(engine));

    // Deliberately not awaited: placePiece suspends on an internal
    // Future.delayed (the clear-flash pause), which only resolves once the
    // test's fake clock is advanced via pump(duration) below — awaiting it
    // directly here would deadlock.
    unawaited(engine.placePiece(0, 5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // A single-cell placement that clears nothing still earns its 1 base
    // point, so the popup must show for it too.
    expect(find.text('+1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('a line clear folds the base points and the bonus into one popup', (tester) async {
    final engine = GameEngine();
    for (var c = 0; c < GameEngine.boardSize - 1; c++) {
      engine.board[0][c] = kPieceColors.first;
    }
    engine.tray[0] = _singleCell();

    await tester.pumpWidget(_harness(engine));

    unawaited(engine.placePiece(0, 0, GameEngine.boardSize - 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // 1 base point for the placed cell + a 10-point single-line bonus.
    expect(find.text('+11'), findsOneWidget);
  });

  testWidgets('consecutive placements each get their own popup', (tester) async {
    final engine = GameEngine();
    engine.tray[0] = _singleCell();
    engine.tray[1] = _singleCell();
    engine.tray[2] = _singleCell();

    await tester.pumpWidget(_harness(engine));

    unawaited(engine.placePiece(0, 3, 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('+1'), findsOneWidget);

    // Placed right after, before the first popup's 900ms animation ends —
    // both should coexist rather than the second silently no-op'ing.
    unawaited(engine.placePiece(1, 8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('+1'), findsNWidgets(2));

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('a line clear bursts into particles that fly out and then disappear', (tester) async {
    final engine = GameEngine();
    for (var c = 0; c < GameEngine.boardSize - 1; c++) {
      engine.board[0][c] = kPieceColors.first;
    }
    engine.tray[0] = _singleCell();

    await tester.pumpWidget(_harness(engine));
    final particlesBefore = tester.widgetList(find.byType(Opacity)).length;

    unawaited(engine.placePiece(0, 0, GameEngine.boardSize - 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // GameEngine.boardSize cells cleared (the whole row), 6 particles each.
    final expectedParticles = GameEngine.boardSize * 6;
    final particlesDuring = tester.widgetList(find.byType(Opacity)).length - particlesBefore;
    expect(particlesDuring, greaterThanOrEqualTo(expectedParticles));

    // The particle animation (500ms) outlives the +N popup's own 900ms
    // timeline at different rates, so just confirm it's fully done by 600ms.
    await tester.pump(const Duration(milliseconds: 600));
    final particlesAfter = tester.widgetList(find.byType(Opacity)).length - particlesBefore;
    expect(particlesAfter, lessThan(expectedParticles));
  });
}
