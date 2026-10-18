# CourtLife Vertical-Slice Mocap Shot List

Owner: Animation. Naming follows [NAMING.md](NAMING.md). Every timing number comes from [TIMING_REFERENCE.md](TIMING_REFERENCE.md), which is generated from the core code.

## 0. Session setup

| Item | Spec |
|---|---|
| Performer | One hero hooper, right-handed shooter, **6'4"–6'8"** (close to the 6'6" reference skeleton, so retarget distortion stays small). A second, taller performer (6'10"+) for defense, contests and rebounds is optional (day 4–5). |
| Volume | At least 30 × 20 ft capture area with a sprung hardwood or sport-court floor. A portable rim at 10 ft is needed for shots and rebounds; mark the 23.75 ft arc if the volume allows. |
| Ball | Regulation size 7 with markers (optical) or a plain ball plus a 120 fps witness camera (inertial). Have a rebounder or ball return on stage. |
| Rate | 120 Hz capture, delivered at 60 fps (NAMING §5). |
| Shoes | Basketball shoes. Same pair all week (foot contact cleanup is calibrated to them). |
| Per take | Start and end in the named rest pose for 1 s. Slate with the asset name from this doc plus the take number. |
| Click track | A metronome in the performer's ear for shots and dribble moves (see §2.3 and §3). |
| Reference video | Two 120 fps witness cameras (front and side). These are mandatory for ball contacts. |

**Takes column** = takes to record. **Selects** = clips that ship. Priority **P0** = needed for the vertical slice, **P1** = capture now while the performer is booked, ship later.

---

## 1. Rest poses (start and end of clips)

| Name | Description |
|---|---|
| `TripleThreat_R` | Ball at right hip, knees bent (about 30° knee flex), feet shoulder-width, chest to the rim. This is where **every shot base starts**. |
| `DribbleReady_R` / `_L` | Ball in the hand at about 2.0–2.3 ft high, 0.7 ft in front and 0.85 ft to the hand side (the core ball keyframe `t=0`). Spine pitched forward about 14° (prototype spine 0.25 rad). Every dribble move starts **and ends** here. |
| `DefStance` | Wide stance, hips low, hands active, facing the ball handler. |
| `Neutral` | Relaxed standing, no ball. |

---

## 2. Jumpshot

### 2.1 How code parameters become performance direction

These are translated from `SHOT_BASES` / `SHOT_RELEASES` and the prototype pose keys in `sampleShotPose` (`courtlife/src/core/jumpshot.js`). Angles are joint rotations from the rest stance.

| Code param | What the performer does |
|---|---|
| `setPoint` (0–1) | Height of the set (ball at the top of the gather, before the push). The shoulder flexes `1.7 + setPoint·1.1` rad: 0.3 ≈ 116° (ball at the chin), 0.5 ≈ 129° (nose), 0.7 ≈ 141° (forehead), 1.0 ≈ 160° (above the head). |
| `dip` (0–1) | Ball and hip dip at 22% of the motion: pelvis drops `dip·0.9 ft` (0.22 ≈ 2.4 in, 0.35 ≈ 3.8 in, 0.5 ≈ 5.4 in) and the knees load by an extra `dip·1.2` rad. |
| `jump` (0–1.05) | **Reference jump** = pelvis rise of `jump` ft at the release frame (1.0 ≈ 12 in, 0.15 ≈ 2 in, i.e. barely leaving the floor). In game it scales 0.6×–1.6× with Vertical (the ABP does this from the `JumpArc` curve, so record the reference height, not your max jump). The peak sits **at** the release. |
| `legKick` (0–0.9) | Right leg kicks at release: hip flexes `0.6·kick` rad, knee bends `0.9·kick` rad and the leg swings out `0.25·kick` rad. At 0.9 that is about 31° hip, 46° knee, 13° out. 0.1–0.2 is a small natural knee bend. |
| `flare` (0–0.55) | Shooting elbow flares out at the set: `0.7·flare` rad. 0.05 ≈ 2° (elbow tucked), 0.55 ≈ 22° (side set, ball set over the right eye). |
| `releaseT` | Where the release falls in the 1.05 s master, perform to the click (§2.3). |
| `drift` (0–0.3) | Body drifts back by `drift` ft by landing (0.1 ≈ 1.2 in, 0.3 ≈ 3.6 in fade). |
| `hitch` (0–0.12) | Pause at the set point for `hitch × 1.05 s` (0.12 → 126 ms) before the push. The release moves later by `hitch/2`. |
| `extension` (release) | Elbow at the release frame: residual bend `0.15 + (1−ext)·0.9` rad. 1.0 = full lock-out (about 9°), 0.7 ≈ 24° left (a push). |
| `snap` (release) | Wrist flexion: `0.9·snap` rad at the release, `1.2·snap` in the follow-through. 1.0 = full goose-neck (about 52° → 69°), 0.4 = barely any wrist. |
| `follow` (release) | Follow-through hold: arm held up for `(0.10 + 0.08·follow) × 1.05 s` after the release (0.3 ≈ 130 ms, 1.0 ≈ 189 ms), then the arm stays high (shoulder ends at `1.2 + 0.8·follow` rad). |
| `height` (release) | Shoulder at the release `2.55 + 0.4·height` rad: 0.3 ≈ 153° (a flat push), 1.0 ≈ 169° (arm almost vertical, high release). |
| `guideOff` (release) | Guide (left) hand at the release: abducts `0.35 + 0.6·guideOff` rad from the ball, elbow opens by `0.4·guideOff`. 0.2 = stays beside the ball, 1.0 = flares well wide (about 54°). |
| `tempo` (release) | **Don't perform it.** The engine applies tempo through `PlayRate` (0.95–1.15). Perform every release on the same click. |

### 2.2 Bases — 8 (P0) + entry variants (P1)

Each base is captured **full body**, from `TripleThreat_R`, with a **neutral release** (a moderate full extension, like `smoothHold`), so the upper body arrives at the set naturally. Only the lower body and the set (pelvis through the set point) are used under the release layer; see §2.4.

| Base ID | Asset | setPoint | dip | jump (ref.) | legKick | flare | releaseT (eff.) | drift | hitch | Direction | Takes | Selects |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `classic` | `AM_Shot_Base_classic` | 0.7 forehead | 0.35 (3.8 in) | 1.0 ft | 0 | 0.1 | 0.66 → **0.693 s** | 0 | 0 | Textbook: medium dip, set at the forehead, straight-up jump, release at the peak. **Also the reference base for releases.** | 6 | 1 |
| `quickSet` | `AM_Shot_Base_quickSet` | 0.3 chin | 0.22 (2.4 in) | 0.8 ft | 0 | 0.05 | 0.58 → **0.609 s** | 0 | 0 | Low and fast: shallow dip, ball goes chin to release, releases on the way up. | 6 | 1 |
| `highSet` | `AM_Shot_Base_highSet` | 1.0 above head | 0.40 (4.3 in) | 1.05 ft | 0 | 0.05 | 0.70 → **0.735 s** | 0 | 0 | Big wind-up: ball travels up past the forehead to above the head, release at or just after the peak. | 6 | 1 |
| `sideSet` | `AM_Shot_Base_sideSet` | 0.6 nose/right eye | 0.30 (3.2 in) | 0.95 ft | 0.1 | **0.55 (22°)** | 0.64 → **0.672 s** | 0 | 0 | Ball set to the right of the head, elbow out, slight right knee bend. | 6 | 1 |
| `oneMotion` | `AM_Shot_Base_oneMotion` | 0.55 nose | **0.50 (5.4 in)** | 0.9 ft | 0 | 0.15 | 0.62 → **0.651 s** | 0.1 (1.2 in) | 0 | Continuous: no stop at the set. Deep dip flows straight into the release, slight drift back. | 6 | 1 |
| `setShot` | `AM_Shot_Base_setShot` | 0.5 nose | 0.30 (3.2 in) | **0.15 ft (≈2 in)** | 0 | 0.1 | 0.60 → **0.630 s** | 0 | 0 | Toes only, feet barely leave the floor. Rhythm comes from the knees. | 6 | 1 |
| `legKick` | `AM_Shot_Base_legKick` | 0.75 forehead | 0.35 (3.8 in) | 1.0 ft | **0.9** | 0.15 | 0.68 → **0.714 s** | **0.3 (3.6 in)** | 0 | Right leg kicks forward and out at the release, fading back about 3.6 in. Land on the left foot first. | 6 | 1 |
| `hitch` | `AM_Shot_Base_hitch` | 0.85 high forehead | 0.35 (3.8 in) | 1.0 ft | 0.2 | 0.1 | 0.74 + 0.06 → **0.840 s** | 0 | **0.12 (126 ms hold)** | Rise, **pause at the set** about 126 ms, then push. The release falls late (0.80 of the motion). | 6 | 1 |
| *(P1)* each base `_Pullup_R` / `_Pullup_L` | `AM_Shot_Base_<id>_Pullup_<R\|L>` | same | same | same | same | same | same | same | same | Starts from a live dribble in the R or L hand (a one-two step into the gather), same click after the gather | 8×2×4 = 64 | 16 |
| *(P1)* each base `_Catch_R` | `AM_Shot_Base_<id>_Catch_R` | same | | | | | | | | Catch-and-shoot, pass from the front-left | 8×3 = 24 | 8 |

### 2.3 Click track (shared tempo)

So that **any base blends with any two releases**, all shots are performed on the same rhythm:

- The click loop is **1.050 s** with three cues. Cue 1 is "go" (button press, start of the clip). Cue 2 is the **dip bottom** at 0.231 s (22% of the motion). Cue 3 is the **release** at the base's release time from the table (for example classic 0.693 s, hitch 0.840 s).
- The performer leaves `TripleThreat_R` on cue 1 and lets the ball go on cue 3. The editor retimes each select so the release lands exactly on the base's Release time (TIMING_REFERENCE §1a) and the clip is exactly 63 frames. Use a time-warp curve only, no frame drops.
- **Releases are performed on the classic click** (release at 0.693 s) and then cut to the 45-frame release layout (NAMING §8: release at frame 18).

### 2.4 Capturing releases separately (spine_01 split)

| Rule | Why |
|---|---|
| Releases are recorded as full-body shots **on the `classic` base** (set at the forehead, 1.0 ft jump), but only `spine_01` and above is kept. | The release layer in ABP_Baller is a layered blend at `spine_01` (ANIM_BLUEPRINT §4). Recording on one reference base keeps the shoulders and torso consistent, so a release sits on any base. |
| Each release is also recorded once on `quickSet` and once on `highSet`. These are **compatibility check takes**, not shipped. | They show whether a release reads at the lowest and highest set points. If a release only looks right from a high set, flag it. |
| The set pose at the start of the release clip (frames 0–6) must match the `classic` set: ball at the forehead, elbow under the ball, guide hand on the side of the ball. | The release layer ramps in over the 0.20 s before the release, which starts from about this pose on every base. |
| No lower-body acting, a normal jump; keep the torso pitch neutral (≤5° lean). | The lower body is discarded, and torso lean would fight the base's spine. |
| The ball leaves the fingers on click cue 3, then **hold** the follow-through for the duration in the table, then relax the arms. | The release frame is pinned at frame 18 of the release clip. |
| All 7 releases are performed on the same click (tempo 1.0). | Tempo comes from `PlayRate` in engine; the core lerps it between the two releases. |

| Release ID | Asset | extension | snap | follow (hold) | height | guideOff | tempo (engine) | Direction | Takes (classic + 2 checks) | Selects |
|---|---|---|---|---|---|---|---|---|---|---|
| `quickFlick` | `A_Shot_Release_quickFlick` | 0.8 (≈19° bend left) | **1.0** | 0.3 (130 ms) | 0.45 (≈156°) | 0.3 | 1.15 | Short arm, all wrist, quick and low follow-through that drops early. | 6 + 2 | 1 |
| `highArc` | `A_Shot_Release_highArc` | **1.0** lock-out | 0.8 | 0.85 (≈176 ms) | **1.0 (≈169°)** | 0.4 | 0.95 | Arm nearly vertical, high soft arc, long hold. | 6 + 2 | 1 |
| `push` | `A_Shot_Release_push` | 0.7 (≈24° left) | 0.4 | 0.4 (≈139 ms) | 0.3 (≈153°) | 0.2 | 1.00 | Flat push from the shoulder, little wrist, guide hand stays on the ball. | 6 + 2 | 1 |
| `smoothHold` | `A_Shot_Release_smoothHold` | **1.0** | 0.9 | **1.0 (189 ms)** | 0.8 (≈164°) | 0.5 | 1.00 | Full extension, full goose-neck, longest hold. **Also the neutral release used in base takes.** | 6 + 2 | 1 |
| `guideFlare` | `A_Shot_Release_guideFlare` | 0.9 | 0.9 | 0.6 (≈155 ms) | 0.7 (≈162°) | **1.0 (≈54° out)** | 1.02 | Guide hand flares wide and away at the release; fingers splay. | 6 + 2 | 1 |
| `slingshot` | `A_Shot_Release_slingshot` | 0.85 | 0.7 | 0.5 (≈147 ms) | 0.55 (≈159°) | 0.35 | 1.10 | Ball dips slightly behind the head, then whips through. Keep the set pose at frames 0–6 per the rule above. | 6 + 2 | 1 |
| `wristy` | `A_Shot_Release_wristy` | 0.75 | **1.0** | 0.7 (≈164 ms) | 0.6 (≈160°) | 0.25 | 1.08 | Exaggerated wrist cock and flick, relaxed arm, medium hold. | 6 + 2 | 1 |

**Jumpshot totals:** P0 = 48 base takes + 56 release takes = 104 takes, 15 selects. P1 = 88 takes, 24 selects.

---

## 3. Dribble moves — 10 moves × 2 hands (P0) × 3 speeds (natural P0, slow and fast P1)

Each move is performed **starting from `DribbleReady_<hand>`** and **ending in `DribbleReady_<end hand>`**, with one pound dribble before and after as handles (trimmed off). The performer works on a click at the move's `durationMs` (natural), at 0.6× (slow) and at 1.5× (fast, only possible for 99 Ball Handle in game). Slow and fast takes are reference for how the engine time-scaling should look; the shipped montage is the natural take.

Directions use the **player's own left and right**. Burst is the total displacement over the move (code `burst`, in feet, `x` relative to the starting hand: a negative code x means toward the other hand's side). Lean = extra forward spine pitch at mid-move in radians (negative = upright or back). Rise = leg straightening at mid-move (hesitation only). Ball keys are from `DRIBBLE_MOVES[*].ball`: lateral offset = `s × 0.85 ft` toward the starting hand, height `y` ft, forward `z` ft.

