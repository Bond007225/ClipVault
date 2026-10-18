"""CourtLife project bootstrap. Runs INSIDE the Unreal Editor only.

STATUS: unverified in Unreal. Written against the UE 5.x editor Python API
(AssetTools, MaterialEditingLibrary, EditorAssetLibrary) but never executed,
because Unreal is not installed where this was authored. First run: watch
the Output Log (filter "CourtLife") and report anything that fails.

How to run (see Docs/TechArt/MATERIALS.md):
    Tools > Execute Python Script... > pick this file, or in the Python console:
        import courtlife_setup.setup_project as s; s.run()

It is idempotent: folders and assets that already exist are left alone.
  * Master materials are only (re)built if missing, or when
    ``run(rebuild_materials=True)`` is passed (rebuilding wipes the graph of
    M_Garment_Master / M_Skin_Master, not their material instances).
  * DA_Cosmetics.TattooRegions / TattooAtlasSize are always synced from
    ``atlas_layout.py``, which is the single source of truth for the layout.
    Every other catalog field (hair, clothing, designs...) is never touched.
"""

from __future__ import annotations

import os

import unreal

from courtlife_setup import atlas_layout, textures

LOG_PREFIX = "[CourtLife setup]"

FOLDERS = (
    "/Game/Maps",
    "/Game/Data",
    "/Game/Characters",
    "/Game/Characters/Body",
    "/Game/Characters/Hair",
    "/Game/Characters/Clothing",
    "/Game/Characters/Tattoos",
    "/Game/Animation",
    "/Game/Animation/Jumpshot",
    "/Game/Animation/Dribble",
    "/Game/Animation/Locomotion",
    "/Game/Animation/Defense",
    "/Game/Environments",
    "/Game/Materials",
    "/Game/Materials/Textures",
)

MATERIALS_DIR = "/Game/Materials"
TEXTURES_DIR = "/Game/Materials/Textures"
DATA_DIR = "/Game/Data"

GARMENT = "M_Garment_Master"
SKIN = "M_Skin_Master"
DEFAULT_MASK = "T_ColorMask_Default"        # solid red = everything Primary
DEFAULT_ATLAS = "T_TattooAtlas_Default"     # fully transparent = no tattoos

MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary


# --------------------------------------------------------------------------- utils

def log(msg: str) -> None:
    unreal.log(f"{LOG_PREFIX} {msg}")


def warn(msg: str) -> None:
    unreal.log_warning(f"{LOG_PREFIX} {msg}")


def error(msg: str) -> None:
    unreal.log_error(f"{LOG_PREFIX} {msg}")


def _path(folder: str, name: str) -> str:
    return f"{folder}/{name}"


def _tools():
    return unreal.AssetToolsHelpers.get_asset_tools()


def _save(asset) -> None:
    if asset is not None:
        EAL.save_asset(asset.get_path_name(), only_if_is_dirty=False)


# ------------------------------------------------------------------------ folders

def ensure_folders() -> None:
    for folder in FOLDERS:
        if EAL.does_directory_exist(folder):
            log(f"folder exists: {folder}")
        elif EAL.make_directory(folder):
            log(f"created folder: {folder}")
        else:
            error(f"could not create folder: {folder}")


# ----------------------------------------------------------------------- textures

def ensure_default_texture(name: str, rgba) -> unreal.Texture2D:
    """Import a tiny solid TGA as a linear (sRGB off) texture if missing.

    A TextureSampleParameter2D must reference a texture or the material fails
    to compile, so the masters point at these placeholders.
    """
    asset_path = _path(TEXTURES_DIR, name)
    if EAL.does_asset_exist(asset_path):
        log(f"texture exists: {asset_path}")
        return EAL.load_asset(asset_path)

    temp_dir = os.path.join(unreal.Paths.project_intermediate_dir(), "CourtLifeSetup")
    os.makedirs(temp_dir, exist_ok=True)
    tga = textures.write_solid_tga(os.path.join(temp_dir, name + ".tga"), rgba)

    task = unreal.AssetImportTask()
    task.set_editor_property("filename", tga)
    task.set_editor_property("destination_path", TEXTURES_DIR)
    task.set_editor_property("destination_name", name)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", False)
    _tools().import_asset_tasks([task])

    tex = EAL.load_asset(asset_path)
    if tex is None:
        error(f"failed to import {asset_path} from {tga}")
        return None
    # Masks and the atlas are data, not color: sample them linearly.
    tex.set_editor_property("srgb", False)
    tex.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_DEFAULT)
    _save(tex)
    log(f"imported texture: {asset_path} (sRGB off)")
    return tex


# ---------------------------------------------------------------------- materials

def _expr(material, cls, x, y):
    return MEL.create_material_expression(material, cls, x, y)


def _vector_param(material, name, default, x, y, group):
    e = _expr(material, unreal.MaterialExpressionVectorParameter, x, y)
    e.set_editor_property("parameter_name", name)
    e.set_editor_property("default_value", default)
    e.set_editor_property("group", group)
    return e


