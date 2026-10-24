# Wyntar Architecture Refactor Plan

## Scope and baseline

Phase R1 is a behaviour-preserving architecture audit and camera extraction. It does not implement C4G, change terrain visuals, alter simulation rules, or change save data.

The audit began from the actual working tree, including uncommitted work. The baseline already contained modifications to `main.tscn`, `project.godot`, `scripts/main.gd`, the terrain/cliff rendering pipeline, and C4 validation files, plus untracked C4E.1/C4F reports and tests. Those changes were treated as protected. In particular, the existing C4F `grid_aligned_cliff_rim_enabled` additions in `main.gd` were preserved. Phase R1 did not modify `main.tscn`, `project.godot`, `_reference`, or any terrain/cliff implementation.

## 1. Current architecture inventory

Line counts are approximate and reflect the post-R1 working tree.

| System / script | Existing responsibility | Approx. size | Main dependencies | Extraction recommendation | Suggested target |
|---|---|---:|---|---|---|
| `scripts/main.gd` | Composition root; creates terrain, cursor, editor, resource interaction, save service, camera and HUD; routes input; configures renderer; coordinates save/load and world replacement | 1,152 | Catalog, TerrainRenderer, CursorOverlay, WorldEditorController, ResourceInteractionController, WorldSaveService, CameraController | Yes, in phases; retain as composition/coordinator root | R2 input/editor presentation, R3 renderer settings, R4 world session lifecycle |
| `scripts/camera_controller.gd` | Map-camera keyboard movement, middle-button drag, cursor-centred wheel zoom, limits, Home reset, state application, and camera-derived visible-world rectangles | ~105 | Godot `Camera2D`, viewport input/state, target `CanvasItem` transform | No further extraction now | Remain the camera boundary introduced in R1 |
| `scripts/terrain_renderer.gd` | Terrain presentation facade and streaming orchestrator; owns shared render resources, build queues, loaded chunks, renderer-facing world queries, resource-state integration, and configuration propagation | 2,269 | TerrainGenerator, TerrainWorld, chunk renderer/jobs, catalogs, placement, resource state, factories, global object renderer | Selective only; a broad split is high risk | R5 may extract bounded scheduling/configuration helpers while retaining the facade |
| `scripts/world_editor_controller.gd` | Transient brush/tool state, stroke batching, bounded undo/redo history, and requests to apply authoritative terrain state transitions | 253 | TerrainRenderer public edit/query interface | Keep; already a good boundary | R2 should route input to it rather than recreate its functionality |
| `scripts/terrain_world.gd` | Authoritative terrain material/elevation state; procedural fallback; sparse player overrides; snapshot validation/import/export | 243 | TerrainGenerator, terrain catalog | Keep unchanged | Authoritative simulation owner |
| `scripts/terrain_chunk_renderer.gd` | Visual-only scene representation for one 32×32 chunk; tile layers, elevated surfaces, cliffs, decorations, organic mesh attachment | 939 | TerrainWorld constants, prepared build-job data, organic mesh builder, decoration placement | Keep unless a later renderer-specific task proves a narrow seam | Chunk presentation owner |
| `scripts/terrain_chunk_build_job.gd` | Resumable, scene-tree-free chunk data preparation; caches halos and derives terrain, cliff, decoration, environment and organic geometry output | 785 | TerrainWorld constants, placement functions, organic mesh builder, callbacks supplied by renderer | Keep | Plain-data incremental build job |
| `scripts/world_save_service.gd` | Versioned JSON capture/validation, safe file replacement/backup, and loading | 288 | TerrainWorld, ResourceStateManager, EnvironmentObjectCatalog validators; camera state read as `Camera2D` | Keep | Persistence service; authoritative owners still validate/import their state |
| `scripts/resource_interaction_controller.gd` | Transient resource selection/mode adapter; requests actions from TerrainRenderer | 89 | TerrainRenderer public resource API | Keep | R2 input routing should delegate to it |
| `scripts/resource_state_manager.gd` | Authoritative resource deviations, inventory, designations, depletion/regrowth and snapshot state | 363 | Environment definition data and deterministic IDs | Keep unchanged | Authoritative resource simulation owner |
| `scripts/environment_object_catalog.gd` | Data-only object definitions and lookup tables | 219 | No runtime owner | Keep unchanged | Definition/data layer |
| `scripts/environment_object_placement.gd` | Pure deterministic placement and exclusion decisions | 257 | Absolute coordinates, seed, authoritative terrain callbacks | Keep unchanged | Deterministic placement logic |
| `scripts/environment_object_renderer.gd` | Global batched visual orchestration across chunk/elevation boundaries | 238 | EnvironmentObjectLayer, atlas/configuration supplied by TerrainRenderer | Keep unchanged | Environment presentation owner |
| `scripts/environment_object_layer.gd` | Draws one elevation band of environment atlas items | 82 | Atlas and immutable draw snapshots | Keep unchanged | Leaf presentation component |
| `scripts/cliff_resource_factory.gd` and other factories | Build shared rendering resources and materials consumed by TerrainRenderer | ~236 for cliff factory | Renderer configuration, shader/assets, build-job constants | Keep; already extracted from renderer lifecycle | Resource factory layer |
| `main.tscn` | Owns only the root `TerrainDemo` node and exported configuration overrides; runtime children are created by `main.gd` | 20 lines | `scripts/main.gd` | No scene restructuring in R1 | Preserve until a deliberate scene-composition phase |

