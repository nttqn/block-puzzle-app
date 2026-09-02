# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this is

A Flutter Android block-puzzle game (`Block Puzzle Plus`), English UI, with AdMob
banner + interstitial ads wired in, intended for Google Play. Play Games
Services leaderboards (one per game mode, real leaderboard IDs from an
existing Play Console project) are wired in code — see "Leaderboard"
below — but **still unverified end-to-end**: Play Games ties sign-in to
the app's signing certificate, and this project has only ever built
debug-signed test APKs, so a real release keystore + the
`PLAY_GAMES_APP_ID` GitHub secret still need to be set before a build can
actually sign in.
The Dart package name (`block_puzzle`, i.e. every `package:block_puzzle/...`
import) and the Android application ID (`com.trungsmail.block_puzzle`) were
deliberately **not** renamed to match — those are internal identifiers, not
the user-visible name, and changing either is a much bigger/riskier
operation (every import statement; the Play Store listing identity, if this
were ever published under the old ID) than the display-name change this
was actually asked for. The display name (`MaterialApp.title`, the Android
`android:label` set by CI, and the home screen's title art) is
"Block Puzzle Plus".
There is no native `android/` (or `ios/`/`web/`) directory committed — see
"Android project is generated, not committed" below.

Two game modes, picked from the home screen (`lib/screens/home_screen.dart`,
one button per `GameMode` value) and passed into `GameScreen(mode: ...)`:
- **Classic**: endless, ends when no tray piece fits anywhere.
- **Survival**: same board/scoring, plus a bomb tile always ticking down
  somewhere on the board — see "Survival mode / bomb tile" below.

Best scores are tracked **per mode** (`ScoreService` keys off `GameMode`,
see `lib/services/score_service.dart`) since Classic and Survival scores
aren't comparable.

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

**Block art**: `kBlockAssetForColor` (same file) maps each of the 8
`kPieceColors` entries to a PNG under `assets/blocks/` — one glossy block
image per color, sliced from a single sprite sheet the user supplied at
`assets/block.png` (kept unbundled — not listed in `pubspec.yaml`'s
assets — purely a source reference, the same relationship `sound_src/` has
to `assets/audio/`). `BlockCell` (`lib/widgets/piece_view.dart`) checks
this map first and renders the matching `Image.asset` when the cell's
color has one; any color with no entry (currently only the survival-mode
bomb's `kBombColor`) falls back to the original procedural gradient box —
so the gradient path still exists and is exercised, it's not dead code.
The line-clear "flash brighter" effect (`bright: true`) is done as a
semi-transparent white overlay stacked on top of the art for image-backed
cells, rather than trying to source/generate a separately-brightened image
per color.

**Gap between placed cells**: `BoardWidget._buildCell` wraps every cell
(empty or filled) in an outer `Padding(EdgeInsets.all(1))` for the
grid-line-style separation between cells — `BlockCell` itself also takes
an `inset` parameter that adds further padding *inside* whatever box it's
given. These used to be applied **both** for board cells (outer Padding(1)
+ `BlockCell(inset: 1)`), doubling the visible gap between two adjacent
placed blocks to a noticeably wide seam once the block art itself was
tightly cropped with near-zero internal margin (a user screenshot flagged
this after the art re-crop above). Fixed by passing `inset: 0` to
`BlockCell` from `_buildCell` specifically, relying solely on the outer
Padding for board-cell separation — `PieceView`'s own `BlockCell` calls
(tray display and drag feedback) still use their own proportional inset
(`cellSize * 0.06`) and are unaffected; that gap is between cells of the
*same* piece and was never doubled up this way.

**App icon** (`assets/icon/icon.png`, consumed only by
`flutter_launcher_icons` — see `pubspec.yaml`'s `flutter_launcher_icons:`
block and `build-apk.yml`'s "Generate launcher icon" step, which runs
`dart run flutter_launcher_icons` to write it into every
`android/app/src/main/res/mipmap-*/` slot): currently a user-supplied
square icon (`block-puzzle-plus-icon.png`, 1254x1254, opaque — rounded
corners and the purple background are baked into the art itself rather
than left transparent for the OS to mask, since this project only
generates the legacy square/round launcher icon, not an adaptive
foreground+background pair). **Originally** this file was a flood-filled
wordmark shared with the home-screen title (see below) — split into two
separate images on 2026-09-02 once the user supplied a dedicated icon-
shaped asset, since a wordmark logo and a square app icon have
fundamentally different aspect-ratio/composition needs and conflating them
was only ever a "reuse what we already have" shortcut, not a deliberate
design choice. The original flood-fill removal work (below) is kept for
its *technique*, in case a future icon needs the same treatment, even
though this specific file no longer needs it (the current source already
ships with clean baked-in edges, confirmed via a pixel probe: corner reads
opaque white, not a checkerboard).
  - **Historical: flood-fill background removal.** The very first icon
    source (`block-puzzle-plus-logo.png`, kept at the repo root as a
    reference) had a *baked-in* checkerboard background (`Format24bppRgb`
    — no alpha channel at all; the "transparent-looking" squares were
    literal light-gray/white pixels). A naive color-threshold removal was
    rejected up front because the checkerboard's two tones are close to
    the wordmark's own white "PUZZLE" lettering — a global threshold would
    have eaten into the text. Used a **flood fill from the image border**
    instead (`PowerShell + System.Drawing`, no ImageMagick — see
    [[user_dev_machine_tooling]]): seed a queue with every border pixel
    that looks checkerboard-like (bright, low saturation: all channels
    ≥225 and within 10 of each other), then BFS/flood-fill 4-connected
    neighbors that pass the same test, zeroing alpha for every visited
    pixel. This only removes background *connected to the edge* — the
    white lettering is enclosed by darker outline/shadow pixels and is
    never reached by the flood, so it survives untouched regardless of how
    similar its color is to the checkerboard. Hit the same `New-Object
    Type($expr)` PowerShell gotcha as the block-art script (see
    [[user_dev_machine_tooling]]) in a new form: `[int]($p / $w)` for
    decoding a flattened pixel index back to (x, y) intermittently rounded
    via banker's-rounding instead of truncating, producing an occasional
    off-by-one row and an `IndexOutOfRangeException` deep in the byte
    array — fixed by computing `$px = $p % $w; $py = ($p - $px) / $w`
    (exact integer division by construction, no cast ambiguity). This
    flood-fill-from-border technique — not a global color/distance
    threshold — is the one to reuse for any future "remove a background
    that's color-similar to real foreground content" task.

**Home screen title** (`assets/title/title.png`, `Image.asset(...,
width: 220)` in `lib/screens/home_screen.dart`): a separate wordmark image
from the app icon (see split rationale above) — source
`block-puzzle-plus-title.png` already shipped with a real alpha channel
(confirmed via pixel probe: corner alpha=0) and needed no background
removal, just an **alpha-bounding-box crop** (same technique as the v2/v3
block-art crops, but without the "force square" step those need — a
wordmark's aspect ratio should stay whatever it naturally is, only the
excess transparent margin gets trimmed) to strip ~105px of dead transparent
margin on each side that would otherwise waste space at a fixed display
width. A small 4px margin was kept around the computed bbox specifically
so anti-aliased edge pixels (alpha just above the presence threshold, not
fully 0) don't get clipped into a visible hard edge.

The block-art slicing script (`PowerShell + System.Drawing`) went through
two versions:
- **v1** (source sheet had no alpha channel): cropped the 4x2 grid into 8
  fixed-size `sheetW/4 x sheetH/2` tiles, then chroma-keyed the background
  (sample a corner pixel, zero alpha within an RGB distance threshold).
  This produced non-square tiles (the sheet's cells were taller than
  wide), which `BoxFit.contain` then letterboxed inside each square board
  cell — wasted space — and the distance-threshold approach let a sliver
  of the *neighboring* tile's color bleed into the crop along shared edges
  in a couple of cases.
- **v2** (after the user regenerated the source sheet with a real alpha
  channel): crops per-tile using the *actual alpha data* instead — scan
  each nominal `sheetW/4 x sheetH/2` region for the tight bounding box of
  pixels at or above an alpha threshold (128), then crop a **square**
  centered on that bounding box, so every output PNG is exactly square and
  sized to the actual block art, not the sheet's nominal (non-square) grid
  cell. A final pass hard-zeros any pixel with alpha below 60 within the
  crop, since the source's soft glow/feather can leave a faint
  semi-transparent halo that would otherwise blend into an adjacent board
  cell's own art once tiled. v2 used `side = max(bboxW, bboxH) * 1.03` (a
  3% safety margin), which turned out to leave a visible few-pixel fully-
  transparent border around the block — harmless in isolation, but visible
  as a gap once cells sit edge-to-edge on the board.
- **v3** (current): same alpha-bbox approach, but `side = max(bboxW,
  bboxH) * 0.99` (flush, very slightly trimmed) instead of `* 1.03` — the
  block's own content now starts at pixel 0-1 of the image with no
  transparent margin. If the sprite sheet is ever regenerated again, reuse
  this v3 alpha-bbox-with-flush-crop approach — v1's fixed-size/chroma-key
  crop and v2's `1.03` margin were both real bugs the user caught from
  screenshots ("cut to exact square dimensions," "remove background with
  leftover pixels," "still trash pixels around each block, crop tighter").

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
- Each tray piece drags via a plain `Draggable` with a **custom
  center-anchoring** `dragAnchorStrategy` — `(draggable, context, position)
  => Offset(feedbackWidth / 2, feedbackHeight / 2)` — computed from the
  piece's own known board-scale dimensions in `tray_widget.dart`. Neither
  of the two built-in strategies worked out (see the fourth and fifth bugs
  below): the default `childDragAnchorStrategy` reintroduces a grab-point-
  dependent offset that broke tight-fit placements, and
  `pointerDragAnchorStrategy` (anchoring the top-left corner) fixed that
  but snapped the piece's corner to the finger regardless of grab point,
  which read as broken/disorienting. Center-anchoring keeps the same
  determinism (no grab-point dependency — the tight-fit fix holds) while
  matching how people actually expect a dragged shape to behave: it moves
  as a rigid body centered on the finger. The "piece grows on pickup" size
  jump (feedback renders at board scale, bigger than the tray thumbnail) is
  still a deliberate genre convention. The piece is lifted above the
  finger for
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
- **A fourth bug, reported by a user as "I'm dragging the piece over 5
  clearly-empty cells and no preview shows at all"**: on a *tight-fit* gap
  — empty space exactly the size of the piece, zero margin for error — the
  default `childDragAnchorStrategy` preserves the pointer's fractional
  position *within the grabbed child* (the tray thumbnail) when placing the
  feedback, so the feedback's tracked top-left ends up offset from the
  pointer by up to half a cell in either axis, by an amount that depends on
  *exactly where within the piece the user happened to grab it* — grab
  near an edge and the offset is small; grab near the center and it can be
  large. That's normally harmless (there's usually slack around a target
  cell), but on a gap with zero slack, half a cell of grab-point-dependent
  offset is enough to compute the wrong origin and make a placement that
  genuinely fits register as invalid. Confirmed via a `flutter_test`
  gesture-driven reproduction (`test/bottom_row_drag_test.dart`) *before*
  jumping to a fix: the same target position showed 5 invalid (red)
  preview cells when grabbed one way and 5 valid (green) cells when grabbed
  another, with the drop math otherwise unchanged — proving the anchor
  strategy, not the cell/coordinate math, was the variable. Fixed by
  switching to `dragAnchorStrategy: pointerDragAnchorStrategy` (see above),
  which anchors the feedback's top-left exactly at the pointer regardless
  of grab point, making the drop cell a fixed, grab-point-independent
  function of pointer position alone. **If a "can't place here even though
  it clearly fits" report comes up again, suspect the anchor strategy
  before the coordinate math** — the math has now been proven correct
  (engine unit tests) and provably deterministic (this bug) three separate
  times; the anchor/offset layer is where every real bug in this feature
  has actually lived.
- **A fifth bug**: `pointerDragAnchorStrategy` fixed the fourth bug's
  correctness problem but introduced a *feel* problem — a user reported
  "I have to drag the block to a different position than the real one for
  it to match." Root cause: anchoring the feedback's *top-left corner* to
  the pointer means the piece snaps so its corner (not wherever you
  grabbed it) sits at the finger the instant the drag starts — grab a
  multi-cell piece anywhere but its own top-left and the whole shape jumps
  up-left of your finger by construction, and that jump then compounds
  with the paint-only lift on top of it, producing a confusing double
  offset between where the piece visually sits and where your finger
  actually is. Fixed by switching to a **custom center-anchoring**
  strategy (see above) — still fully deterministic (no grab-point
  dependency, so the fourth bug's fix holds; `bottom_row_drag_test.dart`
  was updated to target the piece's *bounding-box center*, not its
  top-left corner, and still passes) but the piece now moves as a rigid
  body centered on the finger, matching how a dragged shape is expected to
  behave regardless of where on it you happened to grab. Also reduced the
  paint-only lift from `1.5` to `0.6` cell heights while at it — with the
  piece already centered on the finger, a smaller lift is enough to clear
  a fingertip without visually separating the piece from the touch point
  as much. **If a future report describes the piece's drawn position not
  matching where it actually lands, check whether anything reintroduced a
  corner-based or grab-point-dependent anchor** — center-anchoring is the
  one that has actually held up across a correctness bug (the fourth) and
  a real usability complaint (this one).
- **A sixth bug, a real crash this time (not just a UX complaint)**: shipping
  the center-anchor fix (fifth bug) immediately surfaced a live `RenderFlex
  overflowed by 44 pixels on the right` in `TrayWidget`'s `Row`
  (`tray_widget.dart:35`), caught from the actual Chrome console during
  manual testing, not a test run. `TrayWidget.build()` used
  `mainAxisAlignment: spaceEvenly` with 3 slots each sized to their natural
  `traySlotCellSize * 5` — `spaceEvenly` only *distributes leftover space*,
  it never shrinks children, so on a window where the tray's actual
  available width came out smaller than the 3 slots' combined natural
  width (334px available vs. ~378px needed in the reported case), the Row
  overflowed instead of compressing. This is a distinct failure mode from
  the second bug above (`traySlotCellSize` and `boardCellSize` diverging
  between siblings) — here both values were internally consistent, the row
  just didn't have enough room for them at *any* consistent value on a
  narrow-enough window. Fixed by making the tray inherently overflow-proof
  regardless of window size: each slot is wrapped in `Expanded(child:
  Center(...))` (so the Row always divides its actual available width
  three ways as a hard constraint — this alone guarantees the *Row* itself
  can never overflow, since Expanded children are sized to exactly their
  allocated flex share) and the slot's fixed-size content is wrapped in
  `FittedBox(fit: BoxFit.scaleDown)` (so oversized content shrinks to fit
  within whatever width Expanded actually gave it, rather than silently
  painting outside its slot into a neighbor — Expanded bounds the *Row's*
  layout, not what a plain `Center` child is allowed to paint). Both
  changes are scoped to the **in-place tray display only**; the
  `Draggable.feedback` (rendered through the `Overlay` during a drag, sized
  off `boardCellSize`) is completely untouched by either wrapper, so none
  of the drop-math correctness fixed across the previous four bugs is put
  at risk — confirmed by rerunning `bottom_row_drag_test.dart` unchanged
  after this fix and it still passing. Regression-tested directly in
  `test/tray_overflow_test.dart`: pumps a `TrayWidget` inside a `SizedBox`
  deliberately narrower than 3 natural-sized slots and asserts
  `tester.takeException()` is `null` — verified this test actually fails
  (reproducing the exact crash) against the pre-fix `spaceEvenly` code via
  `git stash` before confirming it passes with the fix, so it's a real
  regression guard and not a tautology. **If tray sizing ever changes
  again, keep both the `Expanded` (Row-level) and `FittedBox`
  (content-level) guards — either alone is insufficient**: `Expanded`
  without `FittedBox` stops the crash but lets oversized art visually spill
  into a neighboring slot; `FittedBox` without `Expanded` has no bounded
  parent to shrink into and does nothing.
- Verified end-to-end via a local Playwright-driven
  `flutter build web --release` + static-server session (drag from tray →
  live preview tint → drop → placement → score update; pause/resume
  overlay). See [[user_dev_machine_tooling]]-style notes in memory for the
  CanvasKit-gstatic-redirect + shadow-root-canvas gotchas this required —
  same as every other web-verified game in this series. **Note**: Flutter
  web's CanvasKit renderer paints everything to a `<canvas>`, so
  Playwright's DOM-text locators (`getByText`, etc.) cannot find or click
  in-game buttons/text — that verification path only works for
  screenshot/console-log checks (e.g. confirming no `RenderFlex overflow`
  console error appears at a given viewport width), not for driving actual
  gameplay interactions; use a `flutter_test` gesture-driven test (like
  `bottom_row_drag_test.dart` or `tray_overflow_test.dart`) for anything
  that needs to click/drag a specific widget.

**Scoring**: 1 point per placed cell; a line clear scores `10*linesCleared`
multiplied by a **multi-clear multiplier** (`linesCleared` itself, so 1x for
a single line, 2x for clearing 2 lines in the same placement, 3x for 3, and
so on — added on user request so simultaneous multi-line clears feel
meaningfully bigger than a flat per-line bonus) multiplied again by
`1 + (combo-1)*0.5` where `combo` is a *different*, unrelated bonus: the
consecutive-clearing-*placement* streak (increments across separate turns,
not simultaneous lines within one turn). These two multipliers stack
because they reward two different things — clearing several lines at once
vs. clearing on back-to-back turns — and nothing stops both being true at
once. Whenever the multi-clear multiplier is ≥2, `GameEngine` also sets
`comboBannerMultiplier` and bumps `comboBannerSeq` (same "new event"
pattern as `popupSeq`/`explosionSeq` below), which `BoardWidget` renders as
a punchy "COMBO xN!" banner — centered on the board rather than following
any per-cell centroid, since a simultaneous row+column clear has no single
natural anchor point. Deliberately named independently in code
(`multiClearMultiplier`/`comboBannerMultiplier`, not reusing `combo`) to
keep the two bonuses distinct in the source even though the UI banner text
says "COMBO" for both, matching genre convention. **Animation-curve gotcha
hit while adding this banner**: `Curves.easeIn.transform((t - 0.7) / 0.3)`
threw `parametric value ... is outside of [0, 1] range` under `flutter
test` even though the *result* was always clamped afterward — an
`AnimationController`'s value can land a hair above `1.0`
(`1.0000000000000002`-style float error from the `/0.3` division) right at
the animation's natural end, and `Curve.transform` asserts on its **input**
being in range before any clamping of the output ever runs. Fix: clamp the
argument passed *into* `transform` (`.clamp(0.0, 1.0)` on the fraction
itself), not just the final opacity/scale value — the existing
`_buildPopup`/`_buildExplosion` curves happen to avoid this by construction
(their fractions are produced by exact multiplication, e.g. `(t-0.5)*2`,
which can't overshoot 1.0 the way a `/0.3` division can), so this bug was
specific to the new curve's math, not a pattern the older effects needed to
guard against — but any *new* animation curve doing non-exact division to
normalize `t` into a sub-range should clamp the input defensively from the
start. **Every** successful
placement (not just ones that clear a line —
this was a deliberate correction after an initial line-clear-only version
looked to a user like "the popup is appearing on every block for no
reason," when actually they wanted exactly that) sets `GameEngine.popup` (a
`ScorePopup` with the *total* points gained this move — base cell count
plus the bonus when a clear also happens — centered on the piece's own
landing spot, not the cleared line, since that's always defined whether or
not anything cleared) and bumps `popupSeq`. `BoardWidget` compares
`popupSeq` against what it last saw (in `didUpdateWidget`, since the same
`GameEngine` instance is reused across rebuilds so field equality can't
signal "this is a new event") and, on a change, spins up a short-lived
`AnimationController` rendering a rising, fading "+N" `Text`. Multiple
popups can be on-screen at once (each placement gets its own, independent
of whether an earlier one is still animating) — `_activePopups` is a list,
not a single slot, precisely so back-to-back placements each show their
own number rather than one clobbering another. Best score persists via `shared_preferences`
(`lib/services/score_service.dart`).

**Line-clear explosion** (`GameEngine.explosion`/`explosionSeq`, an
`ExplosionEvent` of `ExplosionCell{row,col,color}`; rendered by
`BoardWidget._buildExplosion`): exact same `popupSeq`-style "new event"
detection as the score popup (a monotonic counter `BoardWidget` diffs in
`didUpdateWidget`, since the same mutable `GameEngine` instance is reused
across rebuilds). Captured in `placePiece` at the same point `flashed` is
computed — **before** those cells get nulled a few lines later — since the
board itself has no record of a cell's color once it's cleared. Each
cleared cell spawns 6 small colored squares (its own color) flying outward
at evenly-spaced angles over 500ms, shrinking and fading via
`Curves.easeOut`/`easeIn` — runs on its own `AnimationController`
independent of (and longer than) the 160ms bright-flash-then-clear
`clearingCells` treatment already on `BlockCell`, so the shards keep
flying after the cell underneath has already gone empty. Like
`_activePopups`, `_activeExplosions` is a list so overlapping clears (rare
but possible with rapid placements) each get their own burst rather than
one replacing another.

**Survival mode / bomb tile** (`GameEngine.bomb`, a `BombTile { row, col,
secondsLeft }`, plus `kBombColor` in `game_engine.dart`): a bomb is a board
cell like any other — `board[row][col] = kBombColor` — so it's automatically
"occupied" for `canPlacePieceAt` (pieces can't be placed on it) and
automatically counts as "filled" toward its row/column being complete. This
means defusing a bomb reuses the *existing* line-clear machinery entirely:
no bomb-specific placement logic exists. `placePiece` only adds two bomb-
aware steps around that: (1) right after computing `fullRows`/`fullCols`
but before the clear-flash delay, if either contains the bomb's position,
set `bomb = null` (so the UI stops showing/ticking it — the board cell
itself gets nulled a few lines later along with the rest of the line, same
as any other cell); (2) `_maybeSpawnBomb()` runs unconditionally near the
end of every placement and is a no-op unless `mode == GameMode.survival &&
bomb == null`, so a **new** bomb appears on a random empty cell immediately
after the old one is defused — survival mode always has exactly one bomb
ticking once the first one spawns (in `start()`), by design, not as a
side effect. The countdown itself lives outside `placePiece` entirely: a
`Timer.periodic(Duration(seconds: 1), _tickBomb)` started in `start()`
(only for survival mode) and cancelled in `dispose()` and at the top of
every `start()` call (so restarting doesn't leak a second timer ticking
against the new game's `bomb` field) — `_tickBomb` decrements
`bomb!.secondsLeft` and sets `gameOver = true` at zero, **independent of**
whether any tray piece could still be placed (the two game-over conditions
are unrelated and either can fire first). `_tickBomb` no-ops while `paused`
(checked each tick rather than pausing/resuming the `Timer` itself — simpler
than tracking elapsed-time-at-pause). Tested in
`test/game_engine_test.dart`'s "survival mode bomb" group; the timeout path
specifically needs `testWidgets` (not plain `test`) so `tester.pump(duration)`
can fast-forward the real `Timer.periodic` — see that test's comment before
changing bomb timing logic.

**Back button = pause, not exit**: `GameScreen` uses `PopScope(canPop:
gameOver, onPopInvokedWithResult: ...)` to toggle the pause overlay instead
of popping mid-round — mandatory rule for every game in this series.

**Leaderboard (`lib/services/leaderboard_service.dart`)**: Google Play
Games Services, one leaderboard per `GameMode` (Classic/Survival aren't
comparable, same reason `ScoreService` tracks "best" per mode). Same
`games_services` package and defensive pattern as
[[project_number99_app]] (its `LeaderboardService` was the reference
implementation copied here): every call wrapped in try/catch, and an
`_isSupported` check (Android-only — this project has no iOS target) that
short-circuits to a safe no-op/`false` before ever touching a platform
channel. Both leaderboard IDs are now real (`CgkIje_cuZ8REAIQAQ` for
Classic, `CgkIje_cuZ8REAIQAg` for Survival — a Play Console project for
this app now exists). `GameScreen.initState()` calls
`LeaderboardService.signIn()` unawaited (**not** `GameEngine.start()` —
see the timer-leak note below for why it moved); `GameEngine` calls
`LeaderboardService.submitScore(mode, score)` unawaited at both game-over
paths (right next to the existing `ScoreService.saveBest` calls) — same
"call side-effect services directly from the engine" precedent already
established for `SoundService`/`HapticFeedback`. `HomeScreen` shows a
small trophy `IconButton` next to each mode's "Best: N" button that calls
`showLeaderboard(mode)`, falling back to a `SnackBar` ("Leaderboard not
available yet.") when it returns `false`.
- **Every platform call is wrapped in `.timeout(Duration(seconds: 5))`.**
  Discovered why the hard way: with a placeholder (unconfigured) ID,
  `showLeaderboard` short-circuited before ever calling
  `GameAuth.signIn()`, so a real platform-channel call was never actually
  exercised — the moment real IDs went in, a `testWidgets` test tapping
  the trophy button started failing with "Found 0 widgets" for the
  fallback SnackBar. A throwaway probe test (`await GameAuth.signIn()`
  inside a bare `testWidgets`, no timeout) confirmed the call hangs
  **forever** under `flutter_test` rather than throwing
  `MissingPluginException` — with no native handler registered, the
  outbound message just sits in Flutter's channel buffer waiting for a
  handler that never attaches, instead of being rejected the way an
  unregistered channel is commonly assumed to behave. This is the exact
  same failure class as the `flame_audio`/`AudioPool` hang documented
  under "Sound" below (and originally in
  [[project_number_master_app]]) — an unguarded platform-channel Future
  that can hang its caller forever. Fixed the same way: wrap every call in
  `.timeout(...)`. Since `Future.timeout` uses a real `Timer` internally,
  `flutter_test`'s fake clock resolves it deterministically via
  `tester.pump(Duration(seconds: 6))` — no real wall-clock wait needed,
  same mechanism already used for the bomb-countdown `Timer.periodic` test.
- **Timer-leak lesson, why `signIn()` moved out of `GameEngine.start()`.**
  `flutter_test`'s `testWidgets` fails a test outright ("A Timer is still
  pending even after the widget tree was disposed") if any real `Timer` —
  even one from a totally unrelated fire-and-forget side effect — is still
  running when the test ends. The bomb-timeout `testWidgets` test in
  `game_engine_test.dart` calls `engine.start()` directly (not through
  `GameScreen`), so a `signIn()` call fired from inside `start()` left its
  5s timeout `Timer` pending after that test's own ~1.1s pump, breaking a
  previously-passing test. Moved the `signIn()` call to
  `GameScreen.initState()` instead (mirroring number99's actual call site,
  not the engine) so `GameEngine`'s own tests — which construct/start
  engines directly, bypassing the screen — no longer trigger it at all.
  The *other* real trigger, `submitScore()` firing from the engine's own
  game-over paths, couldn't be moved the same way (it's intrinsic to
  `placePiece`/`_tickBomb`), so that same bomb-timeout test instead pumps
  an extra `Duration(seconds: 6)` after asserting `gameOver` — see its
  comment for why. **Any new `testWidgets` test that reaches a real
  game-over (or that mounts `GameScreen`) must budget for this — either
  pump ≥6s past that point, or the test will intermittently/consistently
  fail on a leftover Timer that has nothing to do with what the test is
  actually checking.**

This is functionally live now (real IDs, real Play Console project) but
still **cannot be verified end-to-end** without a real release-signed
build: Play Games ties sign-in to the app's signing certificate, and this
project has only ever built debug-signed test APKs so far (see
[[feedback_release_signing_setup]]). The `PLAY_GAMES_APP_ID` GitHub secret
(see `build-apk.yml`'s manifest patch step, mirroring the `ADMOB_APP_ID`
pattern) also still needs to be set from the Play Console project's Play
Games Services App ID before a CI-built APK can actually sign in. Until
both of those happen, every leaderboard call still safely times out/no-ops
— the game stays fully playable, "Best: N" per mode keeps working locally
via `ScoreService` exactly as before, and the trophy button shows the
fallback message.

**Ads (`lib/services/ads_service.dart`)**: same singleton pattern as the
other games in this series, currently on Google's public TEST ad unit IDs
(never swapped to real ones for this project yet). Interstitial shows
roughly every other finished game, not after every one.

**Sound (`lib/services/sound_service.dart`)**: `flame_audio` + `AudioPool`,
same pattern as [[project_dino_egg_shooter]]/number99-app — `sound_src/`
holds the source WAVs/MP3s, `assets/audio/` holds the bundled copies
actually declared in `pubspec.yaml` (keep both in sync if a sound is ever
added/replaced; there's no build step that copies one to the other).
`SoundEffect` enum values map 1:1 to trigger points: `place`/`clear` fire
from inside `GameEngine.placePiece` (same file, same spots as the existing
`HapticFeedback` calls — this project already established the precedent of
calling side-effect services directly from the engine rather than keeping
it strictly UI-decoupled); `pickupBack` fires from two places since a piece
can fail to place two different ways — `Draggable.onDraggableCanceled` in
`tray_widget.dart` (dropped outside any `DragTarget` entirely) and
`BoardWidget.onAcceptWithDetails`'s invalid-placement branch (dropped ON
the board but on a cell it doesn't fit); `confirm`/`back` fire from
`GameScreen`/`HomeScreen` button handlers (see their doc comments for the
exact confirm-vs-back mapping); `gameOver` (`m_failed.mp3`, the one MP3 in
an otherwise all-WAV set — `AudioPool` doesn't care about format) fires
from both places `gameOver` actually flips to `true` — the bomb-timeout
branch in `_tickBomb` and the tray-can't-fit branch after `_checkGameOver()`
in `placePiece` — right alongside the existing `ScoreService.saveBest`/
`LeaderboardService.submitScore` calls at each site, since both game-over
conditions are otherwise independent and neither reuses the other's code
path. `init()` is fired **unawaited** from
`main()`, each pool creation individually wrapped in try/catch +
`.timeout(5s)` — this exact pattern exists because of a real incident in
[[project_number_master_app]] where an unguarded `FlameAudio.createPool()`
Future never resolved on web, hanging the entire app before its first
frame; do not simplify this back to a bare `await`. Every `play()` call is
`_pools[effect]?.start()` — a safe no-op if that pool never finished
loading (or on `flutter test`, where no plugin is ever registered at all,
so `_pools` just stays empty; this is *why* `GameEngine`'s existing unit
tests never needed any audio mocking despite calling `placePiece` directly
— check this stays true before adding new sound trigger points).
**Known web-only limitation**: `flutter run -d chrome` / this project's
Playwright-verification path throws a console
`MissingPluginException(... audioplayers.global/events ...)` after
`SoundService.init()` runs, because `audioplayers`' web implementation
doesn't support a global event channel `flame_audio`'s `AudioPool` relies
on internally. This does not crash or block anything (confirmed via
Playwright: menus, dragging, and the sound toggle all still work
correctly with this warning present) — it's in the same category as
`AdsService` being a no-op on web, just noisier about it. Real sound
playback can only be verified on an actual Android build, not the web
preview used for the rest of this project's UI verification.

**Sound toggle** (`lib/widgets/sound_toggle_button.dart`, a
`SoundToggleButton` shared by `HomeScreen`'s AppBar and `GameScreen`'s
AppBar): reflects `SoundService.instance.enabledNotifier` via
`ValueListenableBuilder`, calls `.toggle()` (flips the notifier + persists
to `shared_preferences`) on tap. Deliberately just one shared widget
rather than separate implementations per screen — kept in
`lib/widgets/` (not screen-local) specifically so both screens use the
exact same instance/behavior. Placing it in `GameScreen`'s AppBar (rather
than inside `_PauseOverlay` itself) was a deliberate choice since the
AppBar stays visible above the pause overlay anyway, so a second copy
inside the overlay would just be a redundant duplicate control.

**GameScreen AppBar overflow (hardened, not conclusively reproduced,
2026-09-02)**: a live Chrome session threw a real `RenderFlex overflowed
by 79 pixels` in this AppBar's trailing actions slot
(`game_screen.dart:99`), with the actions `Row`'s constraints reported as
`BoxConstraints(0.0<=w<=1.0, 0.0<=h<=1.0)` — an almost perfectly
zero-width box. Investigated properly rather than guessing: built an
isolated width-sweep test harness (title + `SoundToggleButton` + pause
`IconButton`, pushed via a real `Navigator.push` so the auto leading
back-button is present, matching the real screen) and swept widths from
400px down to 140px. **The overflow did not reproduce at any width down
to 140px, for either the original config or the hardened one below** —
whatever produced a trailing constraint of ~1px live almost certainly
wasn't a *stable* narrow layout (which the tray-overflow bug in
`tray_widget.dart` was, and which a static width sweep like this reliably
catches), but something more like a *transient* one-frame layout pass
during an active browser window resize — Flutter web can genuinely see a
degenerate near-zero intermediate constraint mid-resize before the next
frame settles to the real size, which a `pumpWidget`-based test can't
easily force since it doesn't model a resize *in progress*, only discrete
before/after sizes. Given that, no regression test was added for this one
— a test that can't actually fail on the old code isn't a real regression
guard, and inventing narrower and narrower widths just to make an
assertion pass would have been theater, not verification.
Applied a real, low-risk hardening anyway since it's a pure improvement
regardless of root cause: `SoundToggleButton` and the pause `IconButton`
now use `padding: EdgeInsets.zero, constraints: const BoxConstraints()`
(dropping their default 48x48 minimum tap target down to just the icon's
own size — the same pattern already used for the home screen's trophy
leaderboard button), and the AppBar sets `titleSpacing: 0` with the title
`Text` given `overflow: TextOverflow.ellipsis`. **If this specific error
reappears with a *reproducible* width** (i.e. it happens again at a
stable window size you can note down), that's the signal this
investigation's "probably transient" conclusion was wrong — revisit with
that exact width in a test like the sweep described above, rather than
assuming it's still just a resize artifact.

**Background art** (`lib/widgets/app_background.dart`, an `AppBackground`
shared by both `HomeScreen` and `GameScreen`): a full-bleed
`Image.asset('assets/backgrounds/bg.png', fit: BoxFit.cover)` with a
`Colors.black` scrim (`alpha: 0.45`) stacked on top, then the screen's real
content on top of that. Source file kept at the repo root
(`bg.png`) as a reference, same relationship as `assets/block.png` and
`block-puzzle-plus-logo.png` — the bundled copy actually declared in
`pubspec.yaml` lives at `assets/backgrounds/bg.png`. Both screens set
`Scaffold.extendBodyBehindAppBar: true` and `AppBar.backgroundColor:
Colors.transparent` so the image (and scrim) show through behind the
AppBar too, rather than leaving a solid-color strip at the top —
`GameScreen` specifically needs a `SizedBox(height: kToolbarHeight)` as
the first item in its body `Column` to compensate (extending behind the
AppBar means `SafeArea` no longer accounts for the AppBar's own height,
only the system status bar). Gameplay legibility is unaffected by the
scrim's darkness — `BoardWidget`'s cells and the tray both paint their own
fully opaque backgrounds, so the scrim only shows through in the
padding/HUD areas around them, not through the board or pieces themselves.
