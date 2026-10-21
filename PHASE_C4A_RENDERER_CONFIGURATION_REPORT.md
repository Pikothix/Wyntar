# Wyntar Phase C4A Renderer Configuration Report

Date: 2026-10-21

Task classification: Existing System Refactor — behaviour-preserving configuration consolidation

Starting branch and commit: `main` at `3e514ad2c34d4334fcfdc01c95646cf57093727e` (`Phase C3: retire obsolete oblique rendering`)

## Summary

Phase C4A consolidates the configuration that `Main` applies to `TerrainRenderer`. Initial startup and save-world replacement now call the same private `_configure_terrain_renderer()` helper before adding the renderer to the scene tree.

The helper performs direct field assignment only. It does not create nodes, initialize materials, create terrain authority, schedule chunks, or rebuild existing chunks. Save restoration remains a separate responsibility: after common configuration, the validated saved generation configuration and berry-regrowth value override their corresponding scene values before `TerrainRenderer._ready()` initializes the replacement world.

No terrain, chunk, shader, material, water, cliff, generation, resource, or save implementation was changed. `main.tscn` and `_reference` remain untouched.

## Files changed

- `scripts/main.gd`
  - Added `_configure_terrain_renderer(renderer: TerrainRenderer) -> void`.
  - Replaced startup's inline configuration block with one helper call.
  - Replaced save-world replacement's duplicated configuration block with the same helper call.
  - Retained saved generation and resource-state overrides before renderer initialization.
- `tests/phase_c4a_renderer_configuration_validation.gd`
  - Added focused pre-ready, startup, replacement, save-compatibility, and configuration-survival coverage.
- `tests/phase_c4a_renderer_configuration_validation.gd.uid`
  - Godot UID for the focused validator.
- `PHASE_C4A_RENDERER_CONFIGURATION_REPORT.md`
  - This report.

## Configuration inventory

The shared helper transfers 52 active values from `Main` to a supplied renderer.

| Group | Values transferred |
| --- | --- |
| World generation | `world_seed`, `biome_frequency`, `detail_frequency`, `include_origin_demo` |
| Procedural elevation | enabled state, maximum elevation, base/detail frequencies, detail strength, three thresholds, flatness bias, sea level |
| Streaming/performance | load/unload margins, chunks per frame, profiling, processing budget, work quantum, tile-cell budget |
| Texture variation | enabled state, strength, frequency |
| Organic boundaries | enabled state, edge strength, edge frequency |
| Enhanced water | enabled state, ripple strength, secondary scale, drift speed, glint density, glint brightness |
| Cliffs | procedural material, organic geometry, unified components, refined silhouettes, connected contours, unified contours, directional projection, height profile, overlays, shadows |
| Ground decorations | enabled state, density, clustering, seed offset |
| Environment/resources | object visibility, procedural vegetation, density, seed offset, berry regrowth duration |

The effective `main.tscn` overrides recorded before implementation were:

- `include_elevation_demo = true`
- `experimental_water_enhancement_enabled = true`
- `unified_cliff_contours_enabled = true`
- `directional_cliff_projection_enabled = true`
- `cliff_height_profile = 2`
- `cliff_edge_overlays_visible = false`
- `cliff_shadows_visible = false`
- `decoration_density = 2.0`
- `decoration_clustering_strength = 1.0`
- `environment_object_density = 2.0`

Combining those scene overrides with the existing `scripts/main.gd` export defaults produced this effective startup renderer configuration:

| Group | Effective values |
| --- | --- |
| World generation | `world_seed=84521`; `biome_frequency=0.012`; `detail_frequency=0.055`; `include_origin_demo=true` |
| Procedural elevation | `enabled=true`; `max=3`; `frequency=0.006`; `detail_frequency=0.021`; `detail_strength=0.14`; `thresholds=-0.12/0.16/0.43`; `flatness_bias=0.02`; `sea_level=0` |
| Streaming/performance | `load_margin=1`; `unload_margin=2`; `chunks_per_frame=2`; `profiling=false`; `processing_ms=2.5`; `work_quantum=24`; `tile_cells_per_frame=256` |
| Texture variation | `enabled=true`; `strength=0.65`; `frequency=0.0025` |
| Organic boundaries | `enabled=true`; `edge_strength=0.08`; `edge_frequency=0.035` |
| Enhanced water | `enabled=true`; `ripple_strength=0.32`; `secondary_scale=2.4`; `drift_speed=0.55`; `glint_density=0.14`; `glint_brightness=0.38` |
| Cliffs | `procedural_material=true`; `organic_geometry=true`; `unified_components=true`; `refined_silhouettes=true`; `connected_contours=true`; `unified_contours=true`; `directional_projection=true`; `height_profile=2`; `overlays=false`; `shadows=false` |
| Ground decorations | `enabled=true`; `density=2.0`; `clustering=1.0`; `seed_offset=63017` |
| Environment/resources | `objects_enabled=true`; `procedural_vegetation=true`; `density=2.0`; `seed_offset=91423`; `berry_regrowth_seconds=120.0` |

`include_elevation_demo=true` is a `Main` lifecycle option rather than a renderer configuration field; it remains applied after renderer initialization exactly as before. The scene remained byte-for-byte unchanged with SHA-256 `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933`.

## Before and after comparison

### Before C4A

Startup assigned all 52 values inline before `add_child(terrain)`.

