# CourtLife Timing Reference

> **Generated file.** Produced by `Docs/Animation/tools/timing_table.mjs` from `courtlife/src/core/jumpshot.js` and `dribble.js`
> (kept in parity with `Source/CourtLife/Core/CLJumpshot.cpp` / `CLDribble.cpp`). Do not hand-edit; re-run:
>
> `node CourtLifeUE/Docs/Animation/tools/timing_table.mjs > CourtLifeUE/Docs/Animation/TIMING_REFERENCE.md`

Authoring rate is **60 fps**. Frame numbers are 0-based from the first frame of the clip; fractional frames mean the notify sits between frames (Unreal notifies are time-based, so place them by **time in seconds**, not by frame).

## 1. Jumpshot bases

Core rule: `playRate = lerp(0.8, 1.25, (speed-1)/4) * releaseTempo`, `durationMs = round(1050 / playRate)`, `releaseT = clamp(base.releaseT + base.hitch*0.5, 0.5, 0.85)`, `releaseTimeMs = round(durationMs * releaseT)`.
So every base montage must be authored **exactly 1050 ms = 63 frames @ 60 fps** long; the montage then plays at `FCLShotProfile::PlayRate` and lasts exactly `DurationMs`.

### 1a. Release notify placement (authored time, play rate 1.0)

| Base ID | code releaseT | hitch | effective releaseT | Release notify time (s) | Release notify frame @60 | Montage length |
|---|---|---|---|---|---|---|
| `classic` | 0.66 | 0 | 0.66 | 0.6930 | 41.58 | 1.0500 s / 63 f |
| `quickSet` | 0.58 | 0 | 0.58 | 0.6090 | 36.54 | 1.0500 s / 63 f |
| `highSet` | 0.7 | 0 | 0.70 | 0.7350 | 44.10 | 1.0500 s / 63 f |
| `sideSet` | 0.64 | 0 | 0.64 | 0.6720 | 40.32 | 1.0500 s / 63 f |
| `oneMotion` | 0.62 | 0 | 0.62 | 0.6510 | 39.06 | 1.0500 s / 63 f |
| `setShot` | 0.6 | 0 | 0.60 | 0.6300 | 37.80 | 1.0500 s / 63 f |
| `legKick` | 0.68 | 0 | 0.68 | 0.7140 | 42.84 | 1.0500 s / 63 f |
| `hitch` | 0.74 | 0.12 | 0.80 | 0.8400 | 50.40 | 1.0500 s / 63 f |

### 1b. Duration and release time by shot speed (neutral release: `smoothHold`, tempo 1.00)

Each cell is `durationMs / releaseTimeMs`. These are the values the shot meter uses (`FCLShotProfile::DurationMs` / `ReleaseTimeMs`).

| Base ID | Speed 1 | Speed 2 | Speed 3 | Speed 4 | Speed 5 |
|---|---|---|---|---|---|
| `classic` | 1313 / 867 | 1151 / 760 | 1024 / 676 | 923 / 609 | 840 / 554 |
| `quickSet` | 1313 / 762 | 1151 / 668 | 1024 / 594 | 923 / 535 | 840 / 487 |
| `highSet` | 1313 / 919 | 1151 / 806 | 1024 / 717 | 923 / 646 | 840 / 588 |
| `sideSet` | 1313 / 840 | 1151 / 737 | 1024 / 655 | 923 / 591 | 840 / 538 |
| `oneMotion` | 1313 / 814 | 1151 / 714 | 1024 / 635 | 923 / 572 | 840 / 521 |
| `setShot` | 1313 / 788 | 1151 / 691 | 1024 / 614 | 923 / 554 | 840 / 504 |
| `legKick` | 1313 / 893 | 1151 / 783 | 1024 / 696 | 923 / 628 | 840 / 571 |
| `hitch` | 1313 / 1050 | 1151 / 921 | 1024 / 819 | 923 / 738 | 840 / 672 |

Play rate per speed with the neutral release (same for every base):

| | Speed 1 | Speed 2 | Speed 3 | Speed 4 | Speed 5 |
|---|---|---|---|---|---|
| PlayRate | 0.8000 | 0.9125 | 1.0250 | 1.1375 | 1.2500 |
| DurationMs | 1313 | 1151 | 1024 | 923 | 840 |

**Sync check** (all 8 bases x 7 releases x 5 speeds): a 1050 ms montage played at PlayRate ends within **0.50 ms** of `DurationMs` and hits its Release notify within **0.75 ms** of `ReleaseTimeMs` (rounding only; under one 60 fps frame = 16.67 ms).

### 1c. Release tempo (each release used alone, blend 0, Speed 3)

Releases change the play rate of the whole shot through `tempo`. Blended releases lerp tempo by `ReleaseBlend`.

| Release ID | tempo | PlayRate @ Speed 3 | DurationMs @ Speed 3 | ReleaseTimeMs (`classic`) | Speed 1 → 5 duration range |
|---|---|---|---|---|---|
| `quickFlick` | 1.15 | 1.1787 | 891 | 588 | 1141 → 730 ms |
| `highArc` | 0.95 | 0.9737 | 1078 | 711 | 1382 → 884 ms |
| `push` | 1 | 1.0250 | 1024 | 676 | 1313 → 840 ms |
| `smoothHold` | 1 | 1.0250 | 1024 | 676 | 1313 → 840 ms |
| `guideFlare` | 1.02 | 1.0455 | 1004 | 663 | 1287 → 824 ms |
| `slingshot` | 1.1 | 1.1275 | 931 | 614 | 1193 → 764 ms |
| `wristy` | 1.08 | 1.1070 | 949 | 626 | 1215 → 778 ms |

