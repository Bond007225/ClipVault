# Welcome to CourtLife: First Week

## Day 1, everyone

1. Play the web prototype: `cd courtlife && npm install && npm run dev`. Make a player, build a jumper and a combo, then hit the court. This is the design target.
2. Read `CourtLifeUE/README.md` and `Docs/PRODUCTION_PLAN.md`.
3. Get repo access ([PERFORCE/GIT LFS SERVER]), the task board ([BOARD LINK]) and team chat ([DISCORD/SLACK]).
4. Install Unreal Engine 5.6+ and open `CourtLife.uproject`.

## Content contracts

The code already expects these names. If you need to change one, talk to the tech artist and the lead programmer first.

### Characters (character artists, tech artist)

| Thing | Contract | Used by |
|---|---|---|
| Body skin material | Vector params `SkinTone`, `EyeColor`; texture param `TattooAtlas` (RGBA, alpha = coverage) | `CLCustomizationComponent.cpp` |
| Body morphs | Morph targets `body_heavy` (weight) and `body_muscular` (muscle), both 0–1 | `UCLCustomizationComponent::HeavyMorph`/`MuscleMorph` |
| Reference height | Body authored at 6'6" (78 in); height is scaled from that | `ReferenceHeightIn` |
| Garments | Skeletal meshes on the body skeleton. Material params `Primary`, `Secondary`, `Tertiary`; jerseys also have scalar `Number` | `Equip()` |
| Catalog keys | Hair `fade`, `afro`, `dreads`…; jerseys `tank`, `tee`, `sleeved`; shorts `short`, `standard`, `long`; shoes `low`, `mid`, `high`; socks `ankle`, `crew`, `high`. These match the web creator, so build codes import | `CLCosmeticsCatalog` data asset |
| Accessories | `headband`, `armSleeve_left/right/both`, `legSleeve_left/right/both`, `wristband_left/right` | `ImportBuildCode` |
| Tattoo stencils | RGBA: R = ink, G = accent, B = 0, A = max(R,G). `TattooRegions` has one UV rect plus aspect per slot in `ECLTattooSlot` order (layout: `Docs/TechArt/MATERIALS.md`) | `RepaintTattoos()` |

### Animation (animators, tech artist)

| Thing | Contract | Used by |
|---|---|---|
| Ball | Every ball-handling clip animates a `ball_prop` bone. Fallback sockets are `hand_r_ball` and `hand_l_ball` | `CLBallerCharacter` |
| Jumpshot bases | Montages keyed by base ID: `classic`, `quickSet`, `highSet`, `sideSet`, `oneMotion`, `setShot`, `legKick`, `hitch`. Each has a **Release** notify at the release frame | `CLAnimSet.ShotBases`, `CLShotComponent` |
| Jumpshot releases | Upper-body sequences: `quickFlick`, `highArc`, `push`, `smoothHold`, `guideFlare`, `slingshot`, `wristy`. Blended by `ReleaseBlend` in the anim BP | `CLAnimSet.ShotReleases` |
| Dribble moves | Right-hand and left-hand montages per move: `crossover`, `killCross`, `betweenLegs`, `behindBack`, `hesitation`, `inAndOut`, `spin`, `stepBack`, `snatchBack`, `pound`. They are time-scaled to the core's durations, so author them at natural speed | `CLAnimSet.DribbleMoves`, `CLDribbleComponent` |
| Finishes | Montages `CLAnimSet.Finishes` keyed `layup` and `dunk`, each with a **Release** notify at the finish profile's release time | `CLShotComponent` |
| Defender | Montages for stumble and contest | `CLDefenderController` |

### Environments

| Thing | Contract |
|---|---|
| Court origin | A `CLCourt` actor on the floor directly under the rim center, forward (+X) toward half court |
| Units | 1 ft = 30.48 uu. Rim at 10 ft, arc at 23.75 ft, corner three at 22 ft, rim radius 9 in |
| Collision | The rim and backboard need simple collision; the ball physics bounces off them after a miss |

### Code (programmers)

- `Source/CourtLife/Core` is plain C++17 with **no Unreal includes**, so it stays testable and shared with the web creator. Gameplay rules go there.
- When you change any rule, update the web creator (`courtlife/src/core`) too, then regenerate `Tests/Golden.inc` and keep the parity tests green.
- Unreal glue lives in `Public/` and `Private/`. Content is referenced only through data assets, never hard-coded paths.

## First-week goals

| Role | Done when |
|---|---|
| Lead programmer | The project compiles, and a mannequin can dribble, shoot and score on a gray-box court with the meter on screen |
| Tech artist | Skin and garment master materials, the tattoo atlas layout and the rig/retarget plan are written up and checked in |
| Character artist | First MetaHuman player in the game wearing one jersey, shorts and shoes in two colorways |
| Animator | Mocap plan and shot list agreed, and a first crossover (both hands) in engine |
| Environment artist | Gray-box park court at correct dimensions, lit for day and night |
