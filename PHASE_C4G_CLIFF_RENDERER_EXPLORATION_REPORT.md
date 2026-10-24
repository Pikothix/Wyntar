# Wyntar Phase C4G — Switchable Cliff Renderer Exploration

Date: 2026-10-24  
Engine used for validation: Godot 4.7.2 stable Mono  
Projection: strictly top-down

## 1. Recovery audit

The interrupted C4G work contained a partially wired four-mode selector, a first-pass full-cell elevated-surface replacement, an unvalidated stylised wall mesh, and one focused validation script. It did not contain a report, comparison captures, performance measurements, successful recorded validation, or proof that the grid wall faced outward.

The first graphical matrix exposed a real C4F/C4G defect: grid boundary segments were oriented with occupied terrain on their left, but their extrusion used the left-hand normal. Faces therefore projected back into the plateau. The previous dual-grid surface obscured much of this; the shared surface made the error visible. C4G corrects the normal only in the experimental grid branch. Further visual iteration removed full-height east/west slivers and made broad wall ownership strictly south-facing, while retaining a continuous lip on every exposed cardinal edge.

No pre-existing C4E, C4E.1, C4F, R1–R3, G7, scene, save, or unrelated working-tree change was discarded. No commit or push was performed.

## 2. Implemented rendering modes

The selector is `cliff_rendering_mode`:

| Mode | Status | Behaviour |
|---|---|---|
| `LEGACY` | Working; default | Delegates to the existing Boolean switches without changing them. With the checked-in scene overrides this is the C4E.1 organic/unified-contour appearance. |
| `GRID` | Working experimental comparison | Uses the C4F cardinal boundary and corrected outward normal while retaining the existing dual-grid elevated surface. Its boundary mismatch is intentionally still visible. |
| `UNIFIED` | Working prototype | Uses one authoritative-cell outline for the elevated surface, lip, and cliff wall. Full square surface cells replace only elevated presentation layers after the matching cliff batch commits. |
| `STYLISED` | Working visual experiment, not acceptance-ready | Uses the same canonical surface/boundary as UNIFIED and subdivides the south-facing wall into a light upper band, broad geological bands, deterministic seams, and a dark foot. |

`main.tscn` does not override the selector, so its default remains `LEGACY = 0`. Existing C4F and older Boolean switches remain available and retain their rollback behaviour. Experimental modes assume organic cliff geometry is enabled, as it is in the current Main defaults and scene.

The exported Main property can be changed in the Inspector. Its setter forwards runtime changes to `TerrainRenderer.set_cliff_rendering_mode()`. Switching revisions all loaded chunks, reuses cached 34×34 presentation halos where valid, restarts pending stream builds, and commits replacement meshes/surfaces atomically. While replacement is pending, the accepted elevated surface and legacy batched cliff art remain visible. Returning to LEGACY hides and clears the experimental surface path after rebuilding.

## 3. Ownership and data flow

The change is presentation-only:

1. `Main` and `CliffRenderingSettings` capture the selected mode.
2. `TerrainRenderer` owns the active renderer mode and schedules revision-gated chunk rebuilds.
3. `TerrainChunkBuildJob` carries the mode into its immutable material/elevation halo snapshot.
4. `OrganicCliffMeshBuilder` derives cardinal exposed edges and, for UNIFIED/STYLISED, emits one source ID and elevation for each raised non-liquid authoritative cell.
5. `TerrainChunkRenderer` owns the replacement TileMap layers, populated with the existing surface TileSet's full-mask tile. It swaps visibility only when the corresponding organic mesh batch is ready.

`TerrainWorld` remains the owner of material/elevation authority. C4G does not write terrain data, collision, picking, resource state, save data, or gameplay elevation.

## 4. Canonical boundary result

The UNIFIED prototype establishes these invariants:

