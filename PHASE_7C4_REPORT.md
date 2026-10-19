# Phase 7C.4 — Cliff Geometry and Organic Silhouette Refinement

## Task Classification

Existing System Extension / Rendering Architecture Investigation / Visual Correction

## Root cause analysis

Raised terrain is authoritative in `TerrainWorld`; rendering derives a 32×32 surface tile and, for every exposed elevation step, a 32×16 southern wall tile. Elevated surfaces are projected upward by 16 pixels per level. The previous cliff atlas selected one of four wall styles independently for every stacked level. Each style drew a rectangular wall, a strong top seam, and a separate organic-looking shadow row. Consequently:

- adjacent wall steps could change profile within one logical face;
- every stacked step looked like a separate slab instead of one continuous cliff;
- the rectangular face, surface edge, lower contact, and shadow did not describe one silhouette;
- the dark shadow dominated one-level same-material rises;
- the surface shader's organic edge and the cliff atlas had no shared face-profile contract.

The authoritative elevation, liquid, and material data were correct. The defect was in atlas variant selection and cliff artwork generation, not procedural height generation or terrain state.

## Geometry architecture

### Before

- Four wall variants were selected from world position and elevation level.
- A new style could be selected for each 16-pixel step of a multi-level face.
- All steps contained a prominent top seam.
- Wall sides were rectangular.
- The lower shadow used a separate shape and was dark enough to read as wall mass.
- North/east/west readability came from the existing restrained ledge overlay.
- Draw order was shadow at `elevation * 8 - 3`, wall at `-2`, four surface composition layers at `+0..+3`, ledge at `+4`, and decorations at `+5`.

### After

- The existing batched TileMap architecture is retained; there are no per-cell nodes or custom wall meshes.
- Each southern face now selects one deterministic world-space style that remains stable through every exposed elevation step.
- The atlas contains 32 combinations: four styles, a top-step bit, and four terminal-cap masks.
- A shared pixel-quantised boundary profile controls the upper wall cut, top lip, terminal side silhouette, lower contact, and attached shadow.
- Profile endpoints are fixed so adjacent wall segments join without gaps, including across signed chunk boundaries.
- Only the highest exposed step receives the irregular top lip. Lower stacked steps remain connected, producing a continuous face with the correct authoritative step count.
- Terminal caps use small deterministic side insets for coherent isolated, convex, and concave silhouettes without exposing background pixels between neighbours.
- Wall shading is lighter and more gradual, strata are restrained, and the contact shadow is thinner and less opaque.
- The existing 32×32 logical cells, 16-pixel projection step, orthographic camera, ledge cues, liquid renderer, surface artwork, and elevation values are unchanged.

The surface composition shader and CPU-generated cliff atlas do not execute the same deformation function. Instead, the cliff's upper treatment overlaps the projected surface at the authoritative southern boundary while all cliff components share one atlas profile. Replacing the batched atlas with per-cell custom geometry would increase preparation complexity and draw overhead without being necessary for this correction.

## Authoritative ownership and mine readiness

`TerrainWorld` remains the sole owner of material, elevation, liquid, edit, undo/redo, and persistence state. `TerrainChunkBuildJob` reads immutable snapshots and classifies southern exposure and exact exposed step count. `TerrainChunkRenderer` applies those prepared variants, and `TerrainRenderer` owns presentation assets and picking.

The organic profile is cosmetic and never changes logical face coordinates. A future mine entrance can still derive a stable southern face from the cell coordinate, the neighbour elevation, and the exposed level range.

## Controlled visual evidence

The diagnostic overlay is read-only: green is the projected upper surface, brown is exposed wall, yellow is the upper lip, white is lower contact, grey is shadow, and black shows authoritative cell boundaries. Each scenario was captured at 1× and 3× before and after the change.

