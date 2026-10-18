# CourtLife (Unreal Engine 5)

This is the production version of CourtLife, aimed at PC and current-gen consoles. It is built on Unreal Engine 5 for MetaHuman characters, Lumen lighting, Nanite geometry, and access to PlayStation, Xbox and Switch builds.

The web prototype in `../courtlife/` stays useful as a fast design tool and a companion creator. **Its build codes (`CL1.…`) import straight into this project** (`UCLBuildLibrary::ImportBuildCode`).

## Status

| Part | State |
|---|---|
| Gameplay core (`Source/CourtLife/Core`): attributes, jumpshot timing and green window, dribble combos, shot grading and make odds, defender AI | **Done and tested.** Builds with any C++17 compiler. The parity tests prove it matches the web creator's numbers exactly. |
| Unreal gameplay layer (`Public/`, `Private/`): character, shot meter, combo runner, ball, court, defender AI, game mode, saves, customization with a runtime tattoo atlas | **Written but not yet compiled in Unreal.** There was no Unreal install where it was written. Expect a short round of compile fixes on first open. |
| Art and animation: MetaHuman bodies, clothing, hair, arenas, mocap | **Not started.** This needs artists and a Windows/GPU workstation (see `Docs/PRODUCTION_PLAN.md`). |

## Requirements

- Windows 10/11 PC with an RTX 3070-class GPU or better and 64 GB RAM recommended
- Unreal Engine 5.6+ from the Epic Games Launcher (change `EngineAssociation` in `CourtLife.uproject` if you use another version)
- Visual Studio 2022 with the "Game development with C++" workload

## First open

1. Right-click `CourtLife.uproject` and choose **Generate Visual Studio project files**.
2. Open `CourtLife.sln` and build `CourtLifeEditor | Win64 | Development Editor`.
3. Launch the editor and create these assets:
   - **Map** `/Game/Maps/Court`. Place one `CLCourt` actor on the floor under the rim, with its forward arrow pointing to half court. Add a rim mesh with collision 10 ft (304.8 uu) above the floor.
   - **Ball BP** derived from `CLBasketball`. Use a 9.4" sphere mesh with a bouncy physical material.
   - **Player BP** derived from `CLBallerCharacter`. Assign the body mesh and anim BP, `AnimSet`, `Catalog`, `BallClass`, and the input actions (Move, Sprint, Shoot, 8 combo slots) plus their mapping context.
   - **Defender BP**: any Character with `AIControllerClass = CLDefenderController`. Set it as `DefenderClass` on a `CLGameMode` BP.
   - **Data assets**: one `CLAnimSet` and one `CLCosmeticsCatalog` under `/Game/Data`.

## Running the core tests (no Unreal needed)

```bash
cmake -S Tests -B build && cmake --build build && ./build/courtlife_core_tests
```

If you change the web creator's math, regenerate the golden values with `node Tests/gen_golden.mjs > Tests/Golden.inc` and the parity tests will flag any drift.

## How the creator choices become visuals

- **Jumpshot.** Each base is a lower-body montage and each release is an upper-body animation. The anim graph layer-blends Release1 and Release2 by `FCLShotProfile::ReleaseBlend`, and the montage plays at `PlayRate`. Each base montage has a "Release" notify at the core's `releaseT`, so the shot meter and the animation always agree.
- **Dribble moves.** Each move has a right-hand and a left-hand montage. The combo runner plays them back to back, time-scaled to the core's per-step durations, and tracks which hand holds the ball. You can author the displacement as root motion (set `bUseRootMotion`) or let the core move the player.
- **Looks.** Clothing, hair and accessories are modular skeletal meshes that follow the body's pose. Colors are set through `Primary`, `Secondary` and `Tertiary` material parameters. Tattoos are painted at runtime into a texture atlas that the skin material reads, so custom script text works the same way it does on the web.
