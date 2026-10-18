"""Regulation half-court dimensions and the gray-box layout, in plain Python.

No `import unreal` here, so this module is unit-testable with python3
(see test_court_dims.py) and shared by blockout_half_court.py.

Frames
------
Court-local frame = the CLCourt actor frame (CLCourt.h):
    origin on the floor directly under the rim centre,
    +X toward half court, +Y = Unreal right (= core -x), +Z up.
Lengths in this module are feet unless the name ends in _UU.
1 ft = 30.48 uu (CLCoreBridge.h CLUnitsPerFoot).
"""
import math

UU_PER_FT = 30.48

# --- court (feet) -----------------------------------------------------------
COURT_WIDTH_FT = 50.0
HALF_COURT_DEPTH_FT = 47.0             # baseline to half-court line
RIM_FROM_BASELINE_FT = 5.25             # rim centre to baseline
BASELINE_X_FT = -RIM_FROM_BASELINE_FT   # baseline in court-local X (= core kBaselineZFt)
HALF_COURT_X_FT = HALF_COURT_DEPTH_FT - RIM_FROM_BASELINE_FT  # 41.75
LINE_WIDTH_FT = 2.0 / 12.0
KEY_WIDTH_FT = 16.0
FREE_THROW_FROM_BASELINE_FT = 19.0
FREE_THROW_CIRCLE_R_FT = 6.0
RESTRICTED_R_FT = 4.0
THREE_PT_R_FT = 23.75
CORNER_THREE_FT = 22.0
CENTER_CIRCLE_R_FT = 6.0

# --- goal (feet) ------------------------------------------------------------
RIM_HEIGHT_FT = 10.0                    # top of the rim
RIM_RADIUS_FT = 0.75                    # inner radius, 18 in inside diameter
RIM_TUBE_DIAMETER_FT = 0.625 / 12.0     # 5/8 in steel
RIM_SEGMENTS = 24                       # cylinders approximating the torus
BACKBOARD_WIDTH_FT = 6.0
BACKBOARD_HEIGHT_FT = 3.5
BACKBOARD_BOTTOM_FT = 9.5
BACKBOARD_THICKNESS_FT = 0.25           # glass + frame, gray-box
BACKBOARD_FROM_BASELINE_FT = 4.0        # front face
BACKBOARD_FACE_X_FT = BASELINE_X_FT + BACKBOARD_FROM_BASELINE_FT  # -1.25
STANCHION_BEHIND_BASELINE_FT = 4.0      # park pole: 4 ft out of bounds
STANCHION_DIAMETER_FT = 0.5
STANCHION_HEIGHT_FT = 12.5
ARM_HEIGHT_FT = 11.0                    # centre of the horizontal arm
ARM_SECTION_FT = 0.33

# --- engine basic shapes (/Engine/BasicShapes/*) -----------------------------
BASIC_SHAPE_SIZE_UU = 100.0  # Cube 100^3, Cylinder 100 dia x 100 tall, Plane 100x100; all centred
MESHES = {
    "Cube": "/Engine/BasicShapes/Cube.Cube",
    "Cylinder": "/Engine/BasicShapes/Cylinder.Cylinder",
    "Plane": "/Engine/BasicShapes/Plane.Plane",
}

# --- floor texture mapping (SourceArt/Environments/tools/gen_courts.py) ------
# The 2048 px textures hold the 2000 x 1880 px court (40 px/ft) with an apron.
TEX_SIZE_PX = 2048
TEX_PX_PER_FT = 40
TEX_UV_SCALE = (2000.0 / 2048.0, 1880.0 / 2048.0)
TEX_UV_OFFSET = (24.0 / 2048.0, 84.0 / 2048.0)


def ft_to_uu(ft):
    return ft * UU_PER_FT


def court_local_to_tex_uv(x_ft, y_ft):
    """Court-local (X fwd, Y right) in ft -> 0..1 UV of the 2048 textures.

    Texture rows run baseline (top) -> half court; columns run along core +x,
    which is Unreal -Y. Use this in a world-position-based floor material
    instead of trusting the mesh UVs.
    """
    depth = x_ft - BASELINE_X_FT
    core_x = -y_ft
    u = (24.0 + (core_x + COURT_WIDTH_FT / 2.0) * TEX_PX_PER_FT) / TEX_SIZE_PX
    v = (84.0 + depth * TEX_PX_PER_FT) / TEX_SIZE_PX
    return u, v


