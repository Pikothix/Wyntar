# Wyntar Phase C4H — Legacy Cliff Surface Coverage Investigation

Date: 2026-10-24

Engine: Godot 4.7.2 stable Mono, OpenGL Compatibility, NVIDIA GeForce RTX 3080

Scope: diagnostic only; no production renderer, terrain authority, generation, save, collision, or gameplay code changed

## 1. Executive summary

The reported LEGACY defects have more than one visual cause.

1. **Genuine uncovered pixels are present.** A diagnostic magenta canvas clear colour is visible through the final composited frame at multiple elevated/lower-terrain boundaries. These pixels are not dark geology and are not lower terrain showing through.
2. **Adjacent dark strips are often intentional cliff faces.** The narrow brown/grey band beside many uncovered pixels is the five-pixel C4E.1 side-return quad, shaded by `cliff_procedural.gdshader`. A normal screenshot can make the dark face and the immediately adjacent clear pixel read as one larger defect.
3. **The primary root cause is an interaction between independently generated coverage boundaries.** Elevated and lower surfaces use universal-mask alpha fields, while cliff faces use a separately displaced marching contour. C4E's 14 px vertical crest underlap protects the top join for projected faces, but it does not provide a matching lower-foot overlap and it does not enlarge C4E.1's five-pixel lateral side return.
4. **Draw order is correct and is not the cause.** Faces render below their elevated surface and above lower ground. Layer-isolation captures prove that the missing pixels are absent from all relevant layers, rather than being incorrectly occluded.
5. **Rims and shadows do not repair the holes.** Enabling either diagnostic component left the exact-clear-pixel count unchanged in all eight isolated cases.
6. **No chunk-edge inconsistency was reproduced.** The diagonal fixture crossing exact chunk boundary `X=50208` contained zero clear pixels at all four zooms. Existing seam and deterministic-rebuild validators also pass.
7. **The previously reported pointed near-vertical fragments are not reproducible in the current C4E.1 code.** The current complete-path side-return branch removes the artificial midpoint that created those fragments. Pointed silhouettes still occur on isolated masks and valid convex intersections, but the old detached two-tip topology did not recur.

At 250% zoom, the diagnostic clear colour was present in 12 of 13 controlled LEGACY fixtures. The sole clean fixture was the long diagonal chunk-boundary crossing, where broad projected face geometry happened to cover both independently displaced joins. This is deterministic geometry; zoom changes sampling and apparent thickness, not the underlying topology.

LEGACY should remain the default. UNIFIED is not a required correction and is not a safe substitute: it aligns its own square elevated surface and wall, but still meets the old masked lower terrain independently. Under the same clear-colour diagnostic it exposed substantially larger boundary regions in most fixtures.

## 2. Current surface/cliff rendering pipeline

### Authority and configuration

- `TerrainWorld` owns authoritative material IDs, ground elevation, sparse material overrides, and sparse elevation overrides. Rendering reads this data and never writes it during a chunk build.
- `Main` captures `CliffRenderingSettings` and applies it to `TerrainRenderer`. The checked-in scene selects `LEGACY = 0`, enables unified organic contours and directional projection, uses the moderate height profile, and leaves optional edge overlays and shadows off.
- `TerrainRenderer` owns shared presentation resources, loaded chunks, revision-gated build jobs, and renderer-mode selection. `TerrainWorld` remains authoritative through mode changes and rebuilds.

### Surface sampling and atlas coverage

1. `TerrainChunkBuildJob` samples a 34×34 material/elevation halo for a 32×32 chunk.
2. `_prepare_cell()` calls `_prepare_ground_surface()` and `_prepare_elevated_surfaces()`.
3. Both surface builders read four authoritative corner samples for each render cell. Ground masks include corners at elevation zero. Elevated masks include corners at one exact elevation, not `>= level`.
4. Material priority determines the four compositing slots, but it does not change height ownership.
5. `TerrainSurfaceFactory.mask_field()` bilinearly interpolates the four mask bits and adds bounded sinusoidal relief. `_generate_masked_atlas()` stores the field in RGB and its initial `smoothstep(0.43, 0.57, field)` coverage in alpha.
6. `terrain_variation.gdshader` applies a shared world-space organic perturbation to the stored mask field and recomputes final alpha. This moves the visible surface boundary independently of cliff mesh construction.
7. `TerrainChunkRenderer` places height-zero surfaces at their normal position and elevated surfaces at `-elevation * height_step`.

