# Wyntar Phase C4J — Legacy Cliff Coverage Optimisation

Date: 2026-10-24
Engine: Godot 4.7.2 stable Mono, OpenGL Compatibility, NVIDIA GeForce RTX 3080

## Scope and ownership

C4J is a presentation-only optimisation of the C4I LEGACY coverage underlay. It does not change `TerrainWorld`, terrain generation, collision, gameplay state, persistence, the authoritative height/material lookups, or the accepted main cliff-face mesh. The underlay remains a separate mesh at its existing depth and remains controlled by `legacy_cliff_coverage_repair_enabled`, preserving the C4I rollback path. LEGACY remains the default cliff mode.

The pre-existing dirty worktree was preserved. No reset, discard, commit, push, or `main.tscn` edit was performed.

## 1. C4I baseline

The accepted C4I graphical dense fixture provided the comparison baseline:

| Metric | Pre-C4I | C4I |
|---|---:|---:|
| Exact uncovered pixels, complete matrix | 84,668 | 0 |
| Magenta-dominant pixels, complete matrix | 384,872 | 0 |
| Total cliff vertices | 32,848 | 86,880 |
| Total cliff triangles | 16,424 | 43,440 |
| Coverage vertices | 0 | 54,032 |
| Coverage triangles | 0 | 27,016 |
| Organic build time | 192.286 ms | 282.608 ms |
| Mesh-resource construction | 2.410 ms | 4.260 ms |
| Scene attachment | 1.767 ms | 2.626 ms |
| Steady draw calls | 510 | 516 |
| Average steady frame | 5.224 ms | 5.665 ms |
| P95 steady frame | 6.437 ms | 7.843 ms |
| Static memory | 75.144 MiB | 75.729 MiB |

## 2. Confirmed bottlenecks

A temporary component profiler was applied to the unoptimised C4I implementation and its result retained as `.artifacts/c4j_c4i_profile_baseline.json`. The component timers were removed after diagnosis so they do not remain in the hot path. These component figures are diagnostic, overlapping measurements from the same headless run and should be used for distribution, not compared directly with the graphical totals above.

| C4I coverage component | Time | Share of measured coverage generation | Triangles |
|---|---:|---:|---:|
| Crest strips | 37.105 ms | 43.9% | 11,252 |
| Foot strips | 34.915 ms | 41.3% | 11,252 |
| Endpoint caps | 7.761 ms | 9.2% | 3,008 |
| Lateral strips | 4.734 ms | 5.6% | 1,504 |
| Total | 84.515 ms | 100% | 27,016 |

The dominant cost was redundant primitive and packed-array assembly, not resource creation or scene attachment:

- C4I emitted 13,508 coverage quads for 3,565 face paths: separate crest and foot strips for broad paths, plus a lateral strip and two caps for side returns.
- C4I vertex/index assembly was 64.329 ms, an increase of 39.013 ms over the no-coverage reference. This is an overlapping submetric and is not additive with the total build time.
- Mesh-resource construction increased by only 1.850 ms and scene attachment by 0.859 ms.
- Coverage stayed in 36 elevation/chunk meshes, so the six-draw-call increase came from the separate underlay batch rather than the number of per-face primitives.

This ruled out scene attachment and draw batching as primary C4J targets. The safe target was the repeated internal underlay geometry.

## 3. Optimisations implemented

The accepted main cliff-face path and mesh generation are unchanged.

For each existing LEGACY contour path, C4J now emits exactly one coverage quad:

- Broad/projected paths use one conservative screen-space bound containing the full crest-to-foot interval, all organic path points, and the maximum projection of the former C4I strip margin.
- Lateral returns use one oriented quad with independent tangent and normal extents. This retains the former endpoint reach without two duplicate cap quads and without widening the complete lateral run to the cap width.
- Separate crest, foot, and endpoint primitives were removed. Their internal overlap is now one simple region.
- Each remaining disconnected, source-coloured quad already uses the minimum four vertices and two triangles. Cross-face vertex sharing or broad contour merging was not introduced because faces may differ in material source and directional shade, and merging large regions could expose the wrong underlay at intersections.
- The underlay is still generated only when the existing C4I toggle is enabled and the selected mode is LEGACY. GRID, UNIFIED, and STYLISED paths are untouched.

The result is 3,565 coverage quads on the dense fixture instead of 13,508.

## 4. Geometry and performance results

The final benchmark is `.artifacts/c4j_legacy_cliff_coverage_benchmark.json`. It uses the same seed, viewport, camera, renderer, LEGACY prominent profile, and dense fixture as C4I. Coverage-enabled rebuilds were repeated three times. A separate deterministic typical fixture was measured in the same process.

### Dense fixture

| Metric | C4I | C4J | Change |
|---|---:|---:|---:|
| Total vertices | 86,880 | 47,108 | -45.8% |
| Total triangles | 43,440 | 23,554 | -45.8% |
| Coverage vertices | 54,032 | 14,260 | -73.6% |
| Coverage triangles | 27,016 | 7,130 | -73.6% |
| Additional geometry vs pre-C4I | +164.5% | +43.4% | target met |
| Organic build time | 282.608 ms | 193.214 ms mean | -31.6% |
| Build range | single C4I sample | 188.667–196.665 ms | 7.998 ms range |
| Mesh-resource construction | 4.260 ms | 2.475 ms mean | -41.9% |
| Scene attachment | 2.626 ms | 1.740 ms mean | -33.7% |
| Steady draw calls | 516 | 516 | unchanged |
| Average steady frame | 5.665 ms | 3.478 ms | run-to-run sensitive |
| P95 steady frame | 7.843 ms | 4.521 ms | run-to-run sensitive |
| Static memory | 75.729 MiB | 75.678 MiB | -0.051 MiB |

