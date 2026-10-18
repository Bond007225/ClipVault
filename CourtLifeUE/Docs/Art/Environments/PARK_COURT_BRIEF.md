# Venue Brief: City Park Court (Venue 01)

Owner: environment art. Status: Sprint 1, textures + gray-box done, unverified in Unreal.
Companion venue: indoor gym (Venue 02), which uses the same pipeline. Gym notes are at the end.

## 1. Fantasy and mood

This is the court where your MyPlayer starts out. It's a public court in a
dense city neighbourhood: free to play, well used, and looked after just enough
to stay playable. It should feel like a real place with a history, and it should
never look derelict.

Mood references, described in words (no external images are checked in):

- **Late-afternoon summer.** Low warm sun rakes across the court. The fence throws long shadows. The acrylic coat has gone chalky and pale where the sun hits it most, and a heat haze sits over the asphalt beyond the fence.
- **The surface tells its story.** The green colour coat and terracotta key are worn through to grey asphalt under the rim and at the free-throw line. Long transverse cracks have been sealed with glossy black tar bands. One rectangle was repaired and re-rolled in a slightly fresher green. There are gum spots, sneaker scuffs, and dirt that collects along the sidelines and in low spots where puddles dry.
- **The lines were repainted more recently than the surface was resurfaced.** They're still readable but chipped and slightly soft-edged, and dirty where traffic crosses them.
- **Night.** Two or four LED flood poles give hard, slightly cool white pools of light on the court and fall off fast at the fence. Sodium-orange streetlights sit beyond the fence, and the windows of the apartment blocks behind are lit warm. Moths circle the floods. The court should be the brightest thing in frame.
- **Sound and life (for audio/design).** Distant traffic, the chain net, the rattle of the fence when a ball hits it, a bench crowd of two or three.

Readability rules that beat realism:

1. Line markings must stay readable from the gameplay camera, which sits about 17 ft behind the shooter at the top of the arc, 8 ft up. Wear may chip lines but must never erase the three-point line or the key.
2. Value contrast: the court surface sits in the middle values (albedo roughly 0.25 to 0.45). Lines are the brightest thing on the floor. The worn asphalt is the darkest.
3. Keep detail along the playing surface low-frequency so the ball and players read against it. Busy detail goes on the surround (fence, graffiti, foliage).

## 2. Deliverables this sprint

| File | What |
|---|---|
| `SourceArt/Environments/tools/gen_courts.py` | Reproducible generator (fixed seeds) for both venues; `--preview` renders camera previews |
| `SourceArt/Environments/tools/test_court_lines.py` | Checks line geometry against regulation by sampling the masks (27 tests) |
| `SourceArt/Environments/Textures/T_ParkCourt_BaseColor.png` | 2048², sRGB, lines baked in |
| `SourceArt/Environments/Textures/T_ParkCourt_Lines.png` | 2048², linear mask, worn lines (255 = paint) |
| `SourceArt/Environments/Textures/T_ParkCourt_Roughness.png` | 2048², linear |
| `SourceArt/Environments/Textures/T_GymFloor_*.png` | Same set for the gym, plus `T_GymFloor_PaintMask.png` (key + out-of-bounds border) |
| `SourceArt/Environments/_preview_park.png`, `_preview_gym.png` | Perspective previews from the gameplay camera |
| `Content/Python/environments/court_dims.py` | All dimensions and the gray-box layout, in plain Python |
| `Content/Python/environments/blockout_half_court.py` | Editor script that spawns the gray-box (`import unreal`) |
| `Content/Python/environments/test_court_dims.py` | Unit tests for the layout, cross-checked against `CLShooting.h` and `CLCoreBridge.h` |

Regenerate everything:
```
cd CourtLifeUE/SourceArt/Environments/tools
python3 gen_courts.py --preview        # ~30 s, both venues
python3 -m unittest test_court_lines
cd ../../../Content/Python/environments && python3 -m unittest test_court_dims
```

## 3. Texture layout (the contract the material relies on)

