# Wyntar Phase C4I — Legacy Cliff Coverage Repair

Date: 2026-10-24

Engine: Godot 4.7.2 stable Mono, OpenGL Compatibility, NVIDIA GeForce RTX 3080

Scope: presentation-only LEGACY cliff coverage; no terrain authority, generation, save format, collision, gameplay state, or cliff shader changes

## 1. Exact root cause addressed

C4H established that LEGACY elevated surfaces and organic cliff faces derive their final pixel boundaries independently. Surface alpha combines the universal mask, bounded relief, and shader displacement. Cliff faces use a separately displaced marching contour. The existing 14 px crest underlap protects the top join, but projected feet had no equivalent protection and the five-pixel C4E.1 lateral return was narrower than the remaining disagreement envelope. Corners and multilevel intersections combined both failures.

C4I retains both existing owners. It adds coverage-only geometry behind all intended terrain and cliff layers so pixels are supplied only where no accepted layer owns the frame.

## 2. Implementation

- `OrganicCliffMeshBuilder` emits a separate `coverage_meshes` batch only when the new toggle is enabled, the active renderer mode is `LEGACY`, and the established unified-contour path is active.
- Projected contours receive bounded crest and foot strips. Their measured envelope is the existing 14 px contour/mask/alpha bound plus a two-pixel viewport-sampling guard found by the prominent-profile blended-clear diagnostic.
- C4E.1 lateral returns use a narrower ten-pixel residual strip. The full projected bound is spent only at canonical endpoints, preventing a thick complete vertical band while closing concave, convex, and multilevel joins.
- Coverage meshes reuse the existing encoded cliff material. They render at absolute `z_index = -1`, beneath ground surfaces (`0..3`), elevated surfaces, and primary cliff faces. Opaque intended layers therefore clip the skirts without shader changes.
- The primary face meshes are unchanged byte-for-byte with the toggle on or off. They remain the visible cliff silhouette.
- `legacy_cliff_coverage_repair_enabled` is a reversible presentation setting. It defaults on in `Main`, travels through `CliffRenderingSettings`, `TerrainRenderer`, revision-gated build jobs, and chunk renderers, and is not persisted in authoritative world state.
- The C4H harness explicitly disables C4I so it remains a usable baseline reproducer.

The first attempted symmetric 14 px lateral skirt was rejected during visual review because it thickened north/south faces. It is not the shipped implementation.

## 3. Before/after uncovered pixels

The final matrix contains 312 matched PNGs: 13 fixtures × 4 zooms × 3 height profiles × before/after. Exact `#ff00ff` canvas pixels and magenta-dominant antialiased pixels were counted separately.

| Height profile | Exact before | Exact after | Clear/blended before | Clear/blended after |
|---|---:|---:|---:|---:|
| Baseline | 28,908 | 0 | 133,396 | 0 |
| Moderate | 28,752 | 0 | 126,961 | 0 |
| Prominent | 27,008 | 0 | 124,515 | 0 |
| **Total** | **84,668** | **0** | **384,872** | **0** |

Exact-pixel distribution by geometry class:

| Class | Before | After |
|---|---:|---:|
| Lateral north/south and ridge returns | 12,041 | 0 |
| Projected east/west feet | 9,666 | 0 |
| Corners, isolated cells, intersections, material joins, water | 62,961 | 0 |
| Diagonal chunk seam | 0 | 0 |

Exact-pixel distribution by elevation class:

| Class | Before | After |
|---|---:|---:|
| Height-two fixtures | 68,325 | 0 |
| Multi-level fixtures | 16,343 | 0 |

At 250% across all profiles, representative totals changed as follows: long north/south `868 → 0`, long east/west `2,277 → 0`, isolated cell `861 → 0`, one-cell ridge `2,544 → 0`, concave corner `2,509 → 0`, three-way intersection `8,702 → 0`, multilevel `3,109 → 0`, water contact `1,245 → 0`, and chunk boundary `0 → 0`.

## 4. Remaining defects

No exact or blended diagnostic clear pixels remain in the controlled matrix. Visual inspection found no new detached fragments, triangular wedges, material bleed over water, or chunk seams.

The coverage proof remains empirical and bounded to the current mask, contour, shader-displacement, height-profile, and viewport-filter envelopes. Future increases to any of those bounds require rerunning C4I rather than silently enlarging skirts.