### Cliff contour, face, rim, and shadow generation

1. With the current LEGACY Boolean configuration, `OrganicCliffMeshBuilder._process_unified_contour_square()` handles non-uniform four-height squares.
2. For each level, it creates a marching-squares mask from `height >= level`, selects canonical segments, and resolves saddle cases deterministically from absolute world coordinates.
3. `_unified_contour_path()` independently displaces edge endpoints by up to five pixels and bows the midpoint by another bounded world-space field. This path does not consume the final surface-alpha contour.
4. `_append_unified_contour_band()` calls `_append_unified_offset_strip()` with the existing 14 px crest underlap and the selected height profile.
5. Broad/diagonal segments project toward the lower elevation. Near-vertical complete paths take the C4E.1 branch and become one lateral five-pixel side-return quad.
6. Optional lips/returns and contact shadows use the same organic mesh material but separate component roles. The production scene currently hides the separate edge and shadow mesh layers.
7. `CliffResourceFactory` owns the shared organic shader material and the rollback tile atlases. In active organic mode the generated mesh supplies opacity; `cliff_procedural.gdshader` replaces colour, geology, role shading, and shoreline treatment without expanding silhouette coverage.

### Final draw order

For elevation `E`, the relevant z-indices are:

| Layer | z-index |
|---|---:|
| Height-zero surface slots | 0–3 |
| Organic shadow component | `E * 8 - 3` |
| Organic cliff face | `E * 8 - 1` with the current unified-contour/directional settings |
| Elevated surface slots | `E * 8` through `E * 8 + 3` |
| Organic rim/return component | `E * 8 + 4` |
| Decoration layer | `E * 8 + 5` |

This order correctly lets the elevated surface hide the face's crest underlap. The uncovered pixels remain visible when every component is isolated, so reordering cannot create coverage that no layer owns.

## 3. Deterministic fixtures and reproduced defects

All fixtures use the current seed and live renderer settings. Coordinates below are authoritative world-cell coordinates. The reported ranges are the cells touched by exact magenta pixels in the 250% final LEGACY capture; they are intentionally conservative to cell resolution.

| Fixture | Centre | Materials/elevations | Result at 250% | Clear-pixel world-cell range | Deterministic / seam |
|---|---:|---|---|---|---|
| Long north/south boundary | `(49152,24576)` | Dirt 2 / grass 0 | Reproduced narrow side gaps beside valid dark returns | `(49151,24572)`–`(49152,24580)` | Yes / no seam |
| Long east/west boundary | `(49248,24576)` | Dirt 2 / grass 0 | Reproduced saw-tooth foot gaps below a continuous broad face | `(49245,24575)`–`(49254,24576)` | Yes / no seam |
| Grass/dirt elevation boundary | `(49344,24576)` | Grass 2 / dirt 0 | Broad diagonal covered; terminal vertical return contains a true opening | `(49347,24579)`–`(49348,24579)` | Yes / no seam |
| Stone/sand elevation boundary | `(49440,24576)` | Stone 2 / sand 0 | Same terminal-return failure with stone material | `(49443,24579)`–`(49444,24580)` | Yes / no seam |
| Isolated raised cell | `(49536,24576)` | Stone 2 / grass 0 | Pointed organic surface is intentional; a clear wedge remains at the lower point | `(49536,24576)` | Yes / no seam |
| One-cell ridge | `(49632,24576)` | Dirt 2 / grass 0 | Reproduced gaps on both long side returns | `(49630,24572)`–`(49633,24580)` | Yes / no seam |
| Almost-touching formations | `(49728,24576)` | Dirt 2, stone 2, grass 0 | The lower channel is authoritative; additional clear slivers occur on both formation edges | `(49726,24575)`–`(49730,24580)` | Yes / no seam |
| Three-way intersection | `(49824,24576)` | Dirt 2, stone 1, grass 0 | Valid material/height arms plus true side and foot openings at the junction | `(49817,24573)`–`(49832,24580)` | Yes / no seam |
| Concave corner | `(49920,24576)` | Dirt 2 / grass 0 | Reproduced vertical-return and inner-foot gaps | `(49916,24575)`–`(49925,24579)` | Yes / no seam |
| Convex corner | `(50016,24576)` | Stone 2 / grass 0 | Mostly covered; a small clear terminal sliver remains | `(50022,24577)`–`(50022,24579)` | Yes / no seam |
| Multiple elevations | `(50112,24576)` | Dirt 1, stone 2, snow 3 over grass 0 | Reproduced side gaps and foot gaps across stacked bands | `(50104,24572)`–`(50119,24578)` | Yes / no seam |
| Chunk boundary crossing | `(50208,24576)` | Stone 2 / grass 0 | No clear pixels at 100%, 175%, 250%, or 350% | None | Yes / exact X seam |
| Water contact | `(50304,24576)` | Dirt 2, stone 3 / water 0 | Water is correctly present; separate clear slivers occur at both land/water side joins | `(50302,24572)`–`(50305,24580)` | Yes / no seam |

