"""Gray-box a regulation half court in the open level.  ** UNVERIFIED IN UNREAL **

Written against the UE 5.x Editor Python API but never run (Unreal is not
installed in the authoring container). Expect small API fixes on first run.

Usage (Output Log, Python mode, or Tools > Execute Python Script):
    py "<Project>/Content/Python/environments/blockout_half_court.py"
    py "<...>/blockout_half_court.py" --origin 0,0,0 --yaw 0 --venue park \
        --floor-material /Game/Environments/Courts/MI_ParkCourt
or from Python:
    from environments import blockout_half_court as b; b.build_half_court((0, 0, 0), 0.0)

What it spawns (folder CourtLife/HalfCourt_<venue>, one undo transaction):
  * CLCourt actor at `origin`, yaw `yaw` - floor point under the rim centre,
    +X toward half court (CLCourt.h contract).
  * 50 x 47 ft floor plane (baseline 5.25 ft behind the actor) + hidden
    collision slab, stanchion pole and arm, 6 x 3.5 ft backboard (bottom edge
    9.5 ft, front face 4 ft from baseline), 24-segment rim (9 in inner radius,
    top at 10 ft). Rim, backboard, pole and floor use BlockAll collision.
All dimensions come from court_dims.py (plain Python, unit-tested).
"""
import os
import sys

import unreal

try:
    from environments import court_dims as dims
except ImportError:  # run as a loose file
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import court_dims as dims

COURT_CLASS_PATH = "/Script/CourtLife.CLCourt"


def _actor_subsystem():
    return unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def _load_mesh(key):
    mesh = unreal.EditorAssetLibrary.load_asset(dims.MESHES[key])
    if mesh is None:
        raise RuntimeError("Missing engine mesh " + dims.MESHES[key])
    return mesh


def _spawn_part(part, origin_uu, yaw_deg, folder, material=None):
    loc = dims.local_to_world(origin_uu, yaw_deg, part["location_ft"])
    roll, pitch, yaw = part["rotation"]
    rot = unreal.Rotator(roll=roll, pitch=pitch, yaw=yaw + yaw_deg)
    actor = _actor_subsystem().spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(*loc), rot)
    actor.set_actor_label("CL_" + part["name"])
    actor.set_folder_path(folder)
    actor.set_actor_scale3d(unreal.Vector(*part["scale"]))
    smc = actor.static_mesh_component
    smc.set_mobility(unreal.ComponentMobility.STATIC)
    smc.set_static_mesh(_load_mesh(part["mesh"]))
    if part["collision"]:
        smc.set_collision_profile_name("BlockAll")
        smc.set_collision_enabled(unreal.CollisionEnabled.QUERY_AND_PHYSICS)
    else:
        smc.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
    if part["hidden_in_game"]:
        actor.set_actor_hidden_in_game(True)
        smc.set_editor_property("visible", False)
    if material is not None:
        smc.set_material(0, material)
    return actor


def build_half_court(origin_uu=(0.0, 0.0, 0.0), yaw_deg=0.0, venue="park", floor_material_path=None):
    """Spawn the half court. Returns {"court": CLCourt actor, "parts": [actors]}."""
    folder = "CourtLife/HalfCourt_%s" % venue
    floor_mat = None
    if floor_material_path:
        floor_mat = unreal.EditorAssetLibrary.load_asset(floor_material_path)
        if floor_mat is None:
            unreal.log_warning("Floor material not found: %s" % floor_material_path)

    spawned = []
    with unreal.ScopedEditorTransaction("CourtLife: block out %s half court" % venue):
        court_cls = unreal.load_class(None, COURT_CLASS_PATH)
        court = None
        if court_cls is None:
            unreal.log_error("CLCourt class not found (%s); is the CourtLife module built?" % COURT_CLASS_PATH)
        else:
            court = _actor_subsystem().spawn_actor_from_class(
                court_cls, unreal.Vector(*origin_uu), unreal.Rotator(roll=0.0, pitch=0.0, yaw=yaw_deg))
            court.set_actor_label("CL_Court_%s" % venue)
            court.set_folder_path(folder)

        for part in dims.half_court_parts():
            mat = floor_mat if part["name"] == "Floor" else None
            spawned.append(_spawn_part(part, origin_uu, yaw_deg, folder, mat))

    rim = dims.local_to_world(origin_uu, yaw_deg, (0.0, 0.0, dims.RIM_HEIGHT_FT))
    unreal.log("CourtLife: %s half court spawned, %d parts, rim centre at %s uu"
               % (venue, len(spawned), tuple(round(c, 1) for c in rim)))
    return {"court": court, "parts": spawned}


def _parse_args(argv):
    args = {"origin": (0.0, 0.0, 0.0), "yaw": 0.0, "venue": "park", "floor_material": None}
    it = iter(argv)
    for a in it:
        if a == "--origin":
            args["origin"] = tuple(float(v) for v in next(it).split(","))
        elif a == "--yaw":
            args["yaw"] = float(next(it))
        elif a == "--venue":
            args["venue"] = next(it)
        elif a == "--floor-material":
            args["floor_material"] = next(it)
    return args


if __name__ == "__main__":
    _a = _parse_args(sys.argv[1:])
    build_half_court(_a["origin"], _a["yaw"], _a["venue"], _a["floor_material"])
