# CourtLife Animation Naming and Authoring Rules

Owner: Animation. Applies to every clip, montage and animation asset in `/Game/Animation`.
Related docs: [SHOT_LIST.md](SHOT_LIST.md), [ANIM_BLUEPRINT.md](ANIM_BLUEPRINT.md), [TIMING_REFERENCE.md](TIMING_REFERENCE.md).

The content contracts in `Docs/Team/ONBOARDING.md` take priority over this doc: the `ball_prop` bone, the `hand_r_ball` / `hand_l_ball` sockets, the base / release / move IDs and the **Release** notify. Everything below builds on them.

## 1. IDs are the code keys, verbatim

Code finds animations by `FName` keys in `UCLAnimSet` (`CLAssets.h`): `ShotBases`, `ShotReleases`, `DribbleMoves`. Asset names embed the same key **with the same camelCase spelling**. A script can then fill the data asset from asset names, and a reviewer can spot a mismatch at a glance.

| Kind | Valid IDs (exact) |
|---|---|
| Shot base | `classic`, `quickSet`, `highSet`, `sideSet`, `oneMotion`, `setShot`, `legKick`, `hitch` |
| Shot release | `quickFlick`, `highArc`, `push`, `smoothHold`, `guideFlare`, `slingshot`, `wristy` |
| Dribble move | `crossover`, `killCross`, `betweenLegs`, `behindBack`, `hesitation`, `inAndOut`, `spin`, `stepBack`, `snatchBack`, `pound` |
| Hand | `R` = the move **starts** with the ball in the right hand, `L` = starts in the left hand |

## 2. Asset name patterns

General form: `<Prefix>_<Category>_<Subject>[_<Variant>][_<Hand>][_<nn>]`. Words are PascalCase except code IDs, which stay camelCase. `_nn` is a two-digit variation index starting at `01`.

| Prefix | Asset type |
|---|---|
| `A_` | Anim Sequence |
| `AM_` | Anim Montage |
| `BS_` / `BS1D_` | Blend Space / 1D Blend Space |
| `AO_` | Aim Offset |
| `ABP_` | Animation Blueprint |
| `PSD_` / `PSS_` / `PSN_` | Pose Search Database / Schema / Normalization Set |
| `CHT_` | Chooser Table |
| `MDT_` | Mirror Data Table |
| `IK_` / `RTG_` | IK Rig / IK Retargeter |
| `DA_` | Data asset (for example `DA_CL_AnimSet_Default`, the `UCLAnimSet` instance) |

### 2a. Jumpshot (`/Game/Animation/Jumpshot`)

| Asset | Pattern | Example | Goes into |
|---|---|---|---|
| Base sequence (full body, source) | `A_Shot_Base_<baseId>` | `A_Shot_Base_legKick` | — |
| Base montage | `AM_Shot_Base_<baseId>` | `AM_Shot_Base_legKick` | `UCLAnimSet.ShotBases[<baseId>]` |
| Base entry variants (post-slice) | `A_/AM_Shot_Base_<baseId>_<Entry>_<R\|L>` with Entry = `Pullup`, `Catch` | `AM_Shot_Base_classic_Pullup_L` | future handed map, see ANIM_BLUEPRINT requests |
| Release sequence (upper body) | `A_Shot_Release_<releaseId>` | `A_Shot_Release_guideFlare` | `UCLAnimSet.ShotReleases[<releaseId>]` |
| Raw mocap selects | `A_Shot_Base_<baseId>_Take<nnn>` / `A_Shot_Release_<releaseId>_On<baseId>_Take<nnn>` | `A_Shot_Release_wristy_Onclassic_Take014` | stays in `Jumpshot/_Source` |

### 2b. Dribble (`/Game/Animation/Dribble`)

