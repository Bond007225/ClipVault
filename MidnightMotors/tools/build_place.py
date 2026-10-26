#!/usr/bin/env python3
"""Build MidnightMotors.rbxlx (a Roblox place file) from src/ without Rojo.

Mirrors default.project.json:
  src/shared  -> ReplicatedStorage.Shared (Folder of ModuleScripts)
  src/server  -> ServerScriptService.Server (Script from init.server.luau)
  src/client  -> StarterPlayer.StarterPlayerScripts.Client (LocalScript from init.client.luau)
Usage: python tools/build_place.py   (run from the MidnightMotors folder)
"""
import itertools
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
_ref = itertools.count()


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, props="", children=""):
    return (
        f'<Item class="{cls}" referent="RBX{next(_ref)}"><Properties>'
        f'<string name="Name">{esc(name)}</string>{props}</Properties>{children}</Item>\n'
    )


def source(path):
    with open(path, encoding="utf-8") as f:
        return f'<ProtectedString name="Source">{cdata(f.read())}</ProtectedString>'


def script_class(filename):
    if filename.endswith(".server.luau"):
        return "Script", filename[: -len(".server.luau")]
    if filename.endswith(".client.luau"):
        return "LocalScript", filename[: -len(".client.luau")]
    return "ModuleScript", filename[: -len(".luau")]


def directory(path, name):
    """A folder becomes a Folder, or a script if it has an init file (Rojo rules)."""
    entries = sorted(os.listdir(path))
    init = next((e for e in entries if e.startswith("init.") and e.endswith(".luau")), None)
    children = ""
    for e in entries:
        full = os.path.join(path, e)
        if e == init:
            continue
        if os.path.isdir(full):
            children += directory(full, e)
        elif e.endswith(".luau"):
            cls, n = script_class(e)
            children += item(cls, n, source(full))
    if init:
        cls, _ = script_class(init)
        return item(cls, name, source(os.path.join(path, init)), children)
    return item("Folder", name, "", children)


def main():
    out = os.path.join(ROOT, "MidnightMotors.rbxlx")
    body = ""
    body += item(
        "Workspace",
        "Workspace",
        '<bool name="StreamingEnabled">true</bool><float name="Gravity">196.2</float>',
    )
    body += item(
        "Lighting",
        "Lighting",
        '<float name="ClockTime">17.5</float><bool name="GlobalShadows">true</bool>',
    )
    body += item("ReplicatedStorage", "ReplicatedStorage", "", directory(os.path.join(SRC, "shared"), "Shared"))
    body += item("ServerScriptService", "ServerScriptService", "", directory(os.path.join(SRC, "server"), "Server"))
    body += item(
        "StarterPlayer",
        "StarterPlayer",
        "",
        item("StarterPlayerScripts", "StarterPlayerScripts", "", directory(os.path.join(SRC, "client"), "Client")),
    )
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        + body
        + "</roblox>\n"
    )
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(xml)
    print("wrote", out)


if __name__ == "__main__":
    sys.exit(main())
