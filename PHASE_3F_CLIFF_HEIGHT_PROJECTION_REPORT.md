# Wyntar — Phase 3F Cliff Height and Projection Prototype

Date: 2026-10-20

Task classification: Existing System Extension — procedural terrain presentation, elevation projection, and cliff geometry.

Scope: bounded presentation-only prototype. Authoritative terrain data, material definitions, save formats, generator ownership, and chunk ownership are unchanged.

## 1. Architectural findings

1. The accepted renderer projected every elevated top surface upward by 16 pixels per authoritative elevation level. `TerrainChunkRenderer` positioned surface, decoration, and ledge layers with that step; `OrganicCliffMeshBuilder` shifted contour crests and extruded one 16-pixel band per threshold.
2. Phase 3E cliff extrusion matched the 16-pixel top-surface projection. Increasing only face depth would therefore detach toes from lower terrain or overlap unrelated surfaces.
3. Phase 3E extracts a contour from the same four elevation samples used by each elevated top-surface mask. The contour crossing is bounded inside that render square, so the mask covers the high side of the crest.
4. Unified face bands overlap the upper surface by two pixels and terminate one pixel beyond the projected lower level. All bands of a mixed-height square use the square's highest render layer, preventing intervening top layers from splitting a wall into parallel ribbons.
5. Height perception depends on the shared projection, face extrusion, per-elevation z ordering, Phase 3B material facets/strata, and the toe/contact strip. Shadows alone do not communicate the authoritative high side.
6. A projection-step change affects elevated surfaces, organic faces, Phase 3D fallback geometry, decorations, environmental object roots, hover/brush geometry, picking reach, cliff-face hit rectangles, streaming jobs, and runtime replacement. It does not require camera-projection or authoritative-grid changes.
7. A taller cliff is viable in the existing 2D renderer when all presentation consumers use one height step. A face-only multiplier is not viable.

The selected approach is one data-driven presentation profile threaded through the existing chunk and mesh paths. No new renderer, contour owner, node-per-feature path, or world-scale traversal was introduced.

## 2. Files changed

Production:

- `main.tscn`
- `scripts/main.gd`
- `scripts/terrain_renderer.gd`
- `scripts/terrain_chunk_renderer.gd`
- `scripts/terrain_chunk_build_job.gd`
- `scripts/organic_cliff_mesh_builder.gd`
- `scripts/environment_object_renderer.gd`

Validation and evidence:

- `tests/phase1d_validation.gd`
- `tests/phase1e_validation.gd`
- `tests/phase3f_validation.gd`
- `tests/phase3f_capture.gd`
- `tests/phase3f_benchmark.gd`
- `screenshots/phase3f_baseline_capture_manifest.json`
- `screenshots/phase3f_moderate_capture_manifest.json`
- `screenshots/phase3f_prominent_capture_manifest.json`
- `screenshots/phase3f_benchmark_graphical.json`
- 99 matched Phase 3F PNG captures under `screenshots/phase3f_*`

The Phase 1D and 1E tests now explicitly disable Phase 3E before checking their older component paths. This removes an existing test/default mismatch after `main.tscn` began selecting Phase 3E; production behaviour is unchanged.

## 3. Height-profile implementation

`TerrainRenderer.CliffHeightProfile` defines three deterministic profiles:

| Profile | Pixel step per elevation | Purpose |
| --- | ---: | --- |
| Baseline | 16 | Accepted Phase 3E presentation and default |
| Moderate | 24 | 50% more visible depth |
| Prominent | 32 | Option 2 comparison, twice baseline depth |

`Main.cliff_height_profile` exposes the selection in the inspector. `TerrainRenderer.set_cliff_height_profile()` provides the runtime switch. A switch repositions existing presentation layers, marks environmental batches dirty, schedules organic mesh replacements through the current revision-gated incremental scheduler, restarts pending stream builds, and updates cursor projection through a signal.

The profile is not exported in authoritative generation data or save snapshots. All contour noise and topology inputs remain integer, absolute-world, seed-derived values; only the shared projection step changes.

