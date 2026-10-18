"""Runs automatically when the CourtLife project opens in the Unreal Editor.

It does NOT create or change any assets. It only adds a menu entry
"Tools > CourtLife > Run Project Setup" and logs how to run the setup by hand.

STATUS: unverified in Unreal.
"""

import unreal

SETUP_COMMAND = "import importlib, courtlife_setup.setup_project as s; importlib.reload(s); s.run()"


def _register_menu():
    menus = unreal.ToolMenus.get()
    tools = menus.find_menu("LevelEditor.MainMenu.Tools")
    if tools is None:
        raise RuntimeError("Tools menu not found")
    tools.add_section("CourtLife", "CourtLife")
    entry = unreal.ToolMenuEntry(
        name="CourtLifeRunProjectSetup",
        type=unreal.MultiBlockType.MENU_ENTRY,
    )
    entry.set_label("CourtLife: Run Project Setup")
    entry.set_tool_tip("Create folders, master materials and data assets (safe to re-run).")
    entry.set_string_command(unreal.ToolMenuStringCommandType.PYTHON, unreal.Name(""), SETUP_COMMAND)
    tools.add_menu_entry("CourtLife", entry)
    menus.refresh_all_widgets()


try:
    _register_menu()
    unreal.log("[CourtLife] Added Tools > CourtLife: Run Project Setup")
except Exception as exc:  # never block editor startup
    unreal.log_warning(f"[CourtLife] Could not add menu entry ({exc})")
unreal.log("[CourtLife] To bootstrap the project, run in the Python console: " + SETUP_COMMAND)