| Scenario | Before | After |
| --- | --- | --- |
| Isolated elevation 1 | [rendered 3×](screenshots/phase7c4_before_isolated_height_1_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_isolated_height_1_rendered_3_0x.png) |
| Isolated elevation 2 | [rendered 3×](screenshots/phase7c4_before_isolated_height_2_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_isolated_height_2_rendered_3_0x.png) |
| Isolated elevation 3 | [rendered 3×](screenshots/phase7c4_before_isolated_height_3_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_isolated_height_3_rendered_3_0x.png) |
| 3×3 plateau, elevation 1 | [rendered 3×](screenshots/phase7c4_before_plateau_3x3_height_1_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_plateau_3x3_height_1_rendered_3_0x.png) |
| 3×3 plateau, elevation 2 | [diagnostic 3×](screenshots/phase7c4_before_plateau_3x3_height_2_diagnostic_3_0x.png) | [diagnostic 3×](screenshots/phase7c4_after_plateau_3x3_height_2_diagnostic_3_0x.png) |
| Elevation 3 to 1 drop | [rendered 3×](screenshots/phase7c4_before_drop_height_3_to_1_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_drop_height_3_to_1_rendered_3_0x.png) |
| Irregular plateau | [rendered 3×](screenshots/phase7c4_before_irregular_plateau_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_irregular_plateau_rendered_3_0x.png) |
| Raised 1×1 island | [rendered 3×](screenshots/phase7c4_before_water_island_1x1_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_water_island_1x1_rendered_3_0x.png) |
| Raised 3×3 island | [rendered 3×](screenshots/phase7c4_before_water_island_3x3_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_water_island_3x3_rendered_3_0x.png) |
| Two-level island | [diagnostic 3×](screenshots/phase7c4_before_water_island_two_level_diagnostic_3_0x.png) | [diagnostic 3×](screenshots/phase7c4_after_water_island_two_level_diagnostic_3_0x.png) |
| Raised peninsula | [rendered 3×](screenshots/phase7c4_before_raised_peninsula_rendered_3_0x.png) | [rendered 3×](screenshots/phase7c4_after_raised_peninsula_rendered_3_0x.png) |
| Cliff meeting water | [diagnostic 3×](screenshots/phase7c4_before_cliff_meets_water_diagnostic_3_0x.png) | [diagnostic 3×](screenshots/phase7c4_after_cliff_meets_water_diagnostic_3_0x.png) |
| Shoreline chunk boundary | [diagnostic 3×](screenshots/phase7c4_before_shoreline_chunk_boundary_diagnostic_3_0x.png) | [diagnostic 3×](screenshots/phase7c4_after_shoreline_chunk_boundary_diagnostic_3_0x.png) |

The capture set contains 112 PNG files: 14 scenarios × two zoom levels × rendered/diagnostic × before/after.

## Performance measurements

Godot 4.7.2 Compatibility renderer, NVIDIA GeForce RTX 3080:

| Mode | Average | P95 | P99 | Worst | Scheduler overruns |
| --- | ---: | ---: | ---: | ---: | ---: |
| Static terrain | 0.605 ms | 0.687 ms | 0.902 ms | 0.902 ms | 0 |
| Camera streaming | 3.020 ms | 6.146 ms | 8.239 ms | 8.239 ms | 26 |
| Dense cliffs | 0.827 ms | 0.996 ms | 1.160 ms | 1.160 ms | 0 |
| Isolated raised cells | 0.784 ms | 0.977 ms | 1.239 ms | 1.239 ms | 0 |
| Large plateau | 0.800 ms | 0.995 ms | 1.295 ms | 1.295 ms | 0 |
| Large elevation brush | 2.645 ms | 5.768 ms | 7.472 ms | 7.472 ms | 0 |
| Undo/redo | 6.400 ms | 8.891 ms | 24.126 ms | 24.126 ms | 0 |
| Save/load regeneration | 6.847 ms | 3.890 ms | 198.794 ms | 198.794 ms | 30 |

Chunk preparation across 92 chunks averaged 14.260 ms, with a 22.291 ms worst case. Cliff preparation averaged 1.2492 ms per sampled chunk, edge preparation averaged 0.6662 ms, and observed memory was 97.50 MiB. The benchmark passed. The save/load P99 is a one-time regeneration spike rather than steady-state rendering cost.

## Validation

- Godot 4.7.2 project parse: PASS.
- Phase 7C.4 profile seam, quantisation, stacked-height, signed chunk-boundary, and atlas-contact validation: PASS.
- Phase 7C.4 performance benchmark: PASS.
- Phase 5D cliffs and shorelines: PASS.
- Phase 6A decorations: PASS.
- Phase 6B environmental objects: PASS.
- Phase 7A editing: PASS.
- Phase 7B.1 save/load validation: PASS.
- Phase 7B.1 fresh-process save and load round trip: PASS.
- Phase 7C liquid rendering: PASS.
- Phase 7C.2 edge classification: PASS.
- Phase 7C.3 island creation: PASS.
- Phase 8A procedural Isolony assets: PASS.
- Phase 8B harvesting and regrowth: PASS.
- Trailing-whitespace scan of modified scripts: PASS.
- `git diff --check` could not run because the supplied project directory is not a Git repository.

## Remaining limitations

- In the established orthographic view, southern faces carry most height information. North/east/west differences remain intentionally restrained ledge cues rather than fabricated isometric faces.
- A same-material raised top retains its original material artwork. Readability comes from projection, the connected top lip, the exposed wall, and the restrained contact shadow rather than recolouring the surface.
- The atlas profile is pixel-quantised and deliberately subtle. It cannot produce arbitrary vector curvature, but preserves the current pixel-art style and batching model.
- Camera streaming and save/load still produce scheduler overruns during burst preparation; this phase did not alter the scheduler or persistence architecture.

Phase 7C.4 stops here. No ramps, mines, new liquids, underground instances, colonists, pathfinding, or world-management systems were added.
