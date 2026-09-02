import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:block_puzzle/screens/home_screen.dart';

void main() {
  testWidgets('home screen shows a button per game mode', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('CLASSIC'), findsOneWidget);
    expect(find.text('SURVIVAL'), findsOneWidget);
    expect(find.textContaining('Best:'), findsNWidgets(2));
  });

  testWidgets('tapping a leaderboard button with no leaderboard configured shows a fallback message', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Real leaderboard IDs are configured, but there's no native Play
    // Games handler under `flutter_test` — GameAuth.signIn() hangs on an
    // unresolved platform channel rather than throwing (see
    // leaderboard_service.dart's class doc), so LeaderboardService wraps it
    // in a 5s `.timeout()`. Pump past that (a plain `pumpAndSettle()` won't
    // trigger it — the underlying Future is genuinely pending, not just
    // between animation frames) to reach the fallback message.
    await tester.tap(find.byIcon(Icons.leaderboard).first);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('Leaderboard not available yet.'), findsOneWidget);
  });
}
