# Wyntar — Phase 3B.1 Shader Performance Verification

Date: 2026-10-19

Engine: Godot 4.7.2 stable Mono, Compatibility renderer, NVIDIA GeForce RTX 3080

Evidence labels used below:

- **Verified**: established by source inspection, a saved benchmark result, or a passing validation.
- **Visual observation**: judged from the saved matched captures.
- **Interpretation**: a conclusion drawn from the verified measurements.

## 1. Task classification

Performance verification of an existing rendering-system extension.

This phase does not begin Phase 3C geometry work.

## 2. Outcome

**Verified:** the Phase 3B geological shader does not cause a reproducible steady-state regression in the controlled same-session comparison. Its mean frame time was 0.48% lower than the pre-3B baseline, its median was effectively identical, and its P95 was 1.28% higher. All are comfortably inside the 10% acceptance threshold.

**Decision:** no production shader optimisation was made. Removing or weakening the geological operations without measured evidence would trade away the accepted visual result for no demonstrated performance benefit.

The apparent 44.4% increase recorded in `PHASE_3B_GEOLOGICAL_CLIFF_REPORT.md` came from separate application sessions and was explicitly not isolated to shader cost. The new A/B result supersedes that comparison for shader attribution.

## 3. Files and ownership

Added test/evidence infrastructure:

- `tests/fixtures/phase3b_pre_geological_cliff.gdshader`
- `tests/phase3b1_shader_benchmark.gd`
- `screenshots/phase3b1_shader_benchmark_graphical.json`
- Four matched baseline/prototype captures under `screenshots/phase3b1_*_dense_*.png`
- Eight fractional-pan captures under `screenshots/phase3b1_shimmer_*.png`

Production shader changes: none.

Terrain elevation, material authority, save formats, mesh topology, chunk scheduling, and renderer ownership are unchanged. The historical shader exists only as a benchmark fixture. The benchmark swaps the `Shader` resource on the same nine existing `ShaderMaterial` instances; it does not add geometry, feature nodes, or a second renderer.

## 4. Historical baseline recovery

**Verified:** Git history identifies commit `9f2d75d` as the pre-Phase-3B state and `e2c16ea` as the Phase 3B commit present at the start of this task. The old `shaders/cliff_procedural.gdshader` blob was recovered with `git show` and copied into `tests/fixtures/phase3b_pre_geological_cliff.gdshader`.

The current production file was not reverted or overwritten. The fixture differs from the historical blob only in its header comment identifying its benchmark-only purpose.

## 5. Controlled benchmark methodology

`tests/phase3b1_shader_benchmark.gd` extends the existing Phase 1G benchmark so both modes use the exact same dense fixture construction and readiness checks.

| Control | Value |
| --- | --- |
| Scene | `res://main.tscn` |
| Fixture | Existing exact Phase 1G dense fixture |
| Camera cell | `(10200, 5100)` |
| Viewport | 1280x720 |
| Renderer | `gl_compatibility` |
| Display server | Windows |
| VSync | Disabled |
| Materials switched | 9 existing cliff materials |
| Compile warm-up | 180 frames per shader, plus 15 settling frames |
| Switch warm-up | 45 frames before every measured run |
| Run order | Baseline, prototype, repeated five times |
| Measured frames | 240 per run; 1,200 per mode |

Both shader variants were preloaded, rendered, and warmed before the first timed run. The old and new shaders then alternated in one Godot process. Fixture, camera, renderer, materials, draw submission, and process lifetime therefore remained constant.

Frame time is wall time across `process_frame`, recorded in milliseconds. Godot's available render counters were sampled every measured frame. The raw per-run results and aggregate values are retained in `screenshots/phase3b1_shader_benchmark_graphical.json`.

## 6. Steady-state rendering results

| Metric | Pre-3B baseline | Phase 3B prototype | Change |
| --- | ---: | ---: | ---: |
| Mean frame time | 6.960 ms | 6.926 ms | -0.48% |
| Median frame time | 6.864 ms | 6.863 ms | -0.01% |
| P95 frame time | 8.672 ms | 8.783 ms | +1.28% |
| Worst measured frame | 20.977 ms | 15.452 ms | -26.34% |
| Average draw calls | 609 | 609 | 0 |
| Average primitives | 8,302 | 8,302 | 0 |

**Verified:** the five baseline run means ranged from 6.670 to 7.365 ms. The five prototype run means ranged from 6.646 to 7.166 ms. Their ranges overlap substantially; the aggregate differences are smaller than ordinary run-to-run variation.

**Interpretation:** this benchmark provides no evidence that the extra Phase 3B fragment work—world-space fields, irregular strata, sparse fracture checks, and material differentiation—is a material bottleneck on the tested RTX 3080 Compatibility-renderer configuration. Draw calls and primitive count are identical, confirming that the comparison changed shading rather than submitted geometry.

Godot did not expose a reliable isolated GPU-duration value through the harness on this renderer, so the report does not claim a GPU-only time. Wall-frame timings and render counters are the available comparable metrics.

## 7. CPU streaming versus steady rendering

Streaming was measured separately by invalidating the same streamed chunks after each shader switch and waiting for the existing scheduler to settle. Six rebuilds alternated in the reverse order—prototype then baseline—three runs per mode. `chunk_processing_usec_this_frame` and `organic_geometry_processing_usec_this_frame` were accumulated from the existing renderer counters.