| Asset | Pattern | Example | Goes into |
|---|---|---|---|
| Move sequence | `A_Dribble_<moveId>_<R\|L>` | `A_Dribble_killCross_L` | — |
| Move montage | `AM_Dribble_<moveId>_<R\|L>` | `AM_Dribble_killCross_L` | `UCLAnimSet.DribbleMoves[<moveId>].Right / .Left` |
| Speed captures (source/reference) | `A_Dribble_<moveId>_<R\|L>_<Slow\|Fast>` | `A_Dribble_spin_R_Fast` | `_Source`, used to judge time-scaling, not shipped in the AnimSet |
| Stationary dribble loops | `A_Dribble_Loop_<Type>_<R\|L>` with Type = `Pound`, `Low`, `Rhythm`, `Crossover` | `A_Dribble_Loop_Low_R` | Motion Matching idle-with-ball |
| Additive lean / rise | `A_Add_Dribble_Lean`, `A_Add_Dribble_Rise` | — | ABP additive layer |

### 2c. Locomotion (`/Game/Animation/Locomotion`)

`A_Loco_<Ball|NoBall>_<Type>_<Dir>_<Gait>_<nn>`

| Field | Values |
|---|---|
| Ball | `Ball` = dribbling, ball hand in a sub-folder `Ball/R` and `Ball/L` and a suffix on the asset (`A_Loco_Ball_Strafe_FL_Jog_R_01`); `NoBall` |
| Type | `Idle`, `Start`, `Stop`, `Loop`, `Strafe`, `Pivot`, `Plant`, `Circle`, `Dance` (random dance-card takes), `TurnInPlace` |
| Dir | `F`, `FL`, `L`, `BL`, `B`, `BR`, `R`, `FR` (direction of travel relative to the facing). Pivots use the turn angle: `L45`, `L90`, `L135`, `L180`, `R45` … |
| Gait | `Walk` (≈ 4 ft/s), `Jog` (8–11 ft/s), `Run` (11–14 ft/s), `Sprint` (14–19 ft/s) — see SHOT_LIST §4 |

Databases: `PSD_Loco_Ball_R`, `PSD_Loco_Ball_L`, `PSD_Loco_NoBall`, `PSD_Loco_Defense`; schema `PSS_Loco`; chooser `CHT_Loco`.

### 2d. Defense (`/Game/Animation/Defense`)

| Asset | Pattern | Example |
|---|---|---|
| Stance / slides (MM source) | `A_Def_<Stance\|Slide\|Backpedal\|Turn>_<Dir>_<Gait>_<nn>` | `A_Def_Slide_L_Jog_02` |
| Contest | `AM_Def_Contest_<Hand R\|L\|Both>_<nn>` | `AM_Def_Contest_R_01` (assigned to `ACLDefenderController.ContestMontage`) |
| Closeout | `AM_Def_Closeout_<nn>` | |
| Stumble / ankle break | `AM_Def_Stumble_<Light\|Heavy\|AnkleBreak>_<L\|R>_<nn>` (L/R = side the defender falls toward) | `AM_Def_Stumble_AnkleBreak_L_01` (`StumbleMontage`) |
| Recover | `AM_Def_Recover_<From>_<nn>` | `AM_Def_Recover_AnkleBreak_01` |

### 2e. Other actions (`/Game/Animation/Actions/<Rebound|Catch|Celebrate|Gather>`)

`AM_Reb_<Type>_<nn>` (Type = `TwoHand`, `OneHand`, `Tip`, `Box`, `Loose`), `AM_Catch_<Dir>_<Height>_<nn>`, `AM_Celeb_<Name>_<nn>`, `AM_Gather_<From R|L>_<nn>`.

### 2f. Blueprints and shared (`/Game/Animation/_Shared`)

`ABP_Baller` (main graph), `ABP_Baller_PostProcess` (post-process graph on the body mesh), `MDT_CL_Body`, `IK_CL_Body`, `IK_Mocap_<Performer>`, `RTG_Mocap_<Performer>_To_CLBody`, the curve and notify list (§7).

## 3. Folder layout