| Move ID | R asset / L asset | durationMs (1.0x) | Min Ball Handle | Switches hand | Burst from R start | Burst from L start | Lean / rise | Ball path and contacts (from the code keys) | Direction | Takes (2 hands × 3 speeds × 4) | Selects |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `crossover` | `AM_Dribble_crossover_R` / `_L` | 380 | 25 | Yes, at 190 ms | 0.8 ft left, 0.4 ft fwd | 0.8 ft right, 0.4 ft fwd | +0.25 / 0 | Hand at 2.3 ft high, 0.7 fwd → floor at the center line 0.9 fwd at **45% (171 ms)** → other hand 2.3 ft high | Standard crossover in front of the body, push off the starting-hand foot. | 24 | 2 |
| `killCross` | `AM_Dribble_killCross_R` / `_L` | 300 | 75 | Yes, at 150 ms | **1.2 ft left, 0.6 fwd** | 1.2 ft right, 0.6 fwd | **+0.45** / 0 | Low and hard: 1.6 ft high → floor center 1.0 fwd at **45% (135 ms)** → 1.6 ft other hand | Low, violent cross, big shoulder dip and an explosive lateral push. | 24 | 2 |
| `betweenLegs` | `AM_Dribble_betweenLegs_R` / `_L` | 420 | 45 | Yes, at 210 ms | 0, 0.3 ft **back** | 0, 0.3 ft back | +0.20 / 0 | 2.2 ft → floor between the feet 0.05 fwd at **50% (210 ms)** → 2.2 ft other hand | Starting-hand-side foot steps forward, bounce through the legs, slight retreat. | 24 | 2 |
| `behindBack` | `AM_Dribble_behindBack_R` / `_L` | 460 | 55 | Yes, at 230 ms | 0.6 ft left, 0.3 fwd | 0.6 ft right, 0.3 fwd | +0.15 / 0 | 2.2 ft, 0.4 fwd → wraps behind at hip height (1.2 ft, 0.7 **behind**) at 35% → floor behind on the other side (0.5 behind) at **60% (276 ms)** → 2.2 ft other hand 0.5 fwd | Wrap behind the hips while stepping across. | 24 | 2 |
| `hesitation` | `AM_Dribble_hesitation_R` / `_L` | 520 | 35 | No | 0, **1.6 ft fwd** | 0, 1.6 ft fwd | −0.15 / **+0.25** | 2.3 ft → **rises to 2.9 ft** at 30% (sell the pause) → hard to the floor 1.1 fwd, slightly outside, at **65% (338 ms)** → 2.3 ft | Stand tall and slow (legs straighten, chest up), then explode forward. | 24 | 2 |
| `inAndOut` | `AM_Dribble_inAndOut_R` / `_L` | 400 | 40 | No | **0.6 ft right** (toward the ball hand), 0.5 fwd | 0.6 ft left, 0.5 fwd | +0.30 / 0 | 2.3 ft → fakes in toward center (lateral 0.17 ft, 1.8 ft high) at 40% → back out to the floor outside (lateral 0.94 ft) at **70% (280 ms)** → 2.3 ft | Head and shoulder fake toward the cross, ball comes back out the same side. | 24 | 2 |
| `spin` | `AM_Dribble_spin_R` / `_L` | 560 | 50 | Yes, at 280 ms | **1.4 ft left, 1.2 fwd** | 1.4 ft right, 1.2 fwd | +0.10 / 0 | Ball carried (no floor contact in the core keys): 2.0 ft → 2.4 ft high, 0.2 behind at 50% → 2.0 ft other hand | **Full 360°.** From R: turn to the player's left (counter-clockwise from above), the core's sign. From L: clockwise. The core rotates the actor `yaw = ±2π·t`, so the clip must also be a true 360°. | 24 | 2 |
| `stepBack` | `AM_Dribble_stepBack_R` / `_L` | 480 | 45 | No | 0, **2.6 ft back** | 0, 2.6 ft back | **−0.30** / 0 | 2.3 ft → floor at **40% (192 ms)** → gathers high 2.5 ft, slightly inside (s 0.6) | Hard plant and push back, about 2.6 ft. Land balanced and shot-ready. | 24 | 2 |
| `snatchBack` | `AM_Dribble_snatchBack_R` / `_L` | 440 | 80 | No | 0, **2.0 ft back** | 0, 2.0 ft back | **−0.35** / 0 | Ball out front 1.0 fwd → floor far out 1.3 fwd at **35% (154 ms)** → yanked back to the hip (0.3 fwd, 2.4 ft high) | Reach-out dribble, then snatch it back with a two-foot hop back. | 24 | 2 |
| `pound` | `AM_Dribble_pound_R` / `_L` | 260 | 25 | No | 0, 0 | 0, 0 | +0.10 / 0 | 2.0 ft → floor at **50% (130 ms)** → 2.0 ft, same spot | One hard pound dribble in place. Also the chaining glue between moves. | 24 | 2 |
| *(P0)* stationary loops | `A_Dribble_Loop_<Pound\|Low\|Rhythm\|Crossover>_<R\|L>` | loops of ~4 s | — | — | in place | | | | Rhythm dribbles for idle-with-ball (MM) | 4×2×3 = 24 | 8 |