| Metric | Pre-3B baseline | Phase 3B prototype | Change |
| --- | ---: | ---: | ---: |
| Mean frame time during rebuild | 9.426 ms | 9.442 ms | +0.17% |
| Mean accumulated chunk CPU | 443.230 ms | 449.583 ms | +1.43% |
| Median accumulated chunk CPU | 445.479 ms | 453.910 ms | +1.89% |
| Mean accumulated organic-geometry CPU | 133.095 ms | 134.477 ms | +1.04% |
| Median accumulated organic-geometry CPU | 134.337 ms | 135.693 ms | +1.01% |

**Verified:** the shader selection does not change the chunk-build or organic-mesh code paths. The small CPU differences are well below the variation between individual rebuilds and do not track additional CPU work introduced by the shader.

**Interpretation:** CPU-side streaming remains the dominant source of rebuild spikes, while the controlled steady-state result isolates the shading comparison. The Phase 3B material does not shift ownership or add CPU generation work.

## 8. Shader cost review and optimisation decision

Source inspection focused on the operations most likely to be expensive:

- repeated deterministic hash/noise evaluations;
- warped strata placement and bed selection;
- stone fracture line/branch distance calculations;
- role- and material-specific colour modulation.

These paths are bounded fragment calculations. The fracture work has no neighbourhood search or dynamic loop and is gated to eligible stone face fragments. Fine weathering, erosion, and fractures already share the `detail_level` control introduced in Phase 3B.

**Decision:** retain the current implementation. No expensive operation demonstrated a measurable end-to-end penalty large enough to justify altering the visual material. If a future lower-tier GPU profile exceeds the 10% target, the first isolated experiment should reduce fine hash evaluations behind `detail_level`; broad facets and strata should remain intact.

## 9. Matched visual comparison

The benchmark captured baseline and prototype from the same fixture, camera, renderer, and process before timed measurement:

- `screenshots/phase3b1_baseline_dense_1_0x.png`
- `screenshots/phase3b1_prototype_dense_1_0x.png`
- `screenshots/phase3b1_baseline_dense_3_0x.png`
- `screenshots/phase3b1_prototype_dense_3_0x.png`

**Visual observation:** the prototype retains broad tonal planes, irregular horizontal beds, sparse stone fractures, directional return shading, and visible dirt/stone differentiation. The baseline is comparatively uniform and grid-like. No topology changed between the images.

## 10. Fractional-pixel shimmer check

Eight prototype frames were captured at 3x while moving the camera by `(0.25, 0.125)` world pixels per step. The sequence is saved as `screenshots/phase3b1_shimmer_00.png` through `screenshots/phase3b1_shimmer_07.png`.

**Visual observation:** across all eight frames, the geological pattern stays registered to the terrain. Facets, beds, and fractures do not reseed, crawl independently, or reveal a chunk-local restart. The expected nearest-filtered image translation is visible as the camera crosses sampling boundaries; no additional shader shimmer was identified.

Limitation: this is a saved eight-frame inspection, not a high-speed camera-motion capture on multiple displays. It is adequate for detecting pattern reseeding but does not rule out every temporal aliasing case.

## 11. Validation

All tests were run with Godot 4.7.2 stable Mono in headless mode unless noted otherwise.

| Validation | Result |
| --- | --- |
| Godot editor parse/import | Pass; only the existing nested `_reference/project.godot` warning |
| Graphical Phase 3B.1 controlled benchmark | Pass |
| `phase1a_validation.gd` | Pass |
| `phase1b_validation.gd` | Pass |
| `phase1d_validation.gd` | Pass |
| `phase1e_validation.gd` | Pass |
| `phase1f_validation.gd` | Pass |
| `phase1g_validation.gd` | Pass |
| `phase3a_validation.gd` | Pass |
| `phase7c4_validation.gd` | Pass |
| `phase7c5_validation.gd` | Pass |

The passing Phase 1G, Phase 3A, Phase 7C.4, and Phase 7C.5 checks cover the relevant deterministic generation, organic geometry, topology, and seam invariants. The earlier phase validations provide regression coverage for the renderer foundations retained by the benchmark.

## 12. Acceptance criteria

| Criterion | Status |
| --- | --- |
| No more than 10% steady-state frame-time regression | Pass: mean -0.48%, median -0.01%, P95 +1.28% |
| No authority, save, topology, or ownership changes | Pass |
| No additional geometry or per-feature nodes | Pass |
| Deterministic and seam validations pass | Pass |
| Broad facets, irregular strata, differentiation remain visible | Pass by matched capture review |

## 13. Remaining risks and recommendation

- The result applies to the tested RTX 3080, Windows, Compatibility-renderer configuration. Integrated and older GPUs may have a different fragment-cost balance.
- Wall-frame measurement includes normal operating-system and engine scheduling noise; alternation, warm-up, and 1,200 frames per mode reduce but cannot eliminate it.
- The dense fixture is intentionally severe. Other camera compositions can change cliff screen coverage, although that should reduce rather than increase the absolute cost in ordinary play.
- A future multi-hardware performance matrix would be useful before setting a minimum-GPU claim, but it is not required to accept Phase 3B on the tested target.

**Recommendation:** accept the existing Phase 3B shader without optimisation. Keep `tests/phase3b1_shader_benchmark.gd` as the isolated regression harness and require the same alternating-session method for future material changes. Do not begin Phase 3C geometry work as part of this task.
