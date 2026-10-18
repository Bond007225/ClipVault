# Tattoo Stencils

Owner: character artist. Source art: `CourtLifeUE/SourceArt/Characters/Tattoos/`.
Generator: `SourceArt/Characters/tools/gen_tattoos.py`. Checker: `SourceArt/Characters/tools/check_tattoos.py`.

## Stencil list

Keys match `courtlife/src/core/catalog.js` `TATTOO_DESIGNS`, so build codes import unchanged.
They are also the row names in `UCLCosmeticsCatalog::TattooDesigns`.

| Key | Display name | Texture | `bDrawsText` | `bWrapsLimb` | Accent (G) used for |
|---|---|---|---|---|---|
| `tribal` | Tribal | `T_Tattoo_Tribal` | no | no | none (solid black) |
| `band` | Barbed Band | `T_Tattoo_Band` | no | **yes** | none |
| `rose` | Rose | `T_Tattoo_Rose` | no | no | petals |
| `script` | Custom Script | none | **yes** | no | none (text in `Ink`) |
| `stars` | Stars | `T_Tattoo_Stars` | no | no | light halves of the nautical stars |
| `crown` | Crown | `T_Tattoo_Crown` | no | no | gold body, tip balls and cross |
| `geometric` | Geometric Sleeve | `T_Tattoo_Geometric` | no | **yes** | none (blackwork and dotwork) |
| `flames` | Flames | `T_Tattoo_Flames` | no | no | flame fill; dotwork in R darkens it toward the tips |
| `number` | Number | none | **yes** | no | none (text in `Ink`) |
| `clock` | Clock | `T_Tattoo_Clock` | no | no | bezel and centre cap |
| `praying` | Cross | `T_Tattoo_Praying` | no | no | halo ring |
| `waves` | Waves | `T_Tattoo_Waves` | no | no | rising sun |

Contact sheet: `SourceArt/Characters/Tattoos/_preview.png`. It shows each design on light and dark skin, with
ink at 92% and the accent at 90%. The wrapping designs are rolled 50% so the seam sits in the middle of the tile.

## Encoding (contract)

1024×1024 PNG, 8-bit RGBA. All values are linear coverage, not colour:

| Channel | Meaning |
|---|---|
| R | Ink coverage: linework, solid black, and stipple or hatch shading |
| G | Accent coverage: colour-fill areas. Ink can sit on top of accent, and where both are set, ink wins |
| B | Always 0 |
| A | `max(R, G)`: total coverage. Fully transparent pixels are `(0,0,0,0)` |

How to composite the stencil over skin:
`c = lerp(Skin, Accent, G); c = lerp(c, Ink, R); alpha = A`

- **Placed designs** keep at least a 40 px empty border (the checker enforces this) and are centred.
  This means clamped UVs never bleed.
- **Wrap designs** (`band`, `geometric`) are periodic in U. They are built on a 128 px period, rasterised with
  wrap-around and box-downsampled on an aligned 4× grid, so the right edge continues into the left edge
  exactly. They keep a clear border at the top and bottom. Their artwork fills only the middle of the
  texture's height: the band uses about 20% (y 408–616) and the sleeve about 60% (y 205–819). The `Scale`
  slider sets how tall they are on the limb.

## Regenerating

```bash
cd CourtLifeUE/SourceArt/Characters/tools
python3 gen_tattoos.py               # all stencils + _preview.png
python3 gen_tattoos.py rose crown    # just these (the preview is rebuilt from what's on disk)
python3 check_tattoos.py             # must print "All tattoo stencil checks passed"
```

Requirements: Python 3.9+, Pillow and numpy. scipy is not needed. The preview labels use Inter or DejaVu if
they are installed. That only affects `_preview.png`, never the stencils.

The art is drawn in 1024-unit coordinates and rasterised at 4× (4096²). It is then box-downsampled, which
gives anti-aliased edges. Every random choice (stipple jitter, wood grain) uses a fixed seed, so a rerun is
byte-identical on the same Pillow/numpy versions. This was verified with Pillow 12.3 and numpy 2.5. Running a
different version can change individual anti-aliased pixels, but not the design.

The checker verifies the size, RGBA mode, `B == 0`, `A == max(R,G)`, clean transparency, non-empty
ink/accent coverage, margins and centring. For the wrap designs it also checks that the difference across the
seam is no bigger than the difference between neighbouring columns inside the image. Last, it checks that
every catalog key is either a stencil or a text design.

## Unreal import settings

The stencils are **data masks** and are drawn into the `TattooAtlas` render target at runtime by
`UCLCustomizationComponent::RepaintTattoos()`.

