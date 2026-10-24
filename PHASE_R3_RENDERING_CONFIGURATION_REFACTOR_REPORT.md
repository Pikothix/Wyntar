# Wyntar Phase R3 — Rendering Configuration and Settings Refactor

## Scope and protected baseline

R3 is a behaviour-preserving configuration ownership refactor. The existing uncommitted R1, R2, C4E, C4E.1 and C4F work was treated as protected.

No R3 change was made to `main.tscn`, `project.godot`, `_reference`, shaders, terrain generation algorithms, terrain geometry, rendering algorithms, save format, or gameplay semantics. No reset, discard, commit, or push was performed.

## 1. Configuration ownership before and after

### Before R3

`main.gd` exposed the Inspector-compatible settings and manually copied approximately 80 scalar and grouped values into every new `TerrainRenderer`. `TerrainRenderer` also carried standalone defaults because it is instantiated directly by tests and tools.

The existing flow was:

1. `main.tscn` deserialized overrides into `main.gd` exports.
2. Startup called `_configure_terrain_renderer()` before adding the renderer to the tree.
3. World replacement called the same method, then applied saved generation configuration over the new renderer before `_ready()`.
4. Runtime shortcuts updated both the corresponding `main.gd` field and the active renderer through explicit setter methods.
5. After replacement, `_sync_configuration_from_terrain()` copied saved generation/placement values back to the compatibility exports.

The startup/replacement path was already shared, but `main.gd` knew every renderer field, grouped material dictionary and clamp rule.

### After R3

The serialized compatibility surface is unchanged. Typed, transient `RefCounted` settings snapshots now own grouping and transfer:

| Settings owner | Responsibility |
|---|---|
| `WorldGenerationSettings` | Seed, biome/detail noise, procedural elevation and sea level |
| `ChunkStreamingSettings` | Load/unload margins, creation limits, profiling and per-frame budgets |
| `TerrainRenderingSettings` | Surface variation, clustered/organic grass, material repetition controls, stochastic/remaining detail and organic boundaries |
| `WaterRenderingSettings` | Water repetition correction and experimental ripple/glint controls |
| `CliffRenderingSettings` | Cliff repetition, materials, C4 geometry switches, projection, height profile, edge overlays and shadows |
| `EnvironmentRenderingSettings` | Ground decorations, environment objects, procedural vegetation and berry timing |
| `TerrainRendererConfiguration` | Captures the six groups and applies them in one complete pre-ready operation |

`main.gd._configure_terrain_renderer()` is now one configuration capture/apply call. Startup and replacement continue to use that exact method.

The settings classes intentionally define no defaults. They capture the current compatibility exports, avoiding a third duplicated source of defaults. `TerrainRenderer` retains its own defaults because direct renderer construction is a supported existing pattern.

### Settings retained outside renderer configuration

- Camera constants and navigation settings remain owned by `CameraController`.
- Editor tool state remains owned by `WorldEditorController`.
- HUD/UI state, world identifier/display name and `include_elevation_demo` remain in `main.gd`; they are orchestration/presentation settings rather than renderer construction settings.
- Runtime feature switches retain their explicit renderer setter calls because those methods own required invalidation/rebuild behavior.

## 2. Files changed

- `scripts/main.gd` — preserves all exports and delegates complete renderer transfer to `TerrainRendererConfiguration`.
- `scripts/settings/world_generation_settings.gd` and `.uid`.
- `scripts/settings/chunk_streaming_settings.gd` and `.uid`.
- `scripts/settings/terrain_rendering_settings.gd` and `.uid`.
- `scripts/settings/water_rendering_settings.gd` and `.uid`.
- `scripts/settings/cliff_rendering_settings.gd` and `.uid`.
- `scripts/settings/environment_rendering_settings.gd` and `.uid`.
- `scripts/settings/terrain_renderer_configuration.gd` and `.uid`.
- `tests/phase_r3_rendering_configuration_validation.gd` and `.uid` — focused compatibility/default/grouping validation.
- `tests/phase7b1_fresh_load.gd` — repairs the no-op editor-history fixture.
- `PHASE_R3_RENDERING_CONFIGURATION_REFACTOR_REPORT.md` — this report.

`main.gd` is approximately 1,003 lines after R3, down from approximately 1,106 after R2. Compatibility and explicit ownership, rather than line-count reduction, determined the design.

## 3. Settings consolidated

The former manual transfer in `main.gd` has been fully consolidated, including:

- all world generation and procedural elevation inputs;
- all chunk streaming budgets;
- G1 texture variation;
- G2 clustered grass controls;
- G3 organic grass colour controls;
- G4 grass repetition control;
- G5 per-material terrain repetition and stochastic detail controls;
- G6 remaining terrain, water and cliff repetition controls;
- organic terrain boundary settings;
- experimental water enhancement controls;
- procedural/organic cliff settings;
- C4E/C4E.1 connected and unified contour controls;
- C4F grid-aligned rim switch;
- directional cliff projection, height profile, edge overlay and shadow visibility;
- decoration/environment placement settings and resource regrowth timing.

The existing per-material dictionaries are still built once per renderer construction. They are transferred directly to the pre-ready renderer without an additional deep-copy allocation.

## 4. Compatibility strategy