**Dribble totals:** 240 move takes (80 natural P0 + 160 slow and fast P1) plus 24 loop takes. Selects: 20 move montages plus 8 loops (P0).

Capture rules for moves:
- The **left-hand version is performed, not mirrored.** Mirroring is only the fallback (`FCLHandedMontage.Left` empty).
- Hit the floor contact on the click sub-beat at the % given; the editor aligns the contact to TIMING_REFERENCE §2a ±1 frame.
- End facing the same direction as the start (except `spin`, which ends after exactly 360°), so chained moves don't drift in yaw. The core expects zero net yaw on non-spin moves.
- Displacement must match the burst within ±0.2 ft, because the core moves the actor by exactly the burst in v1. Tape floor marks for the end position of each move from both hands.

---

## 4. Locomotion for Motion Matching

Target speeds come from code. With the ball and without it, the player moves at **8–14 ft/s** by SpeedWithBall (`BaseWalkSpeed`), **×1.35 sprinting = up to 18.9 ft/s**. Acceleration is 25–55 ft/s², braking 78.7 ft/s² (2400 uu/s²). Defenders move at 9–14 ft/s. **With the ball the player always faces the rim** (`ACLBallerCharacter::Tick`), so with-ball locomotion is **strafing locomotion**: all 8 directions at every gait while the chest stays forward. Without the ball, the character faces the velocity (forward locomotion plus turns).

