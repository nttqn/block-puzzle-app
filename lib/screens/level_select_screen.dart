import 'package:flutter/material.dart';

import '../game/game_mode.dart';
import '../models/adventure.dart';
import '../services/adventure_service.dart';
import '../services/music_service.dart';
import '../services/sound_service.dart';
import '../widgets/app_background.dart';
import 'game_screen.dart';

/// Adventure level grid: stars earned per level, locked past the first
/// unbeaten one.
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  final _adventure = AdventureService.instance;

  @override
  void initState() {
    super.initState();
    _adventure.addListener(_onChanged);
  }

  @override
  void dispose() {
    _adventure.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open(int level) async {
    SoundService.instance.play(SoundEffect.confirm);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(mode: GameMode.adventure, level: level)),
    );
    MusicService.instance.playMenu();
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _adventure.unlocked;
    return Scaffold(
      backgroundColor: const Color(0xFF10161F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Adventure'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  '${_adventure.totalStars} / ${kAdventureLevels * 3}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 8, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: kAdventureLevels,
                itemBuilder: (context, i) {
                  final level = i + 1;
                  return _LevelTile(
                    level: level,
                    stars: _adventure.starsFor(level),
                    locked: level > unlocked,
                    current: level == unlocked,
                    onTap: () => _open(level),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  final int level;
  final int stars;
  final bool locked;
  final bool current;
  final VoidCallback onTap;

  const _LevelTile({
    required this.level,
    required this.stars,
    required this.locked,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final goal = LevelGoal.values[(level - 1) % 3];
    return Material(
      color: locked ? const Color(0xFF1B2230) : (current ? const Color(0xFF2B4A7A) : const Color(0xFF243246)),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: locked ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: current ? Border.all(color: Colors.amberAccent, width: 2) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (locked)
                const Icon(Icons.lock, color: Colors.white30, size: 22)
              else ...[
                Text('$level', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Icon(
                  switch (goal) {
                    LevelGoal.score => Icons.star_outline_rounded,
                    LevelGoal.lines => Icons.view_stream_rounded,
                    LevelGoal.gems => Icons.diamond_outlined,
                  },
                  size: 14,
                  color: Colors.white54,
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var s = 1; s <= 3; s++)
                    Icon(Icons.star_rounded, size: 13, color: s <= stars ? Colors.amber : Colors.white12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