At 250%, representative exact-clear-pixel counts are 458 for the long north/south boundary, 1,194 for the long east/west boundary, 400 for the isolated cell, 1,502 for the ridge, 1,304 for the concave corner, 2,122 for the multilevel fixture, and zero for the chunk-seam fixture. These are screenshot-space evidence, not a world-area metric; the camera shows a different boundary length at each zoom.

## 4. Diagnostic evidence

The capture harness temporarily changes the canvas clear colour to `#ff00ff`, which is absent from all terrain and cliff materials. It then captures:

- normal final composition;
- ground only;
- elevated surface only;
- organic face only;
- ground plus elevated surface;
- ground plus organic face;
- final composition with rims;
- final composition with shadows.

This supports the requested classification:

| Classification | Finding |
|---|---|
| A. True uncovered pixels | Confirmed. Exact clear-colour pixels survive the final composition in 12 controlled LEGACY fixtures at 250%. |
| B. Lower terrain showing through | Also occurs intentionally in the one-cell channel and outside raised masks, but it is visually distinguishable from the exact clear colour and is not the principal measured defect. |
| C. Dark cliff material mistaken for a gap | Confirmed beside many true gaps. Face-only captures show continuous dark brown/grey side returns and broad geological faces. |
| D. Surface and cliff boundaries disagree | Confirmed primary cause. Surface-only and face-only silhouettes have different displaced contours at crest, side, and foot. |
| E. Incorrect draw order or occlusion | Rejected. z-order matches intent and isolated passes show absent coverage, not hidden coverage. |
| F. Corner/return geometry failures | Confirmed as a secondary manifestation. Five-pixel side returns do not cover the full independent-boundary envelope at vertical terminals, ridges, isolated cells, and concave joins. |
| G. Chunk-edge inconsistencies | Not reproduced. Exact seam fixture is clean and deterministic seam validators pass. |

Enabling rims or shadows changed the exact-clear-pixel count by zero in each isolated diagnostic scenario. This rules out the current optional overlay geometry as a reliable repair.

The old C4E.1 pointed-fragment failure is distinct. Before C4E.1, a bowed near-vertical path was split into two projected quads around its artificial midpoint. The current `_append_unified_offset_strip()` classifies the complete path and emits one quad between canonical endpoints. That historical defect is fixed; the remaining gaps are coverage-envelope failures around otherwise continuous geometry.

## 5. Confirmed root causes

### 5.1 Independent final surface alpha and cliff contour

`TerrainSurfaceFactory` and `terrain_variation.gdshader` own the final surface-alpha boundary. `OrganicCliffMeshBuilder` owns a separate marching contour with separate displacement. They share authoritative height samples, but they do not share the final visible pixel contour.

The face therefore cannot know the exact final alpha edge it must meet. The existing bounds are sufficient at many broad crests but not at every side and foot.

### 5.2 Crest-only underlap does not protect the face foot

C4E's 14 px underlap is applied at the upper edge of projected face geometry and is then intentionally hidden by the elevated surface. The lower edge is projected from the organic contour by the height step, while the lower surface remains an independently masked field at its own unprojected position. No equivalent bounded foot overlap joins those two boundaries.

The long east/west, concave, three-way, isolated, and multilevel captures show clear saw-tooth pixels immediately below otherwise continuous broad faces. These are foot-to-lower-surface gaps, not crest gaps.

### 5.3 Five-pixel side returns are narrower than the complete disagreement envelope