The three C4J dense rebuilds were 194.310, 196.665, and 188.667 ms. Mean was 193.214 ms; the range was 4.1% of the mean. Streaming geometry CPU tracked those results at 193.722, 196.204, and 187.929 ms. Average streaming-frame measurements ranged from 6.092 to 6.265 ms. Visible chunks were ready in 33–34 frames, compared with 39 in the original C4I sample.

The final result meets all stated dense targets: build time is below 220 ms, extra geometry is below +50%, draw calls do not exceed C4I, and coverage does not regress.

### Typical fixture

| Metric | Coverage disabled | C4J enabled |
|---|---:|---:|
| Faces | 793 | 793 |
| Total vertices | 6,824 | 9,996 |
| Total triangles | 3,412 | 4,998 |
| Coverage vertices | 0 | 3,172 |
| Coverage triangles | 0 | 1,586 |
| Organic build | 57.747 ms | 64.398 ms mean |
| Build range | — | 63.606–64.820 ms |
| Steady draw calls | — | 187 |
| Average steady frame | — | 1.397 ms |
| P95 steady frame | — | 1.902 ms |

Typical build variability was 1.214 ms, or 1.9% of the mean. Its coverage geometry is also exactly two triangles per face. Moving from the dense fixture to the distant typical fixture retired every previously loaded dense chunk.

## 5. Coverage and appearance validation

The final `.artifacts/c4j_capture_manifest.json` contains 312 matched captures: 13 fixtures × 4 zooms × 3 height profiles × before/after.

| Check | Result |
|---|---|
| Exact uncovered pixels after C4J | 0 |
| Magenta-dominant blended pixels after C4J | 0 |
| Baseline / moderate / prominent profiles | 0 / 0 / 0 |
| Water-contact fixtures | Pass |
| Chunk-boundary fixtures | Pass |
| Pixel-exact streaming revisit | Pass |
| Deterministic coverage rebuild signature | Pass |
| Main LEGACY face signature vs coverage-disabled build | Byte-exact |
| GRID, UNIFIED, STYLISED coverage geometry | Zero, unchanged |
| Representative C4I/C4J visual inspection | No visible silhouette redesign |

The before side of the same matrix reproduced 84,668 exact-clear and 384,872 magenta-dominant pixels, confirming that the test still detects the original gaps.

## 6. R3 investigation

This investigation was kept separate from C4J performance work and `main.tscn` was not changed.

The seven failures reported during C4I had two causes:

1. Two failures were stale height-profile expectations: one direct scene-property assertion and its startup aggregate. The later C4H investigation explicitly records the current scene's moderate profile as the accepted LEGACY presentation. The R3 validator was updated from profile `2` to profile `1`; these two checks now pass.
2. Five failures remain for water configuration: four direct scene overrides plus the startup aggregate. The R3 report explicitly documents protected values `0.63`, `0.25`, `0.6`, and `0.7`, while the current scene contains no corresponding overrides and therefore uses defaults `0.32`, `0.55`, `0.14`, and `0.38`.

The remaining five failures are therefore real scene-configuration drift relative to the documented R3 baseline, not a C4J coverage regression and not evidence that the R3 capture/apply ownership path is broken. Because there is no later evidence authorising replacement of those water settings, neither the validator expectations nor the user's current scene were changed. R1 and R2 pass; R3 reports exactly the five water-related failures.

## 7. Regression validation

All tests used bounded Godot 4.7.2 runs.

| Validation | Result |
|---|---|
| C4E cliff geometry | Pass |
| C4E.1 contour continuity | Pass |
| C4F grid cliffs | Pass |
| C4G all renderer modes | Pass |
| C4H/C4I full coverage matrix | Pass via the stricter C4J 312-capture matrix |
| C4I ownership, determinism, rollback, non-LEGACY isolation | Pass |
| G1–G7 | Pass |
| R1 camera/streaming | Pass |
| R2 editor/input | Pass |
| R3 | Five documented water-scene failures remain; two stale profile failures corrected |
| Phase 1G streaming and bounded retirement | Pass |
| Dense-to-typical chunk retirement | Pass |
| Save/schema validation | Pass |
| Fresh-process save | Pass |
| Fresh-process load | Pass |
| Project startup | Pass |
| Pixel-exact streaming revisit | Pass |
| `git diff --check` | Pass; existing line-ending warnings only |

The Mono executable consistently prints `.NET: Assemblies not found` in these GDScript-only runs, as in prior phase validation. The relevant scripts execute and report their explicit pass/fail result; this environment diagnostic did not prevent GDScript validation.

## 8. Remaining risks and recommendation

- The conservative bounding quads intentionally contain the complete former C4I strip envelope. They cover more hidden internal area than a polygon union would, but remain behind terrain and face surfaces. Any future change to layer depth, alpha, material encoding, or surface occlusion should rerun the full matrix.
- Frame and memory values vary with host activity. Geometry counts are deterministic; timing conclusions use three rebuilds and report the full range.
- The five R3 water-scene failures remain unresolved by design. The architect/user should decide whether to restore the documented R3 values or explicitly adopt the current defaults in a separate configuration task.
- Further geometry reduction would require merging independently coloured/shaded face ownership regions. That is not justified while the current two-triangle-per-face result meets the target and preserves deterministic material ownership.

Recommendation: proceed to L2. C4J meets the performance and geometry targets, retains C4I's zero-gap result and rollback, and leaves gameplay and simulation ownership unchanged. Keep the R3 water-scene decision separate from L2 and from cliff rendering.