### Ownership map

- Authoritative terrain data: `TerrainWorld`; modified through validated edit calls exposed by `TerrainRenderer`; read by renderer/build systems; saved through exported snapshots.
- Authoritative resource data: `ResourceStateManager`; modified through resource requests; read as snapshots by renderers/UI; saved through exported snapshots.
- Camera state/navigation: `CameraController`; modified by camera input or validated loaded state; read by HUD and `WorldSaveService`.
- Visible terrain streaming: `TerrainRenderer`; `main.gd` supplies a camera-derived rectangle. The camera does not load or unload chunks.
- Editor tool/history state: `WorldEditorController`; it requests authoritative changes and does not own a second world copy.
- Rendering: `TerrainRenderer`, `TerrainChunkRenderer`, `EnvironmentObjectRenderer`, leaf layers and resource factories. These do not become gameplay authority.
- Persistence: `WorldSaveService` owns serialization and file recovery; authoritative runtime owners own import validation and mutation.
- UI/input routing: currently mostly `main.gd`; UI requests actions and does not own gameplay state.

## 2. Main architectural problems

1. `main.gd` is a large composition root with several additional responsibilities: input routing, runtime UI construction/update, renderer configuration mirroring, save/load orchestration, and world replacement. This increases coupling and makes behaviour-preserving changes harder to review.
2. Renderer configuration is duplicated as many exports on `main.gd` and mutable fields on `TerrainRenderer`. The existing `_configure_terrain_renderer()` correctly applies configuration before `_ready()`, but the breadth of the mapping creates drift risk.
3. World replacement is correctly coordinated in one place but mixes construction, authoritative import, signal wiring, presentation rebinding, camera restoration, and UI refresh.
4. `TerrainRenderer` is large because it is both a stable facade and an orchestrator for streaming, resources, factories, editing refresh and diagnostics. Splitting it casually would weaken established ownership and should not be part of a broad cleanup.
5. Input priority is encoded by branch order in `main.gd`. That order is behaviourally important but not explicit as a routing contract.

Existing separated systems should be reused. In particular, R2 must not recreate editor history or resource interactions, and R5 must not move authoritative state out of `TerrainWorld` or `ResourceStateManager`.

## 3. Camera extraction implementation

Phase R1 adds `scripts/camera_controller.gd` as a `Camera2D` subclass. `main.gd` continues to create the runtime `MapCamera` at the same point in startup, with the same parent, name, current-camera status, initial position and zoom. No scene edit was necessary.