## 4. Projection and top-surface alignment

The same selected pixel step now drives:

- elevated top-surface layer positions;
- Phase 3E crest shifts and one-band toe extrusion;
- Phase 3D fallback faces, side returns, lips, and contact shadows;
- decoration and environmental-object elevation offsets;
- projected cell rectangles and polygons;
- vertical pick-search reach and cliff-face hit rectangles;
- hover, selection, and brush overlay height through the existing cursor callbacks.

This keeps top surfaces attached to their crests and puts each toe at the corresponding lower projected level. Camera projection and logical mouse-to-world conversion remain unchanged.

Legacy TileMap cliff atlases retain their original 16-pixel cells. Normal Phase 3E operation uses the aligned organic mesh path; disabling organic cliff geometry while a non-baseline profile is selected is not an approved Phase 3F presentation combination.

## 5. Controlled visual comparison

All evidence uses seed 84521, a 1280×720 viewport, identical fixture coordinates, and 1×, 2.31×, and 3× zooms. The three manifests record exact camera positions.

| Fixture | Baseline | Moderate | Prominent |
| --- | --- | --- | --- |
| One-level grass plateau, 2.31× | `screenshots/phase3f_baseline_one_level_grass_plateau_2_31x.png` | `screenshots/phase3f_moderate_one_level_grass_plateau_2_31x.png` | `screenshots/phase3f_prominent_one_level_grass_plateau_2_31x.png` |
| Two-level landmass, 2.31× | `screenshots/phase3f_baseline_two_level_raised_landmass_2_31x.png` | `screenshots/phase3f_moderate_two_level_raised_landmass_2_31x.png` | `screenshots/phase3f_prominent_two_level_raised_landmass_2_31x.png` |
| Three-level cliff, 2.31× | `screenshots/phase3f_baseline_three_level_cliff_2_31x.png` | `screenshots/phase3f_moderate_three_level_cliff_2_31x.png` | `screenshots/phase3f_prominent_three_level_cliff_2_31x.png` |
| Long diagonal, 2.31× | `screenshots/phase3f_baseline_long_diagonal_escarpment_2_31x.png` | `screenshots/phase3f_moderate_long_diagonal_escarpment_2_31x.png` | `screenshots/phase3f_prominent_long_diagonal_escarpment_2_31x.png` |
| Mixed heights, 2.31× | `screenshots/phase3f_baseline_mixed_height_junctions_2_31x.png` | `screenshots/phase3f_moderate_mixed_height_junctions_2_31x.png` | `screenshots/phase3f_prominent_mixed_height_junctions_2_31x.png` |
| Positive seam, 3× | `screenshots/phase3f_baseline_positive_chunk_boundary_3_0x.png` | `screenshots/phase3f_moderate_positive_chunk_boundary_3_0x.png` | `screenshots/phase3f_prominent_positive_chunk_boundary_3_0x.png` |
| Negative seam, 3× | `screenshots/phase3f_baseline_negative_chunk_boundary_3_0x.png` | `screenshots/phase3f_moderate_negative_chunk_boundary_3_0x.png` | `screenshots/phase3f_prominent_negative_chunk_boundary_3_0x.png` |

The complete matrix also covers winding cliffs, convex/concave corners, narrow ridges, and isolated formations.

Visual assessment:

- One-, two-, and three-level drops increase by the intended amount, and the prominent three-level face has substantial geological presence.
- Long diagonal and winding contours remain connected. No new chunk-seam gaps or detached parallel ribbons were observed.
- Crest, face, and toe remain attached in the reviewed frames, and the Phase 3B material scales over the additional face area without new geometry detail.
- The prominent profile magnifies an existing Phase 3E projection limitation: north- and side-facing walls around enclosed same-material plateaus can read as a thick border. Small isolated fallback formations retain their accepted Phase 3D top-mask quirks. These are not caused by seam divergence, but they prevent recommending prominent as the default without visual approval.

## 6. Validation results

