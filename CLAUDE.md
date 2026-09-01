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
  grid (not one target per cell). The dropped/hovered cell is
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
  than the tray thumbnail — a deliberate "the piece grows on pickup" genre
  convention, not a bug). The piece is lifted above the finger for
  visibility using a `Transform.translate` *inside* the `feedback` widget
  itself — **not** `Draggable.feedbackOffset`. This distinction matters a
  lot: `feedbackOffset` shifts the actual tracked/reported position
  (`DragTargetDetails.offset`, see above) that the drop math reads, so any
  nonzero value there means a piece's *drawn* position and its *actual drop
  cell* diverge — the finger has to hover somewhere other than where the
  piece visually is. A `Transform.translate` only shifts paint, leaving the
  feedback's tracked layout position untouched, so the drop cell stays a
  direct 1:1 mapping of finger position to board cell no matter what visual
  lift is applied. See the third bug below for why this replaced an earlier
  `feedbackOffset`-based version.
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
- **A second real bug, found after a user report of "can't place on the
  top rows" on a wide desktop window**: `GameScreen` computed the tray's
  `boardCellSize` from its own `LayoutBuilder`, using
  `(constraints.maxWidth - 32) / boardSize` — the *tray section's* width,
  which is the full window width. The *board's* actual cell size comes
  from a completely different `LayoutBuilder` (`min(width, height*0.62)`
  inside the `Expanded` area). These two only happened to be close in a
  narrow mobile viewport (where dev testing had been done); on a wide
  window the tray's estimate came out several times larger than the
  board's real cell size, which fed into both the feedback's rendering
  scale *and* `feedbackOffset`'s magnitude — inflating the "lift the piece
  above the finger" distance to several times a real board row. That
  pushed the pointer position needed to reach the top rows off the board
  entirely (or required the pointer near/past the bottom edge). Fixed by
  having `GameScreen` measure the board's real cell size once (inside its
  own `LayoutBuilder`, the authoritative source since `BoardWidget` is
  given a tight `SizedBox` of exactly that size) and pushing it to the
  tray via a `ValueNotifier` (updated through
  `addPostFrameCallback` to avoid `setState`-during-build), instead of
  letting the tray re-derive its own estimate from an unrelated
  constraint. **Lesson**: any two widgets that both need "the board's
  pixel cell size" must read the exact same computed value — never let a
  sibling independently re-derive it from its own local constraints, even
  if the formulas look equivalent, since they can be fed different
  constraint boxes by the layout tree.
- **A third bug, found immediately after fixing the second**: even with the
  cell-size mismatch fixed, `feedbackOffset: Offset(0, -boardCellSize * N)`
  is fundamentally the wrong tool for "lift the piece above the finger,"
  because the board's `DragTarget` only reacts while the *raw pointer* is
  over it, while the drop cell is computed from the *feedback's* offset
  position (which the lift moves away from the pointer by construction).
  For a piece near the top rows, this means the finger has to hover
  *below* the visual target by the lift distance — for the very top row(s)
  that pushes the required finger position uncomfortably close to (or
  toward) the board's own edge, and is deeply unintuitive regardless (a
  user's instinct is "put the piece where I see it," not "hover N rows
  below where I want it to land"). A user hit exactly this hovering it near
  the top row of a 12-row board even after the cell-size fix. Fixed for
  good by switching to the `Transform.translate`-inside-`feedback` approach
  described above — the drop cell is now always exactly where the pointer
  is, with zero coupling to how the piece is drawn, so there is no lift
  distance that can push any row (top or otherwise) out of reach. **Do not
  reintroduce `feedbackOffset` on this widget** — if a future change wants
  the piece to visually follow the finger less directly (e.g. some drift or
  spring effect), implement it as paint-only, the same way.
- Verified end-to-end via a local Playwright-driven
  `flutter build web --release` + static-server session (drag from tray →
  live preview tint → drop → placement → score update; pause/resume
  overlay). See [[user_dev_machine_tooling]]-style notes in memory for the
  CanvasKit-gstatic-redirect + shadow-root-canvas gotchas this required —
  same as every other web-verified game in this series.

**Scoring**: 1 point per placed cell; a line clear scores
`10*linesCleared + 10*(linesCleared-1)` (multi-clear bonus) multiplied by
`1 + (combo-1)*0.5` where `combo` is the consecutive-clearing-placement
streak. Every line clear also sets `GameEngine.popup` (a `ScorePopup` with
the bonus amount and the centroid row/col of the cleared cells) and bumps
`popupSeq` — `BoardWidget` compares `popupSeq` against what it last saw (in
`didUpdateWidget`, since the same `GameEngine` instance is reused across
rebuilds so field equality can't signal "this is a new event") and, on a
change, spins up a short-lived `AnimationController` rendering a rising,
fading "+N" `Text` centered on that centroid — this is the floating score
popup genre games show on a successful clear (added on user request,
matching a reference screenshot). Best score persists via `shared_preferences`
(`lib/services/score_service.dart`).

**Back button = pause, not exit**: `GameScreen` uses `PopScope(canPop:
gameOver, onPopInvokedWithResult: ...)` to toggle the pause overlay instead
of popping mid-round — mandatory rule for every game in this series.

**Ads (`lib/services/ads_service.dart`)**: same singleton pattern as the
other games in this series, currently on Google's public TEST ad unit IDs
(never swapped to real ones for this project yet). Interstitial shows
roughly every other finished game, not after every one.