The controller now owns:

- WASD and arrow-key movement using the original normalized direction, `700.0` pan speed and inverse-zoom scaling;
- middle-button press/release state and inverse-zoom drag movement;
- cursor-centred wheel zoom using the original `1.15` factor;
- the original `0.001` minimum and `166.0` maximum zoom;
- the Home reset shortcut and original centre `(16, 16)`;
- loaded camera state application;
- calculation of a visible-world `Rect2` from the target canvas transform and viewport size.

`main.gd` retains coordination responsibilities:

- resource selection is checked before camera pointer handling, preserving editor/resource input priority;
- the visible rectangle is passed to `CursorOverlay` and `TerrainRenderer`;
- terrain streaming remains wholly owned by `TerrainRenderer`;
- wheel/reset zoom notifications update HUD text at the same points as before;
- save capture still receives a `Camera2D`-compatible object;
- world replacement restores camera state through `CameraController.apply_state()` and then refreshes visible consumers.

## 4. Files changed

- `scripts/camera_controller.gd` — new dedicated camera owner.
- `scripts/camera_controller.gd.uid` — Godot-generated script identity.
- `scripts/main.gd` — narrow composition and delegation changes; pre-existing C4F edits preserved.
- `tests/phase_r1_camera_validation.gd` — focused parity/integration validation.
- `tests/phase_r1_camera_validation.gd.uid` — Godot-generated test-script identity.
- `WYNTAR_ARCHITECTURE_REFACTOR_PLAN.md` — this audit and phased plan.

No R1 changes were made to `main.tscn`, `project.godot`, `_reference`, terrain rendering, elevation, shaders, or save format.

## 5. Validation results

Validation used Godot `4.7.2.stable.mono.official.ed1daf0bf` and was bounded.

| Check | Result |
|---|---|
| Project import and script parsing (`--editor --quit`) | Pass |
| Main-scene startup (`main.tscn`, headless, bounded to 5 frames) | Pass; exit code 0, no runtime errors |
| Focused R1 camera validation | Pass (`PHASE_R1_CAMERA_VALIDATION: PASS`) |
| Pan formula and zoom-dependent speed | Pass |
| Cursor-centred zoom formula and 0.001/166 limits | Pass |
| Middle drag and release | Pass |
| Home reset and initial camera state | Pass |
| Non-camera/editor pointer input remains unconsumed by camera | Pass |
| Resource/editor left-click priority in `main.gd` | Pass |
| Visible-world rectangle parity with the former calculation | Pass |
| Rectangle propagation to cursor | Pass |
| Chunk loading/unloading after camera movement | Pass |
| Save snapshot and world replacement camera restoration | Pass |
| Existing renderer configuration/world-replacement regression | Pass (`PHASE_C4A_RENDERER_CONFIGURATION: PASS`) |
| Existing save/load validation | Pass (`PHASE7B1_VALIDATION: PASS`) |
| `git diff --check` | Pass; only existing line-ending warnings were reported |

Headless checks validate deterministic state transitions and streaming integration. Final feel of continuous pan, cursor anchoring and editor interaction should still receive a short manual in-window smoke test because synthetic/headless input cannot assess subjective interaction feel.

## 6. Proposed subsequent phases

### R2 — World editor and input responsibilities

Goal: make input priority explicit while retaining existing editor/resource owners.

1. Introduce one small input-routing controller owned by `main.gd`, or move only routing logic into an existing suitable controller if its responsibility remains clear.
2. Preserve the current order: UI blocking, resource selection, camera pointer input, editor strokes, then non-overlapping shortcuts.
3. Delegate tool mutations/history to `WorldEditorController` and resource actions to `ResourceInteractionController`; do not duplicate either state machine.
4. Leave HUD construction in `main.gd` unless separating it is specifically scoped and validated.

Dependencies: stable CameraController interface from R1; tests for branch priority and stroke lifecycle.

