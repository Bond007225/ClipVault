# Gameplay Programmer (Unreal Engine 5, C++)

## About CourtLife

CourtLife is a basketball game built entirely around **MyPlayer**. You create one player and customize everything: body, face, hair, clothes, tattoos (including your own written text), your **own jumpshot** (a base blended with two releases), and your **own dribble combos** bound to buttons. It is built in **Unreal Engine 5** with MetaHuman, Lumen and Nanite, targeting PC first and then PlayStation and Xbox.

This is not a pitch deck with nothing behind it. There is a playable web prototype, a tested C++ gameplay core, and an Unreal project with the character, shot meter, dribble system, ball, defender AI and customization code already written. We are hiring the first team to make it look and feel like a current-gen game.

**Studio:** [STUDIO NAME] · **Location:** Remote ([TIME ZONES]) · **Contact:** [EMAIL / DISCORD] · **Pay:** [PAY or RATE or REV-SHARE TERMS]

## What you will do

- Get the existing Unreal project compiling and running: `CLBallerCharacter`, `CLShotComponent`, `CLDribbleComponent`, `CLBasketball`, `CLDefenderController`, `CLCustomizationComponent`.
- Own the gameplay feel: movement, shot timing, dribble combos chained from montages, ball physics, defender AI.
- Build the MyPlayer creator UI in UMG on top of the existing build data (`FMyPlayerBuild`) and the rules library (`UCLBuildLibrary`).
- Extend the engine-independent C++ core (`Source/CourtLife/Core`) and keep its tests green.
- Later: 3v3, passing, layups and dunks, then online play.

## Must have

- Shipped a game or substantial project in Unreal Engine 4/5 with C++ (not Blueprint only).
- Comfortable with UObject/UPROPERTY, components, the Gameplay Framework, Enhanced Input and animation montages.
- Able to read and fix someone else's code.

## Nice to have

- Sports, fighting or action games (input timing, animation-driven gameplay).
- Motion Matching / PoseSearch, the Gameplay Ability System, networking/replication.
- You play 2K MyPlayer and have strong opinions about it.

## Paid test task (about 6 hours, [TEST FEE])

1. Clone the repo. Build the core tests: `cmake -S Tests -B build && cmake --build build && ./build/courtlife_core_tests`.
2. Open `CourtLife.uproject` in UE 5.6+ and fix whatever stops it compiling. Send the diff.
3. Make a gray-box level with a `CLCourt` and a mannequin `CLBallerCharacter`. Get a shot to release on Space, with the meter fill printed on screen.
4. Write a short note on what you would change in the architecture, and why.
