# Wyntar Phase R2 — World Editor and Input Responsibility Refactor

## Scope and protected baseline

Phase R2 is a behaviour-preserving refactor of editor ownership and input routing. The working tree already contained uncommitted C4E, C4E.1, C4F and R1 work. All of it was treated as protected.

R2 did not modify `main.tscn`, `project.godot`, `_reference`, terrain generation, terrain rendering, cliff code, shaders, persistence format, or gameplay semantics. No reset, discard, commit, or push was performed.

## 1. Before and after responsibility ownership

| Responsibility | Before R2 | After R2 |
|---|---|---|
| Authoritative terrain material/elevation | `TerrainWorld`, accessed through `TerrainRenderer` | Unchanged |
| Edit application, stroke transactions, brush rasterization, elevation tools, restore, undo/redo | `WorldEditorController` | Unchanged; confirmed as the correct existing owner |
| Selected material and edit mode | Owned by `WorldEditorController` but duplicated in `main.gd` as `selected_id` and `height_edit_mode` | Sole runtime owner is `WorldEditorController`; `main.gd` observes a state snapshot |
| Pointer stroke button/lifecycle | Button state and polling branches in `main.gd`; transaction internals in `WorldEditorController` | `WorldEditorController.update_pointer_stroke()` owns button selection, drag continuation and release; `main.gd` supplies routed intent |
| Editor shortcuts | Decoded and applied field-by-field in `main.gd` | `WorldEditorController.handle_shortcut()` owns undo/redo, brush-size, material and mode shortcuts |
| Editor tool changes from UI | UI callbacks directly mutated public fields and manually refreshed several HUD elements | UI callbacks call narrow controller setters; one `state_changed` signal updates presentation |
| Editor HUD data | `main.gd` read numerous controller fields and mirrored two of them | `get_state_snapshot()` provides one read-only presentation interface; mirrored state was removed |
| Brush preview | `main.gd` calculated preview through the controller and manually refreshed it from multiple call sites | Calculation still belongs to the controller; one state notification coordinates cursor redraw |
| UI capture | `_mouse_over_ui()` embedded the screen-point test | `main.gd` retains cross-system ownership, with a testable `_screen_position_over_ui()` helper |
| Paint permission | Boolean assembled inline in `_process()` | Small central `_can_editor_paint()` gate explicitly applies UI, resource and camera priority |
| Resource interaction | `ResourceInteractionController` | Unchanged; already correctly separated |
| Camera interaction | `CameraController` from R1 | Unchanged |
| HUD construction and system coordination | `main.gd` | Unchanged; still appropriate for the current composition root |

### Correctly separated systems retained

- `WorldEditorController` already owned brush geometry, line rasterization, material/elevation edit requests, alternate right-button operations, transaction coalescing, restore behavior, undo/redo, and bounded history.
- `ResourceInteractionController` already owned transient resource selection and action requests without owning inventory or resource authority.
- `CameraController` already owned camera navigation and visible-world calculation after R1.
- `CursorOverlay` remained visual-only.
- `TerrainWorld` remained authoritative, while `TerrainRenderer` retained the existing mutation/query facade and render refresh behavior.

No replacement controller or event bus was introduced.

There are no separate editor UI scripts in the current project; the editor panel is constructed dynamically in `main.gd`. R2 keeps that presentation ownership in place rather than introducing a new UI framework.

### Coupling removed

- Duplicate `selected_id` and `height_edit_mode` fields in `main.gd`.
- `_stroke_button` in `main.gd`.
- Unused `_last_height_paint_cell`, `_paint_height_cell_once()` and `_screen_to_world_cell()` remnants. The unused height helper bypassed editor transactions and was an inappropriate alternative authoritative mutation path.
- Repeated shortcut branches that knew how to mutate editor internals.
- Repeated UI callback sequences that mutated a field, refreshed preview, refreshed labels and synchronized controls separately.
- HUD summary code querying history/tool fields through several calls instead of one presentation snapshot.