Gaits to perform: Walk ≈ 4 ft/s, Jog ≈ 9 ft/s, Run ≈ 13 ft/s, Sprint ≈ 17–19 ft/s.

| Set | Contents | Dirs | Gaits | Takes | Notes |
|---|---|---|---|---|---|
| **Ball: idle** | `DribbleReady` idle with rhythm dribbles, weight shifts, looks around, ball-hand swaps via pound-cross | — | — | 6 (3 per hand) × 60 s | MM idle coverage. Ball hand R and L. |
| **Ball: starts** | From idle to a run in each direction | 8 | Jog, Run, Sprint | 8×3×2 hands = 48 | Chest stays to the "rim" (a marker on the wall) the whole time |
| **Ball: stops** | From a run to idle | 8 | Jog, Run, Sprint | 48 | Hard plant on Sprint, 2–3 steps on Jog |
| **Ball: strafes / loops** | Steady-state straight lines, about 25 ft each | 8 | Walk, Jog, Run, Sprint | 8×4×2 = 64 | Backpedal-sprint (B/Sprint) is awkward but needed while the code faces the rim (see ANIM_BLUEPRINT request R6) |
| **Ball: plants / direction changes** | 45/90/135/180° direction changes while strafing | 8 → 8 (key pairs) | Jog, Run | 32 | Covers fast handler juking without a combo |
| **Ball: circles and figure 8s** | Constant-radius curves, CW and CCW, 3 radii | — | Jog, Run | 12 | Dense trajectory coverage |
| **Ball: dribble-jog dance cards** | 3 min random-direction free play on a caller's cues | — | mixed | 4 × 3 min (2 per hand) | Fills the gaps in the database |
| **No ball: idle** | Neutral idle, hands on knees, clap for the ball | — | — | 4 × 60 s | |
| **No ball: starts** | Forward start plus start with turn 45/90/135/180 L/R | F + 8 turns | Jog, Run, Sprint | 27 | Faces velocity |
| **No ball: stops** | Forward stops plus stop-and-turn to face the rim | F | Jog, Run, Sprint | 12 | |
| **No ball: pivots** | Running pivots (plant and cut) 45/90/135/180 L/R | 8 | Run, Sprint | 32 | |
| **No ball: turn in place** | 45/90/135/180 L/R | 8 | — | 16 | |
| **No ball: loops / circles** | Straight loops plus circles | F + curves | Walk to Sprint | 16 | |
| **No ball: dance cards** | 3 min free running | — | mixed | 3 × 3 min | |