- Each texture is 2048 × 2048 at **40 px per ft**. The half court (50 ft wide × 47 ft from baseline to half court) takes up 2000 × 1880 px, centred. That leaves an apron of 24 px (0.6 ft) on the left and right and 84 px (2.1 ft) at the top and bottom. The apron carries the out-of-bounds colour.
- The **baseline is at the top of the image** (row 84) and half court is at the bottom (row 1964). The rim centre is at pixel (1024, 294).
- Columns increase along core +x, which is **Unreal −Y** in the CLCourt frame. Rows increase along **Unreal +X** (toward half court).
- Lines follow the NBA convention. The 2 in line sits inside the dimension it marks: the three-point outer edge is at 23.75 ft, the corner-three outer edge at 22 ft, the key outer edges at ±8 ft, the free-throw line far edge at 19 ft from the baseline, and the free-throw and centre circles have their outer edge at a 6 ft radius. The restricted-area inner edge is at 4 ft, and the half-court line is centred on 47 ft. The bottom half of the free-throw circle is dashed. Lane-space marks sit at 7, 8, 11 and 14 ft.

### Mapping onto the 50 × 47 ft floor

The blockout floor's UVs cover only the court, so remap them in the material:
`UV_tex = UV * TEX_UV_SCALE + TEX_UV_OFFSET` with scale (2000/2048, 1880/2048) and offset (24/2048, 84/2048). The values are in `court_dims.py`.
The orientation of the engine Plane's UVs is **not verified**. If the key shows up at the wrong end or mirrored, flip or rotate the UV in the material. A more robust option is to compute the UV from world position in the court frame. `court_dims.court_local_to_tex_uv()` gives the exact formula:
`u = (24 + (25 − LocalY_ft) · 40) / 2048`, `v = (84 + (LocalX_ft + 5.25) · 40) / 2048`.

### Proposed floor material (needs tech-art sign-off; not yet in ONBOARDING)

`M_CourtFloor` master, instanced as `MI_ParkCourt` and `MI_GymFloor`:

| Param | Type | Notes |
|---|---|---|
| `FloorBaseColor` | Texture (sRGB) | `T_*_BaseColor` |
| `FloorRoughness` | Texture (linear) | `T_*_Roughness` |
| `LineMask` | Texture (linear) | `T_*_Lines`. Lets you tint lines (`LineTint`) and set line roughness (`LineRoughness`), and drives wet-night puddles that avoid paint |
| `PaintMask` | Texture (linear) | Gym only, for recolouring the key with `TeamColor` |
| `Wetness` | Scalar 0–1 | Night/rain variant. Lowers roughness and darkens albedo, except on lines |
| `DetailNormal` | Texture | Tiling asphalt/wood-grain micro-normal, about 2 ft repeat, fades out by 30 ft |

Packing (for later): Roughness, Lines and Paint can go into one linear RGB texture (`T_*_Masks`) to save two samplers.

## 4. Gray-box (blockout_half_court.py)

