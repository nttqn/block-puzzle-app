import 'package:flutter/material.dart';

import '../services/score_service.dart';
import '../widgets/piece_view.dart';
import '../models/piece.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _best = 0;

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final best = await ScoreService.instance.loadBest();
    if (mounted) setState(() => _best = best);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10161F),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LogoPiece(),
              const SizedBox(height: 16),
              const Text(
                'BLOCK PUZZLE',
                style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              Text('Best score: $_best', style: const TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GameScreen()));
                  _loadBest();
                },
                child: const Text('PLAY'),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: () => _showHowToPlay(context), child: const Text('How to play')),
            ],
          ),
        ),
      ),
    );
  }

  void _showHowToPlay(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to play'),
        content: const Text(
          'Drag blocks from the tray onto the 8x8 grid.\n\n'
          'Fill an entire row or column to clear it and score points.\n\n'
          'Clear multiple lines at once, or clear lines back-to-back, for bonus combo points.\n\n'
          'The game ends when none of your 3 blocks fit on the board.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it'))],
      ),
    );
  }
}

class _LogoPiece extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shape = kAllShapes.firstWhere((s) => s.width == 3 && s.height == 3 && s.cells.length == 5);
    final piece = PieceInstance(cells: shape.cells, width: shape.width, height: shape.height, color: const Color(0xFF1E88E5));
    return PieceView(piece: piece, cellSize: 28);
  }
}