## 2. Input routing and priority

`main.gd` remains the small central router because priority depends on several sibling systems. Routing is explicit and direct:

1. Godot `Control` nodes receive UI events before `_unhandled_input()`; `_screen_position_over_ui()` also prevents polled editor strokes from starting or continuing over the HUD, editor panel or reset dialog.
2. An active editor pointer operation is updated by `WorldEditorController`, but only when `_can_editor_paint()` confirms the pointer is not owned by UI, resource mode or camera middle-drag.
3. Resource-mode left clicks are routed to `ResourceInteractionController` before camera pointer handling.
4. Remaining middle-button and wheel input is routed to `CameraController`.
5. Key routing preserves existing ordering: save/load commands, editor shortcuts, camera reset, resource commands and remaining global/presentation toggles.

This keeps policy in the coordinator while moving editor mechanics to the editor owner.

## 3. Functions moved or simplified

### Added to `WorldEditorController`

- `get_state_snapshot()` — compact read-only state for HUD/control synchronization.
- Tool setters for selected material, edit mode, brush shape/size, restore mode, elevation tool and target elevation.
- `handle_shortcut()` — handles Ctrl+Z, Ctrl+Shift+Z, Ctrl+Y, brackets, material number keys and H mode toggle.
- `update_pointer_stroke()` — owns left/right button selection, stroke start, drag continuation, pauses while another system owns the pointer, and release/commit.
- `is_pointer_stroke_active()` — focused diagnostic interface.
- `state_changed` — presentation notification after meaningful editor state/history transitions.

Existing authoritative edit functions remain in place and use the same `TerrainRenderer.apply_world_edit_states()` path.

### Simplified in `main.gd`

- `_process()` now calculates cross-system paint permission and forwards pointer state to the editor.
- `_unhandled_key_input()` delegates editor shortcuts instead of applying editor operations.
- Editor panel callbacks call controller setters.
- `_on_editor_state_changed()` is the single preview/HUD synchronization point.
- `_update_editor_summary()` consumes one state snapshot.
- `_update_selected_label()`, `_update_mode_label()` and compact HUD no longer depend on mirrored editor state.
- `_mouse_over_ui()` delegates its point test to `_screen_position_over_ui()`.

`main.gd` is approximately 1,106 lines after R2, down from 1,152 after R1, despite adding explicit routing helpers and comments. `WorldEditorController` grows from approximately 253 to 388 lines because it now owns the editor behavior previously split across the coordinator.

## 4. Files changed

- `scripts/main.gd` — removed mirrored editor state and delegated editor behavior.
- `scripts/world_editor_controller.gd` — added editor state interface, signals, shortcuts and pointer-stroke ownership.
- `tests/phase_r2_world_editor_refactor_validation.gd` — focused R2 ownership and routing validation.
- `tests/phase_r2_world_editor_refactor_validation.gd.uid` — Godot-generated script identity.
- `PHASE_R2_WORLD_EDITOR_REFACTOR_REPORT.md` — this report.

R1 camera files remain unchanged by R2.

## 5. Behaviour preservation evidence

The same authoritative flow remains in use:

1. `main.gd` determines whether an editor request may proceed.
2. `WorldEditorController` converts the request into material/elevation state transitions.
3. `TerrainRenderer.apply_world_edit_states()` validates/applies changes through the existing authoritative world.
4. Renderer signals and dirty-cell queues refresh presentation.
5. Editor history stores before/after authoritative states for undo/redo.

Focused R2 coverage verifies:

- controller setters and state notifications;
- HUD and brush-preview synchronization;
- number, bracket and H shortcuts;
- material drag interpolation;
- right-drag generated-material restore;
- elevation raise and alternate right-button lower;
- undo/redo through shortcuts;
- UI mouse capture;
- resource mode blocking terrain edits;
- resource left-click priority over camera;
- camera middle-drag priority over editor painting.

