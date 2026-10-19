# Phase 7C.2 — Cliff Edge Simplification and Shape-Aware Rendering

## Classification

Existing System Extension / Visual Rendering Correction

## Root cause and architecture audit

The authoritative height data was correct. The detached pieces came from the presentation-only cliff-edge TileMap layers. Every exposed north, west, or east edge selected a full-cell overlay from the shared edge atlas, independently of the southern wall layer. On small islands and narrow landforms, several overlays accumulated into dark rectangular outlines and full-height grey side strips.

- Southern walls are prepared per elevation level in `TerrainChunkBuildJob._prepare_cliff`, rendered in `CliffsHeight_*`, and use the dirt/stone/shoreline variants from `_generate_cliff_atlas`.
- The lower five rows of the same cliff atlas supply the separate `CliffShadowsHeight_*` layer. Liquid-contact walls use a restrained wet base instead of adding another shoreline shadow.
- North lips and west/east returns are prepared by `_prepare_cliff_edges` and rendered in `CliffEdgesHeight_*`, above the elevated surface layers.
- Liquid surface height and shoreline colour remain material-metadata driven. No water resource ID was added to the cliff rules.
- The observed grey geometry was therefore overlapping edge-atlas presentation, not bad elevation generation, draw clipping, or authoritative terrain corruption.

## Shape-aware treatment

Each eligible boundary cell is classified from its fixed 3×3 neighbourhood. The classifier uses cardinal exposure, diagonal support, exposed/support counts, narrow-axis detection, maximum drop, south-wall connectivity, and liquid metadata. It produces a compact mask/style/flags/drop result and never performs region or whole-world analysis.

Three atlas rows preserve the existing batched TileMap architecture:

1. **Standard** — subtle three-pixel north lip and short contextual returns for broad landforms.
2. **Wall-connected** — thin returns restricted to the corners of an exposed southern wall.
3. **Simplified** — reduced north lip and only the final five pixels of a side return where it joins a southern wall. A cell exposed on both side faces omits its north cap entirely.

Water-adjacent side-only boundaries select the simplified row, removing detached grey strips while leaving true elevation, southern walls, liquid height, surface ownership, and occlusion unchanged. Multi-level southern walls still stack one wall tile per authoritative level.

The hot path returns a `Vector4i` instead of allocating per-cell arrays and dictionaries, and skips the richer classifier for interior or south-wall-only cells. The public diagnostic wrapper remains read-only and returns labels such as `southern_wall`, `northern_lip`, `side_return`, `connected_corner`, `suppressed_secondary_cue`, `water_contact_edge`, `multi_level_drop`, and `small_shape`.

## Matched visual evidence

All ten scenarios were captured at identical positions, seed, viewport, and 0.5×, 1×, and 3× zooms. There are 31 before and 31 after PNGs in `screenshots/` (the extra pair is annotated).

| Scenario | Before | After |
| --- | --- | --- |
| Annotated small sand island | [before](screenshots/phase7c2_before_annotated_small_island_3_0x.png) | [after](screenshots/phase7c2_after_annotated_small_island_3_0x.png) |
| Single-cell island | [before](screenshots/phase7c2_before_single_cell_island_3_0x.png) | [after](screenshots/phase7c2_after_single_cell_island_3_0x.png) |
| Two-cell island | [before](screenshots/phase7c2_before_two_cell_island_3_0x.png) | [after](screenshots/phase7c2_after_two_cell_island_3_0x.png) |
| Narrow peninsula | [before](screenshots/phase7c2_before_narrow_peninsula_3_0x.png) | [after](screenshots/phase7c2_after_narrow_peninsula_3_0x.png) |
| Irregular coastal inlet | [before](screenshots/phase7c2_before_irregular_coastal_inlet_1_0x.png) | [after](screenshots/phase7c2_after_irregular_coastal_inlet_1_0x.png) |
| Broad southern wall | [before](screenshots/phase7c2_before_broad_southern_wall_1_0x.png) | [after](screenshots/phase7c2_after_broad_southern_wall_1_0x.png) |
| North and side boundaries | [before](screenshots/phase7c2_before_north_and_side_boundaries_3_0x.png) | [after](screenshots/phase7c2_after_north_and_side_boundaries_3_0x.png) |
| Multi-level water cliff | [before](screenshots/phase7c2_before_multi_level_water_cliff_3_0x.png) | [after](screenshots/phase7c2_after_multi_level_water_cliff_3_0x.png) |
| Chunk-boundary corner | [before](screenshots/phase7c2_before_chunk_boundary_corner_3_0x.png) | [after](screenshots/phase7c2_after_chunk_boundary_corner_3_0x.png) |
| Mixed materials | [before](screenshots/phase7c2_before_mixed_material_cliffs_3_0x.png) | [after](screenshots/phase7c2_after_mixed_material_cliffs_3_0x.png) |