- A raised authoritative cell produces one 32×32 elevated surface cell at the same pixel origin used by its cardinal outline.
- Adjacent equal-height cells omit their shared cliff edge.
- Square corners are used for UNIFIED/STYLISED; C4F's bevel-only segments are not emitted because a full square surface cannot share a bevelled outline.
- Every exposed north/east/south/west edge receives a continuous three-pixel lip.
- Only the screen-facing south edge owns the broad height-step wall. This avoids long pointed east/west strips under strict top-down projection.
- Each wall projects exactly one configured presentation height step, so multi-level faces stack without gaps.
- Raised liquid cells are excluded. Land cells bordering liquid retain the existing shoreline cliff source selection.
- Chunk ownership is deterministic. A controlled 2×2 plateau produced identical combined face and triangle counts when moved from one chunk into a two-chunk crossing.

This fixes the surface/rim boundary disagreement for the experimental path and produces square-like isolated plateaus. It does not attempt smooth or rounded cell silhouettes. Controlled curvature remains future work and requires a canonical surface representation capable of expressing the same curve; adding curved cliff geometry alone would recreate the C4F mismatch.

## 5. Visual comparison

The graphical matrix contains 160 captures: four modes × ten identical scenarios × four zooms (100%, 175%, 250%, 350%). The manifest is `.artifacts/c4g_capture_manifest.json`.

Scenarios:

1. Single raised cell.
2. 2×2 plateau.
3. Long straight wall.
4. Curved/stepped wall.
5. L-shaped plateau.
6. Multi-level elevation.
7. Grass/stone transition.
8. Sand/water contact.
9. Chunk-boundary crossing.
10. Natural terrain seed.

Observed results:

- **LEGACY:** preserves the accepted C4E.1 look. Organic continuity is strongest, but isolated elevations remain diamond-like and surface-to-cliff mismatch remains.
- **GRID:** makes the rim cardinal and fixes outward extrusion, but still combines it with the old dual-grid/diamond surface. It remains useful only as a defect comparison.
- **UNIFIED:** is the cleanest geometric baseline. Isolated cells and small plateaus are square, long walls are continuous, multi-level walls stack, and the surface/rim crest agrees at water and material contacts. Its hard cell corners and hard per-cell material transitions are intentionally visible.
- **STYLISED:** most closely approaches the reference's light lip, layered wall, seams, and dark lower edge on long walls. On isolated and very short walls the bands and seams are too regular and visually busy. It should not supersede UNIFIED as the geometric baseline.

The capture harness disables new decoration/environment generation, but resource-aware objects already created before the fixture rebuild can remain in a few controlled screenshots. They do not affect cliff geometry measurements; future art review should use a fixture scene that starts with those systems disabled before Main enters the tree.

## 6. Geometry and performance measurements

Matched dense fixture, 1280×720, OpenGL Compatibility, NVIDIA GeForce RTX 3080, three streaming runs and 720 steady frames per mode. Raw data: `.artifacts/c4g_cliff_renderer_benchmark.json`.

| Mode | Vertices | Triangles | Boundary segments | Mesh nodes | Visible shared surface cells/layers | Avg draw calls | Steady avg / p95 | Mean streaming CPU | Mean streaming frame | Worst streaming frame |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| LEGACY | 32,200 | 16,100 | 3,461 | 36 | 0 / 0 | 605 | 3.506 / 4.921 ms | 372.476 ms | 6.325 ms | 19.476 ms |
| GRID | 36,856 | 18,428 | 4,607 | 36 | 0 / 0 | 605 | 3.311 / 4.716 ms | 306.799 ms | 6.075 ms | 20.075 ms |
| UNIFIED | 16,968 | 8,484 | 3,456 | 36 | 9,401 / 36 | 497 | 2.562 / 3.654 ms | 295.368 ms | 5.463 ms | 19.937 ms |
| STYLISED | 27,456 | 13,728 | 3,456 | 36 | 9,401 / 36 | 497 | 2.612 / 3.817 ms | 303.877 ms | 5.482 ms | 16.008 ms |

