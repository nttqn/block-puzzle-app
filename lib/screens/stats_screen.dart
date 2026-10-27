import 'package:flutter/material.dart';

import '../models/piece.dart';
import '../services/adventure_service.dart';
import '../services/score_service.dart';
import '../game/game_mode.dart';
import '../services/skin_service.dart';
import '../services/sound_service.dart';
import '../services/stats_service.dart';
import '../widgets/app_background.dart';
import '../widgets/piece_view.dart';

/// Lifetime stats plus the block-skin picker (skins unlock from stats).
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final Map<GameMode, int> _best = {};

  @override
  void initState() {
    super.initState();
    for (final mode in [GameMode.classic, GameMode.survival]) {
      ScoreService.instance.loadBest(mode).then((v) {
        if (mounted) setState(() => _best[mode] = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = StatsService.instance;
    final tiles = [
      ('Games played', stats.gamesPlayed, Icons.sports_esports),
      ('Lines cleared', stats.linesCleared, Icons.view_stream_rounded),
      ('Blocks placed', stats.blocksPlaced, Icons.grid_view_rounded),
      ('Average score', stats.averageScore, Icons.show_chart),
      ('Best clear streak', stats.bestStreak, Icons.local_fire_department),
      ('Most lines at once', stats.biggestClear, Icons.bolt),
      ('Best Classic', _best[GameMode.classic] ?? 0, Icons.play_arrow),
      ('Best Survival', _best[GameMode.survival] ?? 0, Icons.timer),
      ('Adventure stars', AdventureService.instance.totalStars, Icons.star_rounded),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF10161F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Stats & Skins')),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 8, 16, 24),
                children: [
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [for (final (label, value, icon) in tiles) _StatTile(label: label, value: value, icon: icon)],
                  ),
                  const SizedBox(height: 24),
                  const Text('Block skins', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<BlockSkin>(
                    valueListenable: SkinService.instance.skin,
                    builder: (context, selected, _) => GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.35,
                      children: [
                        for (final skin in BlockSkin.values)
                          _SkinCard(
                            skin: skin,
                            selected: skin == selected,
                            onTap: () {
                              SoundService.instance.play(SoundEffect.confirm);
                              SkinService.instance.select(skin);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _StatTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFF1B2430).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.amberAccent, size: 22),
          const SizedBox(height: 4),
          FittedBox(
            child: Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SkinCard extends StatelessWidget {
  final BlockSkin skin;
  final bool selected;
  final VoidCallback onTap;

  const _SkinCard({required this.skin, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unlocked = skin.isUnlocked;
    return Material(
      color: const Color(0xFF1B2430).withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: unlocked ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? Colors.amberAccent : Colors.transparent, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: unlocked ? 1 : 0.35,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in [kPieceColors[0], kPieceColors[2], kPieceColors[3], kPieceColors[5]])
                      SizedBox(width: 26, height: 26, child: BlockCell(color: c, inset: 1.5, skin: skin)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!unlocked) const Icon(Icons.lock, size: 14, color: Colors.white54),
                  if (selected) const Icon(Icons.check_circle, size: 16, color: Colors.amberAccent),
                  const SizedBox(width: 4),
                  Text(skin.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              if (!unlocked)
                Text(skin.unlockHint, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
