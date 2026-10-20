# Wyntar — Phase 3E Unified Organic Cliff Contours

Date: 2026-10-20

Task classification: Existing System Extension — procedural cliff geometry.

Scope: bounded presentation-only unified-contour prototype. Phase 3D remains the default fallback; this phase does not add world-scale contour graphs, geometry LOD, a new projection, or save-data changes.

## 1. Work recovered from the interrupted session

The interrupted working tree already contained the Phase 3E implementation in progress. It was recovered in place without reverting or replacing any Phase 3B–3D work or the unrelated `_reference` modification.

Recovered work included:

- a separate `unified_cliff_contours_enabled` runtime flag threaded through `Main`, `TerrainRenderer`, `TerrainChunkBuildJob`, and `TerrainChunkRenderer`;
- a four-sample, per-elevation contour path in `OrganicCliffMeshBuilder`;
- deterministic absolute-world edge sampling, bounded broad/fine displacement, pixel quantisation, and deterministic saddle resolution;
- conservative routing of isolated peaks through Phase 3D;
- Phase 3E validation, capture, and benchmark scripts;
- partial baseline/prototype evidence and a design note.

Initial recovery validation found the Phase 3D and Phase 3E targeted suites passing. Visual inspection then found that the capture harness could photograph retiring Phase 3D component batches over the completed Phase 3E face batch. This was an evidence-timing fault, not contour duplication. The capture now waits for the Phase 1G retirement queue as well as build completion.

## 2. Work completed during this continuation

- Re-audited the dirty tree, existing reports, implementation, tests, and evidence before editing.
- Corrected the contour square/sample alignment while preserving the original Phase 3D halo indexing.
- Kept all bands of one projected drop on one render layer so elevated surfaces cannot split stacked bands into parallel slivers.
- Integrated the restrained south-facing contact band into the face batch and removed the unused duplicate crest-strip helper.
- Preserved Phase 3D geometry for isolated samples and conservative formations.
- Added retirement-safe and genuinely filtered capture behaviour.
- Regenerated the complete baseline/prototype matrix and fresh-process primary 2.31× A/B captures.
- Reran the paired graphical benchmark and every available requested regression suite.

## 3. Files changed

Production:

- `main.tscn`
- `scripts/main.gd`
- `scripts/organic_cliff_mesh_builder.gd`
- `scripts/terrain_chunk_build_job.gd`
- `scripts/terrain_chunk_renderer.gd`
- `scripts/terrain_renderer.gd`

Validation and documentation:

- `PHASE_3E_UNIFIED_CONTOUR_APPROACH.md`
- `PHASE_3E_UNIFIED_CONTOUR_REPORT.md`
- `tests/phase3e_validation.gd`
- `tests/phase3e_capture.gd`
- `tests/phase3e_benchmark.gd`
- `tests/phase3d_capture.gd`
- `tests/phase3d_benchmark.gd`
- `screenshots/phase3e_baseline_capture_manifest.json`
- `screenshots/phase3e_prototype_capture_manifest.json`
- `screenshots/phase3e_benchmark_graphical.json`
- 72 matched Phase 3E PNG captures under `screenshots/phase3e_*`

No authoritative terrain, persistence, collision, projection, or Phase 3B shader file changed.

## 4. Contour and mesh-generation approach

Phase 3E reuses the same four height samples that define one elevated render square. For every elevation threshold it classifies those samples into a 16-case marching-squares mask and emits zero, one, or two local contour segments. Saddle cases 6 and 9 use an absolute world-coordinate hash, so the choice is independent of traversal order.

Each grid-edge crossing has a canonical position derived from its absolute edge coordinates and world seed. A 96-pixel broad field and 32-pixel fine field add bounded, linearly interpolated offsets. Segment midpoints receive a second bounded normal displacement. All points are rounded to pixels and clamped inside the owning square; no spline or unbounded overshoot is used.