```
/Game/Animation/
  _Shared/          ABP_Baller, ABP_Baller_PostProcess, MDT_CL_Body, IK rigs, retargeters, DA_CL_AnimSet_Default
  Jumpshot/
    Bases/          A_/AM_Shot_Base_<baseId>
    Releases/       A_Shot_Release_<releaseId>
    _Source/        raw selects, never referenced by data assets
  Dribble/
    Moves/          A_/AM_Dribble_<moveId>_<R|L>
    Loops/          A_Dribble_Loop_*
    Additive/       A_Add_Dribble_Lean / Rise
    _Source/        speed captures, raw selects
  Locomotion/
    Ball/R  Ball/L  NoBall/   A_Loco_* sequences
    Databases/      PSD_*, PSS_*, PSN_*, CHT_Loco
  Defense/
    Locomotion/     A_Def_* (MM source)  Databases/PSD_Loco_Defense
    Reactions/      AM_Def_Contest_*, AM_Def_Stumble_*, AM_Def_Recover_*, AM_Def_Closeout_*
  Actions/
    Rebound/  Catch/  Gather/  Celebrate/
```

The skeleton and body mesh belong to the tech artist / character artist (`/Game/Characters/Body/`). Animation never duplicates the skeleton.

## 4. Skeleton

- **One skeleton for every player:** the body skeleton the character artist ships (MetaHuman body, UE5 mannequin-compatible bone names: `root`, `pelvis`, `spine_01`…`spine_05`, `clavicle_l/r`, `upperarm_l/r`, `lowerarm_l/r`, `hand_l/r`, `thigh_l/r`, `calf_l/r`, `foot_l/r`, `ball_l/r`, plus `ik_foot_*` / `ik_hand_*`), authored at the **6'6" (78 in) reference height** (`ReferenceHeightIn`).
- In-game heights from 5'9" to 7'3" (`HeightIn` 69–87) are a **uniform mesh scale** of 0.885–1.115 (`UCLCustomizationComponent::ApplyBuild`). Animations are never re-authored per height. Wingspan is a post-process arm-length bone scale ([ANIM_BLUEPRINT.md §7](ANIM_BLUEPRINT.md)).
- **Added bone `ball_prop`.** This is a real (not virtual) bone added in the DCC export, so it can carry keys:
  - Parent: **`root`**. It cannot be a child of a hand, because the ball leaves the hand on every dribble. It is also not under `pelvis`, so pelvis jump offsets don't move a ball that is on the floor.
  - Bind pose: ball center at the right-hand palm (where `hand_r_ball` sits in the reference pose), identity rotation.
  - Its origin is the **ball center**. Ball radius in the core is **0.38 ft = 11.58 cm** (`ball.y == 0.38` at a floor contact in `dribble.js`). The ball mesh must be modeled around its center.
- **Sockets** (on the skeleton asset, not the mesh): `hand_r_ball` on `hand_r`, `hand_l_ball` on `hand_l`, at the palm center offset 11.6 cm along the palm normal. The code falls back to them only when `ball_prop` is missing. Animation also uses them as IK targets (§6).
- Mirror table `MDT_CL_Body`: `_l` ↔ `_r` pairs; `ball_prop` maps to itself (mirrored across the sagittal plane).

## 5. Frame rate: 60 fps

**Decision:** capture optical at 120 Hz (inertial at its native 60–240 Hz), then solve, clean and **export every clip at 60 fps**. Set the project's Sequencer / import default to 60.

Why:
1. **The shot master length is exactly 1050 ms.** The core sets `durationMs = round(1050 / playRate)` and the montage plays at `PlayRate`, so a base montage must last 1050 ms at play rate 1.0. That is **63 frames at 60 fps** but 31.5 frames at 30 fps, which can't be represented ([TIMING_REFERENCE §1](TIMING_REFERENCE.md)).
2. **Green windows go down to 10 ms**, and release times are graded to the millisecond. A 33 ms frame at 30 fps is coarser than the tightest window, while 16.7 ms at 60 fps keeps visual release frames within about one frame of the meter.
3. **Dribble moves are short.** `pound` is 260 ms at 1.0x and 173 ms at 1.5x, which is 15.6 / 10.4 frames at 60 fps but only about 5 frames at 30 fps at top speed. Floor and hand contacts need sub-50 ms precision to avoid a visible pop on the ball.
4. Motion Matching samples poses and trajectories more cleanly at 60.