The shared surface uses one layer per active elevation rather than four dual-grid blend layers, which explains the lower draw-call count in this fixture. The numbers do not prove a production speed-up: modes ran sequentially in one process, later modes may benefit from warmed caches, and GPU frame time was unavailable (`null`). The result does show that the minimal UNIFIED prototype does not require more cliff geometry than LEGACY. STYLISED adds 5,244 triangles over UNIFIED on this fixture but remains below LEGACY's geometry count.

## 7. Known defects and limitations

### LEGACY

- Surface/cliff crest mismatch remains.
- Isolated cells remain diamond-shaped.
- Existing narrow slivers and water-contact irregularities remain where already documented by C4E.1/C4F.

### GRID

- Cardinal rim does not share the old dual-grid surface boundary.
- C4F bevels do not have matching surface corners.
- It is a comparison mode, not a candidate for acceptance unchanged.

### UNIFIED

- Canonical cells are deliberately square; smooth curvature is not implemented.
- Material boundaries on elevated surfaces are hard cell transitions rather than the four-source blended masks used by LEGACY.
- The north/east/west treatment is a lip, not a substantial wall. This is a strict top-down readability decision and should be reviewed against the art target.
- Replacement TileMap layers allocate one layer per active elevation per chunk. The measured draw-call result is favourable, but memory/lifecycle behaviour should be profiled on much larger streaming ranges before acceptance.
- Decorations keep their existing projected cell positions; controlled captures did not reveal an authority mismatch, but crowded raised decoration scenes need visual review.

### STYLISED

- Banding is too regular on small formations.
- Deterministic vertical seams can resemble masonry rather than natural geology.
- It reuses existing encoded cliff material roles; there are no dedicated style controls yet.
- Curved corners are not implemented because the shared surface is still square.

## 8. Validation performed

All listed checks passed under Godot 4.7.2:

- Main scene startup (four frames, headless).
- `phase_c4g_cliff_renderer_validation.gd`: selector switching, shared surface population/visibility, authoritative-state invariance, exact LEGACY geometry rollback, deterministic regeneration, chunk-seam equivalence.
- `phase_c4a_renderer_configuration_validation.gd` and `phase_r3_rendering_configuration_validation.gd`: startup/replacement configuration and default-off selector.
- `phase_c4e1_cliff_continuity_validation.gd` and `phase_c4f_grid_cliff_validation.gd`: existing cliff paths and Boolean compatibility.
- `phase1g_validation.gd`: streaming, cached halos, replacement and retirement.
- `phase_g1_validation.gd` through `phase_g7_validation.gd`: terrain material regressions.
- `phase7b1_validation.gd`, followed by separate-process `phase7b1_fresh_save.gd` and `phase7b1_fresh_load.gd`: save/load and rebuilt visuals.
- Graphical comparison capture: 160 PNGs at the four requested zooms.
- Matched graphical performance benchmark for all four modes.
- `git diff --check`: passed; only existing line-ending warnings were reported.

## 9. Recommendation and remaining work

Keep `LEGACY` as the default. Do not promote GRID.

Use `UNIFIED` as the next development baseline because it is the first mode in this branch where the elevated surface, lip, and broad wall share one canonical outline. Before art-direction acceptance:

1. Decide whether square cardinal cells are the intended final boundary language.
2. If curvature is required, introduce one canonical curved/rasterised surface boundary and make both surface coverage and cliff mesh consume it; do not curve only the wall.
3. Restore multi-material blending within the canonical elevated surface without changing boundary ownership.
4. Build a clean fixture scene that disables objects before startup and perform manual gameplay review at chunk seams, water, dense decorations, and negative coordinates.
5. Only then refine STYLISED band spacing, seam density, lip colour, and lower-edge darkness.
6. Profile a wide streaming range and high active-chunk count before considering production adoption.

STYLISED best matches the supplied reference's wall treatment, but UNIFIED is the safer and more coherent basis for further development. No experimental mode should be enabled by default in this phase.