The extracted path is extruded by one 16-pixel elevation band. Repeating this per threshold represents one- to three-level drops. South-facing paths receive a restrained contact band in the same face buffer. The accepted Phase 3B material supplies strata, facets, cracks, crest treatment, and toe response. Meshes remain chunk/elevation batches; no nodes are added per contour feature.

Uniform squares exit immediately. Isolated high samples and their surrounding squares retain the accepted Phase 3D cap/return construction. The implementation remains one square per incremental scheduler quantum and uses only the existing 34×34 immutable halo.

## 5. Phase 3C continuity and ownership

Phase 3C continuity is preserved by construction:

- shared contour endpoints are pure functions of canonical absolute-world edge keys and the world seed;
- total face drop, chunk origin, traversal order, and job completion order are not endpoint inputs;
- all levels of a mixed-height square independently use the same edge-key rule;
- face and integrated contact geometry use the same extracted path;
- positive and negative chunks independently reproduce identical seam endpoints;
- isolated/corner fallback uses the unchanged Phase 3D/Phase 3C path;
- one-cell halo ownership and atomic revision-gated replacement remain unchanged.

`TerrainWorld` remains the material/elevation authority. The renderer samples immutable presentation data and builds discardable meshes. The toggle schedules the existing incremental replacement path and does not mutate simulation state.

## 6. Before-and-after screenshots

All captures use world seed 84521, a 1280×720 viewport, identical fixture/camera coordinates, and 0.5×, 1×, 2.31×, and 3× zooms. Previous Phase 3B/3C/3D screenshots remain preserved.

| Fixture | Phase 3D baseline | Phase 3E prototype |
| --- | --- | --- |
| Primary diagonal, 2.31× | `screenshots/phase3e_baseline_user_diagonal_grass_reproduction_2_31x.png` | `screenshots/phase3e_prototype_user_diagonal_grass_reproduction_2_31x.png` |
| Long multi-chunk diagonal, 2.31× | `screenshots/phase3e_baseline_long_diagonal_multichunk_2_31x.png` | `screenshots/phase3e_prototype_long_diagonal_multichunk_2_31x.png` |
| Winding boundary, 1× | `screenshots/phase3e_baseline_s_winding_boundary_1_0x.png` | `screenshots/phase3e_prototype_s_winding_boundary_1_0x.png` |
| Convex/concave corners, 3× | `screenshots/phase3e_baseline_convex_concave_corners_3_0x.png` | `screenshots/phase3e_prototype_convex_concave_corners_3_0x.png` |
| Mixed heights, 3× | `screenshots/phase3e_baseline_mixed_height_adjacent_3_0x.png` | `screenshots/phase3e_prototype_mixed_height_adjacent_3_0x.png` |
| Isolated formations, 3× | `screenshots/phase3e_baseline_isolated_one_two_three_3_0x.png` | `screenshots/phase3e_prototype_isolated_one_two_three_3_0x.png` |
| Dirt/stone transition, 2.31× | `screenshots/phase3e_baseline_dirt_stone_transition_2_31x.png` | `screenshots/phase3e_prototype_dirt_stone_transition_2_31x.png` |
| Positive/negative seams, 3× | `screenshots/phase3e_baseline_positive_chunk_seam_3_0x.png` / `phase3e_baseline_negative_chunk_seam_3_0x.png` | `screenshots/phase3e_prototype_positive_chunk_seam_3_0x.png` / `phase3e_prototype_negative_chunk_seam_3_0x.png` |

The complete paths and camera metadata are in the two capture manifests.

## 7. Visual acceptance assessment

**Verified:** the primary 2.31× Phase 3D image reads as alternating horizontal south faces and narrow vertical returns. The matched Phase 3E image replaces that staircase with one connected diagonal wall whose width and direction continue through turns.

**Verified:** the prototype frames inspected at 0.5×, 1×, 2.31×, and 3× contain no detached parallel returns after waiting for retirement completion. Positive and negative seam fixtures remain continuous. Isolated one-, two-, and three-level formations retain conservative Phase 3D coverage.