def _scalar_param(material, name, default, x, y, group):
    e = _expr(material, unreal.MaterialExpressionScalarParameter, x, y)
    e.set_editor_property("parameter_name", name)
    e.set_editor_property("default_value", default)
    e.set_editor_property("group", group)
    return e


def _texture_param(material, name, texture, x, y, group):
    e = _expr(material, unreal.MaterialExpressionTextureSampleParameter2D, x, y)
    e.set_editor_property("parameter_name", name)
    e.set_editor_property("group", group)
    if texture is not None:
        e.set_editor_property("texture", texture)
    e.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR)
    return e


def _lerp(material, x, y):
    return _expr(material, unreal.MaterialExpressionLinearInterpolate, x, y)


def _connect(a, a_out, b, b_in) -> None:
    if not MEL.connect_material_expressions(a, a_out, b, b_in):
        error(f"failed to connect {a.get_name()}.{a_out or 'out'} -> {b.get_name()}.{b_in}")


def _connect_prop(a, a_out, prop) -> None:
    if not MEL.connect_material_property(a, a_out, prop):
        error(f"failed to connect {a.get_name()}.{a_out or 'out'} -> {prop}")


def _get_or_create_material(name: str, rebuild: bool):
    """Return (material, needs_build)."""
    asset_path = _path(MATERIALS_DIR, name)
    if EAL.does_asset_exist(asset_path):
        mat = EAL.load_asset(asset_path)
        if not rebuild:
            log(f"material exists, leaving it alone: {asset_path} (run(rebuild_materials=True) to rebuild)")
            return mat, False
        MEL.delete_all_material_expressions(mat)
        log(f"rebuilding material graph: {asset_path}")
        return mat, True
    mat = _tools().create_asset(name, MATERIALS_DIR, unreal.Material, unreal.MaterialFactoryNew())
    if mat is None:
        error(f"could not create material {asset_path}")
        return None, False
    log(f"created material: {asset_path}")
    return mat, True


def _finish_material(mat) -> None:
    mat.set_editor_property("used_with_skeletal_mesh", True)
    MEL.recompile_material(mat)
    _save(mat)
    log(f"compiled and saved: {mat.get_path_name()}")


def build_garment_master(mask_tex, rebuild: bool = False):
    """M_Garment_Master.

    BaseColor = lerp(lerp(Primary, Secondary, Mask.G), Tertiary, Mask.B)
    i.e. R (or black) = Primary, G = Secondary, B = Tertiary.
    Scalar "Number" is exposed for jerseys (consumed by CLCustomizationComponent);
    see MATERIALS.md for why it is wired as a placeholder for now.
    """
    mat, build = _get_or_create_material(GARMENT, rebuild)
    if not build:
        return mat

    mask = _texture_param(mat, "ColorMask", mask_tex, -1200, 0, "Colorway")
    primary = _vector_param(mat, "Primary", unreal.LinearColor(1.0, 1.0, 1.0, 1.0), -900, -300, "Colorway")
    secondary = _vector_param(mat, "Secondary", unreal.LinearColor(0.0, 0.0, 0.0, 1.0), -900, -100, "Colorway")
    tertiary = _vector_param(mat, "Tertiary", unreal.LinearColor(1.0, 1.0, 1.0, 1.0), -900, 100, "Colorway")

    ps = _lerp(mat, -600, -200)
    _connect(primary, "", ps, "A")
    _connect(secondary, "", ps, "B")
    _connect(mask, "G", ps, "Alpha")

    pst = _lerp(mat, -350, -100)
    _connect(ps, "", pst, "A")
    _connect(tertiary, "", pst, "B")
    _connect(mask, "B", pst, "Alpha")
    _connect_prop(pst, "", unreal.MaterialProperty.MP_BASE_COLOR)

    roughness = _scalar_param(mat, "Roughness", 0.7, -900, 300, "Surface")

    # Number: jersey number (0..99). Kept alive (unused parameters are compiled
    # out and vanish from instances) by adding Number * 0 to roughness until
    # the number-decal material function lands. TODO(tech art): replace.
    number = _scalar_param(mat, "Number", 0.0, -900, 450, "Jersey")
    zero = _expr(mat, unreal.MaterialExpressionConstant, -900, 550)
    zero.set_editor_property("r", 0.0)
    keep = _expr(mat, unreal.MaterialExpressionMultiply, -600, 450)
    _connect(number, "", keep, "A")
    _connect(zero, "", keep, "B")
    rough_sum = _expr(mat, unreal.MaterialExpressionAdd, -350, 350)
    _connect(roughness, "", rough_sum, "A")
    _connect(keep, "", rough_sum, "B")
    _connect_prop(rough_sum, "", unreal.MaterialProperty.MP_ROUGHNESS)

    _finish_material(mat)
    return mat


