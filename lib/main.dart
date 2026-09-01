import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/ads_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdsService.instance.initialize();
  // Fired unawaited, not awaited before runApp(): a missing/broken audio
  // asset can leave AudioPool.create()'s Future never resolving on web,
  // which would otherwise hang the whole app before its first frame.
  unawaited(SoundService.instance.init());
  runApp(const BlockPuzzleApp());
}

class BlockPuzzleApp extends StatelessWidget {
  const BlockPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Puzzle Plus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E88E5),
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10161F),
      ),
      home: const HomeScreen(),
    );
  }
}
