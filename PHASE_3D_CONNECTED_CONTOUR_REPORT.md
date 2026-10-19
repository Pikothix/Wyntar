# Wyntar — Phase 3D Connected Organic Cliff Contours

Date: 2026-10-20

Task classification: Existing System Extension — procedural cliff geometry.

Implementation scope: bounded southern-contour prototype. This phase does not add full level-contour extraction, redesign side returns, or add geometry LOD.

## 1. Files changed

Production:

- `scripts/organic_cliff_mesh_builder.gd`
- `scripts/terrain_chunk_build_job.gd`
- `scripts/terrain_chunk_renderer.gd`
- `scripts/terrain_renderer.gd`
- `scripts/main.gd`
- `main.tscn`

Validation and evidence:

- `tests/phase3d_validation.gd`
- `tests/phase3d_capture.gd`
- `tests/phase3d_benchmark.gd`
- `screenshots/phase3d_baseline_capture_manifest.json`
- `screenshots/phase3d_prototype_capture_manifest.json`
- `screenshots/phase3d_benchmark_graphical.json`
- 36 matched Phase 3D PNG captures under `screenshots/phase3d_*`

No terrain-authority, save-format, projection, shader, collision, or node-per-feature code changed.

## 2. Geometry approach

The prototype keeps the existing per-chunk mesh batches and identifies compatible southern runs locally. A face joins its west or east neighbour only when both faces cover the same complete owner-to-south elevation interval. That test is symmetric, uses the immutable 34×34 halo, and works identically across chunk boundaries.

Compatible multi-cell runs use four 8-pixel columns per terrain cell instead of two 16-pixel columns. Their horizontal level boundaries use two absolute-world-coordinate fields:

- a 96-pixel broad formation field;
- a 24-pixel fine rock-edge field.

Both fields use bounded linear interpolation between deterministic hash anchors and round to integer pixels. The combined run displacement is clamped to `[-7, 0]`, so it cannot overshoot. Short runs, isolated faces, mixed-height transitions, and complex endpoints retain the original 16-pixel topology and use a reduced `[-3, 0]` envelope from the same coherent fields.

The connected profile is an explicit presentation toggle, enabled by default in `main.tscn`. Toggling it schedules the same atomic, incremental replacement jobs used by earlier cliff modes. It does not alter authoritative cells.

## 3. Phase 3C continuity preservation

Phase 3C's per-elevation boundary ownership remains intact. Every boundary coordinate is still derived from absolute world X, contour world Y, elevation level, and world seed. Total face drop and chunk traversal order are not inputs.

At a connected-run endpoint, the sample falls back to the conservative shared profile unless the adjacent face independently proves the same run connection. This prevents a dense run from disagreeing with a mixed-height or isolated neighbour.

Contact shadows use the same foot boundary samples as their owning faces. Refined side returns receive the Phase 3D mode and terminate on the same conservative corrected crest sample. Existing per-band cap suppression remains unchanged, so unequal drops still connect only where their elevation bands overlap.

The one-cell halo was not expanded. No world-scale contour state or traversal-dependent run identity was introduced.

## 4. Before-and-after screenshots

All captures use the accepted Phase 3B fixture code and camera path at 0.5×, 1×, and 3×. Previous screenshots were preserved.

| Fixture | Baseline | Prototype |
| --- | --- | --- |
| Broad dirt/stone three-level faces, 3× | `screenshots/phase3d_baseline_materials_three_level_shoreline_3_0x.png` | `screenshots/phase3d_prototype_materials_three_level_shoreline_3_0x.png` |
| Winding convex/concave boundary, 1× | `screenshots/phase3d_baseline_winding_convex_concave_1_0x.png` | `screenshots/phase3d_prototype_winding_convex_concave_1_0x.png` |
| Isolated raised formations, 3× | `screenshots/phase3d_baseline_isolated_raised_formation_3_0x.png` | `screenshots/phase3d_prototype_isolated_raised_formation_3_0x.png` |
| Positive seam diagonal, 0.5× | `screenshots/phase3d_baseline_positive_seam_diagonal_0_5x.png` | `screenshots/phase3d_prototype_positive_seam_diagonal_0_5x.png` |
| Negative seam diagonal, 0.5× | `screenshots/phase3d_baseline_negative_seam_diagonal_0_5x.png` | `screenshots/phase3d_prototype_negative_seam_diagonal_0_5x.png` |
| Natural generated terrain, 1× | `screenshots/phase3d_baseline_natural_gameplay_1_0x.png` | `screenshots/phase3d_prototype_natural_gameplay_1_0x.png` |

