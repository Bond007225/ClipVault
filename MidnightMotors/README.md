# Midnight Motors (Roblox)

A Roblox open-world car game: a big procedurally built city, a highway ring,
a long interstate out to drag strips, NPC traffic, police chases, gas stations,
car meets, and cars you can upgrade and customise.

Everything is built from code and parts. There are no external assets, so it
runs as soon as you sync it into an empty place.

## Running it

1. Install [Rojo](https://rojo.space) (the CLI and the Studio plugin).
2. In this folder, run `rojo serve`.
3. Open an empty Baseplate in Roblox Studio, delete the `Baseplate` part, and connect through the Rojo plugin.
4. Press Play. The server builds the map in a few seconds and spawns your starter car at the Midnight Motors garage.
5. To test saving, turn on *Game Settings → Security → Enable Studio Access to API Services*.

**Without Rojo:** open the prebuilt `MidnightMotors.rbxlx` in Studio. It includes a copy of the map so you can see it in edit mode. When you press Play, the server rebuilds the map identically and wires it up to the game systems.

To regenerate that file after changing code, you need [Lune](https://lune-org.github.io):
```
python tools/build_place.py                              # scripts -> MidnightMotors.rbxlx
lune run tools/harness.luau MidnightMotors.rbxlx place   # bake the map into it
lune run tools/harness.luau MidnightMotors.rbxlx both    # smoke-test server + client startup, traffic, menus
lune run tools/harness.luau MidnightMotors.rbxlx events  # play a full race event with a fake player
```

## Controls

| Action | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Enter car (driver / passenger) | E / R at the door | Y / X | tap the prompt |
| Throttle / brake & reverse | W / S | RT / LT | thumbstick |
| Steer | A / D | left stick | thumbstick |
| Handbrake (drift) | Space | A | Brake button |
| Nitrous | Left Shift | X | NOS button |
| Exit car | F (or jump on mobile) | Y | Exit button |
| Manual gearbox toggle / shift | M, then E / Q | RB / LB | – |
| Flip car upright | R (when slow) | – | – |
| Open menu (shop, my cars, upgrades, events) | G | – | Menu button |
| Join / leave the open race event | J | – | Join button on the banner |

## What's in the world

- **City**: an 18×18 grid of blocks, about 5,400 studs across. It has districts: downtown skyscrapers in the middle, a ring of mid-rise offices and apartments, suburbs with houses and lawns, and an industrial area of warehouses in the south-east. Every intersection has a streetlight. Speed limit is 45 mph.
- **Highway ring**: an elevated, 4-lane divided highway on pillars about 32 studs up. It runs around the city, about 25,600 studs per lap. It has **diamond interchanges** where the three main avenues on each side pass underneath. At each one, an exit ramp leaves on the right before the crossing and slopes down to the avenue, and an entrance ramp climbs back up and merges after it. Speed limit is 70 mph and there are speed cameras on the median.
- **Interstate**: an elevated, 9,000-stud highway heading east. Interchange exits lead to a gas station and a rest-stop car meet. At the end it slopes back down to ground level at the outskirts, next to the track complex.
- **Track complex (outskirts)**: a **quarter-mile** and a **half-mile** drag strip side by side. Each has two lanes, a christmas tree, a checkered finish gantry, a grandstand, a results board, a garage, a gas station and the *Strip Meet* lot. There is no speed limit here.
- **Gas stations**: 8 in total (6 in the city, 1 off the interstate, 1 at the track). Use the prompt at a pump with your car nearby. Fuel drains as you drive, faster with bigger engines.
- **Car meets**: Downtown Lot, Neon Plaza, Warehouse Lot, Rest Stop and Strip Meet. Park there and stay near your car to earn cash every 30 s. You earn more when more cars are parked.
- **Garages**: Midnight Motors (downtown), Westside Customs, and Strip Garage (track). Walk up to the blue terminal to open the garage UI.
- **Day/night cycle**: a 24-minute day. Headlights switch on at night, and underglow looks best after dark.

## Cars and upgrades

There are 6 base cars (FWD, RWD and AWD): Kanto Hatch (the free starter), Shiro S-Coupe, Ridge Pickup, Detroit Charger, Akira Rally and Vortex GT-R.

**Performance upgrades** each have 5 tiers (Stock, Street, Sport, Race, Pro):
Engine, Forced Induction, Transmission (shift speed), Suspension (springs, damping, ride height, grip), Brakes, Tires, Weight Reduction, Nitrous (bottle size and shot strength), and Fuel Tank.

**Visual options**: paint (14 colours), finish (gloss, matte, metallic, chrome, carbon), rim colour, underglow, spoiler (ducktail, wing, GT wing) and window tint.

**Free tuning**: ride height, spring stiffness, gearing (acceleration vs. top speed) and visual camber.

Every number lives in `src/shared/Config.luau`.

## Police

Violations only count when someone sees them. That means a **patrol car** in traffic within about 260 studs, a unit that is already chasing someone, or a **speed camera**.

| Violation | Trigger |
|---|---|
| Speeding | more than 7 mph over the zone limit |
| Swerving | 4+ rapid left/right yaw reversals within 4 s above 35 mph |
| Reckless driving | crashing into NPC traffic |
| Hitting a police car | always counts and escalates straight to a pursuit |

How a chase plays out:

- **Heat 1: pull-over.** The patrol car that saw you becomes a pursuit cruiser. If you stop near it for 3 s, you just pay a ticket. If you don't stop within 12 s, it becomes a pursuit.
- **Heat 2–5: pursuit.** More units join as heat rises. The mix goes from cruisers, to interceptors, to pursuit SUVs that ram you. Heat goes up every 45 s you keep evading and with each new offence.
- **Heat 4+:** roadblocks appear ahead of you and spike strips pop your tyres for 20 s.
- **Heat 5:** a helicopter follows you, and you can't escape while it can see you.
- **Busted:** you are slow or on foot near a unit for 4 s. You pay a fine, your car is impounded, and you're sent to the police station.
- **Escaped:** no unit within about 480 studs, and no helicopter overhead, for 12 s. You earn a cash reward.
- Speed cameras flash and mail you a fine. Half the time they also send a unit after you.

## Menu, shop and spawning

- Every player always owns the free **Kanto Hatch**. It's added back even to old saves.
- Press **G**, or use the **Menu / Shop** button, from anywhere. The tabs are:
  - **Shop**: buy cars.
  - **My Cars**: **Spawn** any car you own. It appears in the nearest driving lane next to you.
  - **Performance**, **Visual** and **Tuning**: these apply to the selected car.
  - **Events**: see and join race events.
- Shopping and spawning work anywhere, except during a police chase or a race event. The garage terminals still open the same menu.

## Race events

Every 3 minutes an event opens a 40-second join window. Join with **J**, from the banner, or from the menu's Events tab.

When the window closes, every racer's car is moved to a grid slot and frozen. If you don't have a car out, one is spawned for you. After a 5-second countdown, you race through glowing checkpoint beacons. The HUD shows your lap, checkpoint, live position and time.

| Event | Route |
|---|---|
| Downtown Circuit | 2 laps of the streets around the downtown towers |
| Cross-Town Sprint | Point-to-point zig-zag from the west side to the east side |
| Ring Highway Run | A full lap of the elevated ring, through traffic |
| Interstate Top Speed | A flat-out run down the interstate |

Payouts are $2,500 for 1st, $1,500 for 2nd and $900 for 3rd, and every finisher also gets $300. Police don't ticket racers during an event.

## Drag racing

1. Drive into the pit lot off the interstate exit at the track.
2. Roll into a lane up to the start line and stop. The white **stage** light turns on.
3. A second player has 4 s to stage in the other lane for a head-to-head race.
4. Three ambers, then green. Going early gets you a red light.
5. The server measures **ET**, **reaction time** and **trap speed**. You get paid per run, with a win bonus and a track-record bonus. Personal bests are saved.

## Code layout

```
src/
  shared/          -> ReplicatedStorage.Shared
    Config.luau      all tunables (cars, upgrades, prices, police, racing)
    CarStats.luau    base car + upgrades + tuning -> physics stats (pure)
    CarPhysics.luau  raycast-suspension vehicle sim (client for players, server for police)
    Remotes.luau     single list of remotes
  server/          -> ServerScriptService.Server
    init.server.luau two-phase bootstrap
    Systems/
      PlayerData     DataStore profiles (retries, autosave, BindToClose, reconcile)
      MapBuilder     procedural world + Layout (lanes, pumps, garages, strips, zones)
      CarFactory     builds car models from parts; cosmetics
      CarService     spawn / enter / exit / upgrades / fuel / pumps (all validated)
      Lanes          lane polylines for traffic and police spawns
      Traffic        NPC traffic spawned around players: city cars drive the street grid
                     with turns, highway cars follow the elevated lanes; police patrols
      Police         violations, pull-overs, pursuits, roadblocks, spikes, helicopter
      Racing         quarter/half-mile drag strips, christmas tree, timing
      Events         scheduled race events: lobby, grid, countdown, checkpoints, payouts
      Meets          car meet detection & payouts
      World          day/night cycle, headlights
  client/          -> StarterPlayerScripts.Client
    init.client.luau
    Controllers/
      DriveController  input -> CarPhysics, driving actions
      HUD              speedo, police meters, race overlay, notifications
      GarageUI         main menu: shop / my cars / performance / visual / tuning / events
      RaceEventUI      event banner, countdown, checkpoint beacons, race panel, results
      Sirens           local lightbar flashing
      UI               UI helpers
```

How it fits together:

- **Physics ownership.** When you sit in your own driver seat, the server unanchors the car and gives you network ownership. Your client then runs `CarPhysics`. Parked cars are snapped to the ground and anchored, which keeps them cheap and stable.
- **Server authority.** Prices, garage proximity, upgrade order, cosmetic options and fuel are all checked on the server. Every remote is type-checked and rate-limited.
- **Known limitation.** Like most Roblox driving games, player car physics run on the client, so a cheater could tamper with their own car's speed. If that matters, add a server-side speed sanity check in `CarService`.

## Audio

No audio ships with the project, so there's nothing to license. `Config.Sounds` reserves slots for engine, siren and horn ids, but sound playback isn't wired up yet.