def build_skin_master(atlas_tex, rebuild: bool = False):
    """M_Skin_Master.

    Skin   = SkinTone
    Inked  = lerp(Skin, TattooAtlas.RGB, TattooAtlas.A)
    Base   = lerp(Inked, EyeColor, IsEye)   (IsEye = 1 on the eye material instance)
    """
    mat, build = _get_or_create_material(SKIN, rebuild)
    if not build:
        return mat

    skin = _vector_param(mat, "SkinTone", unreal.LinearColor(0.27, 0.09, 0.02, 1.0), -1000, -300, "Skin")
    atlas = _texture_param(mat, "TattooAtlas", atlas_tex, -1100, 0, "Tattoos")
    eye = _vector_param(mat, "EyeColor", unreal.LinearColor(0.05, 0.02, 0.01, 1.0), -1000, 300, "Eyes")
    is_eye = _scalar_param(mat, "IsEye", 0.0, -1000, 450, "Eyes")

    inked = _lerp(mat, -650, -150)
    _connect(skin, "", inked, "A")
    _connect(atlas, "RGB", inked, "B")
    _connect(atlas, "A", inked, "Alpha")

    base = _lerp(mat, -350, 0)
    _connect(inked, "", base, "A")
    _connect(eye, "", base, "B")
    _connect(is_eye, "", base, "Alpha")
    _connect_prop(base, "", unreal.MaterialProperty.MP_BASE_COLOR)

    roughness = _scalar_param(mat, "Roughness", 0.45, -1000, 600, "Skin")
    _connect_prop(roughness, "", unreal.MaterialProperty.MP_ROUGHNESS)

    mat.set_editor_property("used_with_morph_targets", True)  # body_heavy / body_muscular
    _finish_material(mat)
    return mat


# -------------------------------------------------------------------- data assets

def _create_data_asset(name: str, cls):
    asset_path = _path(DATA_DIR, name)
    if EAL.does_asset_exist(asset_path):
        log(f"data asset exists: {asset_path}")
        return EAL.load_asset(asset_path)
    factory = unreal.DataAssetFactory()
    factory.set_editor_property("data_asset_class", cls)
    asset = _tools().create_asset(name, DATA_DIR, cls, factory)
    if asset is None:
        error(f"could not create {asset_path}")
    else:
        log(f"created data asset: {asset_path} ({getattr(cls, '__name__', cls)})")
    return asset


def _region_struct(region: atlas_layout.Region):
    box = unreal.Box2D()
    box.set_editor_property("min", unreal.Vector2D(*region.uv_min))
    box.set_editor_property("max", unreal.Vector2D(*region.uv_max))
    box.set_editor_property("is_valid", True)
    s = unreal.CLTattooRegion()
    s.set_editor_property("uv", box)
    s.set_editor_property("aspect", float(region.aspect))
    return s


def ensure_cosmetics_catalog():
    if not hasattr(unreal, "CLCosmeticsCatalog"):
        error("unreal.CLCosmeticsCatalog not found: build the CourtLife C++ module first, then re-run")
        return None
    problems = atlas_layout.validate()
    if problems:
        for p in problems:
            error(f"atlas layout invalid: {p}")
        return None
    catalog = _create_data_asset("DA_Cosmetics", unreal.CLCosmeticsCatalog)
    if catalog is None:
        return None
    regions = atlas_layout.build_layout()
    catalog.set_editor_property("tattoo_regions", [_region_struct(r) for r in regions])
    catalog.set_editor_property("tattoo_atlas_size", atlas_layout.ATLAS_SIZE)
    for r in regions:
        log(f"  TattooRegions[{r.index}] {r.slot}: UV {r.uv_min} -> {r.uv_max}, Aspect {r.aspect}")
    _save(catalog)
    log(f"synced {len(regions)} tattoo regions and TattooAtlasSize={atlas_layout.ATLAS_SIZE} into DA_Cosmetics")
    return catalog


def ensure_anim_set():
    if not hasattr(unreal, "CLAnimSet"):
        error("unreal.CLAnimSet not found: build the CourtLife C++ module first, then re-run")
        return None
    asset = _create_data_asset("DA_AnimSet", unreal.CLAnimSet)
    _save(asset)
    return asset


# --------------------------------------------------------------------------- main

def run(rebuild_materials: bool = False) -> None:
    log("starting (unverified in Unreal: report failures to tech art)")
    ensure_folders()
    mask = ensure_default_texture(DEFAULT_MASK, (255, 0, 0, 255))
    atlas = ensure_default_texture(DEFAULT_ATLAS, (0, 0, 0, 0))
    build_garment_master(mask, rebuild_materials)
    build_skin_master(atlas, rebuild_materials)
    ensure_cosmetics_catalog()
    ensure_anim_set()
    log("done")


if __name__ == "__main__":
    # Tools > Execute Python Script runs the file as __main__.
    run()
