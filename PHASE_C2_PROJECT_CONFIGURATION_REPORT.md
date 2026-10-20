# Wyntar Phase C2 Project Configuration Report

Date: 2026-10-21

Starting branch and commit: `main` at `960dff3cd02ad76064734160fbe908350000936b` (`Phase C1: repository hygiene and artifact cleanup`)

## 1. Summary of changes

Phase C2 updates the active project identity from Universal Mask Terrain to Wyntar, removes the unused .NET project setting, keeps the legacy `user://` location stable for save compatibility, updates the runtime HUD heading, and rewrites the README introduction and workflow guidance around the current project.

No gameplay, simulation, terrain generation, save schema, rendering default, shader, resource path, UID, or scene value was changed. Phase C3 and Phase 3H were not started.

## 2. Files modified

- `project.godot` — active identity, legacy user-directory compatibility pin, and removal of the obsolete `[dotnet]` section.
- `scripts/main.gd` — expanded HUD heading changed from `UNIVERSAL MASK TERRAIN` to `WYNTAR`.
- `README.md` — current Wyntar description, Godot version, startup instructions, top-down presentation goal, source layout, development workflow, artifact/archive locations, experimental controls, and unfinished cliff status.
- `PHASE_C2_PROJECT_CONFIGURATION_REPORT.md` — this report.

The pre-existing `main.tscn` and `_reference` changes were not modified.

## 3. Previous and new project identity

| Surface | Previous | New |
| --- | --- | --- |
| Godot `application/config/name` | `Universal Mask Terrain` | `Wyntar` |
| Godot-provided application/window identity | Derived from `Universal Mask Terrain` | Derived from `Wyntar` |
| Expanded HUD heading | `UNIVERSAL MASK TERRAIN` | `WYNTAR` |
| README title | `Universal Mask Terrain — Godot 4.7 starter` | `Wyntar` |
| Repository directory | `universal_mask_terrain_godot47` | Unchanged by instruction |

A headless identity probe confirmed that Godot reads `PROJECT_NAME=Wyntar` and that an instantiated main scene contains the `WYNTAR` HUD label.

Historical milestone reports and compatibility identifiers were deliberately not renamed. In particular, `WorldSaveService.TERRAIN_RULES_ID` remains `universal-mask-terrain-godot47-v1` because it is a save-format compatibility identifier, not display identity.

## 4. Save-directory compatibility findings

The save service uses only project-relative user paths:

- active save: `user://saves/quicksave.json`;
- write candidate: `quicksave.json.tmp`;
- established backup: `quicksave.json.bak`;
- backup candidate: `quicksave.json.bak.new`.

There are no explicit absolute save paths in runtime code. Before C2, `application/config/use_custom_user_dir` was absent/false, so on this Windows system Godot resolved the project directory to:

`%APPDATA%/Godot/app_userdata/Universal Mask Terrain/`

Changing only `config/name` would instead resolve it to:

`%APPDATA%/Godot/app_userdata/Wyntar/`

The live legacy directory existed and contained engine logs and shader cache files, but no `saves/` files were present during inspection. The prospective Wyntar directory did not exist. The compatibility decision nevertheless protects saves that may exist on other development machines or be restored later.

## 5. Compatibility mechanism

`project.godot` now sets:

```ini
config/name="Wyntar"
config/use_custom_user_dir=true
config/custom_user_dir_name="Godot/app_userdata/Universal Mask Terrain"
```

On Windows this keeps `user://` at the exact pre-rename location while allowing the visible project identity to become Wyntar. An isolated Godot 4.7 probe confirmed that the absolute `user://` and quicksave paths were identical before and after the rename, and that no new `Wyntar` data directory was created.

No file migration was required. Consequently, C2 performs no copying, deletion, destination overwrite, backup replacement, or repeated launch-time migration. Existing saves, `.bak`, `.tmp`, and `.bak.new` files remain where the unchanged save service expects them.

For cross-process evidence, a valid fixture was written before the rename at the legacy path and was found, validated, and applied after the rename. The broader fresh-load test later reported one unrelated editor-history expectation failure; all of its persistence, validation, replacement, inventory, resource-state, camera, streaming, and regrowth checks continued successfully. The focused save-format/backup validator passed in full.

## 6. Removed obsolete configuration

The following unused block was removed from `project.godot`:

```ini
[dotnet]
project/assembly_name="Universal Mask Terrain"
```

The active project contains zero `.cs`, `.csproj`, and `.sln` files and has no remaining `[dotnet]` setting. Standard Godot 4.7 successfully imported, parsed, and launched the project. The `4.7` and `GL Compatibility` features and both GL Compatibility renderer settings remain unchanged.

## 7. Effective rendering settings

This table records the current effective values without changing them. “Scene override” means the value in the preserved current `main.tscn`; “script default” means no scene override is present.

