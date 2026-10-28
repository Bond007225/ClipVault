# Ghost Driver–style GUI plan

This is the research and build plan for giving Midnight Motors a GUI like the Roblox game *Ghost Driver*. Work through it step by step in **Claude Code on desktop**, with Roblox Studio open.

## What the research found

These come from fan wikis and guides. Ghost Driver is in pre-alpha, so details change.

- **Core loop: near-miss combos.** You pass AI traffic closely at speed. Each pass gets a grade: *Close Shave*, *Skimmed* or *Paint Scratcher*. A **combo counter at the top of the screen** builds a multiplier, and crashing loses the combo.
- **Progression.** XP comes from combos, quests and races. **Levels unlock upgrade stages**: Stage 1 at level 5, Stage 2 at 15 and Stage 3 at 30.
- **Daily and weekly quests.** Examples are distance, top speed and playtime. Rewards need a manual **Claim** button. The quest button sits **bottom-left** and is marked with a **"!"**.
- **Icon buttons bottom-left** open the Shop (codes, boosts) and Quests.
- **Garage.** Performance upgrades cost cash, and cosmetics (paint, tint, rims) are mostly free.

General Roblox UI practice:

- **Rotating 3D car previews** in the shop, using ViewportFrame. See the [Roblox docs](https://create.roblox.com/docs/ui/viewport-frames).
- **Tweened hover and press feedback**, using TweenService or Styling Transitions.
- **UIStroke and UIGradient** for polished panels.
- **Mobile-first scaling**: use Scale sizes plus a UIScale.
- **Keep the HUD uncluttered**: show money, the objective and the speedometer, not everything at once.

## Already done in this repo

These were not wired in yet when the cloud session paused:

- `src/shared/Config.luau` has new `NearMiss`, `Progression` (XP curve and `TierLevels` gating) and `Quests` sections.
- `src/shared/Remotes.luau` has new `ClaimQuest`, `Combo` and `LevelUp` remotes.
- `src/server/Systems/PlayerData.luau` profiles now have `XP` and `Quests`.
- `src/server/Systems/Progression.luau` handles XP, levels, daily quests and claiming. **It is not yet added to the `ORDER` list in `src/server/init.server.luau`.**
- `src/server/Systems/Traffic.luau` has `Traffic.getAll()` and `Traffic.onPlayerCollision(fn)`, which supports more than one listener. Police already uses it.

## Steps (paste each one into Claude Code)

Each step is one prompt. After each step, run the checks in the next section, then press Play in Studio.

1. **Wire Progression.** Add `"Progression"` to `ORDER` in `src/server/init.server.luau`, right after `"PlayerData"`. Gate `BuyUpgrade` in `CarService.luau` with `Config.Progression.TierLevels`. Award XP and quest progress:
   - miles driven (`Distance`, `XpPerMile`) in CarService
   - drag runs (`DragRun`) in Racing
   - event finishes (`EventFinish`) in Events
   - police escapes (`Escape`) in Police
   - seconds parked at a meet (`MeetTime`) in Meets
   - top speed (`TopSpeed`)
2. **Near-miss combos.** Create `src/server/Systems/NearMiss.luau`:
   - Each tick, check every driven player car going faster than `MinSpeedMph`.
   - For each traffic car within 40 studs, detect a pass: the sign of its position along the car's forward direction flips.
   - Compute the side gap: |lateral| minus both half-widths. Each car model has a `W` attribute.
   - Grade the pass with `Config.NearMiss.Grades`, add to the combo, and fire the `Combo` remote.
   - Bank the combo after `ComboWindow` seconds with no new pass. The payout is cash = points × multiplier × `CashPerPoint`, plus XP.
   - Lose the combo on `Traffic.onPlayerCollision`.
   - Track the `NearMiss` and `Combo` quests.
3. **Car previews.** On server start, build one preview model per car with `CarFactory`. Remove the seats and prompts, anchor every part, and store the models in `ReplicatedStorage.CarPreviews`.
4. **HUD redesign** in `src/client/Controllers/HUD.luau`. Keep its API: `notify`, `setTelemetry` and `flash`.
   - Top-left: level badge, XP bar, and cash that counts up when it changes.
   - Top-centre: combo counter with the multiplier, pending cash and a draining timer bar. Grade pop-ups float up and fade. Show "BANKED +$X" or "COMBO LOST".
   - Bottom-left: an icon dock of rounded square buttons with emoji icons and labels: Shop 🛒, Garage 🔧, Quests ❗ (with a badge when one is claimable), Events 🏁 and Spawn 🚗. Each gets a UIStroke, a UIGradient and hover/press scale tweens.
   - Bottom-right: a segmented tachometer arc (about 24 rotated Frames that light up with RPM, red near redline) with the speed number and the gear in the middle, and nitro and fuel bars underneath.
   - Toasts slide in from the top.
   - Add a UIScale based on screen size so it works on phones.
   - Show a "LEVEL UP" banner when the `LevelUp` remote fires.
5. **Menu redesign** in `src/client/Controllers/GarageUI.luau`. Keep its API: `open`, `close` and `toggle`.
   - Put the tab buttons in a left sidebar with icons, and add a **Quests** tab.
   - The Shop and My Cars tabs become a card grid (UIGridLayout). Each card has:
     - a rotating ViewportFrame preview cloned from `CarPreviews`
     - a class badge
     - stat bars for top speed, acceleration, grip and braking, using `CarStats`
     - a price and a Buy or Spawn button
   - The Performance tab shows upgrade cards with stage pips, and a 🔒 "Lvl X" label on tiers that are still level-locked.
   - The Quests tab shows a progress bar and a Claim button for each quest.
   - The menu fades and slides open, using a CanvasGroup's GroupTransparency.
6. **Polish pass.** Use one colour theme throughout, `Font.GothamBlack` for numbers, and hover sounds if you have audio ids.

## Checks after every step

```
stylua --check src                                        # must parse (formatting diffs are fine)
python tools/build_place.py
lune run tools/harness.luau MidnightMotors.rbxlx both     # server + client start, menus, race UI
lune run tools/harness.luau MidnightMotors.rbxlx events   # full race event with a fake player
lune run tools/harness.luau MidnightMotors.rbxlx place    # bake the map back into the place file
```

Then open `MidnightMotors.rbxlx` in Studio, or use `rojo serve`, and press Play. Watch **View → Output** for red errors.
