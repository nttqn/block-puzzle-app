import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../debug/screenshot_scenarios.dart';
import '../game/game_engine.dart';
import '../game/game_mode.dart';
import '../models/adventure.dart';
import '../services/ads_service.dart';
import '../services/leaderboard_service.dart';
import '../services/music_service.dart';
import '../services/power_up_inventory.dart';
import '../services/sound_service.dart';
import '../widgets/app_background.dart';
import '../widgets/board_widget.dart';
import '../widgets/music_toggle_button.dart';
import '../widgets/power_up_bar.dart';
import '../widgets/sound_toggle_button.dart';
import '../widgets/tray_widget.dart';

class GameScreen extends StatefulWidget {
  final GameMode mode;

  /// Pick up the saved in-progress game for [mode] instead of starting fresh
  /// (falls back to a fresh game if there turns out to be none).
  final bool resume;

  /// [GameMode.adventure] only: the level to start on.
  final int level;

  const GameScreen({super.key, this.mode = GameMode.classic, this.resume = false, this.level = 1});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final GameEngine _engine = GameEngine();
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  bool _interstitialShown = false;

  // The board's real on-screen cell size, in pixels. The tray must drag its
  // pieces' feedback at this exact scale — see board_widget.dart's doc
  // comment on why a mismatch here breaks drag targeting, sometimes badly
  // enough that whole rows become unreachable on wide/desktop windows.
  final ValueNotifier<double> _boardCellSize = ValueNotifier<double>(40);