Notifies are placed by **time in seconds**, not by frame. Several Release times fall between frames (for example classic at 0.6930 s = frame 41.58). Unreal supports sub-frame notify times; type the time into the notify's *Time* field.

## 6. Root motion rules

| Clip family | Root bone carries | `Enable Root Motion` | Moves the capsule? | Notes |
|---|---|---|---|---|
| Locomotion (MM sources) | Full planar translation + yaw, projected from the pelvis onto the floor (Z = 0) | On | No. The ABP runs `Root Motion Mode = Root Motion from Montages Only`, so graph sequences don't apply it | The PoseSearch databases need clean root trajectories. Smooth the root (no hip sway on root). Facing = chest direction. |
| Dribble move montages | Planar translation matching the core burst **exactly** (TIMING_REFERENCE §2a), plus yaw for `spin` (±360°) | On | **v1: no** (`bUseRootMotion = false`; the core moves the actor). Later: yes | Translation follows the core's `sin(t·π/2)` ease-out. With `bUseRootMotion = false` the code must stop montage root motion from also moving the capsule; see the ANIM_BLUEPRINT request R1. |
| Shot bases | Planar drift only (`oneMotion` 0.1 ft back, `legKick` 0.3 ft back, others 0). **Root Z stays 0**; the jump lives on the pelvis | On | Yes (drift only). The code does `StopMovementImmediately()` and faces the rim at shot start | Jump height in the clip is the reference jump (§SHOT_LIST 2.1). The ABP scales it per Vertical rating. |
| Shot releases | None. Upper body only, root and pelvis are ignored (mask at `spine_01`) | Off | — | |
| Defender contest | Planar translation removed; **jump arc removed** (pelvis Z relative to the takeoff stance) | Off | No. The code calls `ACharacter::Jump()` and sets an 8 ft/s velocity toward the shooter | The capsule provides the height. Keep the limbs and the "reach". |
| Stumble / recover | Planar translation | On | Yes | The core freezes AI movement for `stumble` seconds (0.9–1.8 s) |
| Rebounds / catches / celebrations | Planar translation | On | Yes | No vertical root motion. Jumps are pelvis-only unless gameplay adds a jump call |

**Root rules for every clip:** the root starts at the origin facing +X (Unreal forward) on frame 0. There is no root rotation on frame 0, and the root never leaves the floor plane.

## 7. `ball_prop` animation, contacts, curves and notifies

### How the ball is animated
- **Optical capture:** track a marker ball (at least 4 markers, or a retroreflective-taped ball) as a rigid prop. Solve it to `ball_prop` (translation and rotation). Spin matters: the backspin on a jumper release and the roll on a crossover are both visible.
- **Inertial or markerless capture:** the ball isn't tracked. Keyframe `ball_prop` in the DCC using the contact frames from the reference video and from TIMING_REFERENCE §2a.
- **Every clip that plays while the ball is held must key `ball_prop`.** That covers dribble moves, dribble loops, with-ball locomotion, shot bases, gathers and catches. The code snaps the ball actor to `ball_prop` whenever the bone exists (`ACLBallerCharacter::AttachBallToHand`), so an unkeyed clip leaves the ball frozen at the bind pose in the right palm.
- Clips without the ball (no-ball locomotion, defense, rebounds before the catch) key `ball_prop` at the bind pose. It is hidden because the ball actor is detached.

