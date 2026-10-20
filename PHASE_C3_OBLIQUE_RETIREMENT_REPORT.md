# Wyntar Phase C3 Oblique Retirement Report

Date: 2026-10-21

Starting branch and commit: `main` at `73d45588a3c67f311673fc7e92da537e68e8bbcf` (`Phase C2: Wyntar project identity and configuration`)

## Summary

Phase C3 removes Wyntar's obsolete experimental oblique/isometric presentation subsystem. The active project now has one presentation projection: the existing top-down path.

The removal is limited to oblique-only scripts, shader, APIs, state, branches, and Phase 2A/2B test programs. Terrain authority, generation, elevation, the top-down camera, chunk scheduling, top-down picking, cliffs, water, saving, resource interaction, and current scene settings are unchanged.

Git history, historical milestone reports, ignored local evidence, and the external Phase C1 archive remain intact. No commit, push, or history rewrite was performed.

## Files modified

- `scripts/main.gd`
  - Removed the two oblique export flags.
  - Removed propagation of oblique settings during startup and save-driven world replacement.
  - Kept cliff overlay and shadow controls unchanged under the existing cliff export group.
- `scripts/terrain_renderer.gd`
  - Removed oblique preloads, state, renderer ownership, lifecycle calls, switching APIs, projection branches, picking branch, visibility switching, and oblique rebuild work.
  - Left the former top-down branches as the direct code path.
- `tests/phase3b_capture.gd`
  - Removed the obsolete `oblique_projection` manifest field.
- `README.md`
  - States that Wyntar supports only top-down presentation and that the former oblique prototype was retired in Phase C3.
- `PHASE_C3_OBLIQUE_RETIREMENT_REPORT.md`
  - This report.

## Files removed

Runtime implementation and UID sidecars:

- `scripts/oblique_projection.gd`
- `scripts/oblique_projection.gd.uid`
- `scripts/oblique_terrain_mesh_builder.gd`
- `scripts/oblique_terrain_mesh_builder.gd.uid`
- `scripts/oblique_terrain_renderer.gd`
- `scripts/oblique_terrain_renderer.gd.uid`
- `shaders/oblique_terrain.gdshader`
- `shaders/oblique_terrain.gdshader.uid`

Oblique-only Phase 2A/2B validation, capture, benchmark programs and UID sidecars:

- `tests/phase2a_validation.gd` and `.uid`
- `tests/phase2a_capture.gd` and `.uid`
- `tests/phase2a_benchmark.gd` and `.uid`
- `tests/phase2b_validation.gd` and `.uid`
- `tests/phase2b_capture.gd` and `.uid`
- `tests/phase2b_benchmark.gd` and `.uid`

These tests exclusively exercised APIs and geometry deleted by C3. Unrelated source tests remain tracked.

## Functions, state, and branches eliminated

Removed public oblique runtime APIs:

- `set_oblique_presentation_enabled()`
- `is_oblique_presentation_enabled()`
- `set_organic_oblique_refinement_enabled()`
- `is_organic_oblique_refinement_enabled()`
- `get_oblique_metrics()`

Removed runtime state and integration:

- `oblique_presentation_enabled`
- `organic_oblique_refinement_enabled`
- `oblique_renderer`
- `ObliqueProjection` and `ObliqueTerrainRenderer` preloads
- creation/configuration of `ExperimentalObliqueTerrain`
- oblique visible-cell-bound projection
- oblique chunk unload, invalidation, edit rebuild, and finalisation hooks
- switching that hid top-down chunks and environmental-object batches
- oblique rectangle/polygon projection branches
- oblique picking branch
- conditional top-down chunk visibility
- startup and replacement-world propagation from `Main`

The retained statements are the same statements previously executed whenever oblique mode was disabled.

## Approximate lines removed

The change removes approximately 1,708 lines of GDScript, test code, and shader code, plus 10 one-line UID sidecars. Three direct top-down statements replace former mode-selection branches, for a net reduction of approximately 1,705 active code lines before documentation and UID accounting.

The oblique runtime itself accounted for 675 GDScript lines and a 92-line shader. The retired Phase 2A/2B programs accounted for 849 lines.