**Visual observation:** the result moves toward the long, coherent contour language visible in the [Out of Pixkrieg showcase](https://www.reddit.com/r/proceduralgeneration/comments/1x85755/procedural_generation_in_out_of_pixkrieg/) while retaining Wyntar's top-down projection and Phase 3B material. This is a visual comparison, not a claim about the reference implementation.

Acceptance result: **pass for the bounded Phase 3E prototype**. The improvement is structural topology, not additional subdivisions or noise inside the old rectangular faces.

## 8. Validation results

Tests were executed with Godot 4.7 stable (`5b4e0cb0f`). The installed 4.7.2 Mono runner remains unsuitable for reliable automated startup on this machine, so exact 4.7.2 reruns remain a tooling follow-up.

| Validation | Result |
| --- | --- |
| Phase 1B | Pass |
| Phase 1C | No validation script exists in the repository |
| Phase 1D | Pass |
| Phase 1E | Pass |
| Phase 1F | Pass |
| Phase 1G | Pass |
| Phase 3C | Pass |
| Phase 3D | Pass |
| Phase 3E | Pass |
| Phase 7A | Pass |
| Phase 7C | Pass |
| Phase 7C.2 | Pass |
| Phase 7C.3 | Pass |
| Phase 7C.4 | Pass |
| Phase 7C.5 | Pass |
| Baseline capture matrix | Pass, 36 captures |
| Prototype capture matrix | Pass, 36 captures |
| Paired graphical benchmark | Pass |

The Phase 3E suite explicitly covers topology change on diagonals, mixed-height/corner triangles, byte-identical synchronous/incremental results, positive/negative seam endpoints, runtime rollback, edits, and regeneration.

## 9. Performance and geometry results

The paired benchmark used the exact Phase 1G dense fixture at `(10200, 5100)`, a 1280×720 viewport, Compatibility renderer, NVIDIA GeForce RTX 3080, three streaming runs per mode, and 720 steady frames per mode.

| Metric | Phase 3D | Phase 3E | Change |
| --- | ---: | ---: | ---: |
| Face/segment records | 734 | 3,453 | +370.44% |
| Vertices | 33,116 | 34,760 | +4.96% |
| Triangles | 18,276 | 17,384 | -4.88% |
| Mesh nodes | 108 | 40 | -62.96% |
| Steady mean frame | 2.968 ms | 2.671 ms | -10.00% |
| Steady P95 | 3.880 ms | 3.240 ms | -16.49% |
| Mean streaming frame | 5.580 ms | 5.237 ms | -6.15% |
| Mean total streaming CPU | 338.988 ms | 353.261 ms | +4.21% |
| Worst geometry work frame | 3.338 ms | 3.619 ms | +8.42% |

The higher face count is an internal count of small contour-band records, not nodes or draw calls. Batching reduces node count substantially, and total vertex growth is 4.96%. Both measured CPU regressions remain under the requested 10% target. The JSON evidence is `screenshots/phase3e_benchmark_graphical.json`.

## 10. Remaining issues and limitations

- This is local marching extraction, not a stored or world-scale traced contour graph.
- Curvature is analytically coherent across cells but does not use run-wide simplification or long-range tangent fitting.
- Deterministic saddle choices are bounded and watertight but can still create an angular local turn.
- Isolated samples deliberately keep Phase 3D geometry, so tiny formations do not receive the full unified contour treatment.
- Phase 3E is disabled by default in `main.tscn`; this preserves Phase 3D as the production fallback pending user acceptance.
- Exact automated reruns with Godot 4.7.2 remain blocked by the available runner, although all suites pass on Godot 4.7 stable.

## 11. Recommended next steps

Review the saved 2.31× primary A/B pair and the 0.5×/1×/3× matrix in normal gameplay context. If accepted, enable the Phase 3E flag deliberately in the main scene as a separate approval step. Do not begin Phase 3F, full contour-graph extraction, major return redesign, or geometry LOD as part of this phase.
