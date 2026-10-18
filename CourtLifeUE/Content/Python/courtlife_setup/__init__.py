"""CourtLife editor setup package.

Pure-Python modules (no ``unreal`` import, unit-tested with plain python3):
    atlas_layout  - tattoo atlas UV layout for the 9 ECLTattooSlot regions
    textures      - tiny TGA writer for placeholder default textures

Unreal-only module (import inside the Unreal Editor):
    setup_project - idempotent project bootstrap (folders, master materials,
                    data assets). Run with:
                        import courtlife_setup.setup_project as s; s.run()
"""
