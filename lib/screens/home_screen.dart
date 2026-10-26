import 'package:flutter/material.dart';

import '../debug/screenshot_scenarios.dart';
import '../game/game_mode.dart';
import '../services/ads_service.dart';
import '../services/daily_service.dart';
import '../services/game_save_service.dart';
import '../services/leaderboard_service.dart';
import '../services/music_service.dart';
import '../services/power_up_inventory.dart';
import '../services/score_service.dart';
import '../services/sound_service.dart';
import '../widgets/app_background.dart';
import '../widgets/music_toggle_button.dart';
import '../widgets/sound_toggle_button.dart';
import 'game_screen.dart';

const Map<PowerUp, IconData> _powerUpIcons = {
  PowerUp.undo: Icons.undo,
  PowerUp.hammer: Icons.gavel,
  PowerUp.shuffle: Icons.shuffle,
};

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

  /// Score of each mode's saved in-progress game, if there is one.
  final Map<GameMode, int> _savedScore = {};
  DailyStatus _daily = const DailyStatus(streak: 0, todayBest: 0, playedToday: false);

  @override
  void initState() {
    super.initState();
    _loadBests();
    PowerUpInventory.instance.addListener(_onInventoryChanged);
    MusicService.instance.playMenu();
    final shot = screenshotScenario;
    if (shot != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        shot == 'howto' ? _showHowToPlay(context) : _play(scenarioMode(shot));
      });
    }
  }

  @override
  void dispose() {
    PowerUpInventory.instance.removeListener(_onInventoryChanged);
    super.dispose();
  }

  void _onInventoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBests() async {
    for (final mode in _bestByMode.keys) {
      final best = await ScoreService.instance.loadBest(mode);
      if (mounted) setState(() => _bestByMode[mode] = best);
    }
    final daily = await DailyService.instance.status();
    final saved = <GameMode, int>{};
    for (final mode in GameMode.values) {
      final save = await GameSaveService.instance.load(mode);
      if (save == null) continue;
      // Yesterday's unfinished daily can't be resumed (see GameEngine.resume).
      if (mode == GameMode.daily && save['daily'] != todayKey()) continue;
      saved[mode] = save['score'] as int? ?? 0;
    }
    if (!mounted) return;
    setState(() {
      _daily = daily;
      _savedScore
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> _showLeaderboard(GameMode mode) async {
    final opened = await LeaderboardService.showLeaderboard(mode);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leaderboard not available yet.')));
    }
  }

  Future<void> _play(GameMode mode) async {
    var resume = false;
    final saved = _savedScore[mode];
    if (saved != null) {
      SoundService.instance.play(SoundEffect.confirm);
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${mode.label} game in progress'),
          content: Text('Pick up where you left off (score $saved), or start over?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('New game')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Resume')),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      resume = choice;
    }
    SoundService.instance.play(SoundEffect.confirm);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GameScreen(mode: mode, resume: resume)));
    // GameScreen switched the looping bgm to its own track on the way in
    // (Bgm.play() replaces whatever was already playing) — switch it back
    // now that we're home again.
    MusicService.instance.playMenu();
    _loadBests();
  }

  Future<void> _claimGift() async {
    SoundService.instance.play(SoundEffect.confirm);
    final p = await PowerUpInventory.instance.claimGift();
    if (p != null && mounted) _showGift(p);
  }

  Future<void> _claimAdBonus() async {
    final earned = await AdsService.instance.showRewarded();
    if (!mounted) return;
    if (!earned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not available right now. Try again later.')),
      );
      return;
    }
    final p = await PowerUpInventory.instance.claimAdBonus();
    if (p != null && mounted) _showGift(p);
  }

  void _showGift(PowerUp p) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily gift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_powerUpIcons[p], size: 56, color: Colors.amberAccent),
            const SizedBox(height: 8),
            Text('+1 ${p.label}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Saved for later. It kicks in once a game\'s free use is spent.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          if (PowerUpInventory.instance.canClaimAdBonus)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _claimAdBonus();
              },
              child: const Text('Watch video: +1 more'),
            ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Nice!')),
        ],
      ),
    );
  }

  String _subtitle(GameMode mode) {
    final saved = _savedScore[mode];
    if (saved != null) return 'Saved game · $saved';
    if (mode == GameMode.daily) {
      final streak = _daily.streak > 0 ? '🔥 ${_daily.streak} day${_daily.streak == 1 ? '' : 's'}' : 'New every day';
      return _daily.playedToday ? '$streak · Today: ${_daily.todayBest}' : streak;
    }
    return 'Best: ${_bestByMode[mode] ?? 0}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10161F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [MusicToggleButton(), SoundToggleButton()],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/title/title.png', width: 220),
                  const SizedBox(height: 32),
                  for (final mode in GameMode.values) ...[
                    // Fixed total width (matches the old solo _ModeButton's own
                    // width) with the leaderboard button carved out of it via
                    // Expanded, rather than adding its width on top — keeps
                    // this row exactly as narrow-screen-safe as it already was
                    // (see tray_widget.dart's RenderFlex overflow fix for why
                    // that margin matters: a fixed-width row content can
                    // overflow on some real device widths even when it looks
                    // fine at whatever width was last eyeballed).
                    SizedBox(
                      width: 260,
                      child: Row(
                        children: [
                          Expanded(
                            child: _ModeButton(
                              mode: mode,
                              subtitle: _subtitle(mode),
                              highlight: _savedScore.containsKey(mode),
                              onTap: () => _play(mode),
                            ),
                          ),
                          // Daily scores have no leaderboard (everyone's
                          // board differs after the first move anyway).
                          if (mode == GameMode.daily)
                            const SizedBox(width: 22)
                          else
                            IconButton(
                              onPressed: () => _showLeaderboard(mode),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.leaderboard, color: Colors.amberAccent, size: 22),
                              tooltip: '${mode.label} leaderboard',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _GiftPanel(onClaim: _claimGift, onAdBonus: _claimAdBonus),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _showHowToPlay(context),
                    child: const Text('How to play'),
                  ),
                ],
              ),
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
        content: const SingleChildScrollView(
          child: Text(
            'Drag blocks from the tray onto the grid.\n\n'
            'Fill an entire row or column to clear it and score points.\n\n'
            'Clear multiple lines at once, or clear lines back-to-back, for bonus combo points.\n\n'
            'Power-ups: Undo your last move, smash one block with the Hammer, or Shuffle your 3 blocks. One free use each per game, plus any saved from the daily gift, more by watching a short video.\n\n'
            'Classic: the game ends when none of your 3 blocks fit on the board.\n\n'
            'Survival: a bomb tile is always ticking down somewhere on the board — clear its row or column before time runs out, or it\'s game over.\n\n'
            'Daily: everyone gets the same blocks today. Play every day to grow your streak.\n\n'
            'Your game is saved automatically, so you can close the app and resume later.',
          ),
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

/// Today's free power-up (then one more for a rewarded ad), plus what's
/// already banked.
class _GiftPanel extends StatelessWidget {
  final VoidCallback onClaim;
  final VoidCallback onAdBonus;

  const _GiftPanel({required this.onClaim, required this.onAdBonus});

  @override
  Widget build(BuildContext context) {
    final inv = PowerUpInventory.instance;
    final Widget action;
    if (inv.canClaimGift) {
      action = FilledButton.icon(
        onPressed: onClaim,
        style: FilledButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
        icon: const Icon(Icons.card_giftcard),
        label: const Text('Daily gift: free power-up'),
      );
    } else if (inv.canClaimAdBonus) {
      action = OutlinedButton.icon(
        onPressed: onAdBonus,
        style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent),
        icon: const Icon(Icons.ondemand_video),
        label: const Text('Watch video: +1 power-up'),
      );
    } else {
      action = const Text('Next gift tomorrow', style: TextStyle(color: Colors.white54));
    }
    final banked = [for (final p in PowerUp.values) if (inv.count(p) > 0) p];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        action,
        if (banked.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in banked) ...[
                Icon(_powerUpIcons[p], size: 16, color: Colors.white70),
                Text(' ${inv.count(p)}   ', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final GameMode mode;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  const _ModeButton({
    required this.mode,
    required this.subtitle,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
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
            switch (mode) {
              GameMode.classic => Icons.play_arrow,
              GameMode.survival => Icons.local_fire_department,
              GameMode.daily => Icons.calendar_today,
            },
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
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: highlight ? Colors.amberAccent : Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