| Setting | Value | Why |
|---|---|---|
| Asset path / name | `/Game/Characters/Tattoos/T_Tattoo_<Key>` | matches the file names |
| **sRGB** | **Off** | the channels hold coverage, not colour; with sRGB on, edges and stipple would get darker and thicker |
| **Compression Settings** | **BC7** (`TC_BC7`) | four independent channels with good quality on thin lines and dots. `Masks (no sRGB)` also works but encodes to BC3/DXT5 because of the alpha, which blocks up the fine stipple. Do not use `Default` (it forces sRGB colour) or `Normalmap` |
| **Mip Gen Settings** | **FromTextureGroup / SimpleAverage** (keep mips) | each stencil is drawn at roughly 100–400 px into a 2048 atlas. Without mips, 1024→200 px minification aliases the dotwork into sparkle and moiré. Average-filtered mips keep coverage correct |
| Texture Group | `Character` (or a custom `Tattoo` group with `MipFilter=Average`) | |
| **Never Stream** | **On** | the stencil is loaded with `LoadSynchronous()` and baked into the atlas once. If streamed-out mips get baked, the tattoo stays blurry until the next repaint |
| Filter | Default (trilinear) | |
| Address X | **Wrap** for `band` and `geometric`; Clamp for everything else | wrap designs are drawn with U tiling (`Extent.X / DesignU`) |
| Address Y | Clamp | |
| Max Texture Size | 0 (keep 1024) | |
| Power of two mode | none needed (already 1024²) | |
| Compress Without Alpha | Off | |

Data asset rows: set `Stencil`, `bWrapsLimb = true` for `band` and `geometric`, and `bDrawsText = true` for
`script` and `number`.

> **Integration note (unverified in Unreal, owned by gameplay/tech art):**
> `RepaintTattoos()` currently draws the stencil with `K2_DrawTexture(..., T.Ink)`, which multiplies the
> texture by the ink colour. With the R/G encoding above, the whole design would come out ink-coloured,
> `FCLTattoo::Accent` would never be applied, and the raw R/G values would leak into the atlas as colour.
> The stencil needs to be drawn with a small material through `K2_DrawMaterial`: a translucent material
> that samples the stencil and outputs `rgb = (Accent*G*(1-R) + Ink*R) / max(A, 1e-3)` and `alpha = A`.
> `Ink` and `Accent` are set as MID parameters for each tattoo. Over fully covered pixels this equals the
> two-lerp composite above exactly; on mixed anti-aliased edges it differs by less than one AA step. Then the skin
> material's `TattooAtlas` (RGBA, A = coverage) works as-is.

## Text designs: font recommendations

`script` (up to `MAX_SCRIPT_LENGTH` = 16 characters) and `number` (jersey number, or custom text) are drawn
with `UCLCosmeticsCatalog::ScriptFont` via `K2_DrawText`, tinted with `Ink`. All of the fonts below are
**SIL Open Font License 1.1** (free to ship and embed, available on Google Fonts). Check each font's licence
file when you import it.

**Script (`script`)**, from most to least tattoo-authentic:

| Font | Style | Notes |
|---|---|---|
| **Pirata One** | Chicano / blackletter hybrid | The classic forearm-script look. Very legible at small sizes. **Recommended default** |
| **UnifrakturMaguntia** | Old English blackletter | "Old English" lettering. Hard to read past about 10 characters |
| **Grenze Gotisch** | Modern blackletter, variable weight | Pick a weight between 600 and 800 so it holds up on skin |
| **Pinyon Script** | Copperplate script | The elegant cursive option for names and dates |
| **Great Vibes** | Flowing script | Very thin hairlines. Use Bold or Black weight only, or enlarge the outline |
| **Italianno** | Calligraphic | Use it for short words. It gets too thin at small scale |

**Number (`number`):**

| Font | Style | Notes |
|---|---|---|
| **Graduate** | Collegiate varsity block | Matches jersey numbers. **Recommended default** |
| **Alfa Slab One** | Heavy slab | Bold and reads well on dark skin |
| **Bebas Neue** | Condensed sans | Fits three-digit numbers or dates |
| **UnifrakturCook** | Blackletter bold | Old-English numerals ("23" chest pieces) |
| **Pirata One** | Chicano | Pairs with the script default |

Unreal setup: import the fonts as a **Composite Font** (`UFont`, Runtime cache) with the Latin range at
minimum. Since `ScriptFont` is a single property, the recommended pairing is Pirata One for script with
Graduate as a second `UFont` for numbers. That needs an extra `NumberFont` property on the catalog (a proposed
contract change, see the sprint report). The stroke weight of the chosen font should be at least as thick as
the stencils' finest linework (about 3 px at 1024), so text tattoos look like the same artist made them.

## What procedural art can't replace yet

These stencils are production-usable flash-style placeholders. A human tattoo artist should still do these:
- Hand-drawn passes on the rose (the bowl petal is still a bit symmetrical and stiff) and the waves (a real
  Hokusai-style crest would have foam claws that vary in size).
- More designs per category (left- and right-facing variants, sleeve-scale pieces), plus whip shading and
  pepper shading, which a brush gives you and procedural dots only approximate.
- A final art-direction check on real skin in engine, in lighting and at gameplay camera distance.
