# Wyntar Phase C4K — Legacy Cliff Sidewall Occlusion Repair

Date: 2026-10-24  
Engine: Godot 4.7.2 stable Mono, OpenGL Compatibility, NVIDIA GeForce RTX 3080

## Scope and ownership

C4K is a presentation-only repair for inappropriate lower-terrain visibility beside LEGACY lateral cliff walls. It does not change `TerrainWorld`, terrain generation, material/elevation authority, collision, gameplay, persistence, or the accepted main cliff-face geometry. LEGACY remains the default. C4J coverage and L2 shader LOD retain independent rollback switches, and C4K adds its own `legacy_cliff_sidewall_occlusion_repair_enabled` switch, enabled by default.

The pre-existing dirty working tree was preserved. No reset, discard, commit, push, file move, or unrelated refactor was performed.

## 1. Reproduced visual defect

The defect reproduced deterministically on long left/right-facing boundaries, concave and convex corners, narrow ridges, multiple elevations, mixed terrain materials, water contacts, and a chunk-boundary crossing. The most visible case was a brown elevated surface beside green lower terrain: irregular green vertical slits appeared within the expected brown lateral wall. The same class of defect also occurred with non-green lower materials, so green was a useful symptom rather than the definition of failure.

Normal before/after, long lateral boundary at 2.5×:

| Before | After |
|---|---|
| ![C4K before long lateral boundary](.artifacts/c4k_sidewall_occlusion/c4k_before_long_north_south_boundary_250.png) | ![C4K after long lateral boundary](.artifacts/c4k_sidewall_occlusion/c4k_after_long_north_south_boundary_250.png) |

Normal before/after, concave corner at 2.5×:

| Before | After |
|---|---|
| ![C4K before concave corner](.artifacts/c4k_sidewall_occlusion/c4k_before_concave_corner_250.png) | ![C4K after concave corner](.artifacts/c4k_sidewall_occlusion/c4k_after_concave_corner_250.png) |

The diagnostic suite produced 95 captures. It included normal views at 1×, 2.5×, and 3.5×, plus isolated lower surface, upper surface, main face, C4J underlay, C4K sidewall, and combined layers. Diagnostic colours were green for lower surfaces, yellow for upper surfaces, purple for main faces, cyan for the C4J underlay, red for the C4K sidewall region, and magenta for uncovered background.

![C4K isolated sidewall occluder](.artifacts/c4k_sidewall_diagnostic/c4k_concave_corner_sidewall_only_250.png)

## 2. Confirmed cause

The visible regions were genuine lower-elevation terrain, not cliff-shader colour contamination and not uncovered background:

- They remained in the isolated lower-surface pass and in the lower-plus-main-face pass.
- They disappeared when lower terrain was hidden.
- The procedural cliff shader did not generate the green colour.
- The cyan C4J underlay existed beneath the affected boundary but could not hide an opaque terrain surface rendered above it.

Elevated surfaces and lower surfaces use independently displaced organic alpha masks. The accepted cliff contour follows the elevation topology, while a near-vertical LEGACY lateral return only extends 5 pixels toward the low side. At some vertical runs and corners, alpha disagreement on the high side of that return left the lower terrain visible beside the face. Broad north/south projected faces already cover their intended interval and did not need expansion.

Some green pixels close to a cliff are legitimate lower ground. The repair therefore targets only the footprint proven by lateral contour segments; it does not classify proximity or colour as failure.

## 3. Why C4J did not detect it

C4J measures clear/magenta background exposure. Its coverage mesh is an absolute-z underlay below ground, elevated surfaces, and the accepted face. It successfully replaces uncovered background but deliberately cannot occlude genuine lower terrain.

Consequently, the affected pixels satisfied the C4J zero-gap condition: a valid lower-terrain pixel existed there, so there was no clear pixel for the C4J metric to count. C4K adds a separate sidewall-occlusion metric instead of weakening or redefining C4J.

## 4. Implementation

The existing contour builder now optionally emits a separate LEGACY sidewall-occlusion mesh for near-vertical lateral returns only:

- A segment qualifies only when its vertical extent is greater than its horizontal extent and its horizontal return remains within the accepted 5-pixel lateral range.
- The companion quad preserves the existing 5-pixel low-side reach and adds a bounded 10-pixel high-side reach, starting 2 pixels above the crest to cover the observed alpha disagreement.
- It inherits the same source material and directional shade encoding as its owning face.
- It is rendered at `elevation * 8 - 3`: above lower-elevation surfaces, below the accepted main face at `elevation * 8 - 2`, and below the owning elevated surface.
- It is batched per elevation/chunk, is emitted only in LEGACY mode, and is controlled by the new C4K rollback switch.

The accepted main face mesh and C4J coverage mesh are not altered. Focused validation compares their packed mesh signatures with C4K disabled/enabled and confirms both remain byte-identical. GRID, UNIFIED, and STYLISED emit zero C4K geometry.

## 5. Before/after capture matrix

The matched C4K matrix contains 104 images: 13 fixtures × 4 zooms × before/after. Zooms were 1×, 1.75×, 2.5×, and 3.5×. Fixtures cover:

- long left/right-facing and north/south-facing boundaries;
- concave and convex corners;
- a narrow one-cell ridge and an isolated raised cell;
- multiple elevation levels and almost-touching formations;
- grass/dirt and stone/sand boundaries;
- water contact, a three-way intersection, and a chunk boundary.

