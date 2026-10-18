# Technical Artist

## About CourtLife

CourtLife is a basketball game built entirely around **MyPlayer**. You create one player and customize everything: body, face, hair, clothes, tattoos (including your own written text), your **own jumpshot** (a base blended with two releases), and your **own dribble combos** bound to buttons. It is built in **Unreal Engine 5** with MetaHuman, Lumen and Nanite, targeting PC first and then PlayStation and Xbox.

This is not a pitch deck with nothing behind it. There is a playable web prototype, a tested C++ gameplay core, and an Unreal project with the character, shot meter, dribble system, ball, defender AI and customization code already written. We are hiring the first team to make it look and feel like a current-gen game.

**Studio:** [STUDIO NAME] · **Location:** Remote ([TIME ZONES]) · **Contact:** [EMAIL / DISCORD] · **Pay:** [PAY or RATE or REV-SHARE TERMS]

## What you will do

- Set the content standards everyone builds against (see `Docs/Team/ONBOARDING.md`):
  - **Skin material**: `SkinTone` and `EyeColor` parameters, plus a `TattooAtlas` render-target texture that tattoos (including custom text) are painted into at runtime.
  - **Garment master material** with `Primary`/`Secondary`/`Tertiary` color masks, and a `Number` parameter on jerseys.
  - **Tattoo atlas UV layout** for 9 body regions, with padding.
- Rigging and retargeting: one skeleton across bodies from 5'9" to 7'3", arm-length scaling for wingspan, and the `ball_prop` bone used in all ball animations.
- Modular clothing that follows the body's pose, Chaos Cloth setup for jerseys and shorts, and Groom hair setup.
- Performance budgets for PC and consoles (Nanite, Lumen, Virtual Shadow Maps, skin cache, LODs).

## Must have

- Shipped work as a tech artist in Unreal Engine 5.
- Strong material graph skills, plus rigging/skinning and the IK Retargeter.
- Able to write clear guides that artists can actually follow.

## Nice to have

- MetaHuman customization and Mesh to MetaHuman, Groom, Chaos Cloth.
- Python or C++ for editor tooling.
- Experience on character-customization-heavy games.

## Paid test task (about 6 hours, [TEST FEE])

1. Build a garment master material with three color masks and expose `Primary`/`Secondary`/`Tertiary`.
2. Build a skin material that composites a `TattooAtlas` texture (RGBA, alpha = coverage) over skin tinted by `SkinTone`.
3. Propose a tattoo atlas layout for the 9 slots in `ECLTattooSlot` (`Public/CLTypes.h`), with the UV rectangle and aspect for each.
4. Send screenshots and a short guide written for a character artist.