  late int _level = widget.level;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    WidgetsBinding.instance.addObserver(this);
    PowerUpInventory.instance.addListener(_onInventoryChanged);
    _begin();
    unawaited(LeaderboardService.signIn());
    MusicService.instance.playGame();
    _bannerAd = AdsService.instance.createBannerAd(
      onLoaded: () => setState(() => _bannerLoaded = true),
    );
  }

  Future<void> _begin() async {
    if (widget.resume && await _engine.resume(widget.mode)) return;
    await _engine.start(mode: widget.mode, levelNumber: _level);
    final shot = screenshotScenario;
    if (shot != null && mounted) {
      _engine.persistEnabled = false;
      setState(() => applyScenario(shot, _engine));
    }
  }

  void _onInventoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    // Backgrounded (or a call came in): stop the bomb clock and save, so the
    // run is still there if the OS kills the app.
    if (!_engine.paused && !_engine.gameOver && !_adInFlight) _engine.togglePause();
    _engine.persist();
  }

  void _onEngineChanged() {
    if (_engine.gameOver && !_interstitialShown) {
      _interstitialShown = true;
      AdsService.instance.maybeShowInterstitialAfterGame();
    }
    setState(() {});
  }

  void _restart() {
    SoundService.instance.play(SoundEffect.confirm);
    _interstitialShown = false;
    _hammerArmed = false;
    _engine.start(mode: widget.mode, levelNumber: _level);
  }

  void _nextLevel() {
    setState(() => _level++);
    _restart();
  }

  void _togglePauseWithSound() {
    SoundService.instance.play(SoundEffect.back);
    _engine.togglePause();
  }

  void _exitToMenu() {
    SoundService.instance.play(SoundEffect.confirm);
    Navigator.of(context).pop();
  }

  bool _hammerArmed = false;
  bool _adInFlight = false;

  /// Runs [action] directly while this game's free charge remains, then
  /// from the banked daily-gift inventory, and only after that offers a
  /// rewarded ad; the last two run it with `grantedByAd: true` (free of the
  /// engine's own charges).
  Future<void> _usePowerUp(PowerUp type, int charges, void Function({bool grantedByAd}) action) async {
    if (charges > 0) {
      action();
      return;
    }
    if (_adInFlight) return;
    if (PowerUpInventory.instance.consume(type)) {
      action(grantedByAd: true);
      return;
    }
    final wasPaused = _engine.paused;
    if (!wasPaused) _engine.togglePause();
    _adInFlight = true;
    final earned = await AdsService.instance.showRewarded();
    _adInFlight = false;
    if (!mounted) return;
    if (!wasPaused && _engine.paused) _engine.togglePause();
    if (earned) {
      action(grantedByAd: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not available right now. Try again later.')),
      );
    }
  }

  void _onHammerButton() {
    SoundService.instance.play(SoundEffect.confirm);
    setState(() => _hammerArmed = !_hammerArmed);
  }

  void _onHammerTap(int row, int col) {
    if (_engine.board[row][col] == null) return;
    setState(() => _hammerArmed = false);
    _usePowerUp(
      PowerUp.hammer,
      _engine.hammerCharges,
      ({bool grantedByAd = false}) => _engine.hammerDestroy(row, col, grantedByAd: grantedByAd),
    );
  }

  Future<void> _continueAfterGameOver() async {
    if (_adInFlight) return;
    _adInFlight = true;
    final earned = await AdsService.instance.showRewarded();
    _adInFlight = false;
    if (!mounted) return;
    if (earned) {
      _interstitialShown = false;
      _engine.continueAfterGameOver();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not available right now. Try again later.')),
      );
    }
  }

  Future<void> _doubleScore() async {
    if (_adInFlight) return;
    _adInFlight = true;
    final earned = await AdsService.instance.showRewarded();
    _adInFlight = false;
    if (!mounted) return;
    if (earned) {
      _engine.doubleScore();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not available right now. Try again later.')),
      );
    }
  }

  int _total(PowerUp type, int charges) => charges + PowerUpInventory.instance.count(type);

  @override
  void dispose() {
    _engine.persist();
    WidgetsBinding.instance.removeObserver(this);
    PowerUpInventory.instance.removeListener(_onInventoryChanged);
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    _bannerAd?.dispose();
    _boardCellSize.dispose();
    super.dispose();
  }

  void _reportBoardCellSize(double cellSize) {
    if (_boardCellSize.value == cellSize) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _boardCellSize.value = cellSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _engine.gameOver,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _togglePauseWithSound();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10161F),
        extendBodyBehindAppBar: true,
        // A real "RenderFlex overflowed" was hit here on a narrow window:
        // AppBar's title + 2 actions (each a default 48x48-tap-target
        // IconButton) don't leave enough room at small widths, and unlike
        // a plain Row, AppBar's internal NavigationToolbar layout can
        // squeeze the actions area down arbitrarily far (observed:
        // BoxConstraints down to ~1px) rather than growing the AppBar or
        // wrapping — so this needs the actions themselves to have a
        // smaller natural footprint, not a wrapper fix at this call site.
        // titleSpacing: 0 reclaims the default gap next to the (absent)
        // leading widget; the title ellipsizes rather than fighting the
        // actions for space if it's still tight.
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          title: Text(
            widget.mode == GameMode.adventure ? 'Level $_level' : widget.mode.label,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            const MusicToggleButton(),
            const SoundToggleButton(),
            IconButton(
              icon: Icon(_engine.paused ? Icons.play_arrow : Icons.pause),
              onPressed: _engine.gameOver ? null : _togglePauseWithSound,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        body: AppBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // extendBodyBehindAppBar lets the background image show
                    // through the transparent AppBar, but that also means
                    // body content starts from the very top of the screen —
                    // push it down to clear the AppBar's own height first.
                    const SizedBox(height: kToolbarHeight),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _ScoreTile(label: 'SCORE', value: _engine.score),
                          if (_engine.mode == GameMode.survival &&
                              _engine.bomb != null)
                            _BombTimerChip(
                              secondsLeft: _engine.bomb!.secondsLeft,
                            ),
                          if (_engine.level != null)
                            _GoalChip(level: _engine.level!, progress: _engine.goalProgress),
                          if (_engine.level != null)
                            _ScoreTile(label: 'MOVES', value: _engine.movesLeft, highlight: true)
                          else
                            _ScoreTile(label: 'BEST', value: _engine.best, highlight: true),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Fill nearly all of the space Expanded actually
                              // gives this area (only a small margin, not an
                              // arbitrary shrink) so the board doesn't float
                              // in a sea of empty space on tall phone screens.
                              final boardExtent =
                                  constraints.maxWidth <
                                      constraints.maxHeight * 0.96
                                  ? constraints.maxWidth
                                  : constraints.maxHeight * 0.96;
                              _reportBoardCellSize(
                                boardExtent / GameEngine.boardSize,
                              );
                              return SizedBox(
                                width: boardExtent,
                                height: boardExtent,
                                child: BoardWidget(
                                  engine: _engine,
                                  hammerArmed: _hammerArmed,
                                  onHammerTap: _onHammerTap,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    PowerUpBar(
                      undoCharges: _total(PowerUp.undo, _engine.undoCharges),
                      hammerCharges: _total(PowerUp.hammer, _engine.hammerCharges),
                      shuffleCharges: _total(PowerUp.shuffle, _engine.shuffleCharges),
                      canUndo: _engine.canUndo,
                      enabled: !_engine.paused && !_engine.gameOver,
                      hammerArmed: _hammerArmed,
                      onUndo: () => _usePowerUp(PowerUp.undo, _engine.undoCharges, _engine.undo),
                      onHammer: _onHammerButton,
                      onShuffle: () => _usePowerUp(PowerUp.shuffle, _engine.shuffleCharges, _engine.shuffleTray),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: ValueListenableBuilder<double>(
                        valueListenable: _boardCellSize,
                        builder: (context, boardCellSize, _) {
                          return TrayWidget(
                            engine: _engine,
                            traySlotCellSize: boardCellSize * 0.55,
                            boardCellSize: boardCellSize,
                          );
                        },
                      ),
                    ),
                    if (_bannerLoaded && _bannerAd != null)
                      SizedBox(
                        width: _bannerAd!.size.width.toDouble(),
                        height: _bannerAd!.size.height.toDouble(),
                        child: AdWidget(ad: _bannerAd!),
                      ),
                  ],
                ),
                if (_engine.paused && !_engine.gameOver)
                  _PauseOverlay(
                    onResume: _togglePauseWithSound,
                    onRestart: _restart,
                    onExit: _exitToMenu,
                  ),
                if (_engine.gameOver && _engine.won)
                  _LevelCompleteOverlay(
                    level: _level,
                    stars: _engine.stars,
                    score: _engine.score,
                    onNext: _level < kAdventureLevels ? _nextLevel : null,
                    onReplay: _restart,
                    onExit: _exitToMenu,
                  ),
                if (_engine.gameOver && !_engine.won)
                  _GameOverOverlay(
                    title: _engine.level == null
                        ? 'GAME OVER'
                        : (_engine.movesLeft <= 0 ? 'OUT OF MOVES' : 'NO ROOM LEFT'),
                    showBest: _engine.level == null,
                    score: _engine.score,
                    best: _engine.best,
                    onContinue: _engine.canContinueAfterGameOver ? _continueAfterGameOver : null,
                    onDouble: _engine.canDoubleScore ? _doubleScore : null,
                    onRestart: _restart,
                    onExit: _exitToMenu,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;

  const _ScoreTile({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final labelColor = highlight ? Colors.amber : Colors.white54;
    final valueColor = highlight ? Colors.amberAccent : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(color: labelColor, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.bold),
        ),
        Text(
          '$value',
          style: TextStyle(
            color: valueColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: highlight
                ? [Shadow(color: Colors.amber.withValues(alpha: 0.6), blurRadius: 8)]
                : null,
          ),
        ),
      ],
    );
  }
}

