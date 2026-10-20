# Wyntar Phase A — Procedural Water Enhancement Report

Date: 2026-10-20  
Classification: Existing System Extension — procedural liquid rendering and visual effects

## 1. Existing Water Capabilities

The pre-Phase-A water path already used the shared terrain material architecture:

- `TerrainWorld` owned authoritative material and elevation data.
- `TerrainCatalog` identified water as a liquid and supplied its presentation profile.
- `TerrainRenderer` created one shared `ShaderMaterial` per terrain material and bound liquid profile values.
- `terrain_variation.gdshader` retained the water texture and palette, applied a primary animated world-space band, broad value-noise variation, depth shading, and a shoreline highlight derived from the existing universal mask.
- Water animation used Godot's global `TIME`, so chunk creation and reload did not own or reset animation phase.
- The shader already quantised water lookups to absolute world pixels, avoiding screen-space anchoring and camera-relative swimming.

The genuinely missing Phase A behaviours were a second independently drifting ripple scale, deterministic crest-linked glints, bounded controls for both effects, and a dedicated default-off runtime rollback toggle.

## 2. Procedural Almanac Techniques Investigated

Reviewed source:

- `src/water.js`: `waterTime` and `waterPixel`
- `src/noise.js`: `noiseTile`, value-noise interpolation, and wrapping coordinates
- Repository examples/tests and the MIT licence

Relevant ideas were:

- a global shared water clock rather than per-object animation time;
- multiple water fields at different scales and drift directions;
- whole-pixel/beat quantisation for a pixel-art cadence;
- deterministic spatial hashing for sparse glint candidates;
- brief per-candidate temporal gates;
- glints restricted to ripple crests.

Wyntar already had absolute world-space value noise and a global shader clock, so no JavaScript renderer, wrapping noise texture, dependency, particle system, or CPU pixel update path was imported.

## 3. Algorithms Adapted and Why

### Secondary ripple field

The existing primary band is unchanged. When Phase A is enabled, the shader evaluates one additional sine field at a separately controlled spatial scale. Its drift vector travels in a different direction from the primary band. Input position and drift are quantised to world pixels, and time is stepped at eight beats per second.

This is deliberately a bounded single-field addition: it creates broad interference and variation without an expensive multi-octave shader or large waves.

### Pixel-art glints

World pixels are divided into deterministic 12 × 7 pixel candidate cells. A seed-derived hash controls placement, dash row, start, length, optional one-pixel angled tip, and temporal offset. A candidate is visible only when:

1. its spatial hash is below the bounded density;
2. the secondary field is near a crest;
3. its short 4 Hz beat is active.

The result is a sparse 2–4 pixel horizontal or slightly angled dash. Placement is spatially stable, while the brief beat prevents static sparkle clutter. Smooth animation was considered, but the quantised eight-beat ripple drift and four-beat glint cadence produced the clearer pixel-art result without objectionable frame-to-frame flicker in the captured sequence.

## 4. Files Changed

Phase A implementation and evidence files:

- `shaders/terrain_variation.gdshader`
- `scripts/terrain_catalog.gd`
- `scripts/terrain_renderer.gd`
- `scripts/main.gd`
- `tests/phase_a_water_validation.gd`
- `tests/phase_a_water_validation.gd.uid`
- `tests/phase_a_water_capture.gd`
- `tests/phase_a_water_capture.gd.uid`
- `tests/phase_a_water_benchmark.gd`
- `tests/phase_a_water_benchmark.gd.uid`
- `THIRD_PARTY_NOTICES.md`
- `PHASE_A_PROCEDURAL_WATER_REPORT.md`
- `screenshots/phase_a_capture_manifest.json`
- `screenshots/phase_a_water_benchmark.json`
- 75 `screenshots/phase_a_*.png` comparison and animation captures

The working tree contained unrelated pre-existing cliff, environment, scene, test, log, report, and screenshot changes. Phase A did not revert or rewrite those changes.

## 5. Shader and Runtime Controls

The dedicated toggle is `experimental_water_enhancement_enabled`, default `false`.