Across every base, release and speed, ReleaseTimeMs spans **423–1106 ms** after the button press.

## 2. Dribble moves

Core rule: `segmentMs = durationMs / speed`, speed clamped to [0.6, maxStepSpeed(BallHandle)], `maxStepSpeed = lerp(1.0, 1.5, invLerp(60, 99, BallHandle))`. `UCLDribbleComponent` plays each montage at `PlayLength / segmentMs`, so author at natural speed; if you author the clip at exactly `durationMs` the play rate equals the step speed.

| Move ID | Min Ball Handle | durationMs (1.0x) | Frames @60 | 0.6x ms | 1.0x ms | 1.5x ms |
|---|---|---|---|---|---|---|
| `crossover` | 25 | 380 | 22.80 | 633.3 | 380.0 | 253.3 |
| `killCross` | 75 | 300 | 18 | 500.0 | 300.0 | 200.0 |
| `betweenLegs` | 45 | 420 | 25.20 | 700.0 | 420.0 | 280.0 |
| `behindBack` | 55 | 460 | 27.60 | 766.7 | 460.0 | 306.7 |
| `hesitation` | 35 | 520 | 31.20 | 866.7 | 520.0 | 346.7 |
| `inAndOut` | 40 | 400 | 24 | 666.7 | 400.0 | 266.7 |
| `spin` | 50 | 560 | 33.60 | 933.3 | 560.0 | 373.3 |
| `stepBack` | 45 | 480 | 28.80 | 800.0 | 480.0 | 320.0 |
| `snatchBack` | 80 | 440 | 26.40 | 733.3 | 440.0 | 293.3 |
| `pound` | 25 | 260 | 15.60 | 433.3 | 260.0 | 173.3 |

Ball Handle needed to set a step to each speed: 0.6x → any, 1.0x → any, 1.5x → 99 (plus the move's own minimum).

### 2a. Contact frames, hand switch and displacement (authored at 1.0x, right-hand start)

Floor contacts come from the core ball keyframes (`ball.y == 0.38 ft`, the ball radius). Hand switch is where `SampleCombo` flips `hand` (local t > 0.5). Burst is the total displacement in ft; the core eases it in with `sin(t·π/2)`. Lean/rise peak at local t = 0.5 (`sin(t·π)`).

| Move ID | Floor contact t | Contact ms / frame @60 | Hand switch ms / frame @60 | Burst R-start (x, z) ft | Burst L-start (x, z) ft | Peak lean | Peak rise | Yaw |
|---|---|---|---|---|---|---|---|---|
| `crossover` | 0.45 | 171 / 10.26 | 190 / 11.40 | (0.80, 0.40) | (-0.80, 0.40) | 0.25 | 0.00 | 0 |
| `killCross` | 0.45 | 135 / 8.10 | 150 / 9 | (1.20, 0.60) | (-1.20, 0.60) | 0.45 | 0.00 | 0 |
| `betweenLegs` | 0.5 | 210 / 12.60 | 210 / 12.60 | (0.00, -0.30) | (0.00, -0.30) | 0.20 | 0.00 | 0 |
| `behindBack` | 0.6 | 276 / 16.56 | 230 / 13.80 | (0.60, 0.30) | (-0.60, 0.30) | 0.15 | 0.00 | 0 |
| `hesitation` | 0.65 | 338 / 20.28 | no switch | (0.00, 1.60) | (0.00, 1.60) | -0.15 | 0.25 | 0 |
| `inAndOut` | 0.7 | 280 / 16.80 | no switch | (-0.60, 0.50) | (0.60, 0.50) | 0.30 | 0.00 | 0 |
| `spin` | — | — | 280 / 16.80 | (1.40, 1.20) | (-1.40, 1.20) | 0.10 | 0.00 | 360° (R start: turns left, counter-clockwise from above; L start: clockwise) |
| `stepBack` | 0.4 | 192 / 11.52 | no switch | (0.00, -2.60) | (0.00, -2.60) | -0.30 | 0.00 | 0 |
| `snatchBack` | 0.35 | 154 / 9.24 | no switch | (0.00, -2.00) | (0.00, -2.00) | -0.35 | 0.00 | 0 |
| `pound` | 0.5 | 130 / 7.80 | no switch | (0.00, 0.00) | (0.00, 0.00) | 0.10 | 0.00 | 0 |

Axis convention for the burst columns: core local space, player faces +z, **+x is the player's left** (the core puts the right side at -x). A right-hand crossover therefore moves +0.80 ft to the left and 0.40 ft forward. In Unreal mesh space (+X forward, +Y right) that is X = +z·30.48 uu, Y = -x·30.48 uu.

### 2b. Default combos (Ball Handle 99, right-hand start)

| Combo | Segments (move @ start–end ms, hand) | Total ms | End hand | End offset (x, z) ft |
|---|---|---|---|---|
| Cross Step | crossover @ 0–380 (R); stepBack @ 380–860 (L) | 860 | L | (0.80, -2.20) |
| Hesi Go | pound @ 0–260 (R); hesitation @ 260–780 (R) | 780 | R | (0.00, 1.60) |
| Legs Behind | betweenLegs @ 0–420 (R); behindBack @ 420–880 (L) | 880 | R | (-0.60, 0.00) |
| Spin | spin @ 0–560 (R) | 560 | L | (1.40, 1.20) |

