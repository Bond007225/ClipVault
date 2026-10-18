# CourtLife

A MyPlayer-first basketball game. You build one player exactly how you want, from how they look to how they shoot and how they handle the ball, then take them on the court.

This is a standalone project. It has nothing to do with the ClipVault app elsewhere in this repo.

This web version is the fast prototype and companion creator. The production game for PC and consoles is the Unreal Engine 5 project in `../CourtLifeUE/`. It uses the same gameplay math, ported to C++ with parity tests, and imports build codes made here.

## Run it

```bash
cd courtlife
npm install
npm run dev     # open the printed localhost URL
npm test        # core game logic tests
npm run build   # production build in dist/
```

## What's in v0.1

**MyPlayer Creator**
- **Body:** height (5'9" to 7'3"), weight, wingspan, muscle, skin tone (presets or any color). Your frame sets your attribute caps.
- **Face & Hair:** 11 hairstyles, 6 facial hair styles, any hair, beard or eye color.
- **Outfit:** jersey style and colors (your name and number are printed on it), shorts length, colors and stripe, 3 shoe models with upper, accent and sole colors, sock length, headband, arm and leg sleeves (left, right or both), wristbands.
- **Tattoos:** 9 body spots with up to 3 pieces per spot. There are 12 designs, including **custom script text**. Each piece has its own ink and accent color, size, up/down position and rotation around the limb. Sleeves cover tattoos.
- **Attributes:** 17 ratings with a point budget. Caps come from your body, so you trade off instead of paying to win. Overall rating and archetype update live.

**Jumpshot Creator**
- 8 bases and 7 releases. You blend two releases with a percentage slider and choose from 5 release speeds.
- The preview plays the same animation and timing you shoot with in game.
- It shows release time, green window, release height, contest resistance and rhythm. Blending releases with mismatched tempos shrinks your green window.

**Dribble Creator**
- 10 moves: crossover, kill cross, between the legs, behind the back, hesitation, in-and-out, spin, step back, snatch back and pound.
- Chain up to 6 moves per combo, set each step's speed, and bind combos to keys (1-4, Q, E, R, F).
- Ball Handle decides your top step speed and unlocks elite moves (for example, Snatch Back needs 80).
- The preview shows combo length and an "ankle breaker" rating.

**On Court (1-on-1 half court)**
- Move with WASD, sprint with Shift, and fire your combos with their bound keys.
- Hold Space to shoot. The shot meter's green zone comes from your own jumpshot. Greens are buckets unless you're smothered.
- An AI defender reads you based on its Perimeter Defense rating. It closes out and contests shots, and your combos can break its ankles.
- The game tracks points, FG, 3PT, greens and ankles broken. Press T to toggle the defender for shootaround.

**Sharing**
- Save up to 10 MyPlayers in the browser.
- **Build codes** copy your whole player (looks, jumper and combos) as text, so the community can share and import builds.

## Layout

```
src/core/    pure game logic (no rendering), fully unit tested
  player.js      player schema, defaults, and sanitizing for shared or old saves
  attributes.js  body-based caps, budget, overall rating, archetype
  jumpshot.js    bases, releases, shot profile, shot animation keyframes
  dribble.js     move library, combo validation, combo timelines
  shooting.js    meter grading, contest, make probability, 3pt line
  locomotion.js  skeleton proportions, idle/run poses, arm reach
  storage.js     save slots and build codes
src/render/  Three.js: procedural character rig, tattoo painter, court, studio
src/game/    1-on-1 game loop and defender AI
src/ui/      menu and creator screens
```

The core is kept separate from rendering on purpose. The jumpshot or combo you see in the creator is the same data the game uses, and all of it can be tested without a browser.

## Roadmap

These are the things the community keeps asking for, roughly in order:

1. **Current-gen graphics:** the Unreal Engine 5 project (`../CourtLifeUE/`) with MetaHuman players, Lumen and Nanite. See its production plan.
2. **Motion-captured animation:** the same creator data drives mocap clips in Unreal, blending bases and releases on a skeleton.
3. **More of the bag:** signature size-ups, dribble styles, hop steps, eurosteps, layups and dunks, plus a dunk creator.
4. **Full games:** 3v3 and 5v5 with teammate AI, passing, rebounding, fouls and a shot clock.
5. **Progression without pay-to-win:** earn upgrades by playing, with no paid currency for attributes.
6. **Online:** a park/rec-style matchmaking hub with server-authoritative shot timing.
7. **Clothing and tattoo editors:** custom logo and design uploads with layers.
