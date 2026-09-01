import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../game/game_engine.dart';
import '../services/ads_service.dart';
import '../widgets/board_widget.dart';
import '../widgets/tray_widget.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

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
    _engine.start();
    _bannerAd = AdsService.instance.createBannerAd(onLoaded: () => setState(() => _bannerLoaded = true));
  }

  void _onEngineChanged() {
    if (_engine.gameOver && !_interstitialShown) {
      _interstitialShown = true;
      AdsService.instance.maybeShowInterstitialAfterGame();
    }
    setState(() {});
  }

  void _restart() {
    _interstitialShown = false;
    _engine.start();
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
        _engine.togglePause();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10161F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF10161F),
          title: const Text('Block Puzzle'),
          actions: [
            IconButton(
              icon: Icon(_engine.paused ? Icons.play_arrow : Icons.pause),
              onPressed: _engine.gameOver ? null : _engine.togglePause,
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ScoreTile(label: 'SCORE', value: _engine.score),
                        _ScoreTile(label: 'BEST', value: _engine.best),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final boardExtent = constraints.maxWidth < constraints.maxHeight * 0.62
                                ? constraints.maxWidth
                                : constraints.maxHeight * 0.62;
                            _reportBoardCellSize(boardExtent / GameEngine.boardSize);
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
                  onResume: _engine.togglePause,
                  onRestart: _restart,
                  onExit: () => Navigator.of(context).pop(),
                ),
              if (_engine.gameOver)
                _GameOverOverlay(
                  score: _engine.score,
                  best: _engine.best,
                  onRestart: _restart,
                  onExit: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final String label;
  final int value;

  const _ScoreTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.5)),
        Text(
          '$value',
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const _PauseOverlay({required this.onResume, required this.onRestart, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PAUSED', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
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
                OutlinedButton(onPressed: onRestart, child: const Text('Restart')),
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

  const _GameOverOverlay({required this.score, required this.best, required this.onRestart, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final isNewBest = score >= best && score > 0;
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GAME OVER', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (isNewBest)
              const Text('New Best!', style: TextStyle(color: Colors.amberAccent, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Score: $score', style: const TextStyle(color: Colors.white, fontSize: 20)),
            Text('Best: $best', style: const TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onExit, child: const Text('Menu')),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: onRestart, child: const Text('Play Again')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
