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
}