The comprehensive existing Phase 7A editor validation also passes all brush sizes and shapes, material painting, elevation raise/lower/set/flatten/restore, mixed histories, drag rasterization, undo/redo, reset, chunk-boundary edits and staged renderer refresh.

## 6. Validation results

Validation used Godot `4.7.2.stable.mono.official.ed1daf0bf`.

| Check | Result |
|---|---|
| Project import and script parsing | Pass |
| Bounded main-scene startup | Pass |
| Focused R2 editor/input validation | Pass (`PHASE_R2_WORLD_EDITOR_REFACTOR_VALIDATION: PASS`) |
| Existing Phase 7A editor validation | Pass (`PHASE7A_VALIDATION: PASS`) |
| Existing R1 camera validation | Pass (`PHASE_R1_CAMERA_VALIDATION: PASS`) |
| Existing save/schema validation | Pass (`PHASE7B1_VALIDATION: PASS`) |
| Fresh-process save | Pass (`PHASE7B1_FRESH_SAVE: PASS`) |
| Renderer configuration and world replacement | Pass (`PHASE_C4A_RENDERER_CONFIGURATION: PASS`) |
| Protected C4E.1 cliff continuity | Pass (`PHASE_C4E1_CLIFF_CONTINUITY_VALIDATION: PASS`) |
| Protected C4F grid cliff validation | Pass (`PHASE_C4F_GRID_CLIFF_VALIDATION: PASS`) |
| Chunk streaming | Pass through focused R1 and Phase 7A integration coverage |
| `git diff --check` | Pass; existing line-ending warnings only |

### Existing fresh-load fixture caveat

`phase7b1_fresh_load.gd` completed its load, world replacement, inventory, resource rebuild, unload/reload and regrowth assertions, but reported one pre-load setup failure: `pre-load world has editor history`.

A bounded diagnostic confirmed this is not an R2 regression. The protected current `main.tscn` setup starts its hard-coded cell `(5,5)` with material override `3`, while the fixture paints the already-selected material `3`. The editor correctly omits the resulting no-op transaction, so no undo entry is created. The diagnostic file was removed after confirmation. Updating that pre-existing test fixture was left out of R2 to preserve unrelated work.

As with R1, a short in-window smoke test remains advisable for subjective pointer feel and physical UI capture behavior.

## 7. Remaining responsibilities in `main.gd`

`main.gd` still appropriately owns:

- construction and wiring of runtime systems;
- cross-system input priority policy;
- renderer pre-ready configuration;
- camera/terrain/cursor coordination;
- runtime HUD and editor-panel construction;
- global visual/debug toggles;
- save/load requests and world replacement coordination;
- dirty/save status and high-level diagnostics.

It no longer owns editor tool truth or pointer-stroke mechanics.

## 8. Recommendations for R3

R3 should address rendering configuration only, as planned after R1:

1. Inventory `main.gd` exports by owner: generation, streaming budgets, terrain material presentation, water, cliffs, decorations and environment objects.
2. Preserve the existing requirement that complete renderer configuration is applied before `TerrainRenderer._ready()`.
3. Consider small typed Resource configuration groups only with architect approval because changing exported scene fields can affect `main.tscn` compatibility.
4. Retain explicit runtime renderer setters for toggles that trigger rebuild/invalidation behavior.
5. Do not combine R3 with C4G, world-session extraction or a broad `TerrainRenderer` split.
6. Add a configuration parity test that compares startup and replacement configuration, extending the existing C4A test rather than duplicating it.

Primary R3 risks are omitted configuration fields, changed pre-ready timing, scene-export compatibility, and accidental renderer rebuilds. `TerrainWorld`, `WorldEditorController`, `CameraController`, `ResourceInteractionController`, save format, chunk build jobs and presentation leaf classes should remain unchanged.