## Shared functionality retained

- `TerrainWorld` remains the authoritative owner of material and elevation state.
- `TerrainGenerator` and all procedural generation settings are unchanged.
- `TerrainChunkBuildJob` and `TerrainChunkRenderer` remain the top-down preparation and rendering path.
- Organic, connected, unified, and directional top-down cliff code is unchanged.
- `world_pixel_to_cell()`, top-down `get_projected_cell_rect()`, `get_projected_cell_polygon()`, and raised-surface/cliff picking remain intact.
- Camera panning, zooming, reset behavior, and visible-world-rectangle production in `Main` are unchanged.
- Chunk load/unload margins, scheduling, retirement, edit invalidation, and environment-object batches are unchanged apart from removal of parallel oblique work.
- Water shaders, materials, enhancement controls, sea-level behavior, and tests are unchanged.
- Save paths, schemas, compatibility identifiers, backups, and world replacement behavior are unchanged.
- Resource selection, designation, harvesting, inventory, depletion, and regrowth are unchanged.
- Current `main.tscn` cliff, water, density, and presentation settings are preserved byte-for-byte.

## Dependency verification

There are no remaining oblique or isometric references in active scripts, tests, shaders, `main.tscn`, or `project.godot`. README references only document the retirement and top-down visual intent. Historical audit, plan, milestone, and C2 reports still describe the former subsystem as historical evidence.

No remaining tracked source file has a preload, call, feature flag, test dependency, or resource path pointing to the removed implementation.

## Tests executed

Validation used standard Godot `4.7.stable.official.5b4e0cb0f` with isolated app data. Every Godot process had an explicit timeout.

| Check | Timeout | Result |
| --- | ---: | --- |
| Project import and parse | 120 seconds | Pass |
| Main-scene startup | 60 seconds | Pass |
| `tests/phase5d_validation.gd` — top-down terrain/chunks | 120 seconds | Pass |
| `tests/phase3g_validation.gd` — cliffs and projected picking | 120 seconds | Pass; visual acceptance remains separate |
| `tests/phase_a_water_validation.gd` — water and streaming | 120 seconds | Pass |
| `tests/phase7a_validation.gd` — terrain editing | 120 seconds | Pass |
| `tests/phase7c3_validation.gd` — top-down ground picking/edit ordering | 120 seconds | Pass |
| `tests/phase1g_validation.gd` — camera movement and chunk streaming | 120 seconds | Pass |
| `tests/phase7b1_validation.gd` — save/load and compatibility | 120 seconds | Pass |
| `tests/phase8b_validation.gd` — resource interaction and streaming | 180 seconds | Pass |
| Active oblique dependency scan | N/A | Pass; zero runtime/test/shader/config references |
| Runtime resource and UID integrity | N/A | Pass |
| `git diff --check` | N/A | Pass |

Top-down cliff and water implementation files, shaders, material controls, defaults, and scene overrides have no C3 changes. Their focused validators pass. C3 did not generate a new artistic baseline or claim new visual approval.

## Preservation checks

- `main.tscn` SHA-256 remains `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933`.
- `_reference` remains at gitlink and nested HEAD `6ee33aa6d4f2f87d23841dc212b11b8fbf6ea64c` with its original dirty status fingerprint.
- The Wyntar project identity and legacy save-directory compatibility configuration from C2 remain unchanged.
- The external Phase C1 archive remains outside the working tree and was not modified.

## Remaining risks

- Historical reports refer to removed oblique paths and APIs. They are intentionally retained as historical evidence and remain recoverable through Git history.
- No new pixel-by-pixel screenshot comparison was generated. Visual preservation is supported by the unchanged top-down renderer/shader/cliff/water code paths, the preserved scene hash, and passing focused validators; final artistic review remains manual.
- The existing directional-cliff visual acceptance issue remains unrelated to C3.
- `_reference` remains a dirty nested checkout and was deliberately untouched.

## Recommended next cleanup

Review and commit C3 independently. A later, separately approved cleanup may index historical Phase 2A/2B evidence more explicitly or reconcile remaining cliff experiment switches after visual approval. Do not combine that work with Phase 3H or unrelated rendering changes.