class _BombTimerChip extends StatelessWidget {
  final int secondsLeft;

  const _BombTimerChip({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (urgent ? Colors.redAccent : Colors.orangeAccent).withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: urgent ? Colors.redAccent : Colors.orangeAccent,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💣', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            '$secondsLeft s',
            style: TextStyle(
              color: urgent ? Colors.redAccent : Colors.orangeAccent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const _PauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUSED',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onExit, child: const Text('Menu')),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: onRestart,
                  child: const Text('Restart'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final String title;
  final bool showBest;
  final int score;
  final int best;
  final VoidCallback? onContinue;
  final VoidCallback? onDouble;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const _GameOverOverlay({
    required this.title,
    required this.showBest,
    required this.score,
    required this.best,
    required this.onContinue,
    required this.onDouble,
    required this.onRestart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final isNewBest = showBest && score >= best && score > 0;
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (isNewBest)
              const Text(
                'New Best!',
                style: TextStyle(color: Colors.amberAccent, fontSize: 18),
              ),
            const SizedBox(height: 8),
            Text(
              'Score: $score',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            if (showBest)
              Text(
                'Best: $best',
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
            const SizedBox(height: 24),
            if (onContinue != null) ...[
              ElevatedButton.icon(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('Continue (watch ad)'),
              ),
              const SizedBox(height: 12),
            ],
            if (onDouble != null) ...[
              ElevatedButton.icon(
                onPressed: onDouble,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.ondemand_video),
                label: const Text('x2 Score (watch ad)'),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onExit, child: const Text('Menu')),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: onRestart,
                  child: Text(showBest ? 'Play Again' : 'Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Adventure: the level's goal and how far along it is, e.g. "💎 2 / 5".
class _GoalChip extends StatelessWidget {
  final AdventureLevel level;
  final int progress;

  const _GoalChip({required this.level, required this.progress});

  @override
  Widget build(BuildContext context) {
    final (icon, unit) = switch (level.goal) {
      LevelGoal.score => (Icons.star_rounded, 'pts'),
      LevelGoal.lines => (Icons.view_stream_rounded, 'lines'),
      LevelGoal.gems => (Icons.diamond, 'gems'),
    };
    final shown = progress.clamp(0, level.target);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'GOAL',
            style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: level.goal == LevelGoal.gems ? const Color(0xFFEA80FC) : Colors.amberAccent),
              const SizedBox(width: 4),
              Text(
                '$shown / ${level.target} $unit',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelCompleteOverlay extends StatelessWidget {
  final int level;
  final int stars;
  final int score;
  final VoidCallback? onNext;
  final VoidCallback onReplay;
  final VoidCallback onExit;

  const _LevelCompleteOverlay({
    required this.level,
    required this.stars,
    required this.score,
    required this.onNext,
    required this.onReplay,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LEVEL $level COMPLETE!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 3; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == 2 ? 14 : 0),
                    child: Icon(
                      Icons.star_rounded,
                      size: i == 2 ? 72 : 56,
                      color: i <= stars ? Colors.amber : Colors.white24,
                      shadows: i <= stars ? const [Shadow(color: Colors.orange, blurRadius: 16)] : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Score: $score', style: const TextStyle(color: Colors.white, fontSize: 20)),
            if (stars < 3)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Finish with more moves left for more stars', style: TextStyle(color: Colors.white54)),
              ),
            const SizedBox(height: 24),
            if (onNext != null) ...[
              ElevatedButton.icon(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next level'),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onExit, child: const Text('Menu')),
                const SizedBox(width: 16),
                OutlinedButton(onPressed: onReplay, child: const Text('Replay')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