| Setting | Script export default | Current scene override | Effective current value | Source/status |
| --- | --- | --- | --- | --- |
| Top-down vs oblique presentation | `oblique_presentation_enabled = false` | None | Top-down (`false`) | Script default; unchanged |
| Organic terrain boundaries | `organic_boundaries_enabled = true` | None | `true` | Script default; unchanged |
| Organic cliff geometry | `organic_cliff_geometry_enabled = true` | None | `true` | Script default; unchanged |
| Unified cliff components | `unified_cliff_components_enabled = true` | None | `true` | Script default; unchanged |
| Connected cliff contours | `connected_cliff_contours_enabled = true` | None | `true` | Script default; unchanged |
| Unified cliff contours | `unified_cliff_contours_enabled = false` | `true` | `true` | Committed scene override; unchanged |
| Directional cliff projection | `directional_cliff_projection_enabled = false` | `true` | `true` | Committed scene override; unchanged |
| Cliff height profile | Baseline (`0`) | Prominent (`2`) | Prominent (`2`) | Pre-existing user scene override; unchanged |
| Cliff edge overlays | `true` | `false` | `false` | Pre-existing user scene override; unchanged |
| Cliff shadows | `true` | `false` | `false` | Pre-existing user scene override; unchanged |
| Organic oblique refinement | `false` | None | `false` | Script default; unchanged |
| Experimental water enhancement | `false` | `true` | `true` | Pre-existing user scene override; unchanged |

Phase 3G explicitly documents directional projection as default-off pending visual acceptance, while the committed `main.tscn` enables it. This disagreement remains unresolved and is documented for later visual approval; C2 does not choose a new visual default. The pre-existing working-tree scene also enables prominent cliff height and experimental water while hiding cliff overlays and shadows. Those user settings were preserved exactly.

## 8. Documentation updates

The README now states:

- what Wyntar currently implements and which ownership boundary is authoritative;
- standard Godot 4.7 and GL Compatibility requirements;
- how to import, run, interact with, save, and load the project;
- the top-down 2D presentation goal;
- the roles of `scripts/`, `scripts/procgen/`, `art/`, `shaders/`, and `tests/`;
- that new generated evidence belongs in `.artifacts/`;
- that historical evidence is archived under `G:/Sim/Wyntar_Archive/` and indexed by the Phase C1 report;
- that organic/directional cliffs, oblique presentation, and enhanced water remain experimental controls;
- that directional cliff quality and default acceptance remain unfinished.

Historical development reports were not rewritten.

## 9. Test results

Validation used standard Godot `4.7.stable.official.5b4e0cb0f` with isolated app-data directories after the live-profile inventory.

| Check | Result |
| --- | --- |
| C1 commit and clean phase boundary | Pass — C1 is commit `960dff3`; only pre-existing `main.tscn` and `_reference` changes remained |
| Godot project import and parse | Pass (exit 0) |
| Main-scene startup | Pass (exit 0) |
| Wyntar project identity and HUD probe | Pass |
| Legacy `user://` absolute path preserved | Pass; exact before/after match |
| Pre-rename fresh save write | Pass; 2,540-byte validated JSON fixture |
| Post-rename access to that fixture | Persistence portion passed; overall auxiliary test reported the unrelated `pre-load world has editor history` expectation |
| `tests/phase7b1_validation.gd` save/load, backup, corruption and authoritative round trip | Pass |
| `tests/phase5d_validation.gd` terrain/chunk generation | Pass |
| `tests/phase_a_water_validation.gd` | Pass |
| `tests/phase3g_validation.gd` | Pass (structural; visual acceptance remains separate) |
| Runtime resource-path existence | Pass; zero missing static runtime paths |
| UID integrity | Pass; 129 UID files, no duplicate values, no missing script/shader sidecars |
| C#/.NET dependency scan | Pass; zero C#, project, solution, or active .NET configuration entries |
| Runtime assets remain tracked | Pass; 16 art entries, 64 script entries, 6 shader entries, main scene and project configuration present |
| `main.tscn` preservation | Pass; SHA-256 remains `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933` |
| `_reference` preservation | Pass; gitlink/HEAD and dirty status fingerprint unchanged |
| `git diff --check` | Pass |

## 10. Remaining risks

- The custom user-directory name intentionally retains the legacy prototype wording. This is compatibility debt, not visible product identity. A future migration requires a separately approved design with collision handling and backup retention.
- The auxiliary fresh-process load test has a fragile editor-history precondition: painting cell `(5, 5)` can be a no-op when its selected material already matches generated terrain. This did not prevent it from finding or loading the legacy-path save, and the focused Phase 7B.1 validator passed.
- Directional cliff projection is enabled in the committed scene despite the Phase 3G default-off recommendation. Visual acceptance remains outstanding.
- The pre-existing `main.tscn` settings enable enhanced water and prominent cliffs and disable cliff overlays/shadows. They are preserved, not approved by C2.
- `_reference` remains a dirty nested checkout and was deliberately untouched.

## 11. Recommended next phase

Stop for review. After C2 is accepted, separately schedule visual-default approval for the current cliff/water scene overrides and a future save-directory migration decision if removing the legacy directory name becomes important. Do not combine either decision with C3 implementation.