Coverage guidance:
- Cover each (direction × gait) cell with ≥ 2 s of steady-state motion and ≥ 2 transitions in and out. A cell with less shows up as foot sliding or snapping in the PoseSearch debugger.
- Every with-ball take keeps a **live dribble with `ball_prop` keyed** and `BallInHand_*` / `BallContact_Floor` curves. Dribble rate: about 2 bounces/s walking, 3/s running. The ball stays in one hand per take (R or L database).
- Perform every gait at the **target speed**, not by feel. Use a pacer line or call times over 25 ft (Jog ≈ 2.8 s, Run ≈ 1.9 s, Sprint ≈ 1.4 s).
- Stops must reach a full stop within the braking implied by 78.7 ft/s² (from 14 ft/s that is about 0.18 s and 1.2 ft). Sprint stops will look abrupt; capture a "hard plant" version.

**Locomotion totals:** about 330 takes, including 10 long dance-card or idle takes.

---

## 5. Defense

| Set | Asset(s) | Contents | Takes | Selects | Code hook |
|---|---|---|---|---|---|
| Stance idle | `A_Def_Stance_Idle_01..03` | Active stance, hand flicks, chop steps | 3 × 45 s | 3 | MM `PSD_Loco_Defense` |
| Slides | `A_Def_Slide_<L\|R>_<Walk\|Jog>_nn` | Lateral defensive slides, plus starts and stops | 2 dirs × 2 gaits × (loop + start + stop) × 2 = 24 | 12 | Defender always faces the handler (`ACLDefenderController` interp 12) |
| Backpedal / drop / turn-and-run | `A_Def_Backpedal_*`, `A_Def_Turn_<L\|R>_*` | Retreat steps, hip turn into a run (open the gate) at 45/90/135 | 20 | 10 | Speeds 9–14 ft/s |
| Closeout | `AM_Def_Closeout_01..02` | Sprint 10 ft → chop steps → hand high | 8 | 2 | P1 (no code trigger yet) |
| Contest | `AM_Def_Contest_<R\|L\|Both>_01` | Jump contest, hand up at the shooter, 0.80 s. **Perform it as a real jump, but the delivered clip has the jump arc removed** (the capsule jumps through `ACharacter::Jump()`) | 12 | 3 | `ContestMontage`, core `contest = 0.8 s` |
| Stumble — Light | `AM_Def_Stumble_Light_<L\|R>_01` | Hips caught leaning the wrong way, one recovery step, about 0.9 s | 8 | 2 | `StumbleMontage`; core stumble 0.9–1.8 s = `lerp(0.9, 1.8, effectiveness)` |
| Stumble — Heavy | `AM_Def_Stumble_Heavy_<L\|R>_01` | Stagger 2–3 steps, hand to the floor, about 1.3 s | 8 | 2 | (variant selection is request R7) |
| Ankle break | `AM_Def_Stumble_AnkleBreak_<L\|R>_01` | Feet cross and the defender falls to the floor, about 1.8 s. **Pads and crash mats.** | 8 | 2 | |
| Recover | `AM_Def_Recover_<Light\|Heavy\|AnkleBreak>_01` | Get back into the stance from each stumble end pose | 9 | 3 | |