Visual inspection confirmed that the full-height side overlays disappear from islands and peninsulas; single-cell surfaces keep their full southern wall without a detached cap; broad and multi-level southern walls retain their former height, texture, and continuity; and the x=1792 chunk-boundary corner has no seam.

## Performance comparison

The preserved pre-7C.2 project and the final project ran the same 48-frame graphical benchmark on the same machine and fixture.

| Mode | Before avg / P95 / P99 / worst (ms) | After avg / P95 / P99 / worst (ms) |
| --- | --- | --- |
| Static view | 0.950 / 0.989 / 0.997 / 0.997 | 0.949 / 0.966 / 1.009 / 1.009 |
| Camera streaming | 3.278 / 5.523 / 6.827 / 6.827 | 3.313 / 5.586 / 6.418 / 6.418 |
| Dense cliffs | 0.765 / 0.782 / 0.797 / 0.797 | 0.896 / 0.909 / 0.947 / 0.947 |
| Shoreline-heavy | 0.620 / 0.636 / 0.673 / 0.673 | 0.616 / 0.628 / 0.641 / 0.641 |
| Small-island stress | 1.276 / 1.290 / 1.317 / 1.317 | 1.293 / 1.412 / 1.523 / 1.523 |
| Large elevation brush | 1.954 / 3.945 / 4.633 / 4.633 | 2.402 / 5.073 / 5.717 / 5.717 |
| Undo/redo cliff edits | 2.631 / 4.150 / 4.240 / 4.240 | 3.310 / 5.324 / 5.978 / 5.978 |
| Save/load regeneration | 4.422 / 3.523 / 93.342 / 93.342 | 4.408 / 3.527 / 94.657 / 94.657 |

Final preparation results: 12.285 ms average and 13.946 ms worst per chunk, compared with 12.008 ms and 13.910 ms before. Edge preparation increased from 0.509 ms to 0.683 ms per chunk; total cliff preparation increased from 1.053 ms to 1.252 ms. Static memory moved from 80.64 MiB to 80.97 MiB. Scheduler overruns were 393 versus 382 overall; camera streaming was unchanged at 27, and all editing modes recorded zero overruns. The one-time save/load P99 spike remains isolated to regeneration.

## Validation

Passed on Godot 4.7.2:

- Phase 5D cliffs/shorelines (including its 25-chunk benchmark)
- Phase 6A ground decorations
- Phase 6B environmental objects
- Phase 7A editing and undo/redo
- Phase 7B.1 persistence validation plus fresh-process save/load
- Phase 8A procedural assets
- Phase 8B harvesting/resource state
- Phase 7C liquid and height-aware rendering
- Phase 7C.2 classification, water metadata, positive/negative coordinates, stored job styles, diagnostics, and the x=-1/0 chunk boundary
- Phase 7C.2 31-image before and 31-image after capture matrix
- Phase 7C.2 eight-mode graphical benchmark

No save schema, authoritative terrain state, resource state, generation rule, editor command, or gameplay semantic was changed.

## Remaining perspective limitations

The renderer remains a top-down 2D projection: north, west, and east boundaries are deliberately shallow ledge cues rather than true vertical faces. Very jagged concave coasts can still reveal the cell-stepped silhouette of the universal masks at high zoom. This phase does not add ramps, pathfinding, mine entrances, underground rendering, or perspective-aware wall geometry.
