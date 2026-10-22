# Snow Peak — multiplayer Roblox snowboarding

A complete Rojo project for an online snowboarding game:

- **Riding physics** that carve on any surface: slopes, kickers, rails and halfpipe walls
- **Smooth trick animations**: spins and flips ease in and out, release the stick and the rotation settles on the nearest clean landing, grabs/crouch/grind poses blend in. Everything is procedural, so no animation uploads are needed
- **Ragdoll wipeouts** on bad landings, high-speed impacts and snowball hits, using physics ball-socket joints
- **Strap in / unstrap at any time.** On foot your board is slung on your back
- **Snowball fights** when you're off the board. Hits are decided by the server
- **Cabin village** with a **Snow Shop** and fitting rooms: hats, glasses, scarves, jackets, long sleeves, gloves, pants, boots and snowboards. Boards have their own speed/turn/pop stats
- **Lobby** with global leaderboards (all-time trick points and best combo) and teleport pads
- **Five trails**: Beginner Run, Rail Garden, and an Olympic set of Slopestyle, Superpipe and Big Air
- Combo system, coins, DataStore saving with session locking

The whole map is generated in code when the server starts (`WorldBuilder.luau`), so the place works as soon as you sync it. No assets need uploading.

## Getting it running

1. Install [Rojo](https://rojo.space) 7.x (CLI + Studio plugin).
2. Either:
   - **Live sync:** `rojo serve` in this folder, open a new Baseplate in Studio, delete the Baseplate part, then connect the plugin.
   - **Build a file:** `rojo build -o SnowPeak.rbxl`, then open it in Studio.
3. **Game Settings → Avatar:** set Avatar Type to **R15** (the trick poses are written for R15 rigs).
4. **Game Settings → Security:** enable **Studio Access to API Services** if you want saving and global leaderboards in Studio. Without it the game still runs; progress just isn't saved, and the leaderboards show players in the current server.
5. Press Play. To test snowball fights and multiplayer, use **Test → Clients and Servers** with 2+ players.

## Controls

| Action | Keyboard / mouse | Gamepad | Mobile |
|---|---|---|---|
| Strap in / unstrap | E | B | "Board" button |
| Carve (ground) / spin (air) | A / D | Left stick ← → | Thumbstick |
| Push, brake (ground) / flip (air) | W / S | Left stick ↑ ↓ | Thumbstick |
| Ollie (hold to charge, release to pop) | Space | A | "Ollie" button |
| Grabs: Indy / Method / Nose / Tail | Q / F / R / T | X / Y / LB / RB | "Grab" button (Indy) |
| Grind | Drop onto a rail or box from above | | |
| Throw snowball (on foot) | Left click | RT | "Throw" button |
| Orbit the camera while riding | Hold right mouse | Right stick | |
| Open the shop | G at the counter or fitting room | X | Tap the prompt |
| Hide the controls panel | H | | |

**Scoring:** Spins (each 180°), flips, grabs (longer holds score more), airtime and grinds all score. Corks (a flip and a 360+ spin together) get a 25% bonus. Tricks you chain within 3 seconds of each other stack a combo multiplier, up to x5. A combo banks once you stop chaining tricks. If you crash first, you lose the whole pending combo. Banked points count toward the leaderboard, and 10% of them come back as coins.

## Project layout

```
src/
  shared/                     ReplicatedStorage.Shared
    Config.luau               all tuning: physics, scoring, snowballs, economy
    Catalog.luau              every shop item (+ board stats)
    Cosmetics.luau            builds outfits and boards from welded parts
    Tricks.luau               trick naming, scoring, report validation (pure)
    Remotes.luau              declares every RemoteEvent/Function
  server/                     ServerScriptService.Server
    Main.server.luau          bootstrap
    Services/
      WorldBuilder.luau       terrain, trails, park features, lobby, village, pads
      DataService.luau        session-locked saving, autosave, BindToClose
      SnowboardService.luau   board on feet/back, riding state, pose relay
      TrickService.luau       validates + scores tricks, combos, wipeouts
      RagdollService.luau     Motor6D ↔ BallSocket ragdolls
      SnowballService.luau    server-simulated snowballs and hits
      ShopService.luau        purchases / equipping
      LeaderboardService.luau OrderedDataStore boards in the lobby
      RateLimiter.luau        per-player token bucket for remotes
  client/                     StarterPlayerScripts.Client
    Main.client.luau          bootstrap
    Controllers/
      SnowboardController     riding physics, tricks, grinds, landings, crashes
      PoseController          procedural animation for every rider
      CameraController        speed-aware chase camera
      RagdollController       Physics state while ragdolled, knockback
      SnowballController      throwing + visuals
      ShopController          shop / fitting room UI with live preview
      HUDController           points, coins, trick popups, combo meter
      EffectsController       snowfall
```

## How the multiplayer pieces fit together

- **Riding** runs on the client, because Roblox gives each player physics ownership of their own character, so movement replicates on its own. The server decides *whether* you're riding (the `Riding` attribute). The client only asks to toggle it.
- **Poses**: the rider sends a tiny pose name and lean value over an `UnreliableRemoteEvent`. The server validates it and sets it as attributes. Every client then animates every rider from those attributes, and spins/flips arrive through normal physics replication.
- **Tricks**: the client sends raw data (airtime, spin degrees, flips, grab, grind time), never points. The server checks the data is physically plausible (max rotation rates, no overlapping airtime, rate limits), then scores it with the shared `Tricks` module.
- **Snowballs** are simulated on the server with sphere-casts, and only the server decides hits. Clients just draw the balls.
- **Shop**: prices, ownership and coins are checked on the server. The client only sends item ids.

## Customising

- **Feel:** everything in `Config.luau` (speed, grip, spin rate, ollie power, landing tolerance, crash sensitivity, snowball ragdoll on/off, combo window, coin rate).
- **New items:** add a row to `Catalog.luau`. Pick an existing `Style`, or add a builder in `Cosmetics.luau`.
- **Hand-built map:** you can replace generated pieces with your own models. Gameplay only depends on:
  - the `Grindable` CollectionService tag for rails and boxes (each part's length runs along its Z axis)
  - teleport pads having a `Destination` attribute that names a part in `Workspace.Map.Destinations`
  - leaderboard parts having a `Stat` attribute and a `Rows` frame in their SurfaceGui
  - shop prompts having an `OpensShop` attribute
- **Real animations:** if you'd rather use uploaded animations, play them from `PoseController`. It already gets the pose name for every rider.

## Validation done

- Every script type-checks cleanly under `--!strict` with `luau-lsp` against the Roblox API definitions.
- `rojo build` produces a working place file.
- The trick validator and scorer (`Tricks.luau`) were unit-tested with the Luau CLI.
- The game has **not** been playtested in Studio yet. Expect to tune physics values and the coordinates of some generated geometry after your first ride.