Every existing exported property name, type, range and default remains declared in `main.gd`. Tests and scripts may continue assigning properties directly before the node enters the scene tree.

This preserves all current `main.tscn` overrides:

- `include_elevation_demo = true`;
- experimental water enhancement enabled;
- ripple strength `0.63`, drift speed `0.25`, glint density `0.6`, glint brightness `0.7`;
- unified cliff contours enabled;
- directional projection enabled;
- cliff height profile `2`;
- edge overlays and shadows disabled;
- decoration density `2.0`, clustering `1.0`;
- environment-object density `2.0`.

No nested Resource property was introduced into the scene, so the scene requires no migration and no effective value can silently reset. A future Inspector migration should only happen as an explicit data migration with scene changes reviewed separately.

## 5. Runtime behaviour parity evidence

- Complete configuration still occurs before `TerrainRenderer._ready()` constructs generators, render resources, contexts and authoritative runtime state.
- Startup and replacement still call `_configure_terrain_renderer()`.
- Saved generation configuration still overrides scene generation values during replacement before the renderer enters the tree.
- Water and cliff clamp ranges are unchanged.
- Runtime V/O/D/T/P and related visual controls still use existing renderer methods and invalidation paths.
- Experimental defaults remain disabled in a detached/default `Main`.
- Protected scene overrides remain enabled where explicitly serialized.
- The exhaustive C4A all-field comparison passes for detached pre-ready application, startup, and replacement.
- Focused R3 validation confirms captured settings do not change when compatibility exports are subsequently mutated.

## 6. Test fixture correction

The previous fresh-load fixture painted material `3` at `(5,5)`. Under the protected current scene configuration, that cell already has an explicit material-3 override, so the operation is correctly a no-op and creates no undo entry.

The fixture now:

1. reads the current material at its test cell;
2. selects `(current_material + 1) % 8`, which is always a different valid material;
3. performs the stroke and verifies history exists before loading.

Production editor behavior is unchanged. Both fresh-process save and fresh-process load now pass, and the history assertion will fail for a genuine editor transaction regression.

## 7. Validation results

Validation used Godot `4.7.2.stable.mono.official.ed1daf0bf`.

| Check | Result |
|---|---|
| Project import and script parsing | Pass |
| Bounded main-scene startup | Pass |
| Focused R3 compatibility/default/grouping validation | Pass (`PHASE_R3_RENDERING_CONFIGURATION_VALIDATION: PASS`) |
| Exhaustive startup/replacement configuration parity | Pass (`PHASE_C4A_RENDERER_CONFIGURATION: PASS`) |
| Protected scene override preservation | Pass |
| G1 texture variation | Pass |
| G2 clustered grass | Pass |
| G3 organic grass colour | Pass |
| G4 grass repetition | Pass |
| G5 terrain repetition/stochastic detail | Pass |
| G6 remaining terrain/water/cliff controls | Pass |
| Water regression | Pass (`PHASE_A_WATER_VALIDATION: PASS`) |
| C4E.1 cliff continuity | Pass (`PHASE_C4E1_CLIFF_CONTINUITY_VALIDATION: PASS`) |
| C4F grid cliff validation | Pass (`PHASE_C4F_GRID_CLIFF_VALIDATION: PASS`) |
| R1 camera and chunk-streaming integration | Pass (`PHASE_R1_CAMERA_VALIDATION: PASS`) |
| R2 editor/input behavior | Pass (`PHASE_R2_WORLD_EDITOR_REFACTOR_VALIDATION: PASS`) |
| Save/schema regression | Pass (`PHASE7B1_VALIDATION: PASS`) |
| Corrected fresh-process save/load | Pass (`PHASE7B1_FRESH_SAVE: PASS`, `PHASE7B1_FRESH_LOAD: PASS`) |
| `git diff --check` | Pass; only existing line-ending warnings were reported |

A short in-window visual smoke test remains advisable for subjective presentation parity, but deterministic configuration, renderer state and relevant geometry/water paths are covered by the bounded tests above.

## 8. Remaining responsibilities in `main.gd`

`main.gd` still owns:

- the legacy exported Inspector surface for scene compatibility;
- runtime system construction and signal wiring;
- configuration snapshot creation at renderer construction boundaries;
- saved-world replacement coordination;
- global input priority and presentation toggles;
- HUD/editor-panel construction and updates;
- camera-to-streaming coordination;
- world identity and save/load requests.

It no longer knows how individual renderer configuration groups are represented or transferred.

## 9. Recommended next steps

Proceed to the planned world-session lifecycle phase before considering any renderer-orchestration split:

1. Extract only renderer creation, signal wiring, authoritative import, cursor/editor/resource rebinding and old-renderer retirement.
2. Keep `WorldSaveService` limited to serialization/schema validation.
3. Keep `TerrainWorld` and `ResourceStateManager` authoritative.
4. Pass a captured `TerrainRendererConfiguration` into the session creation boundary rather than exposing individual settings there.
5. Preserve failed-import atomicity and camera/visible-region refresh ordering.

C4G unified elevated-surface boundaries should remain a separate rendering feature task. Do not combine it with configuration or lifecycle refactors. `TerrainRenderer`, chunk build jobs, chunk renderers, editor/camera/resource controllers and the new settings groups should remain unchanged unless that feature directly requires a narrow extension.