## 5. Visual comparisons

Generated evidence is stored in ignored `.artifacts` storage:

- `c4i_before_<profile>_<fixture>_<zoom>.png`
- `c4i_after_<profile>_<fixture>_<zoom>.png`
- `c4i_capture_manifest.json`

Zoom labels cover `1_0x`, `1_75x`, `2_5x`, and `3_5x`. Fixtures cover grass/dirt, stone/sand, isolated raised cells, narrow ridges, almost-touching formations, three-way intersections, concave/convex corners, multilevel terraces, water, and an exact chunk-boundary crossing.

The accepted organic contour remains visually recognisable. The final lateral strip is narrower than the rejected prototype; projected strips remain hidden behind valid surfaces and the primary face except at former uncovered pixels.

## 6. Geometry and performance cost

Matched prominent-profile dense fixture, 12 loaded chunks, 180 steady frames:

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| Total vertices | 32,848 | 86,880 | +54,032 |
| Total triangles | 16,424 | 43,440 | +27,016 |
| Coverage meshes | 0 | 36 | +36 |
| Organic build time | 192.286 ms | 282.608 ms | +47.0% |
| Steady draw calls | 510 | 516 | +6 |
| Average steady frame | 5.224 ms | 5.665 ms | +0.441 ms |
| Steady p95 frame | 6.437 ms | 7.843 ms | +1.406 ms |
| Static memory | 75.144 MiB | 75.729 MiB | +0.585 MiB |
| Streaming geometry CPU | 192.597 ms | 282.086 ms | +46.5% |
| Streaming p95 frame | 10.154 ms | 10.933 ms | +0.779 ms |
| Visible-ready frame | 34 | 39 | +5 frames |

The cost is measurable but bounded: one additional coverage mesh per active elevation/chunk, six additional steady draw calls in this dense view, and no per-cell nodes. Average runtime frame cost increased by 0.441 ms in the matched sample. Raw results are in `.artifacts/c4i_legacy_cliff_coverage_benchmark.json`.

## 7. Regression results

Passed:

- Godot 4.7.2 project parse/editor initialization and main scene startup.
- C4I deterministic face-preservation, coverage, rollback, and R3 setting-path validation.
- Phase 1F incremental/synchronous geometry equivalence and C4A renderer configuration.
- C4E cliff geometry, C4E.1 contour continuity, C4F grid rim, and C4G renderer modes.
- G1, G2, G3, G4, G5, G6, and G7 validations.
- R1 camera and R2 world-editor refactor validations.
- Phase 1G lifecycle, bounded halo reuse, atomic replacement, streaming, and retirement validation.
- Phase 7B.1 authoritative save/load validation and fresh-process save then load.
- Pixel-exact stream-away/revisit in the C4I chunk-boundary fixture.
- Other cliff modes create zero C4I coverage triangles.
- `git diff --check`.

The full pre-existing R3 validator reports seven protected `main.tscn` override mismatches: four water values, `cliff_height_profile`, and their two startup aggregate checks. The current dirty scene selects the moderate height profile and does not contain the water-value overrides expected by that validator. C4I did not modify `main.tscn` or those expectations. The focused C4I R3 test passes both enabled and rollback states through `CliffRenderingSettings` before renderer readiness.

## 8. Known limitations

- Coverage increases cliff mesh vertices and triangles by about 164% in the dense benchmark because it deliberately remains a separate ownership batch.
- Absolute `z_index = -1` assumes ground presentation remains at zero or above. That is an existing renderer ordering contract and is documented in the chunk renderer.
- Diagnostic counts are screenshot-space measurements. Zoom affects sampling and count magnitude, although all four required zooms are clean after repair.
- The repair is intentionally inactive when unified contours are disabled and in GRID, UNIFIED, or STYLISED modes.

## 9. Shared-boundary recommendation

Further shared organic-boundary work is not justified for the tested LEGACY defect: bounded skirts eliminate both exact and antialiased clear pixels while preserving the accepted silhouette, authority boundaries, deterministic rebuilds, and streaming behaviour.

A shared boundary remains the preferable future architecture only if surface/cliff displacement bounds grow, the absolute underlay ordering contract changes, or new fixtures reveal gaps that cannot be closed within the measured envelope without visible thickening. C4I should not be expanded beyond its current bounds to solve such future cases.