### Contact rules
- **Floor contact:** ball center Z = 11.58 cm (radius) in clip space at 1.0 scale. Hold it for 1 frame at 60 fps (a hard bounce), with no penetration and no float. Use a linear tangent in and out of the contact frame so the ball has a real impact.
- **Hand contact:** while the ball is in a hand, the ball center sits on the `hand_*_ball` socket (±1 cm). Key `BallInHand_R` / `BallInHand_L` = 1 on those frames.
- **Dribble ball path:** must pass through the core ball keyframes (`DRIBBLE_MOVES[*].ball` in `courtlife/src/core/dribble.js`; hand-space lateral = `s × 0.85 ft`, height `y`, forward `z`) within about 2 in, and hit floor contacts at the times in TIMING_REFERENCE §2a.

### Curves (Anim Curves, float, authored in the sequence)

| Curve | Range | Clips | Meaning / consumer |
|---|---|---|---|
| `BallInHand_R`, `BallInHand_L` | 0/1 (2-frame ease) | Everything with the ball | Post-process re-attaches `ball_prop` to the hand socket after arm scaling and height scaling |
| `BallContact_Floor` | 0/1 | Dribble moves, loops, with-ball loco | Post-process clamps the ball center to the floor + radius at runtime scale |
| `ReleaseAlpha` | 0→1 | Shot bases | Weight of the release layer (ANIM_BLUEPRINT §4) |
| `ReleaseClock` | seconds, linear | Shot bases | `t − releaseTime`: negative before the Release notify, 0 at it, positive after. Drives the release sequence time |
| `JumpArc` | cm | Shot bases (also rebounds and contest) | Authored pelvis height above the stance pelvis height. Used to scale the jump per Vertical |
| `FootLock_L`, `FootLock_R` | 0/1 | All grounded clips | Foot planted. Drives foot locking and IK |
| `DisableLegIK` | 0/1 | Airborne sections | Turns leg IK off in the air |

### Notifies (Anim Notify, name exact)

| Notify | Clips | Placement |
|---|---|---|
| **`Release`** (contract) | Every shot base montage | At `releaseT × 1.050 s`. Times are in TIMING_REFERENCE §1a. Ball leaves the fingertips on this frame |
| `BallBounce` | Dribble moves, loops, with-ball loco | Each floor contact (audio, VFX) |
| `HandSwitch` | Hand-switching moves | When the receiving hand takes the ball. The core flips the hand at local t = 0.5 |
| `FootPlant_L`, `FootPlant_R` | Everything grounded | Heel or ball-of-foot strike (sneaker squeak) |
| `BallCatch` | Catches, rebounds, gathers | When the ball contacts both hands |

## 8. Lengths, montage settings and export checklist

- **Shot base montage:** exactly **1.050 s (63 frames)**, one section `Default`, slot `DefaultSlot`, Blend In 0.10 s, Blend Out 0.20 s, Auto Blend Out on.
- **Shot release sequence:** **0.750 s (45 frames)**. Release (ball leaves) at **0.300 s (frame 18)**, with 0.30 s of lead-in from the set pose and 0.45 s of follow-through and hold. This layout lets any release play under any base: it covers the longest pre-release blend window of 0.20 s and the longest post-release tail of 0.441 s (`quickSet`).
- **Dribble montage:** author at natural speed. Trim to the whole frame nearest the core `durationMs` (for example `crossover` 380 ms → 23 frames = 383 ms). The component rescales any length to the exact segment time. Slot `DefaultSlot`, Blend In 0.05 s, Blend Out 0.08 s, Auto Blend Out on. The first and last frames must be the hand's dribble-ready pose for its hand (ball at the hand, about 2.0–2.3 ft high), so moves chain cleanly.
- **Defender contest** 0.80 s (`contest = 0.8` in the core). **Stumbles:** Light ≈ 0.9 s, Heavy ≈ 1.3 s, AnkleBreak ≈ 1.8 s, matching the core stumble range 0.9–1.8 s.
- **Export checklist:** 60 fps, cm, Z-up, root at the origin facing +X, `ball_prop` keyed, curves and notifies present, name and folder per this doc, the source take number in the asset's metadata tag `SourceTake`.