| Control | Range | Default | Purpose |
| --- | ---: | ---: | --- |
| `water_ripple_strength` | 0.0–1.0 | 0.32 | Secondary field contribution |
| `water_secondary_ripple_scale` | 0.5–6.0 | 2.4 | Secondary spatial frequency |
| `water_ripple_drift_speed` | 0.0–2.0 | 0.55 | Quantised secondary drift |
| `water_glint_density` | 0.0–1.0 | 0.14 | Candidate-cell density |
| `water_glint_brightness` | 0.0–1.0 | 0.38 | Blend toward existing water highlight tint |

`TerrainRenderer.set_experimental_water_enhancement_enabled()` updates only shared liquid materials and does not rebuild chunks. `set_water_enhancement_controls()` clamps and propagates the five controls. Main-scene exports provide the established runtime configuration surface. Save/load world replacement copies the runtime presentation settings, but authoritative snapshots and save formats do not include them.

When disabled, the added shader work is behind a uniform branch, the pre-existing primary water path remains active, and the animation clock still resolves to Godot's original global `TIME`. A negative `water_animation_time_override` is the runtime default; the non-negative override exists only to produce deterministic matched captures.

## 6. Before-and-After Screenshots

The capture matrix contains baseline, enhanced with glints disabled, and enhanced with glints enabled for all seven required scenes at 0.5×, 1×, and 3× zoom. All captures use seed 84521, viewport 1280 × 720, identical authored fixtures/cameras, and fixed animation time 6.0 seconds.

Manifest: [`screenshots/phase_a_capture_manifest.json`](screenshots/phase_a_capture_manifest.json)

Representative comparisons:

| Scenario | Baseline | Enhanced, no glints | Enhanced, glints |
| --- | --- | --- | --- |
| Large open lake, 1× | [`baseline`](screenshots/phase_a_baseline_large_open_lake_1_0x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_large_open_lake_1_0x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_large_open_lake_1_0x.png) |
| Small enclosed pond, 1× | [`baseline`](screenshots/phase_a_baseline_small_enclosed_pond_1_0x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_small_enclosed_pond_1_0x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_small_enclosed_pond_1_0x.png) |
| Sandy shoreline, 0.5× | [`baseline`](screenshots/phase_a_baseline_irregular_sandy_shoreline_0_5x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_irregular_sandy_shoreline_0_5x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_irregular_sandy_shoreline_0_5x.png) |
| Grass shoreline, 0.5× | [`baseline`](screenshots/phase_a_baseline_grassland_shoreline_0_5x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_grassland_shoreline_0_5x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_grassland_shoreline_0_5x.png) |
| Water by cliffs, 1× | [`baseline`](screenshots/phase_a_baseline_water_adjacent_to_cliffs_1_0x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_water_adjacent_to_cliffs_1_0x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_water_adjacent_to_cliffs_1_0x.png) |
| Chunk boundaries, 3× | [`baseline`](screenshots/phase_a_baseline_water_crossing_chunk_boundaries_3_0x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_water_crossing_chunk_boundaries_3_0x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_water_crossing_chunk_boundaries_3_0x.png) |
| Negative coordinates, 3× | [`baseline`](screenshots/phase_a_baseline_negative_world_coordinates_3_0x.png) | [`ripples`](screenshots/phase_a_enhanced_no_glints_negative_world_coordinates_3_0x.png) | [`ripples + glints`](screenshots/phase_a_enhanced_glints_negative_world_coordinates_3_0x.png) |

Manual visual review was performed on the real OpenGL renderer. The secondary field remains restrained, glints are visible but do not dominate, shorelines and cliff contacts remain readable, and no seam was visible in the all-water chunk-boundary capture at 3×.

## 7. Animation Comparison

Each mode includes four large-lake frames at 1× and fixed times 6.00, 6.25, 6.50, and 6.75 seconds. Files use the pattern:

`screenshots/phase_a_<mode>_animation_large_lake_1_0x_frame_<00-03>_t_<time>.png`

The enhanced sequence shows the secondary field drifting continuously in world space and glints changing on deterministic short beats. Camera position is fixed. Glints do not all toggle together, and the observed cadence avoids rapid full-surface flicker.

## 8. Validation Results

