import 'package:flutter/material.dart';

import '../models/piece.dart';
import '../services/skin_service.dart';

/// Renders a [PieceInstance] as its own little grid of block cells, sized
/// by [cellSize]. Used both for the tray display and as a Draggable's
/// feedback — the two must be built from the same widget so a tray piece's
/// on-screen shape exactly matches what gets dragged.
class PieceView extends StatelessWidget {
  final PieceInstance piece;
  final double cellSize;
  final double opacity;

  const PieceView({super.key, required this.piece, required this.cellSize, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: piece.width * cellSize,
        height: piece.height * cellSize,
        child: Stack(
          children: [
            for (final cell in piece.cells)
              Positioned(
                left: cell.col * cellSize,
                top: cell.row * cellSize,
                width: cellSize,
                height: cellSize,
                child: BlockCell(color: piece.color, inset: cellSize * 0.06),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single block cube — the shared visual unit for both placed board cells
/// and piece previews, drawn in the selected [BlockSkin] (or [skin] when
/// given, as the skin picker's previews do).
class BlockCell extends StatelessWidget {
  final Color color;
  final double inset;
  final bool bright;
  final BlockSkin? skin;

  const BlockCell({super.key, required this.color, this.inset = 2, this.bright = false, this.skin});

  @override
  Widget build(BuildContext context) {
    final assetPath = kBlockAssetForColor[color];
    final Widget child = switch (skin ?? SkinService.instance.skin.value) {
      BlockSkin.candy => assetPath != null ? _buildArt(assetPath) : _buildGradient(),
      BlockSkin.flat => _buildFlat(),
      BlockSkin.neon => _buildNeon(),
      BlockSkin.crystal => _buildCrystal(),
    };
    return Padding(padding: EdgeInsets.all(inset), child: child);
  }

  Color get _base => bright ? Color.lerp(color, Colors.white, 0.55)! : color;

  Widget _buildFlat() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _base,
        borderRadius: BorderRadius.circular(5),
        border: Border(bottom: BorderSide(color: Color.lerp(_base, Colors.black, 0.3)!, width: 3)),
      ),
    );
  }

  Widget _buildNeon() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(_base, Colors.black, bright ? 0.2 : 0.75),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Color.lerp(_base, Colors.white, 0.25)!, width: 2),
        boxShadow: [BoxShadow(color: _base.withValues(alpha: 0.7), blurRadius: 6)],
      ),
    );
  }

  /// A faceted gem look: hard color stops make a diagonal "cut" line.
  Widget _buildCrystal() {
    final light = Color.lerp(_base, Colors.white, 0.55)!;
    final dark = Color.lerp(_base, Colors.black, 0.3)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: light.withValues(alpha: 0.8), width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, _base, _base, dark, _base],
          stops: const [0, 0.42, 0.5, 0.5, 1],
        ),
      ),
    );
  }

  Widget _buildArt(String assetPath) {
    final art = Image.asset(assetPath, fit: BoxFit.contain);
    if (!bright) return art;
    // Line-clear flash: brighten the art itself rather than looking for a
    // separately-colored asset — a plain white overlay blended on top reads
    // as the same "about to disappear" pulse the gradient cells use.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        art,
        Positioned.fill(
          child: Opacity(opacity: 0.55, child: ColoredBox(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildGradient() {
    final base = bright ? Color.lerp(color, Colors.white, 0.55)! : color;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(base, Colors.white, 0.35)!, base, Color.lerp(base, Colors.black, 0.15)!],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
    );
  }
}

/// An Adventure gem tile: a sparkling diamond on a dark violet tile,
/// distinct from every block color and skin.
class GemCell extends StatelessWidget {
  final bool bright;

  const GemCell({super.key, this.bright = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: bright ? Colors.white : const Color(0xFF2A1240),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE040FB), width: size * 0.05),
            boxShadow: [BoxShadow(color: const Color(0xFFE040FB).withValues(alpha: 0.5), blurRadius: size * 0.2)],
          ),
          child: Icon(Icons.diamond, color: const Color(0xFFEA80FC), size: size * 0.66),
        );
      },
    );
  }
}

/// A survival-mode bomb tile: a dark, glowing disc with its remaining
/// seconds — visually distinct from a normal placed [BlockCell] so it reads
/// as "something you must act on," not just another color.
class BombCell extends StatelessWidget {
  final int secondsLeft;

  const BombCell({super.key, required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 5;
    final glow = urgent ? Colors.redAccent : Colors.orangeAccent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Padding(
          padding: EdgeInsets.all(size * 0.05),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color.lerp(glow, Colors.black, 0.35)!, const Color(0xFF0B0D10)],
              ),
              border: Border.all(color: glow, width: size * 0.05),
              boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.6), blurRadius: size * 0.25)],
            ),
            child: Center(
              child: Text(
                '$secondsLeft',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.5,
                  shadows: [Shadow(color: glow, blurRadius: size * 0.15)],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