The C4E.1 side-return branch deliberately uses `lateral_depth = 5`. It repairs near-degenerate topology and removes pointed midpoint fragments, but it is not a coverage proof against the combined surface-mask relief, organic surface shader displacement, and independent cliff-contour displacement.

The long north/south and one-cell-ridge captures show a valid dark five-pixel return with clear pixels immediately beside it. Increasing the vertical crest underlap cannot fix this because the missing coverage is lateral.

### 5.4 Complex intersections expose both limitations at once

Concave corners, isolated cells, close formations, three-way joins, and stacked levels combine broad projected segments with side-return segments. Each segment remains deterministic and continuous, but their union does not necessarily cover the union of both surface-alpha envelopes. This creates small wedges and openings without any authority, chunk, or material-data failure.

### 5.5 Material shader and draw order are not coverage owners

`cliff_procedural.gdshader` preserves mesh alpha. It can make a valid face very dark, but it cannot create or close a hole outside mesh geometry. Likewise, changing z-order cannot close a region absent from every layer.

## 6. Findings that remain uncertain

- The original screenshots did not include seed, authoritative coordinates, clear-colour diagnostics, or a revision identifier. Their exact individual pixels cannot be mapped one-to-one to these fixtures.
- Some pointed shapes in screenshots may be valid isolated-cell or convex marching-mask silhouettes. The prior detached C4E.1 midpoint-fragment topology was not reproduced in current code.
- The investigation establishes exact missing coverage and responsible stages, but it does not yet establish the smallest visually acceptable overlap constants. Those should be measured in a focused implementation phase against all material shaders and height profiles before production values are chosen.
- Screenshot pixel counts vary with viewport coverage and nearest-neighbour sampling. They demonstrate visibility, not a stable world-area measurement.

## 7. Comparison with C4G UNIFIED

UNIFIED replaces elevated dual-grid masks with full square cells and derives its wall from the same cardinal outline. This removes disagreement between that elevated square and its own wall crest.

It does **not** make the lower terrain consume the same boundary. The height-zero terrain still uses the existing universal-mask path. With the diagnostic clear colour, UNIFIED exposed larger boundary regions in most fixtures—for example 21,936 exact clear pixels versus LEGACY's 458 on the 250% long north/south view, and 49,372 versus 1,194 on the long east/west view. These counts include the square surface's deliberate mismatch with the old lower mask and are not an art-quality score.

UNIFIED therefore proves the value of one boundary owner but does not supply the required organic correction. Promoting it would replace the preferred natural silhouette with square geometry and would still leave the lower-surface join to solve.

## 8. Ranked correction approaches

| Rank | Approach | Expected effectiveness | Implementation risk | LEGACY appearance |
|---:|---|---|---|---|
| 1 | Add a bounded coverage-only skirt to existing LEGACY faces: directional lateral coverage for complete-path side returns and bounded foot coverage for projected faces, derived from the existing contour path | High for confirmed side/foot gaps | Low–medium if isolated to mesh coverage and regression-tested | Preserves current surface contour and geology; smallest safe candidate |
| 2 | Derive a shared organic boundary artifact from the existing C4E.1 contour and let the elevated surface, face crest, and lower join consume it | Highest long-term correctness | Medium–high; touches surface masking/material blending and chunk preparation | Best organic result if carefully rasterised; avoids square geometry |
| 3 | Correct only corner caps and return joins | Medium for isolated/concave/three-way cases; low for long face-foot gaps | Low–medium | Preserves style, but incomplete alone |
| 4 | Increase one global overlap/underlap constant | Medium at one join, poor across directional cases | Medium visual risk; can overpaint valid lower terrain and thicken walls | Not recommended without directional bounds |
| 5 | Change draw order | Ineffective | Low code risk, high correctness risk | Would hide or expose the wrong layers without creating coverage |

A global increase to `UNIFIED_CREST_UNDERLAP` is specifically not recommended. The diagnostic evidence shows that the remaining failures are predominantly lateral side-return and lower-foot failures; the crest constant does not control those regions.

## 9. Proposed smallest safe implementation phase

Proposed follow-up: **Phase C4I — Targeted LEGACY Boundary Coverage Skirts**.

The phase should remain presentation-only and should not introduce another renderer.