Visual observation: the long horizontal dirt and stone walls no longer repeat one 32-pixel scallop. Their crest/foot silhouettes and face subdivision vary across several cells while remaining pixel-quantised. Isolated formations retain conservative widths and cap treatment.

Visual limitation: steep diagonal and predominantly north/east/west winding sections remain governed mainly by the existing foreshortened side returns. Their 1×/3× captures can therefore be unchanged or only subtly changed. Extending the same contour language around turns requires a later, explicitly authorised contour-extraction/return phase.

## 5. Validation results

Validation used Godot 4.7 stable for the available non-Mono graphical runner. The project and accepted Phase 3C report target Godot 4.7.2; the available 4.7.2 Mono console did not complete startup in this environment, so exact 4.7.2 graphical reruns remain a follow-up.

| Validation | Result |
| --- | --- |
| Production-script parse checks | Pass |
| Phase 1B | Pass |
| Phase 1D | Pass |
| Phase 1E | Pass |
| Phase 1F | Pass |
| Phase 1G | Pass |
| Phase 3C | Pass |
| Phase 3D connected/mixed/deterministic/seam suite | Pass |
| Phase 7A editing and undo/redo | Pass |
| Phase 7C | Pass |
| Phase 7C.2 | Pass |
| Phase 7C.3 | Pass |
| Phase 7C.4 | Pass |
| Phase 7C.5 | Pass |
| Matched graphical captures | Pass, 18 baseline + 18 prototype |
| Paired graphical benchmark | Pass |
| `git diff --check` | Pass |

The Phase 3D suite verifies denser connected-run topology, conservative mixed-height topology, exact shared vertices across unequal drops, deterministic synchronous/incremental buffers, and positive/negative chunk seams.

## 6. Performance and geometry counts

The paired benchmark used the exact Phase 1G dense fixture at `(10200, 5100)`, a 1280×720 viewport, Compatibility renderer, NVIDIA GeForce RTX 3080, three streaming runs per mode, and 720 steady frames per mode.

| Metric | Phase 3C baseline | Phase 3D prototype | Change |
| --- | ---: | ---: | ---: |
| Faces | 734 | 734 | 0 |
| Vertices | 28,724 | 33,116 | +4,392 / +15.29% |
| Triangles | 16,080 | 18,276 | +2,196 / +13.66% |
| Mesh nodes | 108 | 108 | 0 |
| Steady mean frame | 5.589 ms | 6.068 ms | +8.56% |
| Steady P95 | 7.244 ms | 7.700 ms | +6.29% |
| Mean streaming frame | 8.117 ms | 8.061 ms | -0.70% |
| Mean total streaming CPU | 424.026 ms | 442.254 ms | +4.30% |
| Worst geometry work frame | 2.976 ms | 3.246 ms | +9.07% |

The vertex/triangle increase is limited to compatible connected runs and their matching contact shadows. Face count, batch count, and node count do not grow. Work remains incremental under the existing scheduler and uses its existing cell quantum; no unbounded contour pass was added. The prototype's worst measured geometry quantum is 0.270 ms above the Phase 3C run, while overall streaming frame mean was unchanged within run variance.

## 7. Remaining limitations

- This is not a traced level contour. It connects compatible horizontal southern runs only.
- Steep diagonals are still visually dominated by short southern steps and legacy side returns, so their high-zoom silhouette improvement is limited.
- Mixed-height junctions keep 16-pixel topology by design; only their bounded coordinate field changes.
- The broad profile is clamped inward to preserve surface coverage. It cannot create true bays, overhangs, or erosion notches outside the authoritative cell footprint.
- Exact graphical validation should be repeated with Godot 4.7.2 when a working non-hanging runner is available.
- The one Phase 3D steady benchmark contained a 43.756 ms external/engine outlier; P95 remained 7.700 ms.

## 8. Recommended next milestone

Review and accept or reject this southern-run prototype on the saved 0.5×/1×/3× captures. If accepted, the next bounded milestone should trace local level-contour turns and make side-return sampling share those turn keys. It should keep the same one-cell halo and absolute edge identities, and should not yet add geometry LOD or redesign the complete return system.