Godot 4.7 stable (`5b4e0cb0f`) was used because the available 4.7.2 Mono runner still does not terminate reliably during automated editor startup. Individual scripts parse under 4.7 stable, and the focused runtime suites completed there.

| Validation | Result |
| --- | --- |
| Phase 1B | Pass |
| Phase 1C | No validation script exists in the repository |
| Phase 1D | Pass after isolating the Phase 1D toggle |
| Phase 1E | Pass after isolating the Phase 1E toggle |
| Phase 1F | Pass |
| Phase 1G | Pass |
| Phase 3C | Pass |
| Phase 3D | Pass |
| Phase 3E | Pass |
| Phase 3F | Pass |
| Phase 7A | Pass |
| Phase 7C.4 | Pass |
| Phase 7C.5 | Pass |
| Capture matrices | Pass, 33 images per profile |
| Graphical benchmark | Pass |
| `git diff --check` | Pass |

The Phase 3F suite specifically checks height ordering, crest displacement, mixed-height determinism, signed chunk seams, runtime profile switching, top-surface picking, authoritative elevation preservation, and baseline rollback. Existing editor/persistence suites cover painting, undo/redo, regeneration, and save ownership; projected polygons are still the brush/selection source.

## 7. Performance benchmark

The matched graphical benchmark used the Phase 1G dense fixture, a 1280×720 viewport, Compatibility renderer, NVIDIA GeForce RTX 3080, three streaming runs per profile, and 720 steady frames per profile.

| Metric | Baseline 16 px | Moderate 24 px | Prominent 32 px | Prominent change |
| --- | ---: | ---: | ---: | ---: |
| Vertices | 34,760 | 34,760 | 34,760 | 0.00% |
| Triangles | 17,384 | 17,384 | 17,384 | 0.00% |
| Mesh nodes | 40 | 40 | 40 | 0.00% |
| Steady mean frame | 2.524 ms | 2.574 ms | 2.616 ms | +3.63% |
| Steady P95 | 2.815 ms | 2.949 ms | 2.986 ms | +6.07% |
| Mean streaming frame | 5.087 ms | 5.130 ms | 5.209 ms | +2.41% |
| Mean total streaming CPU | 350.814 ms | 351.024 ms | 354.992 ms | +1.19% |
| Worst incremental geometry frame | 3.698 ms | 3.095 ms | 3.762 ms | +1.73% |
| Worst observed streaming frame | 17.022 ms | 18.316 ms | 17.680 ms | +3.87% |

All measured regressions remain below the 10% target. Geometry counts are identical because the profile changes coordinates, not topology or batching.

## 8. Remaining limitations

- Phase 3E remains a local marching-contour system, not a stored world-scale contour graph.
- Pure vertical 2D extrusion cannot make every compass-facing edge read like a conventional perspective wall. Enclosed plateaus can show a pronounced north/side border at 32 pixels.
- Isolated-sample fallback deliberately preserves Phase 3D topology and its existing small-mask artefacts.
- The legacy non-organic TileMap cliff path remains calibrated for the baseline 16-pixel projection.
- Oblique presentation retains its independent experimental projection and was not expanded by this bounded top-down prototype.
- Exact 4.7.2 automated execution remains a local tooling follow-up.

## 9. Recommendation

Keep **Baseline (16 px)** as the default. Moderate is the safer comparison profile for general play. Prominent should remain selectable for Option 2 review because it communicates one-, two-, and three-level height much more strongly and stays within the performance target, but its all-direction border read needs explicit visual approval.

## 10. Option 2 feasibility

A bounded Option 2 approximation is achievable within the existing renderer: the current system can provide substantially taller, deterministic, chunk-batched geological faces without changing authority, saves, the camera, or the terrain grid.

A fully convincing raised-landmass treatment in every contour orientation is not achievable by height scaling alone. Resolving the remaining north/side border read would require a later, explicitly approved investigation into directional face visibility, top-mask occlusion, and draw-order policy. That work is outside Phase 3F and was not started.