**Defense totals:** about 110 takes, 39 selects (P0: idle, slides, contest, the three stumbles, recover).

---

## 6. Rebounds, catches, gathers, celebrations

| Set | Asset(s) | Contents | Takes | Selects | Priority |
|---|---|---|---|---|---|
| Loose-ball pickup | `AM_Reb_Loose_01..03` | Scoop a rolling or bouncing ball (code picks up within 3 ft and below 4 ft height) | 9 | 3 | P0 (snap is hidden by the montage; needs request R8) |
| Rebounds | `AM_Reb_<TwoHand\|OneHand\|Tip\|Box>_nn` | Box-out, jump two-hand and one-hand, tip, land and chin the ball | 24 | 6 | P1 (no jump or rebound action in code yet) |
| Catches | `AM_Catch_<F\|L\|R\|B>_<Chest\|High\|Low>_01` | Stationary and moving catches, landing in `TripleThreat_R` or `DribbleReady_R` | 12 dirs × heights × 2 = 36 | 12 | P1 (no pass yet) |
| Gathers | `AM_Gather_<R\|L>_01` | From a dribble in R or L to `TripleThreat_R` (shot entry) | 8 | 2 | P1 |
| Made-shot celebrations | `AM_Celeb_<Name>_01` | Short (≤ 2 s) upper-body-safe celebrations: arm hang, three-goggles, chest pound, point, shrug, ice-in-veins, crowd hype | 7 × 3 = 21 | 7 | P1 (no trigger yet, request R9) |
| Miss reactions | `AM_Celeb_Miss_<nn>` | Head shake, hands on head | 6 | 2 | P1 |

