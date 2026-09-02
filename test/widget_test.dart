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

    // The leaderboard IDs are still placeholders (see leaderboard_service.dart)
    // until Play Console is set up, so this must degrade to a message rather
    // than crash or silently do nothing.
    await tester.tap(find.byIcon(Icons.leaderboard).first);
    await tester.pumpAndSettle();

    expect(find.text('Leaderboard not available yet.'), findsOneWidget);
  });
}
