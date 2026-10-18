# CourtLife Production Plan: PC and Consoles

Code alone can't produce graphics that compete with today's games. That comes from the art pipeline, the animation pipeline and console access, and each of those needs people, hardware and approvals. This plan covers how to get from the current state to a launch.

## 1. Engine: Unreal Engine 5

- **MetaHuman** gives photoreal heads and bodies with a deep face and body editor, which is exactly what a MyPlayer creator needs.
- **Lumen** (dynamic lighting) and **Nanite** (high-detail geometry) cover arena lighting, reflections on the hardwood and detailed crowds.
- **Motion Matching** (the PoseSearch plugin) gives fluid locomotion from mocap data, which is the biggest single step up in how the game feels.
- **Chaos Cloth** handles jerseys and shorts, and **Groom** handles strand-based hair: braids, dreads and afros.
- Console support comes through each platform holder's program (see section 5).
- The license is free to start, with a 5% royalty above $1M gross per title. Check Epic's current EULA terms.

## 2. Art pipeline

| Need | Tooling | Notes |
|---|---|---|
| Player faces and bodies | MetaHuman, Mesh to MetaHuman | Height, weight, wingspan and muscle map to body types and morphs. Face presets plus sculpting. |
| Hair | Groom (Alembic from Houdini/Blender) | One groom per hairstyle in the catalog. |
| Clothing | Marvelous Designer → Maya/Blender → Substance Painter | Modular skeletal meshes with color masks for `Primary`/`Secondary`/`Tertiary`. |
| Shoes | Substance plus photogrammetry | Original designs only (no real-brand logos without licenses). |
| Tattoos | 2048² stencil textures (R = ink, G = accent) | Atlas regions per slot are set in `CLCosmeticsCatalog`. |
| Arenas and parks | Nanite kits, Megascans, Lumen | Start with one park court and one arena. |
| Crowds | Mass AI with instanced animated crowds | |

## 3. Animation pipeline

This is where quality is won.

- **Mocap.** Options run from inertial suits (Xsens, Rokoko) or markerless capture (Move.ai) up to an optical stage rental for hero sessions. Capture real hoopers.
- **Shot list for v1.** Locomotion sets (with and without the ball) for motion matching; 8 shot bases and 7 releases, each captured separately; 10 dribble moves × 2 hands × 3 speeds; gathers, layups, dunks, contests, stumbles, rebounds and celebrations.
- **Ball as a prop bone** (`ball_prop`) baked into every clip, so dribbles look hand-perfect. The code already prefers this bone.
- **Retargeting.** Use the IK Retargeter so the same clips play on every body from 5'9" to 7'3".

## 4. Milestones

1. **Vertical slice.** One park court, the MyPlayer creator in UMG, 1-on-1 with real mocap and MetaHuman players. This is what you show investors and publishers.
2. **Alpha.** 3v3 park, teammate AI, passing, layups, dunks and rebounding; a dunk creator; progression (earned, no pay-to-win).
3. **Beta.** Online play (dedicated servers, server-authoritative shot timing, rollback-friendly input) and 5v5.
4. **Launch.** PC (Steam) first, then consoles once platform certification passes.

## 5. Getting onto consoles

- **PlayStation:** apply to PlayStation Partners. Dev kits and SDK come after approval.
- **Xbox:** apply to ID@Xbox. This gives the GDK and dev kits.
- **Nintendo:** apply through the Nintendo Developer Portal.
- **Unreal console code:** Epic grants access to platform-specific engine code once a platform holder has approved you.
- Each platform has certification requirements (save data, trophies/achievements, suspend/resume, user switching). Budget months of time for this.
- **Ratings:** ESRB/PEGI, done through IARC for digital storefronts.
- A registered company, a pitch deck and ideally a playable vertical slice greatly improve approval odds.

## 6. Licensing

- 2K has held the NBA simulation license for years. **Do not use NBA or team names, logos, arenas or real player likenesses** without NBA and NBPA licenses.
- Launch with an original league, a streetball/park setting and original shoe and apparel brands. Many people in the 2K community say the park is the part they care about most.
- Trademark the game name before marketing it.

## 7. Team (rough, for a credible vertical slice in about 12 months)

| Role | Count |
|---|---|
| Gameplay/engine programmers (Unreal C++) | 3–4 |
| Online/backend programmer | 1 (from Alpha) |
| Character artists (MetaHuman, groom, clothing) | 2–3 |
| Environment artist | 1–2 |
| Animators plus mocap technician | 2–3 |
| Tech artist (materials, rigs, retargeting) | 1 |
| UI/UX designer | 1 |
| Producer/design lead | 1 |

Full production for 5v5, online and multi-platform launch typically means a larger team and 2–3+ years. Publisher funding or investment usually starts with the vertical slice.

## 8. What the code already gives you

- A tested, engine-independent gameplay core shared by the web creator and Unreal (`Source/CourtLife/Core`, `Tests/`).
- Unreal classes for the MyPlayer character, the jumpshot meter, dribble combos, the ball, the court, the defender AI, the game mode, saves and runtime customization with a tattoo atlas.
- Build-code import from the web creator, so the community can design players before the full game ships.