1. Extend the C4H harness with a machine-checked clear-pixel assertion for the confirmed fixtures and all three height profiles.
2. In `OrganicCliffMeshBuilder`, keep the current visible contour, material roles, topology, z-order, and 14 px crest underlap.
3. Add a bounded, behind-surface coverage skirt only where diagnostics require it:
   - a directional lateral skirt for complete-path side returns;
   - a bounded foot skirt for projected broad/diagonal faces;
   - explicit cap union at mixed side/broad intersections.
4. Determine bounds from the configured maximum surface-alpha displacement plus cliff-contour displacement. Do not use an unmeasured global expansion.
5. Render the skirt with the existing face material/role and behind the accepted visible contour so it closes clear pixels without replacing organic outlines or becoming gameplay authority.
6. Re-run the complete C4H matrix with clear-colour counting, then manually review normal-colour captures for widened walls, covered lower terrain, water overpaint, and corner massing.
7. If a bounded skirt cannot close all fixtures without visible overpainting, stop and promote approach 2—a shared organic boundary artifact—as a separately reviewed architectural phase.

No part of this implementation has begun.

## 10. Validation results

All commands used Godot 4.7.2 and bounded execution.

| Check | Result |
|---|---|
| Main scene startup | Pass |
| C4H graphical matrix | Pass; 104 matched mode/fixture/zoom captures and 64 layer-isolation captures |
| C4E cliff geometry | Pass |
| C4E.1 contour continuity | Pass |
| C4F grid cliff | Pass |
| C4G selector, rollback, authority invariance, determinism, seam equivalence | Pass |
| G1–G7 material regressions | Pass |
| Phase 1G streaming, rebuild, and retirement | Pass |
| Phase 7B.1 same-process save/load | Pass |
| Phase 7B.1 fresh-process save and load | Pass |
| Deterministic chunk/mesh rebuilds | Pass through C4E, C4E.1, C4F, and C4G validators |
| Exact chunk-boundary visual fixture | Pass; zero diagnostic clear pixels at all requested zooms |
| `git diff --check` | Pass; pre-existing line-ending warnings only |

## 11. Screenshots and capture locations

All evidence is retained in ignored `.artifacts` storage:

- Manifest: `.artifacts/c4h_capture_manifest.json`
- LEGACY matrix: `.artifacts/c4h_legacy_<scenario>_<zoom>.png`
- UNIFIED comparison matrix: `.artifacts/c4h_unified_<scenario>_<zoom>.png`
- Layer isolation: `.artifacts/c4h_diag_<scenario>_<pass>.png`

Requested zoom suffixes are `1_0x`, `1_75x`, `2_5x`, and `3_5x`.

Representative evidence:

- `.artifacts/c4h_legacy_long_north_south_boundary_2_5x.png`
- `.artifacts/c4h_diag_long_north_south_boundary_surface_only.png`
- `.artifacts/c4h_diag_long_north_south_boundary_face_only.png`
- `.artifacts/c4h_legacy_long_east_west_boundary_2_5x.png`
- `.artifacts/c4h_legacy_grass_dirt_elevation_boundary_2_5x.png`
- `.artifacts/c4h_diag_grass_dirt_elevation_boundary_ground_and_surface.png`
- `.artifacts/c4h_diag_grass_dirt_elevation_boundary_ground_and_face.png`
- `.artifacts/c4h_legacy_one_cell_ridge_2_5x.png`
- `.artifacts/c4h_legacy_three_way_intersection_2_5x.png`
- `.artifacts/c4h_legacy_concave_corner_2_5x.png`
- `.artifacts/c4h_legacy_chunk_boundary_crossing_2_5x.png`
- `.artifacts/c4h_legacy_water_contact_2_5x.png`

The magenta colour in C4H captures is diagnostic background visibility, not a production rendering change or terrain material.

## 12. Ownership confirmation

- `TerrainWorld` still owns and modifies authoritative material/elevation state.
- Chunk build jobs and the organic mesh builder only read authority and produce disposable presentation data.
- `TerrainChunkRenderer` still owns visual nodes, meshes, TileMap layers, visibility, and draw order.
- Shaders still own presentation colour and alpha within supplied geometry/masks.
- UI remains a request layer and owns no gameplay state.
- Save/load continues to persist authoritative state only.

The C4H test harness creates temporary overrides solely to build deterministic fixtures. It does not alter production ownership or save format. No production renderer was modified, no experimental mode was activated by default, and no commit or push was performed.