All validation used standard Godot 4.7 stable (`4.7.stable.official.5b4e0cb0f`), not Mono/.NET.

| Validation | Result |
| --- | --- |
| Project editor parse/import | PASS |
| `tests/phase_a_water_validation.gd` | PASS |
| `tests/phase7c_validation.gd` — existing liquid/shoreline authority | PASS |
| `tests/phase7b1_validation.gd` — existing save/load contract | PASS |
| `tests/phase3g_validation.gd` — cliff compatibility | PASS (structural; visual acceptance separately inspected) |
| Main scene, real OpenGL renderer, three-frame startup | PASS |
| `git diff --check` | PASS |

Phase A validation covers:

- toggle default and runtime propagation;
- bounded shader controls;
- disabled ordinary-terrain path;
- deterministic spatial calculations at positive and negative positions;
- floor-based negative-coordinate lattice ownership;
- absolute world-position shader contract and absence of screen-space UVs;
- material/elevation edit compatibility;
- no authoritative snapshot or save-format contribution from presentation toggles;
- negative-coordinate streaming;
- chunk unload/reload with stable shared water material and animation state;
- existing shoreline, liquid authority, save/load, and cliff regressions.

No authoritative terrain, terrain generation, elevation semantics, save schema, cliff geometry, shoreline geometry, terrain masks, environmental placement, or water material identity was changed.

## 9. Performance Measurements

Artifact: [`screenshots/phase_a_water_benchmark.json`](screenshots/phase_a_water_benchmark.json)

Real OpenGL compatibility renderer, NVIDIA GeForce RTX 3080, 1280 × 720, identical static water scene, 30 warm-up frames and 180 measured frames per mode:

| Metric | Baseline | Enhanced | Change |
| --- | ---: | ---: | ---: |
| Mean frame time | 1.267 ms | 1.314 ms | +3.69% |
| P95 frame time | 5.023 ms | 4.851 ms | −3.42% |
| Worst observed frame | 9.381 ms | 9.452 ms | +0.76% |
| Mean draw calls | 1.0 | 1.0 | 0 |
| Shader/material count | 8 | 8 | 0 |
| Loaded chunks | 16 | 16 | 0 |
| Pending chunks after sample | 0 | 0 | 0 |
| Last sampled streaming CPU | 0.001 ms | 0.003 ms | +0.002 ms |

All measured wall-frame regressions remain below the 10% target. Toggle changes do not rebuild or reload chunks, add materials, or add draw calls.

Godot 4.7 does not expose a supported `Performance.TIME_GPU` monitor in this project configuration, so reliable GPU frame time was unavailable. The CPU/wall-frame result must not be interpreted as proof that the extra shader branch has zero GPU cost. The process-time monitor was noisy across sequential modes and is retained in the JSON for transparency but not used for the acceptance comparison.

## 10. Remaining Visual Limitations

- The secondary ripple is intentionally subtle; at 0.5× it reads mainly as low-contrast surface variation rather than discrete waves.
- Glint density is uniform in world space and does not account for weather, wind, time of day, or water depth; those systems are outside Phase A.
- Hashing uses the shader's existing float hash. It is deterministic on the tested renderer and coordinates, but extreme world-coordinate precision was not expanded into a new integer-hash system.
- GPU cost could not be isolated with a reliable engine monitor. A platform GPU profiler is required for a definitive GPU timing result.
- Final artistic acceptance remains a human visual decision; automated checks were not used as the sole acceptance basis.

## 11. Recommended Next Steps

1. Review the representative matrix and four-frame sequences in motion order.
2. If desired, tune only the five bounded Phase A controls; do not alter the underlying terrain or shoreline systems.
3. Profile the enabled shader with RenderDoc, Nsight, or the target platform's GPU profiler before enabling it by default.
4. Keep `experimental_water_enhancement_enabled` disabled by default until visual review is signed off.

Phase A stops here. No vegetation work or additional water phase was started.

## Attribution

The adapted technique is documented in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Procedural Almanac is MIT licensed, copyright (c) 2026 Blaiselabs. No JavaScript, Node.js, package, runtime, or network dependency was added.
