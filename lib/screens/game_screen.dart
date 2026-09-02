import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../game/game_engine.dart';
import '../game/game_mode.dart';
import '../services/ads_service.dart';
import '../services/leaderboard_service.dart';
import '../services/sound_service.dart';
import '../widgets/app_background.dart';
import '../widgets/board_widget.dart';
import '../widgets/sound_toggle_button.dart';
import '../widgets/tray_widget.dart';

class GameScreen extends StatefulWidget {
  final GameMode mode;

  const GameScreen({super.key, this.mode = GameMode.classic});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GameEngine _engine = GameEngine();
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  bool _interstitialShown = false;

  // The board's real on-screen cell size, in pixels. The tray must drag its
  // pieces' feedback at this exact scale — see board_widget.dart's doc
  // comment on why a mismatch here breaks drag targeting, sometimes badly
  // enough that whole rows become unreachable on wide/desktop windows.
  final ValueNotifier<double> _boardCellSize = ValueNotifier<double>(40);

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    _engine.start(mode: widget.mode);
    unawaited(LeaderboardService.signIn());
    _bannerAd = AdsService.instance.createBannerAd(
      onLoaded: () => setState(() => _bannerLoaded = true),
    );
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
    _engine.start(mode: widget.mode);
  }

  void _togglePauseWithSound() {
    SoundService.instance.play(SoundEffect.back);
    _engine.togglePause();
  }

  void _exitToMenu() {
    SoundService.instance.play(SoundEffect.confirm);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            widget.mode == GameMode.survival ? 'Survival' : 'Classic',
          ),
          actions: [
            const SoundToggleButton(),
            IconButton(
              icon: Icon(_engine.paused ? Icons.play_arrow : Icons.pause),
              onPressed: _engine.gameOver ? null : _togglePauseWithSound,
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
                                child: BoardWidget(engine: _engine),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                if (_engine.gameOver)
                  _GameOverOverlay(
                    score: _engine.score,
                    best: _engine.best,
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
  final int score;
  final int best;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const _GameOverOverlay({
    required this.score,
    required this.best,
    required this.onRestart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final isNewBest = score >= best && score > 0;
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GAME OVER',
              style: TextStyle(
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
            Text(
              'Best: $best',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onExit, child: const Text('Menu')),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: onRestart,
                  child: const Text('Play Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
