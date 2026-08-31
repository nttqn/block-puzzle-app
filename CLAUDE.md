# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this is

A Flutter Android block-puzzle game (`Block Puzzle`), English UI, with AdMob
banner + interstitial ads wired in, intended for Google Play. No leaderboard
/ Play Games Services (deliberately skipped — this genre doesn't need one).
There is no native `android/` (or `ios/`/`web/`) directory committed — see
"Android project is generated, not committed" below.

## Commands

```
flutter pub get
flutter analyze
flutter test                       # unit tests for GameEngine + a home-screen widget test
flutter run -d chrome              # fastest way to eyeball gameplay changes
flutter build apk --release        # debug-signed test APK
flutter build appbundle --release  # AAB for Play Store upload (needs real signing config)
```

Real APK builds happen in CI: push to `main` (or `workflow_dispatch`) runs
`.github/workflows/build-apk.yml`.

## Android project is generated, not committed

Same pattern as this series' other games (chess-app, dino-egg-shooter,
number99-app): `android/`, `web/`, etc. are gitignored, and CI regenerates
`android/` via `flutter create` then patches in the AdMob App ID, INTERNET
permission, minSdk/compileSdk bump, R8 WorkManager keep rules, launcher
icon, and (if secrets are set) release signing. See `build-apk.yml`'s
inline comments for the exact why on each step — they're copied verbatim
from the validated pattern, minus the Play Games Services steps (not needed
here).

## Architecture

**`lib/models/piece.dart`** defines every piece shape as a grid of `#`/`.`
strings (`_shapeGrids`), parsed once into normalized `Cell` lists
(`kAllShapes`). `randomPiece()` picks a random shape + random color from
`kPieceColors`. Roughly 35 shapes: lines (1-5 long), squares, L/J/T/S/Z
tetrominoes (all rotations), a plus-pentomino, big-L and P pentominoes.

**`lib/game/game_engine.dart`** (`GameEngine extends ChangeNotifier`) is the
whole game's logic, deliberately Flutter-widget-free so it's unit-testable
(`test/game_engine_test.dart`) without pumping any widgets:
- `board`: `List<List<Color?>>`, 8x8, `null` = empty cell.
- `tray`: 3 `PieceInstance?` slots; refills all 3 at once only when all 3
  are empty (not per-slot) — matches the genre convention.
- `canPlacePieceAt(piece, row, col)`: bounds + overlap check, pure/no
  side effects — the UI calls this on every drag-hover frame to decide the
  green/red preview tint, and again before calling `placePiece`.
- `placePiece` is **not** self-validating — it trusts the caller already
  checked `canPlacePieceAt`. It fills cells, scores 1 point/cell, detects
  full rows/cols, flashes them via `clearingCells` for ~160ms (UI reads
  this set to brighten those cells before they vanish), then clears them
  and scores a combo-multiplied bonus (`combo` increments on any clearing
  placement, resets to 0 the moment a placement clears nothing).
- `_pickFairPiece` retries the random pick (up to 20x) if the candidate
  can't be placed anywhere on the current board — softens (doesn't
  eliminate) the "unlucky refill = instant game over" genre problem.
- Game over: none of the tray's non-null pieces can be placed anywhere.

**Drag-and-drop (`lib/widgets/tray_widget.dart` +
`lib/widgets/board_widget.dart`)** — the one part of this build that took
real trial-and-error, worth understanding before touching either file:
- The board is a *single* `DragTarget<TrayDragData>` covering the whole
  8x8 grid (not 64 individual targets). The dropped/hovered cell is
  computed by converting `DragTargetDetails.offset` (confirmed via
  instrumented testing to be the **feedback widget's global top-left
  corner**, already accounting for `feedbackOffset` and the anchor
  strategy — not the raw pointer position) into board-local coordinates via
  `RenderBox.globalToLocal`, then `(local / cellSize).floor()`. Both the
  live preview (`onMove`/`onWillAcceptWithDetails`) and the actual drop
  (`onAcceptWithDetails`) use this same conversion, so whatever the
  feedback visually overlaps is exactly what gets validated/placed — no
  separate hit-testing math to keep in sync.
- Each tray piece drags via a plain `Draggable` (default
  `childDragAnchorStrategy`, so the finger stays at the same *relative*
  position within the feedback even though the feedback renders larger
  than the tray thumbnail — see below) with `feedbackOffset: Offset(0,
  -boardCellSize * 3)` to lift the piece up above the finger so it's
  visible while dragging (standard genre UX; the piece "grows" on pickup
  since the feedback renders at full board-cell scale vs. the tray's
  smaller display scale — also standard and was a deliberate choice, not
  a bug).
- **The bug that actually broke dragging during development**: `Draggable`
  wrapped only `Center(child: PieceView(...))` as its child, so the
  hit-testable area was *exactly the drawn cube pixels* — any point in an
  irregular shape's empty cells, or in the ~1.5px padding gap between two
  adjacent cubes, hit nothing and silently failed to start a drag. Fixed
  by wrapping the piece in a `Container(color: Colors.transparent)` sized
  to the *entire tray slot* before handing it to `Draggable` — a
  transparent `Container` still hit-tests across its whole box. If drag
  gestures ever stop registering again, suspect this exact class of bug
  first (something wrapping `Draggable.child` in a widget that doesn't
  paint solidly across the area you expect to be grabbable).
- Verified end-to-end via a local Playwright-driven
  `flutter build web --release` + static-server session (drag from tray →
  live preview tint → drop → placement → score update; pause/resume
  overlay). See [[user_dev_machine_tooling]]-style notes in memory for the
  CanvasKit-gstatic-redirect + shadow-root-canvas gotchas this required —
  same as every other web-verified game in this series.

**Scoring**: 1 point per placed cell; a line clear scores
`10*linesCleared + 10*(linesCleared-1)` (multi-clear bonus) multiplied by
`1 + (combo-1)*0.5` where `combo` is the consecutive-clearing-placement
streak. Best score persists via `shared_preferences`
(`lib/services/score_service.dart`).

**Back button = pause, not exit**: `GameScreen` uses `PopScope(canPop:
gameOver, onPopInvokedWithResult: ...)` to toggle the pause overlay instead
of popping mid-round — mandatory rule for every game in this series.

**Ads (`lib/services/ads_service.dart`)**: same singleton pattern as the
other games in this series, currently on Google's public TEST ad unit IDs
(never swapped to real ones for this project yet). Interstitial shows
roughly every other finished game, not after every one.
