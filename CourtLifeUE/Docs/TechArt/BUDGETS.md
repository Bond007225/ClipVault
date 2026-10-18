# CourtLife Performance Budgets

These are starting budgets for Sprint 1. We will tighten them once we can profile a full park scene on target hardware. Platforms:

- **PC**: recommended spec RTX 3070 / RX 6800 class, 1440p, upscaled with TSR, DLSS or FSR.
- **Console**: PS5 and Xbox Series X. Xbox Series S gets the console budget with textures dropped one mip and lower screen percentage.

Frame target: **60 fps** (16.6 ms) in gameplay on both. The creator and menus can run at 30 fps with higher quality. The worst case is gameplay with **10 players on screen** (5v5 park), plus crowd cards and the court.

## Characters (the player is the product, so spend here)

| Asset | PC | Console | Notes |
|---|---|---|---|
| Body + head, LOD0 | 60–80k tris | 45–60k tris | MetaHuman LOD0 is heavier. Use MetaHuman LOD1 as our LOD0 in gameplay and keep LOD0 for the creator and replays |
| LODs | 5 (LOD0–LOD4), ~50% per step | same | LOD4 at or below 5k tris. Screen sizes about 1.0 / 0.5 / 0.25 / 0.12 / 0.06 |
| Skeleton | ≤ 250 bones, ≤ 8 influences | ≤ 250 bones, ≤ 4 influences beyond LOD0 | Includes `ball_prop`, `hand_r_ball`, `hand_l_ball`. Face rig bones are culled after LOD1 |
| Morph targets | `body_heavy`, `body_muscular` + face | same | GPU morph targets on; skin cache on |
| Body textures | 4K base color / normal / ORM in the creator, 2K in gameplay | 2K | Through texture streaming. Skin detail normal is tiled at 512 |
| Tattoo atlas | 2048 RGBA8 render target, 16 MB | same | One per visible custom player. Drop to 1024 for players beyond about 5 m, or share one atlas for NPCs |
| Material slots | ≤ 4 on the body (body, head, eyes, teeth/mouth) | same | Every slot uses `M_Skin_Master` instances |
| Draw calls per player | ≤ 20 (body + garments + hair) | ≤ 15 | Each modular piece is a separate draw. Merge accessories where possible |

## Garments (modular skeletal meshes on the body skeleton)

| Asset | PC LOD0 | Console LOD0 | Textures | Notes |
|---|---|---|---|---|
| Jersey | 8–12k tris | 6–9k | 2K BC + N + ORM + mask (mask can be 1K) | Chaos Cloth on LOD0–1 only; skinned only on LOD2+ |
| Shorts | 6–10k | 5–8k | 2K | Chaos Cloth on LOD0–1 |
| Shoes (pair) | 10–15k | 8–12k | 2K | Rigid-skinned to the foot and ball bones |
| Socks | 2–4k | 2–3k | 1K | |
| Accessories (each) | ≤ 3k | ≤ 2k | 512–1K | Headband, sleeves, wristbands |
| LODs | 4, matching the body screen sizes | same | | Delete hidden body triangles under tight garments with the body-part mask |

- Every garment uses an `M_Garment_Master` instance with a `ColorMask` (sRGB off).
- Garment meshes do **not** use Nanite. Skeletal Nanite is still experimental in 5.6, so we only consider it after profiling.
- Cloth sim budget: ≤ 2 cloth assets per player and ≤ 1.0 ms of cloth for all 10 players on console. Disable cloth beyond about 15 m.

## Hair (Groom)

| Setting | PC | Console |
|---|---|---|
| Strands, LOD0 | ≤ 60k guides / 150k strands (afro, dreads) | ≤ 40k / 100k |
| Groom LODs | strands → cards at about 0.3 screen size → mesh at about 0.1 | cards from about 0.4 screen size |
| Cards fallback | ≤ 15k tris, 2K atlas | same |
| Physics | creator only, or the local player in gameplay | local player only |

- Short styles (`fade`, buzz) should be **cards or texture on the head mesh**, not strands.
- Hair color arrives as the `Primary` vector param, so the groom and card materials must expose `Primary`.

## Environments (park courts)

| Asset | Budget | Notes |
|---|---|---|
| Static props, courts, fences, buildings | **Nanite on** for everything static and opaque | No LODs needed for Nanite meshes. Keep a fallback mesh about 2% of source |
| Nanite triangle source | ≤ 2M per hero prop, ≤ 50M scene total on disk | Nanite renders the visible triangles; on-disk size is the real limit |
| Masked foliage (fences, leaves) | Nanite with masked materials (5.1+); keep masked area small | Chain-link fence: geometry or Nanite, not a large masked plane |
| Court floor | 4K base color + normal + ORM, plus a 2K line and logo decal set | Lines must hit the court units in ONBOARDING (1 ft = 30.48 uu) |
| Rim and backboard | Simple collision only, Nanite off | Ball physics needs clean, simple collision |
| Texture memory, whole level | ≤ 2.5 GB streaming pool PC, ≤ 1.8 GB console | Use virtual textures for large terrain and court decals |
| Crowd / NPC spectators | Animated cards or low-LOD skeletal (≤ 5k tris) | Not full MetaHumans |

## Lighting and shadows

- **Lumen** GI and reflections: on for both platforms. Console uses the Lumen *High* scalability with software ray tracing. PC can turn on hardware ray tracing as an option.
  - Interior gyms: keep emissive light sources as real lights. Lumen emissive alone is noisy.
  - Lumen cost target: ≤ 4 ms on console at 60 fps.
- **Virtual Shadow Maps (VSM)**: on. Characters and the ball must be **Movable**. Keep the number of shadow-casting local lights per court to ≤ 4 (day: sun + 1 to 2 fills; night: 4 court floodlights).
  - Turn off *Cast Shadow* on tiny props and accessories to save VSM page invalidation.
  - Avoid world position offset on large Nanite meshes, because it invalidates VSM pages every frame.
- Skin: use a **Subsurface Profile** shading model (next skin task), and make sure skin cache is on (`r.SkinCache.CompileShaders=1`) for the morph targets.
- Post: TSR at about 67% screen percentage on console, 75–100% on PC. Keep motion blur low; it smears the dribble moves.

## Frame budget (console, 16.6 ms GPU)

| Pass | Budget |
|---|---|
| Base pass + Nanite | 4.0 ms |
| Lumen (GI + reflections) | 4.0 ms |
| Shadows (VSM) | 2.5 ms |
| Characters (10 players, skin cache, morphs, grooms) | 2.5 ms |
| Translucency, VFX, UI and shot meter | 1.5 ms |
| Post + TSR | 2.0 ms |

## How to check

- `stat unit`, `stat gpu`, `ProfileGPU` (Ctrl+Shift+,), and Unreal Insights for CPU (cloth, animation).
- Viewport > **Nanite Visualization** and **Lumen > Overview**. Use `r.Shadow.Virtual.Visualize` for VSM page invalidation.
- Character LODs: Skeletal Mesh Editor > LOD settings. Check `stat anim` and `stat cloth` with 10 players spawned.
