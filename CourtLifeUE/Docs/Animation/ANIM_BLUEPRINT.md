# ABP_Baller — Animation Blueprint Spec

Owner: Animation, with the tech artist (post-process, retargeting) and the gameplay programmer (requests in §11).
Status: **spec, unverified in Unreal.** Unreal is not installed in the authoring environment. Node names are UE 5.6 (PoseSearch / Motion Matching, Chooser, AnimationWarping, Control Rig, IK Retargeter plugins).

Assets: `ABP_Baller` (main anim graph, skeleton `SK_CL_Body`), `ABP_Baller_PostProcess` (set as the body mesh's *Post Process Anim Blueprint*). Both players and AI defenders use `ABP_Baller`. Naming, curves and notifies are listed in [NAMING.md](NAMING.md) §7. Numbers are in [TIMING_REFERENCE.md](TIMING_REFERENCE.md).

---

## 1. What the code does (the contract this graph serves)

| Code | Behavior the graph must honor |
|---|---|
| `UCLShotComponent::BeginShot` | `Montage_Play(ShotBases[Build.Jumpshot.Base], Profile.PlayRate)`. Full-body base montage on whatever slot the montage uses (→ `DefaultSlot`). The comment says releases are blended **in the graph** from `Profile.ReleaseBlend`. |
| `UCLShotComponent::TickComponent` | The shot lasts exactly `Profile.DurationMs` of game time. Auto-release at `0.95 × DurationMs`. The meter fills over `1.5 × ReleaseTimeMs`. |
| `UCLShotComponent::ReleaseShot` | Grades `HeldMs` against `ReleaseTimeMs` (button timing, **not** the notify), then `Ball->Shoot()` detaches the ball from wherever `ball_prop` is **right now**. |
| `UCLDribbleComponent::PlaySegmentMontage` | Per combo step: picks `DribbleMoves[move].Right/Left` by the hand **at segment start**, falls back to `Right` if `Left` is empty, and plays at `Rate = PlayLength·1000 / segmentMs`. |
| `UCLDribbleComponent::TickComponent` | With `bUseRootMotion = false` (the default) the core moves and rotates the actor every tick (burst offsets, spin yaw). Exposes `GetBallHand()`, `GetLean()`, `GetRise()`, `IsInCombo()`. |
| `ACLBallerCharacter::Tick` | With the ball and not in a combo or shot, the actor **faces the rim** (yaw interp 10). Without the ball, it faces velocity. The ball actor is snapped to `ball_prop` (`SnapToTargetNotIncludingScale`). |
| `UCLCustomizationComponent::ApplyBuild` | Uniform mesh scale `HeightIn / 78`. Wingspan is left to "an arm-length bone scale in the post-process anim BP" (§7). |
| `ACLDefenderController` | `Montage_Play(StumbleMontage)` / `Montage_Play(ContestMontage)` at rate 1. `ACharacter::Jump()` on contest. Always faces the handler. |

---

## 2. Variables (gathered once per frame)

Gather on the game thread in **Event Blueprint Update Animation**, or better in a C++ `UCLBallerAnimInstance::NativeUpdateAnimation` (request R0). Then read them in the graph through thread-safe property access.

| Variable | Type | Source |
|---|---|---|
| `Baller` | `ACLBallerCharacter*` | `TryGetPawnOwner()` cast (null for the defender pawn → `bIsDefender`) |
| `bIsDefender` | bool | Pawn's controller is `ACLDefenderController` |
| `bHasBall` | bool | `Baller->GetBall()->GetState() == Held` |
| `BallHand` | `ECLHand` | `GetDribble()->GetBallHand()` |
| `bInCombo` | bool | `GetDribble()->IsInCombo()` |
| `DribbleLean`, `DribbleRise` | float | `GetDribble()->GetLean()` / `GetRise()`: lean = extra forward spine pitch in **radians** (peak −0.35…+0.45), rise = leg straightening amount (peak 0.25, hesitation only); both shaped `sin(π·t)` by the core |
| `bShooting` | bool | `GetShot()->IsShooting()` |
| `ShotPlayRate`, `ReleaseBlend` | float | `GetShot()->GetProfile().PlayRate / .ReleaseBlend` |
| `ShotReleaseT`, `JumpScale` | float | **Not exposed yet** (request R4). Until then use the curve fallbacks in §4 / §5. |
| `Release1Seq`, `Release2Seq` | `UAnimSequence*` | `AnimSet->ShotReleases.Find(GetBuild().Jumpshot.Release1 / Release2)`. `AnimSet` is not Blueprint-readable (request R3); interim: the ABP holds its own reference to `DA_CL_AnimSet_Default` |
| `HeightScale` | float | `GetBuild().Body.HeightIn / 78` |
| `ArmScale` | float | §7 formula from `GetBuild().Body.HeightIn / WingspanIn` |
| `bMirrorDribble` | bool | **Not exposed** (request R2). Interim: false. Both hands are authored, so no mirroring is needed |
| Velocity, acceleration, trajectory | | From `UCharacterMovementComponent` through the PoseSearch trajectory generator (§3) |

Recompute `Release1Seq`, `Release2Seq`, `HeightScale` and `ArmScale` only when the build changes (bind to a build-changed event, or compare the build's jumpshot names each frame; it's cheap).

---

## 3. Locomotion: Motion Matching

```
[Chooser: CHT_Loco] ──► [Motion Matching] ──► [Orientation Warping] ──► [Stride Warping] ──► (Locomotion pose)
```

- **Chooser `CHT_Loco`** selects the PoseSearch database. First row match wins:
  1. `bIsDefender` → `PSD_Loco_Defense`
  2. `bHasBall && BallHand == Left` → `PSD_Loco_Ball_L`
  3. `bHasBall` → `PSD_Loco_Ball_R`
  4. else → `PSD_Loco_NoBall`
- **Schema `PSS_Loco`.** Pose channels: `foot_l`/`foot_r` position + velocity, `pelvis` velocity; the with-ball schema variant adds `hand_r`/`hand_l` position (keeps the dribble hand phase continuous). Trajectory samples at −0.3 / 0 / +0.35 / +0.7 / +1.0 s, position + **facing** (with the ball the facing stays locked to the rim while the position strafes, so facing must be a channel). Blend time 0.20 s. Continuing-pose bias −0.01.
- **Trajectory.** Generate it from the CMC (PoseSearch trajectory library, `PoseSearchGenerateTransformTrajectory`). With the ball and not in a combo, set the predicted facing to the rim yaw, because the code interps there. **Height scaling:** divide trajectory translations by `HeightScale` before the query. The mesh is uniformly scaled, so authored 6'6" root speeds look `HeightScale` times faster; this keeps database speeds matching the visual stride.
- **Orientation Warping** (locomotion angle = velocity vs actor yaw) cleans up residual strafe angles. Disable it while `bInCombo || bShooting`.
- **Stride Warping**: `Locomotion Speed = CMC speed / HeightScale`. Clamp the stride scale to 0.8–1.25.
- **Root Motion Mode** of the anim instance: `Root Motion from Montages Only`. Locomotion sequences carry root motion for the database but never move the capsule (the CMC does).
- **In air:** state machine `Grounded` (MM) / `InAir` (`A_Loco_Jump_Loop` + land). Only the defender's contest jump uses it today; the contest montage covers it on `DefaultSlot`.

---

## 4. Shot: base montage + layered release blend

### 4.1 Graph section

```
(Locomotion pose)
  └─► [Slot 'DefaultSlot'] ──────────────────────────────────────┐ base pose
                                                                 ▼
  [SeqEval Release1Seq @ RelTime] ─┐                    [Layered blend per bone]
                                   ├─► [Blend α=ReleaseBlend] ─► blend pose 0
  [SeqEval Release2Seq @ RelTime] ─┘                    weight 0 = ReleaseLayerAlpha
                                                         branch filter: spine_01, blend depth 3
                                                         Mesh Space Rotation Blend = ON
                                                         Mesh Space Scale Blend = OFF
                                                         Curve Blend = Use Base Pose
```

- **Release1 / Release2**: two *Sequence Evaluator* nodes. Sequence comes from `Release1Seq` / `Release2Seq` (set in an *On Become Relevant* / *On Update* function with `SetSequence`). Explicit Time = `RelTime`. No loop. Teleport-to-explicit-time on.
- **Blend** node: `Alpha = ReleaseBlend` (`FCLShotProfile::ReleaseBlend`, 0 = Release1, 1 = Release2). This is the same t the core uses to lerp tempo, height and extension, so the visual blend and the timing blend agree.
- **Layered blend per bone**: branch filter `spine_01` with **blend depth 3**, so spine_01 → spine_03 phase in gradually instead of a hard seam at the waist. Mesh-space rotation blend keeps the shooting arm's aim at the rim consistent regardless of each base's torso pitch. `ball_prop` (child of `root`) is **outside** the branch. The base drives it, and post-process re-attaches it to the hand (§7), so the ball follows the release hand.
- **`ReleaseLayerAlpha`** = `bShooting ? GetCurveValue('ReleaseAlpha') : 0`. Authored per base: 0 until **Release − 0.20 s**, ease to 1 at **Release − 0.05 s**, hold 1 to the end (the montage blend-out fades it out).

### 4.2 Release sequence time (`RelTime`)

Release sequences are 0.750 s with the ball leaving at **0.300 s** (NAMING §8). Align that frame to the base montage's Release notify:

- **Preferred (needs R4):** `RelTime = 0.300 + (Montage_GetPosition(BaseMontage) − ShotReleaseT × 1.050)`. Both times are in authored seconds, so they scale with `PlayRate` together. A release always fires exactly on the base's Release frame, at any speed.
- **Interim fallback (works today):** `RelTime = 0.300 + GetCurveValue('ReleaseClock')`, where `ReleaseClock` is authored on each base as `t − releaseTime` (linear, seconds). Caveat: curve values are scaled by montage weight during blend-in and blend-out, so the release rewinds slightly during the last 0.2 s fade. That is acceptable for gray-box; switch to the preferred version when R4 lands.
- Clamp `RelTime` to [0, 0.750].

### 4.3 The Release notify and meter sync

- Each base montage is **exactly 1.050 s** and contains an Anim Notify named **`Release`** at `releaseT × 1.050 s`, with `releaseT = clamp(base.releaseT + base.hitch/2, 0.5, 0.85)`:

  | Base | classic | quickSet | highSet | sideSet | oneMotion | setShot | legKick | hitch |
  |---|---|---|---|---|---|---|---|---|
  | Release notify (s) | 0.6930 | 0.6090 | 0.7350 | 0.6720 | 0.6510 | 0.6300 | 0.7140 | 0.8400 |

  (Generated: TIMING_REFERENCE §1a.)
- **Why it stays in sync:** `BeginShot` plays the montage at `PlayRate = lerp(0.8, 1.25, (speed−1)/4) × tempo`, and the core defines `DurationMs = round(1050 / PlayRate)` and `ReleaseTimeMs = round(DurationMs × releaseT)`. So in game time the montage ends at `1050 / PlayRate` ms ≈ `DurationMs`, and the notify fires at `releaseT × 1050 / PlayRate` ms ≈ `ReleaseTimeMs`. Across all 8 × 7 × 5 combinations the error is ≤ 0.75 ms (TIMING_REFERENCE sync check). The meter's green band is centered on `ReleaseTimeMs`, so a perfect button release lands on the frame where the ball leaves the fingers.
- **Never** change a base montage's length, rate scale or section play rate, and never insert time warps in the montage. Any change breaks the meter. Montage `Rate Scale` = 1.0.
- Montage blend-in 0.10 s, blend-out 0.20 s (auto blend-out starts at 0.85 s authored, after every Release notify including hitch at 0.84 s).
- Validation (dev only, request R5): a `UCLAnimNotify_Release` class logs `|wallTimeAtNotify − ReleaseTimeMs| > 17 ms`.

---

## 5. Jump height per Vertical rating

The core computes `jumpFt = base.jump × lerp(0.6, 1.6, invLerp(25, 99, Vertical))`, but a montage can only hold one jump. Bases are captured at the **reference jump** (multiplier 1.0, i.e. `base.jump` ft) and carry a `JumpArc` curve (pelvis rise above stance, cm).

In the main graph after the release layer: `Transform (Modify) Bone` on `pelvis`, Add To Existing, component space, translation Z = `(JumpScale − 1) × GetCurveValue('JumpArc')`. `JumpScale = jumpFt / base.jump` needs R4. Until then `JumpScale = 1` (every build jumps the reference height). Feet move with the pelvis (they're airborne while `JumpArc > 0`). Leg IK is off via `DisableLegIK`.

No `/ HeightScale` here: the curve is in authored (reference) cm, and the core's jumpFt is absolute. Strictly, the correct offset is `(jumpFt·30.48 − JumpArc·HeightScale) / HeightScale` at the peak. Use that exact form once `JumpFt` is exposed (R4).

---

## 6. Dribble moves

```
(after shot release layer)
  └─► [Mirror (MDT_CL_Body), bMirror = bMirrorDribble]   (fallback only, R2)
      └─► [Apply Additive: BS1D_Add_Dribble_Lean(DribbleLean), α = LeanRiseScale]
          └─► [Apply Additive: A_Add_Dribble_Rise, α = clamp(DribbleRise / 0.4) × LeanRiseScale]
```

- Dribble montages play on **`DefaultSlot`** (same slot as the shot, so pressing shoot mid-combo cleanly interrupts). Author them at natural speed: `UCLDribbleComponent` sets `Rate = PlayLength / segmentMs`, so a clip authored at the core `durationMs` plays at exactly the step speed (0.6×–1.5×). See TIMING_REFERENCE §2 for every segment length.
- Montage blend-in 0.05 s, blend-out 0.08 s. Each step calls `Montage_Play` on the same slot, so step N+1's blend-in replaces step N's tail. Start and end poses are `DribbleReady_<hand>` to make that seamless.
- **Lean / rise:** the mocap carries the real lean. The code curves (`GetLean`/`GetRise`) are applied as **additives on top**, weighted by the ABP constant `LeanRiseScale`:
  - `1.0` while using gray-box or placeholder clips (matches the web prototype, which does `spine = 0.25 + lean` and `standTaller(rise)`),
  - `0.25` with final mocap (a little extra "sell" that scales with step speed, since the core shapes it over the segment time),
  - `0` when an animator wants pure mocap.
  - `BS1D_Add_Dribble_Lean`: mesh-space additive 1D blend space, axis −0.5…+0.5 rad, samples at −0.5 (spine_01–03 extended back, total 0.5 rad), 0 (identity), +0.5 (flexed forward).
  - `A_Add_Dribble_Rise`: local-space additive, hips extend 1.2·0.4 rad and knees extend 2·0.4 rad at weight 1 (the prototype's `standTaller(0.4)`), with the pelvis raised to match.
- **Root motion** (`bUseRootMotion = false` today): the core moves the actor by exactly the burst and rotates it for `spin`. The montage root must therefore **not** move the capsule. See request R1. Animations still author the root displacement to match the burst (TIMING_REFERENCE §2a), so flipping `bUseRootMotion` later needs no re-export.
- **Ball:** every dribble montage keys `ball_prop` with `BallBounce` notifies and `BallInHand_*` / `BallContact_Floor` curves (NAMING §7).
- **Hand tracking:** `GetBallHand()` flips at local t = 0.5 in hand-switching moves. The montage's `HandSwitch` notify should sit at or before 0.5 (TIMING_REFERENCE §2a), so the fallback socket and the locomotion database switch don't run ahead of the visual catch.

---

## 7. Post-process (`ABP_Baller_PostProcess`)

Runs on the body mesh after the main graph, in this order:

1. **Arm length (wingspan)**: Control Rig `CR_CL_ArmLength`, input `ArmScale`.
   - The reference mesh's wingspan `RefWingspanIn` is measured once by the tech artist (expected ≈ 81 in, i.e. height + 3, matching the default build). After uniform scaling, the wingspan is `RefWingspanIn × HeightScale`.
   - Extra reach per arm in component space: `e = (WingspanIn − RefWingspanIn × HeightScale) / 2 / HeightScale` (inches; × 2.54 for cm). Wingspan is clamped to height −2…+8 in by the core.
   - `ArmScale = 1 + e / (L_upperarm + L_lowerarm)`, with L measured on the reference mesh. Expected range ≈ 0.9–1.1.
   - Implementation: multiply the **local translation X** (bone length axis) of `lowerarm_l/r`, `hand_l/r` and the arm twist bones by `ArmScale`. Don't use bone *scale*: it would scale the hands and the ball socket. Shoulders and clavicles are untouched.
2. **Ball re-attach**: Control Rig `CR_CL_Ball`.
   - `ball_prop = lerp(ball_prop, hand_r × hand_r_ball offset, BallInHand_R)`, then the same for `_L`. Translation and rotation, component space. This re-binds the ball to the palm after arm scaling, release layering, jump scaling and mirroring, all of which move the hand but not `ball_prop` (a root child).
   - **Floor clamp:** ball center component Z `≥ 11.58 / HeightScale` cm (world radius 11.58 cm, because the component is scaled by `HeightScale`). While `BallContact_Floor > 0.5`, set Z to exactly `11.58 / HeightScale`. Without this, a 5'9" player's ball sinks 1.3 cm into the floor and a 7'3" player's ball floats 1.3 cm above it on every bounce.
3. **Foot IK on hardwood**: Leg IK (or the AnimationWarping *Foot Placement* node) with `FootLock_L/R` curves.
   - The court is a flat plane at the `CLCourt` actor's Z (world). Use a fixed plane instead of traces (cheaper, no noise from the ball or players). Keep a single downward trace only as a fallback for non-court levels.
   - Foot locking while `FootLock_* = 1` removes the sliding left over from stride warping and height scaling. Pelvis adjust max 5 cm. IK off while `DisableLegIK > 0.5` (jump shots, contests, rebounds).
   - Hardwood: no surface-normal foot rotation (the floor is flat). Toe-bone (`ball_l/r`) roll comes from the clip.
4. **Hand IK** (optional, post-slice): two-hand ball hold for catches and gathers, using the `hand_l_ball` → ball distance.

---

## 8. Slots and slot groups

| Slot | Group | Used by | Layer |
|---|---|---|---|
| `DefaultSlot` | `DefaultGroup` | Shot bases, dribble moves, defender contest and stumble, rebounds, gathers, catches | Full body, before the release layer |
| `UpperBody` | `UpperBodyGroup` | Celebrations on the move, future passes, catches on the run | Layered blend per bone at `spine_01` (depth 2, mesh-space rotation) **after** the release layer, so an upper-body clip never cancels a `DefaultSlot` montage (different group) |

All code-driven montages (`ShotBases`, `DribbleMoves`, `StumbleMontage`, `ContestMontage`) must use `DefaultSlot`. That's the slot `Montage_Play` drives in the code paths above.

Full graph order:

```
Locomotion (MM + warping)
 → Slot DefaultSlot
 → Release layer (layered blend at spine_01; Blend Release1/Release2 by ReleaseBlend)
 → Jump scale (pelvis Z)
 → Mirror (dribble fallback)
 → Lean / Rise additives
 → Slot UpperBody (layered at spine_01)
 → Output
[Post-process: arm length → ball re-attach + floor clamp → foot IK → hand IK]
```

---

## 9. Retargeting (performer → SK_CL_Body) and the 5'9"–7'3" range

- **Source:** the mocap solve skeleton per performer → `IK_Mocap_<Performer>`. **Target:** `IK_CL_Body` on the 6'6" reference. **Retargeter:** `RTG_Mocap_<Performer>_To_CLBody`.
- **Chains:** spine, neck, head, clavicle/arm L/R (IK goal on the hands), leg L/R (IK goal on the feet), fingers, plus a **`Ball` chain containing only `ball_prop`**.
- Root: translation mode *Globally Scaled*. Leg goals: *Floor constraint* on. Arms: FK + IK blend 1.0 on dribble clips so the palm stays on the ball (the ball is the ground truth).
- `Ball` chain: FK translation mode *Absolute*, with a post op that offsets the ball by the hand-goal delta while `BallInHand > 0.5` (or do it in the DCC). Then re-clamp floor contacts to Z = 11.58 cm. A performer shorter or taller than 6'6" otherwise shifts every contact.
- **In-game heights 5'9"–7'3" are NOT retargets.** The game uniformly scales one skeleton (0.885–1.115). Consequences handled above: trajectory and stride scaling (§3), the ball floor clamp (§7.2), jump offset (§5) and wingspan (§7.1). Dribble heights scale with the player (a 7'3" player dribbles about 12% higher in absolute terms). That's intended.
- Run a retarget pose check at the extremes (69 in / 87 in, wingspan −2 / +8): the ball must touch both palms in `crossover` and `killCross` and land within 2 cm of the floor plane.

---

## 10. Defender

`ABP_Baller` with `bIsDefender`: MM on `PSD_Loco_Defense` (stance, slides, backpedals), facing the handler (the code interps the actor yaw).

- `ContestMontage`: in place, **jump arc removed** (the capsule jumps through `ACharacter::Jump()` with an 8 ft/s lunge velocity), 0.80 s to match `contest = 0.8`.
- `StumbleMontage`: today a single montage at rate 1, while the core freezes the defender for 0.9–1.8 s; see R7. Author `AM_Def_Stumble_Heavy_*` (≈1.3 s) as the assigned default, so it is never wildly short or long.

---

## 11. Requests to the gameplay programmer

Found while matching this spec against the code. None of them block the vertical-slice capture; R1 and R4 matter for the first in-engine shots and moves.

| # | Area | Finding | Request |
|---|---|---|---|
| **R1** | `UCLDribbleComponent` root motion | With `bUseRootMotion = false` the core moves the actor via `SetActorLocation`. But the montages are played with the anim instance's default `Root Motion from Montages Only`, so any dribble montage with root motion enabled **also** moves the capsule → **double displacement** (and double spin yaw). | While a combo runs with `bUseRootMotion == false`, set `AnimInstance->SetRootMotionMode(ERootMotionMode::IgnoreRootMotion)`. Restore it on finish or cancel. That lets one asset (root authored to match the burst) serve both modes. When `bUseRootMotion == true`, the root motion must match the core burst; worth a debug check comparing actor displacement vs `Timeline.offset` at combo end. |
| **R2** | Left-hand fallback | `CLAssets.h` says an empty `Left` is "mirrored at runtime via a mirror data table", but `PlaySegmentMontage` just plays `Right` **unmirrored**. A left-hand move would play the right-hand animation with the ball on the wrong side. | Expose `UFUNCTION(BlueprintPure) bool IsMirroringCurrentMove() const` (true when the segment hand is Left and `Left` was null). The ABP mirrors `DefaultSlot` output with `MDT_CL_Body` (§6). We plan to author both hands, so this is a safety net. |
| **R3** | Release sequences | The ABP must evaluate `ShotReleases[Release1]` and `[Release2]`, but `ACLBallerCharacter::AnimSet` is `EditAnywhere` only (not Blueprint-readable) and the shot component doesn't hand the sequences to the anim instance. | Add `UFUNCTION(BlueprintPure) UCLAnimSet* GetAnimSet() const`, or better have `UCLShotComponent` expose `GetRelease1Sequence()/GetRelease2Sequence()` (resolved in `Configure`). |
| **R4** | `FCLShotProfile` missing fields | The core's `ShotProfile` has `releaseT` and `jumpFt`, but `FCLShotProfile` / `CLBridge::FromCore` drop them. The ABP needs `releaseT` to align releases exactly (§4.2) and the jump scale to make Vertical visible (§5). | Add `ReleaseT`, `JumpFt` and `JumpScale` (= `lerp(0.6, 1.6, invLerp(25, 99, Vertical))`, or `JumpFt / base.jump`) to `FCLShotProfile` + `FromCore`. Also useful: the active base montage pointer (`GetActiveBaseMontage()`), so the ABP can read its position. No rule change, so the parity golden is unaffected. |
| **R5** | Release notify is unused | Nothing listens for the **Release** notify. `ReleaseShot` launches the ball the instant the button is released, from wherever `ball_prop` is. An early release launches from the set point (before the arm extends). A late one launches from the follow-through. | (a) Add `UCLAnimNotify_Release`, which in non-shipping builds logs desync between the notify's wall time and `ReleaseTimeMs` (> 17 ms). (b) Design call: keep grading on the button, but launch the **ball visually** at `max(button release, Release notify)` when early, and immediately when late. The ball then always leaves the fingertips. Grading and the make roll are unchanged. |
| **R6** | With-ball facing | With the ball, the actor always faces the rim, so dribbling or sprinting away from the basket is a **backpedal sprint at up to 18.9 ft/s**, which no real player does. It also forces strafe coverage at every gait (SHOT_LIST §4). | Consider facing velocity while sprinting, or when moving more than ~110° away from the rim, blending back to the rim when slowing or stopping. Tell animation which rule ships so the with-ball database coverage can be trimmed. |
| **R7** | Defender stumble | One `StumbleMontage` at rate 1 regardless of `State.stumble` (0.9–1.8 s from `lerp(0.9, 1.8, effectiveness)`). The defender stands frozen after a short clip, or a long clip outlasts the freeze. There's no direction and no recover. | Replace it with `TArray` variants (Light < 1.15 s, Heavy < 1.55 s, AnkleBreak ≥ 1.55 s) × fall side (from the handler's lateral offset), or at least play at `Rate = Length / stumble`. Add a `RecoverMontage` hook. |
| **R8** | Ball pickup | Rebound pickup snaps the ball to the hand (`AttachBallToHand`) with no event, so no gather or pickup animation can play. Also, shot bases always start from a right-hand gather, even when the ball is in the left hand. | Add an `OnBallPickedUp` delegate (or a BlueprintImplementableEvent) to play `AM_Reb_Loose_*`. Post-slice: make `ShotBases` handed (`FCLHandedMontage`) for pull-up entries `AM_Shot_Base_<id>_Pullup_<R\|L>`. |
| **R9** | Celebrations | No trigger exists. | After `OnShotReleased` with `bMade`, when the ball goes through the net (`ThroughNet` state), play a random `AM_Celeb_*` on `UpperBody` if the player isn't in another action. Low priority. |
| **R10** | `UCLDribbleComponent::Cancel` hand bug | `Cancel()` sets `BallHand = Timeline.endHand`, the hand at the **end of the whole combo**. Pressing shoot mid-combo (which calls `Cancel`) can flip the ball to the wrong hand, so the fallback socket, the locomotion database and the future pull-up entry all use the wrong side. | Keep the last sampled `BallHand` on cancel (it's already updated every tick), i.e. drop that assignment, or set it from `SampleCombo(Timeline, ElapsedMs)`. |
| **R11** | Ball path parity | The JS core's dribble moves carry `ball` keyframes (used here for contact frames), but the C++ `DribbleMove` has none. UE can't validate `ball_prop` against the design path, and future steal or deflection logic would have no ball position. | Port `ball` keyframes to `CLDribble.h/.cpp` with the parity test, or confirm they stay web-only (animation then treats TIMING_REFERENCE §2a as the source). |
| **R12** | Units of lean / rise | `GetLean()`/`GetRise()` have no documented units. The prototype uses lean as **radians of extra spine pitch** and rise as the `standTaller` amount (0–0.4). | Document the units on `DribbleMove::lean/rise` and the getters. |
| **R13** | Spin direction | The core's spin yaw is `−side·2π·t`: a right-hand start spins **left** (counter-clockwise from above) and moves 1.4 ft left. The shot list follows the code. | Confirm this is the intended direction before the dribble capture day (it's a sign flip if not). |
| **R0** | Anim instance (recommended) | Every value above lives behind non-thread-safe BlueprintPure getters, so the ABP must gather on the game thread. | Add a small C++ `UCLBallerAnimInstance` (parent of `ABP_Baller`) whose `NativeUpdateAnimation` copies these into `UPROPERTY(BlueprintReadOnly)` fields, so the graph can use thread-safe property access. It would also be the natural home for R2/R3/R4 accessors. |