Risks: input handling order, held mouse buttons, shortcut overlap (`D` is both movement and a toggle on key press), and strokes continuing when the pointer crosses UI.

### R3 — Rendering configuration and settings

Goal: reduce the large export-to-renderer mapping without changing initialization timing.

1. Inventory settings by owner: world generation, streaming budget, material/visual controls, cliffs, decorations and environment objects.
2. Prefer Resource-based immutable configuration groups only if the architect approves the serialization/editor-facing shape.
3. Preserve the critical rule that complete renderer configuration is applied before `TerrainRenderer._ready()`.
4. Keep runtime toggles as explicit renderer methods so changes trigger only their existing rebuild/invalidation paths.

Dependencies: R2 need not be complete, but current C4 work should be stable so configuration fields are not moving concurrently.

Risks: exported scene overrides, omitted fields during world replacement, accidental rebuilds, and save-generation compatibility.

### R4 — World session lifecycle

Goal: isolate creation/replacement wiring while retaining authoritative owners.

1. Extract a narrowly scoped world-session coordinator for renderer construction, signal connection, cursor/editor/resource rebinding, authoritative import, and retirement of the previous renderer.
2. Keep `WorldSaveService` responsible only for persistence and schema validation.
3. Keep `TerrainWorld` and `ResourceStateManager` authoritative; invalid snapshots must not mutate the active session.
4. Keep `main.gd` responsible for requesting replacement and updating top-level UI/session metadata.

Dependencies: settled renderer configuration handoff from R3.

Risks: signal duplication, queued-free old worlds, cursor parent transfer, dirty-state timing, failed import atomicity, and camera/visible-region refresh ordering.

### R5 — Terrain renderer orchestration, only where beneficial

Goal: reduce orchestration complexity without breaking the renderer facade.

Potential narrow seams:

- chunk streaming queue/scheduler state;
- renderer diagnostics/profiling aggregation;
- shared visual-resource construction already partly delegated to factories;
- environment batch coordination if a clean existing boundary can be retained.

Keep `TerrainRenderer` as the public facade used by editor, resource interaction, saves, cursor queries and main coordination. Keep `TerrainChunkBuildJob`, `TerrainChunkRenderer`, `TerrainWorld`, placement classes, catalogs, factories, `ResourceStateManager`, and environment render classes unchanged unless a measured problem directly requires modification.

Dependencies: R3 and R4 should establish stable configuration/session boundaries first; C4G should be planned independently rather than folded into this refactor.

Risks: job cancellation and revision ordering, frame budgets, chunk retirement, edit refresh correctness, deterministic placement, organic cliff rebuild scheduling, and public API churn.

## 7. Risks and rollback instructions

### Remaining risks

- The controller intentionally preserves extreme zoom limits even though `WorldSaveService` currently validates persisted zoom only in the narrower `0.1` to `10.0` range. That mismatch predates R1 and was not changed because save schema changes are out of scope.
- `main.gd` still owns a large HUD and configuration surface; R1 removes only camera behaviour.
- Continuous physical mouse/keyboard feel should be manually smoke-tested in a window.
- Existing uncommitted C4E/C4E.1/C4F work remains interleaved in the working tree and must continue to be preserved.

### Rollback

Rollback must be surgical because `scripts/main.gd` contains protected pre-existing C4F changes. Do not reset or restore the whole file.

1. Manually reverse only the R1 camera delegation hunks in `scripts/main.gd`: restore the five camera constants, `Camera2D.new()`, `_middle_panning`, the former movement/zoom/reset methods, direct input branches, direct load-state assignment, and former visible-rectangle calculation. Leave the C4F grid-aligned cliff setting and all unrelated changes intact.
2. Remove only the R1-added files: `scripts/camera_controller.gd`, `tests/phase_r1_camera_validation.gd`, and this plan document.
3. Re-run project parse, bounded main startup, relevant save/world replacement tests, and `git diff --check`.

No commit or push was created, and no existing work was reset or discarded.