Save-world replacement had a second inline block with these differences:

- It did not transfer `chunk_profiling_enabled`; the replacement used the renderer default.
- Streaming limits were copied from the old renderer, while other presentation values came from `Main` exports.
- Directional cliff projection was copied from the old renderer, while other cliff values came from `Main` exports.
- Water controls were assigned without startup's defensive range clamps.
- Decoration density, clustering and seed plus environment density and seed were not in the duplicated presentation block; they arrived indirectly through the saved generation configuration.
- Generation values and berry regrowth correctly came from the saved snapshot because those values are authoritative saved-world configuration.

No other production renderer recreation path exists. Tests that construct isolated renderers remain independent fixtures and were not changed.

### After C4A

- Startup constructs a renderer, calls `_configure_terrain_renderer()`, then adds it to the tree.
- Save replacement constructs a renderer, calls the same helper, applies validated saved generation and berry-regrowth overrides, then adds it to the tree and imports authoritative terrain/resource state.
- Both paths therefore share one complete presentation, streaming, performance, water, cliff, decoration, and environment configuration mechanism.
- Saved generation and resource configuration retain precedence during load, preserving the save format and world identity.

## Duplicated assignments removed

The startup block of 52 direct assignments and the save replacement's partial duplicate block were replaced by two calls to the shared helper. `scripts/main.gd` has a net reduction of 22 lines (`61` additions and `83` removals), including lifecycle comments.

No configuration framework, resource type, factory, or additional abstraction was introduced.

## Lifecycle considerations

`TerrainRenderer._ready()` builds shared tilesets/materials and placement contexts, creates `ResourceStateManager`, creates the environment renderer, configures `TerrainGenerator`, and creates `TerrainWorld`. Several transferred values are consumed during those operations and cannot safely be deferred.

Accordingly, common configuration remains before `add_child()` on both paths. Saved generation and berry-regrowth values are also applied before `add_child()` so the replacement initializes directly with saved authority. Authoritative terrain/resource snapshot import remains after `_ready()`, as required by the existing validation and import APIs. Renderer rebinding and old-renderer retirement order is unchanged.

The helper uses direct field assignments rather than runtime setter methods. The focused validator confirms that calling it on a detached renderer leaves `generator`, `world`, and `resource_state_manager` uninitialized, with zero pending or loaded chunks. The refactor therefore adds no chunk rebuild or scheduling pass.

## Focused regression test

`tests/phase_c4a_renderer_configuration_validation.gd` uses deterministic, deliberately non-default values to verify:

1. Every transferred startup value matches the corresponding `Main` export, including profiling.
2. Configuration is complete while the renderer is still detached and before `_ready()` initialization.
3. Direct configuration schedules no chunks and triggers no rebuilds.
4. An existing-format snapshot validates successfully.
5. Save-world replacement succeeds and retains an exact 52-value configuration match.
6. Water, cliff, decoration, vegetation, and environment settings survive replacement.
7. Saved generation/resource values remain compatible with the existing replacement sequence.

## Validation results

Validation used standard Godot `4.7.stable.official.5b4e0cb0f` with isolated local app data. Each Godot process had an explicit timeout.

| Check | Timeout | Result |
| --- | ---: | --- |
| Project import and parse | 120 seconds | Pass |
| Main-scene startup | 60 seconds | Pass |
| Focused C4A renderer configuration | 120 seconds | Pass |
| `tests/phase5d_validation.gd` — terrain/chunks | 120 seconds | Pass |
| `tests/phase_a_water_validation.gd` — water | 120 seconds | Pass |
| `tests/phase3g_validation.gd` — cliffs | 120 seconds | Pass; structural validation, visual acceptance remains separate |
| `tests/phase7b1_validation.gd` — save/load | 120 seconds | Pass |
| `tests/phase8b_validation.gd` — resource interaction | 180 seconds | Pass |
| `git diff --check` | N/A | Pass; only pre-existing line-ending warnings were emitted |

No screenshots or large evidence sets were generated.

## Preservation checks

- C3 was committed before C4A began at `3e514ad2c34d4334fcfdc01c95646cf57093727e`.
- `main.tscn` retains SHA-256 `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933`.
- `_reference` retains gitlink and nested HEAD `6ee33aa6d4f2f87d23841dc212b11b8fbf6ea64c` and its pre-existing dirty-state fingerprint `44D3134CE04BF1025509D801092E36CFF578BA53FE9A5FB27743AC77E84F6D55`.
- The pre-existing unrelated untracked pager artifact remains untouched.
- No commit or push was performed.

## Remaining risks

- The focused test proves configuration equality and pre-ready timing structurally; final artistic acceptance remains a manual visual check.
- Historical code allowed runtime-only mutation of the active renderer's streaming or directional-projection fields to carry into a replacement independently of `Main`. Normal project controls keep `Main` as the composition configuration source, and no production mutation path was found. External debug code that bypasses `Main` would now need to update the owning export value as well.
- Existing cliff-default visual acceptance and the dirty `_reference` checkout remain separate, unchanged concerns.

## Recommended next phase

Review and commit C4A independently. If the project architect approves a single production cliff baseline, a separate C4B task can consolidate the remaining cliff experiment/rollback switches with dedicated visual acceptance. Do not combine that work with Phase 3H, atlas/material factory refactoring, or changes to rendering defaults.
