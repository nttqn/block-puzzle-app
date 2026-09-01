import 'package:flutter/material.dart';

import '../game/game_mode.dart';
import '../services/score_service.dart';
import '../services/sound_service.dart';
import '../widgets/app_background.dart';
import '../widgets/piece_view.dart';
import '../widgets/sound_toggle_button.dart';
import '../models/piece.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<GameMode, int> _bestByMode = {
    GameMode.classic: 0,
    GameMode.survival: 0,
  };

  @override
  void initState() {
    super.initState();
    _loadBests();
  }

  Future<void> _loadBests() async {
    for (final mode in GameMode.values) {
      final best = await ScoreService.instance.loadBest(mode);
      if (mounted) setState(() => _bestByMode[mode] = best);
    }
  }

  Future<void> _play(GameMode mode) async {
    SoundService.instance.play(SoundEffect.confirm);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GameScreen(mode: mode)));
    _loadBests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10161F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [SoundToggleButton()],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LogoPiece(),
                const SizedBox(height: 16),
                const Text(
                  'BLOCK PUZZLE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 40),
                for (final mode in GameMode.values) ...[
                  _ModeButton(
                    mode: mode,
                    best: _bestByMode[mode] ?? 0,
                    onTap: () => _play(mode),
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _showHowToPlay(context),
                  child: const Text('How to play'),
                ),
              ],
            ),
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
          'Drag blocks from the tray onto the grid.\n\n'
          'Fill an entire row or column to clear it and score points.\n\n'
          'Clear multiple lines at once, or clear lines back-to-back, for bonus combo points.\n\n'
          'Classic: the game ends when none of your 3 blocks fit on the board.\n\n'
          'Survival: a bomb tile is always ticking down somewhere on the board — clear its row or column before time runs out, or it\'s game over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final GameMode mode;
  final int best;
  final VoidCallback onTap;

  const _ModeButton({
    required this.mode,
    required this.best,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.centerLeft,
        ),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(
              mode == GameMode.survival
                  ? Icons.local_fire_department
                  : Icons.play_arrow,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mode.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Best: $best',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoPiece extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shape = kAllShapes.firstWhere(
      (s) => s.width == 3 && s.height == 3 && s.cells.length == 5,
    );
    final piece = PieceInstance(
      cells: shape.cells,
      width: shape.width,
      height: shape.height,
      color: const Color(0xFF1E88E5),
    );
    return PieceView(piece: piece, cellSize: 28);
  }
}