The complete manifest is `.artifacts/c4k_sidewall_occlusion/c4k_capture_manifest.json`.

## 6. Sidewall-occlusion validation

For each before/after pair, the suite also renders the new sidewall layer in isolation to form an exact pixel mask. It then verifies that every changed output pixel is inside that mask.

| Metric | Result |
|---|---:|
| Matched pairs / captures | 52 / 104 |
| Pixels changed by the repair | 135,772 |
| Green-dominant lower pixels replaced | 6,471 |
| Changed pixels outside the sidewall mask | 0 |
| Long north/south-facing cliff fixture | 0 changed pixels |
| Isolated raised-cell fixture | 0 changed pixels |
| Deterministic repeated build | Byte-identical |
| Main face with C4K on/off | Byte-identical |
| C4J underlay with C4K on/off | Byte-identical |
| Non-LEGACY C4K geometry | Zero |

The 6,471 green-dominant pixels are a deliberately narrow sub-count. Changed dirt, sand, stone, and water-contact pixels are included in the 135,772 total but are not mislabeled as green defects. Visual review confirmed that lower terrain beyond the isolated mask remains visible, horizontal cliff projection remains unchanged, contours stay irregular, corner transitions remain natural, and no rectangular wall or broad brown halo is introduced.

The full C4J 312-image matrix also passed with C4K enabled: 38,437 uncovered pixels before C4J, zero afterward, and a pixel-exact streaming revisit. This confirms the C4J underlay remains gap-free.

## 7. Performance impact

The final benchmark is `.artifacts/c4k_sidewall_occlusion_benchmark.json`. It uses matched C4K-disabled/enabled LEGACY fixtures at 1280×720, with three enabled rebuilds and 180 steady frames.

| Metric | Dense disabled | Dense enabled | Typical disabled | Typical enabled |
|---|---:|---:|---:|---:|
| Total vertices | 47,108 | 50,116 | 9,996 | 10,804 |
| Added C4K vertices | 0 | 3,008 (+6.4%) | 0 | 808 (+8.1%) |
| Total triangles | 23,554 | 25,058 | 4,998 | 5,402 |
| Added C4K triangles | 0 | 1,504 (+6.4%) | 0 | 404 (+8.1%) |
| C4K meshes | 0 | 36 | 0 | 15 |
| Organic build time | 246.571 ms | 257.388 ms mean | 75.406 ms | 82.589 ms mean |
| Enabled build range | — | 247.864–272.063 ms | — | 82.046–82.967 ms |
| Steady draw calls | 516 | 522 | 187 | 189 |
| Average steady frame | 6.002 ms | 5.875 ms | 2.319 ms | 2.930 ms |
| P95 steady frame | 7.034 ms | 6.908 ms | 3.258 ms | 3.850 ms |
| Static memory | 75.494 MiB | 75.984 MiB | 63.448 MiB | 63.521 MiB |

Dense build time increased by 10.817 ms (+4.4%); typical increased by 7.183 ms (+9.5%). Steady frame values are host-noise sensitive: the dense sample improved slightly while the typical sample increased by 0.611 ms. Geometry and draw-call counts are deterministic and are the more reliable cost indicators. Moving from the dense fixture to the distant typical fixture retired every dense chunk.

## 8. Regression results

All runs used bounded Godot 4.7.2 validation.

| Validation | Result |
|---|---|
| C4E cliff geometry | Pass |
| C4E.1 contour continuity | Pass |
| C4F grid cliffs | Pass |
| C4G all renderer modes | Pass |
| C4H deterministic fixtures | Pass through C4K diagnostic and matched matrices |
| C4I ownership, determinism, rollback, non-LEGACY isolation | Pass |
| C4J full 312-image coverage matrix and revisit | Pass, zero uncovered after repair |
| C4K structural/ownership validation | Pass |
| C4K matched sidewall-occlusion matrix | Pass, zero changes outside mask |
| L2 enabled and disabled | Pass; fixed-detail rollback and zoom-aware path both validated |
| G1–G7 | Pass |
| Streaming and bounded retirement | Pass |
| Dense-to-typical retirement | Pass |
| Save/schema validation | Pass |
| Fresh-process save/load | Pass |
| Main scene startup | Pass |
| R3 | Exactly five previously documented water-configuration failures; no C4K failure |
| `git diff --check` | Pass; existing line-ending warnings only |

## 9. Remaining limitations

- The 10-pixel high-side reach is a deliberately bounded presentation constant derived from the accepted alpha displacement and reproduced fixtures. Future changes to organic edge amplitude, terrain alpha-mask construction, or layer z-order require rerunning the C4K matrix.
- Each active elevation/chunk can add one batched sidewall mesh, producing the measured draw-call increase. Merging it into the accepted face would remove rollback and signature isolation and was intentionally avoided.
- The metric proves containment to the generated sidewall footprint and separately counts replaced green pixels; it cannot infer artistic intent from terrain colour alone. Final visual review remains required when new materials or contour styles are introduced.
- Five pre-existing R3 water-scene configuration failures remain unresolved and are unrelated to C4K.

Recommendation: accept C4K as the LEGACY default repair. It removes the confirmed lower-terrain sidewall intrusions without changing terrain authority, the organic main silhouette, C4J coverage, L2 shading, or non-LEGACY modes.