**Action totals:** about 104 takes.

---

## 7. Totals and schedule

| Block | Takes | Selects (P0 / P1) |
|---|---|---|
| Jumpshot | 192 | 15 / 24 |
| Dribble moves + loops | 264 | 28 / — (slow and fast captures are reference only) |
| Locomotion | ~330 | database (about 45 min usable) |
| Defense | ~110 | 30 / 9 |
| Rebounds, catches, celebrations | ~104 | 3 / 29 |
| **Total** | **~1,000** | |

Rough session days (one hero performer, optical stage, about 7 productive hours per day after calibration; short action takes ≈ 35–45/hour including ball retrieval and resets; MM takes are long):

| Day | Block |
|---|---|
| 1 | Calibration, ROM, rest poses, **all jumpshot bases and releases** (P0 + P1 entries) |
| 2 | **Dribble moves** (both hands, 3 speeds), stationary dribble loops |
| 3 | **With-ball locomotion** (idle, starts, stops, strafes, plants, circles, dance cards), both ball hands |
| 4 | **No-ball locomotion**, defensive stance, slides, backpedals, closeouts, contests |
| 5 | Stumbles and ankle breaks (mats), recovers, rebounds, catches, gathers, celebrations, pickups, plus a re-shoot buffer |

**Estimate: 5 stage days plus 0.5 day of contingency.** Add 1 day if a second (tall) performer covers defense and rebounds. Cleanup: about 3 animator-weeks to ship the P0 selects (shots, moves, loops, defense) plus database curation. Ball-prop cleanup is the long pole on inertial capture.