def local_to_world(origin_uu, yaw_deg, local_ft):
    """Court-local feet -> world uu for a court actor at origin_uu rotated by yaw."""
    x, y, z = (ft_to_uu(c) for c in local_ft)
    c, s = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    return (origin_uu[0] + c * x - s * y, origin_uu[1] + s * x + c * y, origin_uu[2] + z)


def _part(name, mesh, loc, size, rot=(0.0, 0.0, 0.0), collision=True, hidden_in_game=False):
    """size = desired extent in ft along the mesh's local X, Y, Z (before rotation)."""
    if mesh == "Plane":
        scale = (ft_to_uu(size[0]) / BASIC_SHAPE_SIZE_UU, ft_to_uu(size[1]) / BASIC_SHAPE_SIZE_UU, 1.0)
    else:
        scale = tuple(ft_to_uu(v) / BASIC_SHAPE_SIZE_UU for v in size)
    return {
        "name": name, "mesh": mesh, "location_ft": tuple(loc), "size_ft": tuple(size),
        "rotation": tuple(rot),  # (roll, pitch, yaw) degrees, court-local
        "scale": scale, "collision": collision, "hidden_in_game": hidden_in_game,
    }


def rim_tube_center_radius_ft():
    return RIM_RADIUS_FT + RIM_TUBE_DIAMETER_FT / 2.0


def half_court_parts():
    """Gray-box parts in court-local feet. The CLCourt actor itself is at (0,0,0)."""
    parts = []
    floor_cx = (BASELINE_X_FT + HALF_COURT_X_FT) / 2.0  # 18.25
    parts.append(_part("Floor", "Plane", (floor_cx, 0.0, 0.0), (HALF_COURT_DEPTH_FT, COURT_WIDTH_FT, 0.0)))
    # Thin slab under the plane so the ball always has floor collision.
    parts.append(_part("FloorCollision", "Cube", (floor_cx, 0.0, -0.25),
                       (HALF_COURT_DEPTH_FT + 10.0, COURT_WIDTH_FT + 10.0, 0.5), hidden_in_game=True))

    pole_x = BASELINE_X_FT - STANCHION_BEHIND_BASELINE_FT
    parts.append(_part("Stanchion_Pole", "Cylinder", (pole_x, 0.0, STANCHION_HEIGHT_FT / 2.0),
                       (STANCHION_DIAMETER_FT, STANCHION_DIAMETER_FT, STANCHION_HEIGHT_FT)))
    bb_back_x = BACKBOARD_FACE_X_FT - BACKBOARD_THICKNESS_FT
    arm_len = bb_back_x - pole_x
    parts.append(_part("Stanchion_Arm", "Cube", (pole_x + arm_len / 2.0, 0.0, ARM_HEIGHT_FT),
                       (arm_len, ARM_SECTION_FT, ARM_SECTION_FT)))
    parts.append(_part("Backboard", "Cube",
                       (BACKBOARD_FACE_X_FT - BACKBOARD_THICKNESS_FT / 2.0, 0.0,
                        BACKBOARD_BOTTOM_FT + BACKBOARD_HEIGHT_FT / 2.0),
                       (BACKBOARD_THICKNESS_FT, BACKBOARD_WIDTH_FT, BACKBOARD_HEIGHT_FT)))

    tube_z = RIM_HEIGHT_FT - RIM_TUBE_DIAMETER_FT / 2.0
    rc = rim_tube_center_radius_ft()
    # Bracket from the backboard face to the back of the rim.
    rim_back_x = -rc - RIM_TUBE_DIAMETER_FT / 2.0
    br_len = rim_back_x - BACKBOARD_FACE_X_FT
    parts.append(_part("Rim_Bracket", "Cube", (BACKBOARD_FACE_X_FT + br_len / 2.0, 0.0, tube_z - 0.05),
                       (br_len, 0.4, 0.1)))
    seg_len = 2.0 * math.pi * rc / RIM_SEGMENTS * 1.08  # slight overlap closes the ring
    for i in range(RIM_SEGMENTS):
        phi = 360.0 * i / RIM_SEGMENTS
        px = rc * math.cos(math.radians(phi))
        py = rc * math.sin(math.radians(phi))
        # Cylinder axis is local Z; pitch 90 lays it along X, yaw turns it tangent.
        parts.append(_part("Rim_%02d" % i, "Cylinder", (px, py, tube_z),
                           (RIM_TUBE_DIAMETER_FT, RIM_TUBE_DIAMETER_FT, seg_len),
                           rot=(0.0, 90.0, phi + 90.0)))
    return parts
