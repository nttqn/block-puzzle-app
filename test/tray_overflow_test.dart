import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/game/game_engine.dart';
import 'package:block_puzzle/widgets/tray_widget.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the tray never overflows its row, even when slots are wider than the available width', (
    tester,
  ) async {
    final engine = GameEngine();

    // traySlotCellSize is normally derived from the board's own layout, but
    // nothing guarantees it always leaves exactly enough room for 3 tray
    // slots at every window size — a real run hit a "RenderFlex overflowed
    // by 44 pixels" crash in this widget's Row at a 334px-wide window.
    // Pick a traySlotCellSize whose 3 natural slot widths (5 cells each)
    // clearly exceed a deliberately narrow row to reproduce that regime.
    const narrowRowWidth = 200.0;
    const traySlotCellSize = 25.0; // slotSize = 125, so 3 slots = 375 > 200.
    const boardCellSize = 30.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: narrowRowWidth,
              child: AnimatedBuilder(
                animation: engine,
                builder: (context, _) =>
                    TrayWidget(engine: engine, traySlotCellSize: traySlotCellSize, boardCellSize: boardCellSize),
              ),
            ),
          ),
        ),
      ),
    );

    // No RenderFlex overflow (or any other) exception should have been
    // thrown during layout/paint.
    expect(tester.takeException(), isNull);
  });
}