Run it in the editor (it's **unverified in Unreal**, so expect small API fixes on first run):
```
py "<Project>/Content/Python/environments/blockout_half_court.py" --origin 0,0,0 --yaw 0 --venue park --floor-material /Game/Environments/Courts/MI_ParkCourt
```
It spawns the following, in one undo transaction under the `CourtLife/HalfCourt_park` folder:

- A `CLCourt` actor at the origin. This is the floor point under the rim centre, facing half court (+X).
- A floor Plane, 47 ft (X) × 50 ft (Y), running from X = −5.25 ft (baseline) to 41.75 ft (half court). A hidden 0.5 ft collision slab sits under it.
- A stanchion pole 4 ft behind the baseline (6 in diameter, 12.5 ft tall) with an arm to the back of the board.
- A backboard, 6 × 3.5 × 0.25 ft. Its front face is at X = −1.25 ft (4 ft from the baseline), and its bottom edge is at 9.5 ft.
- A rim made of 24 cylinder segments of 5/8 in tube. The inner radius is 9 in, the top is at 10 ft, and the rim centre is 15 in in front of the board. A bracket connects it to the board.
- `BlockAll` collision on the rim, backboard, pole and floor. Basic shapes come with simple collision. Check that the rim segments keep their simple collision when they're scaled this thin. If the ball tunnels through, enable CCD on the ball or thicken the collision ring.

1 ft = 30.48 uu throughout. All the numbers are in `court_dims.py`, which is checked against `CLShooting.h` (`kRimHeightFt`, `kRimRadiusFt`, `kThreePtRadiusFt`, `kCornerThreeXFt`, `kBaselineZFt`) by `test_court_dims.py`.

## 5. Modular kit (final art, park)

| Asset | Notes | Tris (LOD0) |
|---|---|---|
| Court floor | One plane plus the 2048² set above. Later: a full-court variant | 2 |
| Asphalt surround tile | Tiling 4k trim, 4 m repeat, with decals for variety | 2 / tile |
| Curb, sidewalk, grass verge | Spline mesh kit | 500 / 4 m |
| Chain-link fence panel, 10 ft × 12 ft | Masked opacity card plus a mesh frame, with bent and damaged variants | 300 |
| Fence posts, top rail, gate | Snap to 10 ft grid | 200 each |
| Stanchion A: gooseneck pole + fan steel backboard | Classic park | 6k |
| Stanchion B: square pole + rectangular acrylic board | Renovated court | 6k |
| Rim: double rim / single breakaway | Collision is a ring of capsules | 2k |
| Nets: chain, torn nylon, none | Chain net uses a physics or anim asset (coordinate with tech art) | 1.5k |
| Benches (2), bleacher (3-row aluminium) | | 2k / 4k |
| LED flood light pole (2 heads), streetlamp | Emissive heads plus IES spot | 3k |
| Trash can, water fountain, bike rack, park sign (generic, no real branding) | | 1–2k each |
| Trees (2 species × 3 sizes), shrubs, weeds in cracks | Nanite foliage or cards. Keep it off the court | per foliage budget |
| Backdrop: 4–5 storey brick apartment facades, corner store | Low-detail, about 60 m away | 20k total |
| Decals: graffiti (original art only), puddles, leaves, litter, oil, chalk marks | DBuffer decals, never inside the key | — |

## 6. Lighting

Day (`LV_Park_Day`):
- A directional light at about 30° elevation and 5600 K. Aim it so the backboard shadow falls across the key, not toward the camera. Use a Sky Atmosphere and Sky Light (real-time capture) and Volumetric Clouds (sparse). Lumen GI is on.
- Exposure: manual or clamped auto, around EV100 13–14, so the court albedo reads true.
- The fence shadows give the floor its "pattern". Keep them soft enough not to fight the lines.

Night (`LV_Park_Night`):
- Use 2 LED flood poles at the corners behind each baseline (4 for a full court). Spot lights at 4000–4500 K with an IES profile and inner and outer cones covering the half court evenly. Aim for about 300–500 lux on court, with the minimum at least half the average.
- Sodium streetlights (2000 K) sit outside the fence, with emissive windows on the backdrop. Moon: a directional light at 0.05–0.1 lux, blue.
- Set the floor `Wetness` to 0.15 for a faint dew sheen on the asphalt. Painted lines stay dry-looking.
- Every court light is a stationary or movable spot with shadows from the floods only (cap at 4 shadowed lights in view).

Both setups must keep the ball readable. Check them with the gameplay camera at the top of the arc, in the corners, and under the rim.

## 7. Performance budgets (target 60 fps on current-gen consoles, 1440p upscaled)

| Item | Budget |
|---|---|
| Court floor textures | 3 × 2048² (or 1 BaseColor + 1 packed mask), streaming, about 8 MB VRAM compressed |
| Whole venue texture memory | ≤ 400 MB |
| Draw calls (park, in view) | ≤ 1500. Use HISM/ISM for fence, posts and foliage |
| Triangles in view | ≤ 3 M with Nanite on static kit; skeletal players excluded |
| Dynamic shadowed lights | ≤ 4 in view at night |
| Translucency | Fence cards masked (not translucent). Nets are the only translucent-ish material |
| Lumen | Software ray tracing, medium. Bake reflection captures as a fallback |

## 8. What a human artist still needs to do

- Replace the procedural asphalt close-up with scanned asphalt or acrylic detail. The worn patch under the rim looks noisy and fractal at 1 m.
- Add a tiling detail normal. Paint final crack, sealer and patch placement by hand so it supports gameplay (nothing dramatic in the shooting lanes).
- Author the fence, stanchion, rim, net, foliage and backdrop kit (section 5), plus the original graffiti and decal sheet.
- Do the lighting passes in engine, day and night, from the gameplay camera.

## 9. Gym (Venue 02) notes

The gym floor is maple strips 2¼ in wide that run from the baseline to half court. Each column is made of staggered boards of random length, 2–9 ft. Board tones vary subtly, and the floor has growth-ring grain and an amber polyurethane tint. The roughness map (~0.25–0.4) has sheen variation and higher roughness in traffic areas.

The key and the out-of-bounds border are painted in the team colour (default navy `(24, 52, 128)`), with the grain showing through. White lines are crisp. The centre-circle logo area is plain wood. Use `T_GymFloor_PaintMask` with the proposed `TeamColor` param to recolour the floor without regenerating it.

Lighting: overhead LED high-bays at 5000 K, an even 1000+ lux, and strong floor reflections. That needs Lumen reflections or SSR, because the gloss is the main read of a gym floor.
