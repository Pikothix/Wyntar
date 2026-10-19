# Wyntar — Phase 3C Cliff Corner and Side-Return Correction

Date: 2026-10-19

Engine: Godot 4.7.2 stable Mono, Compatibility renderer, NVIDIA GeForce RTX 3080

Evidence labels:

- **Verified**: established by source inspection, isolated geometry assertions, saved captures, or a passing validation.
- **Visual observation**: judged from the saved matched captures.
- **Interpretation**: a conclusion drawn from verified implementation and visual evidence.

## 1. Task classification

Bugfix — deterministic presentation geometry.

This phase corrects the existing tile-derived face/corner construction. It does not implement connected contours or change the top-down projection.

## 2. Confirmed root cause

The grey wedges were background exposure caused by discontinuous south-face geometry, not intentional grey side surfaces and not a material-source error.

Two defects combined at corners where adjacent cliff cells had different total drops:

1. `_append_face()` generated each cell's internal row boundaries by interpolating between that face's top and bottom outlines. Two adjacent faces meeting at the same elevation therefore produced different Y coordinates when one dropped one level and the other dropped two or three levels.
2. `_has_face_values()` reduced neighbor coverage to one boolean for the complete face. Any overlap suppressed the exposed cap for every row, including lower elevation bands where the neighboring face no longer existed.

There was also an endpoint inconsistency in the exposed X cap. One X coordinate was assembled from both row fractions and applied to both vertices. Adjacent row quads could therefore disagree at their shared corner.

**Verified diagnostic:** the reproduction fixture was captured normally, without contact shadows, and without lip/return geometry. The wedge remained in both isolation views. Hiding the south-face batch exposed the same neutral canvas/background colour over the affected area. This excludes the Phase 3B shader, contact-shadow mesh, return material, and ordinary component draw order as the primary cause.

Refined side returns are intentional foreshortened side surfaces. Their narrow ribbons remain, but they now use the owning dirt/stone source and terminate on the corrected face crest rather than masking an unrelated hole.

## 3. Files changed

Production:

- `scripts/organic_cliff_mesh_builder.gd`

Validation and evidence:

- `tests/phase3c_validation.gd`
- `tests/phase3c_capture.gd`
- `tests/phase3c_benchmark.gd`
- `screenshots/phase3c_baseline_capture_manifest.json`
- `screenshots/phase3c_prototype_capture_manifest.json`
- `screenshots/phase3c_benchmark_graphical.json`
- 28 matched baseline/prototype PNG captures under `screenshots/phase3c_*`

No shader, terrain renderer, chunk renderer, terrain authority, persistence, or scene file changed.

## 4. Geometry correction

### Shared per-elevation face boundaries

South faces now sample a deterministic boundary for every 16-pixel elevation level rather than interpolating a boundary from the face's total drop. `_face_level_offset()` depends only on absolute world X, world cell Y, elevation level, and world seed. Adjacent cells meeting at the same world boundary/elevation therefore obtain identical points regardless of their respective total drops.

The profile is clamped inward beneath the unchanged authoritative top surface. This preserves the existing no-gap contract at the crest.

### Per-band neighbor coverage

Neighbor coverage is evaluated for every elevation band. A face row suppresses its cap only when the adjacent face actually covers that band. At a transition from connected to exposed, the new cap begins at the shared endpoint and then moves to its deterministic exposed outline. This avoids both holes and overlapping rectangular plugs.

### Return and shadow attachment

Refined returns now receive top-band connectivity rather than whole-face connectivity. Their final outer point snaps to the corrected crest cap only when that top band is exposed.

Contact-shadow endpoints receive foot-specific connectivity and use the same per-level foot profile as the visible face. Crest lips and the existing restrained contact-shadow material are otherwise unchanged.

### Topology and material

Vertex, index, triangle, batch, and node counts are unchanged. Existing vertex-colour source encoding remains responsible for dirt, stone, and shoreline selection. No corner-specific node, mesh layer, or material was added.

## 5. Controlled visual validation

`tests/phase3c_capture.gd` builds six controlled scenarios and captures each at 1× and 3× using the same seed, fixture code, camera path, renderer, and presentation flags for baseline and prototype:

| Fixture | Coverage |
| --- | --- |
| `grey_wedge_reproduction` | Tall dirt/stone blocks and asymmetric lower shelves matching the reported wedges |
| `convex_concave_corners` | Explicit convex spurs and concave notches |
| `isolated_one_two_three` | Isolated one-, two-, and three-level formations |
| `adjacent_dirt_stone` | Adjacent material walls with crossed lower shelves |
| `positive_chunk_boundaries` | Corners and returns crossing positive X/Y boundaries |
| `negative_chunk_boundaries` | Equivalent negative-coordinate boundaries |

Each manifest records 12 normal matched captures. The wedge fixture also has matched 3× diagnostic captures with contact shadows hidden and with lips/returns hidden.

Representative comparisons:

| View | Before | After |
| --- | --- | --- |
| Wedge reproduction, 3× | `screenshots/phase3c_baseline_grey_wedge_reproduction_3_0x_all_components.png` | `screenshots/phase3c_prototype_grey_wedge_reproduction_3_0x_all_components.png` |
| Isolated levels, 1× | `screenshots/phase3c_baseline_isolated_one_two_three_1_0x_all_components.png` | `screenshots/phase3c_prototype_isolated_one_two_three_1_0x_all_components.png` |
| Adjacent materials, 3× | `screenshots/phase3c_baseline_adjacent_dirt_stone_3_0x_all_components.png` | `screenshots/phase3c_prototype_adjacent_dirt_stone_3_0x_all_components.png` |
| Positive seam, 3× | `screenshots/phase3c_baseline_positive_chunk_boundaries_3_0x_all_components.png` | `screenshots/phase3c_prototype_positive_chunk_boundaries_3_0x_all_components.png` |
| Negative seam, 3× | `screenshots/phase3c_baseline_negative_chunk_boundaries_3_0x_all_components.png` | `screenshots/phase3c_prototype_negative_chunk_boundaries_3_0x_all_components.png` |

**Visual observation:** the neutral grey wedges at unequal-drop corners are replaced by continuous dirt or stone cliff coverage. Full face widths and the existing geological shader treatment remain visible. Crest accents and foot shadows remain coherent. No new positive- or negative-coordinate seam is visible.

## 6. Targeted geometry validation

`tests/phase3c_validation.gd` builds isolated and mixed-drop meshes directly and verifies:

- full 32-pixel south-face coverage is retained at crest and foot;
- every independently emitted row shares exact west/east endpoints with the next row;
- refined west/east returns terminate on the corrected crest corners;
- two adjacent faces with different total drops share exact vertices in their common bands;
- the unmatched lower band begins at the shared endpoint and ends on its deterministic exposed cap;
- repeated builds produce byte-identical face and return vertices.

This directly guards against missing face coverage, detached returns, unsupported corner caps, and nondeterministic correction geometry.

## 7. Performance

`tests/phase3c_benchmark.gd` uses the exact Phase 1G dense fixture, camera cell `(10200, 5100)`, 1280×720 viewport, Compatibility renderer, 180 warm-up frames, and five 240-frame measured runs.

### Steady rendering

| Metric | Phase 3B.1 accepted shader | Phase 3C | Change |
| --- | ---: | ---: | ---: |
| Mean frame time | 6.926 ms | 6.637 ms | -4.18% |
| Median frame time | 6.863 ms | 6.531 ms | -4.84% |
| P95 frame time | 8.783 ms | 8.803 ms | +0.23% |
| Average draw calls | 609 | 609 | 0 |
| Average primitives | 8,302 | 8,302 | 0 |

The Phase 3C run recorded one 39.253 ms operating-system/engine outlier. It did not affect P95 and was not accompanied by additional draw calls or primitives.

### Streaming/build CPU

| Metric | Phase 3B.1 | Phase 3C | Change |
| --- | ---: | ---: | ---: |
| Mean organic geometry CPU | 134.477 ms | 145.568 ms | +8.25% |
| Mean total chunk CPU | 449.583 ms | 458.232 ms | +1.92% |

The bounded per-level sampling performs several additional integer hashes for multi-level faces. The measured organic-build increase remains below 10%, total chunk CPU changes by less than 2%, and the work remains inside the existing incremental scheduler. Steady rendering topology and cost are unchanged.

## 8. Regression validation

All tests used Godot 4.7.2 stable Mono.

| Validation | Result |
| --- | --- |
| Phase 1B | Pass |
| Phase 1D | Pass |
| Phase 1E | Pass |
| Phase 1F | Pass |
| Phase 1G | Pass |
| Phase 3C targeted validation | Pass |
| Phase 7C.4 | Pass |
| Phase 7C.5 | Pass |
| Phase 3C graphical capture/shader compilation | Pass |
| Phase 3C graphical performance benchmark | Pass |

There is no standalone `phase3b_validation.gd`. Phase 3B material behavior was exercised by all 28 graphical Phase 3C captures; `shaders/cliff_procedural.gdshader` was not changed. The accepted Phase 3B.1 benchmark supplies the comparison baseline.

## 9. Ownership and constraints

- Terrain elevation and material data remain authoritative in the existing world system.
- `OrganicCliffMeshBuilder` still owns only deterministic, discardable presentation geometry.
- `TerrainChunkRenderer` continues to batch and render complete meshes without corner nodes.
- `TerrainRenderer` scheduling, streaming, edit invalidation, and chunk ownership are unchanged.
- Save formats, mesh topology, standard projection, and material-source encoding are unchanged.

## 10. Remaining limitations

- The correction retains tile-derived cells and narrow foreshortened side-return ribbons. It fixes their continuity but does not turn them into a connected formation contour.
- The new per-level profile deliberately favours watertight shared boundaries over independent full-face interpolation. Further silhouette art direction should be handled as a separately authorised contour phase.
- Performance was measured on an RTX 3080. The geometry CPU result is renderer-independent in principle, but slower CPUs should be checked before substantially increasing cliff density or elevation range.
- The single worst-frame outlier demonstrates why P95 and repeated runs remain more useful than one maximum sample for this change.

## 11. Recommendation

Accept the Phase 3C corner correction as a bounded bugfix. Retain the new targeted fixture and validation as regression coverage. Do not proceed automatically to connected-contour geometry.
