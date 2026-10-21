# Phase G1 — Deterministic Clustered Grass Detail Report

Date: 2026-10-21

Task classification: Existing System Extension — Procedural Terrain Surface Rendering

Starting branch and commit: `main` at `45d5b25` (`Phase C4C: evaluate cliff rendering baselines`)

## 1. Files changed

- `scripts/main.gd`
  - Adds exported clustered-grass presentation controls and passes them to every renderer before `_ready()`.
- `scripts/terrain_renderer.gd`
  - Owns the runtime visual settings and updates the one shared grass material without chunk invalidation.
- `scripts/terrain_surface_factory.gd`
  - Initializes grass-only shader parameters while explicitly leaving every non-grass material on the legacy branch.
- `scripts/terrain_catalog.gd`
  - Marks grass as the sole eligible terrain and records the source-art luma threshold and clear palette colour.
- `shaders/terrain_variation.gdshader`
  - Adds deterministic, low-frequency world-space clustering and grouped dark-mark retention.
- `tests/phase_c4a_renderer_configuration_validation.gd`
  - Extends startup and save-world renderer-replacement coverage to the new visual preferences.
- `tests/phase_g1_validation.gd` and `.uid`
  - Adds focused determinism, coverage, density, softness, rollback, isolation and recreation validation.
- `tests/phase_g1_capture.gd` and `.uid`
  - Adds the reproducible 12-image comparison matrix and a small matched graphical benchmark.
- `PHASE_G1_CLUSTERED_GRASS_DETAIL_REPORT.md`
  - Records implementation, evidence and limitations.

The pre-existing C4D validator/report work, modified `main.tscn`, dirty `_reference` gitlink checkout, and unrelated pager artifact were preserved.

## 2. Root cause of the current visual noise

The dense high-frequency pattern primarily comes from `art/grass.png`. Approximately ten percent of its 32×32 pixels use the repeated dark-blade palette, and every grass tile repeats that layout. All four grass visual variants reuse the same source texture with colour adjustments, so tint variation changes colour but not mark placement. Ground-decoration tufts and environmental vegetation add larger readable objects, but they are not the source of the uniform pixel noise across nearly every grass cell.

The existing terrain shader already has absolute world position and one shared material per terrain type. That makes a grass-only shader branch the smallest architecture-preserving place to vary which existing dark marks survive. No atlas, tile, decoration or chunk data needs to be regenerated.

## 3. Chosen implementation approach

The terrain surface shader now performs two deterministic grass-only decisions:

1. Smooth value noise at a low world-space frequency divides the meadow into broad clear, transition and dense regions.
2. Existing dark source-texture marks receive one deterministic retention roll per 4×3 world-pixel group. Suppressed marks are replaced by the catalogued clear grass colour while retaining the active tint/variation delta.

This preserves small irregular source-art clusters instead of drawing new single-pixel noise. The transition is continuous and does not follow tile or chunk boundaries. The disabled branch reaches the previous `surface_rgb` path without changing it, so the source atlas and legacy algorithm remain intact.

Only grass opts into the branch. Dirt, sand, rock, water, snow, mud, gravel and cliffs keep their prior shader/material paths.

## 4. New configurable parameters

| Parameter | Default | Precise meaning |
| --- | ---: | --- |
| `clustered_grass_detail_enabled` | `true` | Enables the grass-only mark-retention branch. `false` uses the previous appearance. |
| `grass_clear_area_coverage` | `0.70` | Percentile-like threshold on the smooth cluster field. Approximately this share of a large representative grass sample is assigned to the sparse side of the field. It is not guaranteed per viewport. |
| `grass_detail_density` | `0.35` | Maximum retention probability for dark marks already present in the grass texture inside dense regions. It is not 35% coverage of all grass pixels. |
| `grass_cluster_scale` | `0.004` | World-pixel sampling frequency. Lower values produce larger regions; higher values produce smaller regions. |
| `grass_transition_softness` | `0.12` | Width around the clear/dense threshold over which retention probability blends gradually. |
| `grass_clear_area_residual_density` | `0.04` | Retention probability for existing dark marks in fully clear regions, preventing perfectly flat grass. |
| `grass_detail_seed_offset` | `48131` | Visual-only salt combined with the world seed to move the cluster and retention distributions deterministically. |

The representative validation sample measured `72.8%` of points below the 70% clear threshold. The difference is expected because smoothed value noise is only approximately percentile-distributed.

## 5. Determinism strategy

- Cluster noise samples `floor(world_position)`, never screen position, camera state, local chunk coordinates, time or mutable RNG state.
- The world seed and configurable detail seed are combined into fixed shader offsets.
- Existing marks are retained in deterministic 4×3 world-pixel groups so their placement is stable under camera movement and zoom.
- The high-frequency roll is bounded onto paired prime-period lattices before the sine hash. This avoids 32-bit Compatibility-shader precision collapse at large world coordinates. Its repeat periods are approximately 8,156 world pixels horizontally and 6,087 vertically; the independent low-frequency cluster field prevents the full appearance from repeating at that interval.
- Chunk seam validation reconstructs the same positive and negative shared coordinates from either neighboring chunk and receives the same field value.

Exact GPU pixels are expected to remain stable on the same renderer/driver. As with the existing float-based terrain variation shader, bit-identical output across unrelated GPU architectures is not guaranteed.

## 6. Chunk streaming and configuration integration

The system uses the existing shared grass `ShaderMaterial`; it creates no per-cell nodes, per-chunk textures or per-mark draws. Camera movement, retirement, recreation and chunk rebuilding all sample the same absolute world coordinates.

`Main._configure_terrain_renderer()` applies all seven controls before renderer initialization at startup and before save-world replacement. C4A validation confirms the replacement receives the same visual configuration. The settings are presentation preferences, so they are deliberately absent from `export_generation_config()` and the save schema remains unchanged.

Runtime setter calls update the shared grass material without invalidating streamed chunks. Renderer retirement releases the material normally, and recreation produces an equivalent parameter signature.

## 7. Performance findings

Matched graphical sample: Godot 4.7 Compatibility renderer, NVIDIA GeForce RTX 3080, seed `84521`, 1280×720, fixed fixture/camera, 360 measured frames per mode.

| Mode | Mean | P95 | P99 | Worst | Mean draw calls | Static memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Legacy branch | 3.845 ms | 7.656 ms | 27.502 ms | 40.262 ms | 172.0 | 57.27 MiB |
| 70% clear / 35% density | 3.785 ms | 8.030 ms | 15.755 ms | 19.228 ms | 172.0 | 57.27 MiB |

This short run demonstrates unchanged draw-call count and effectively unchanged static memory. Frame samples contain unrelated scheduling spikes and are too close/noisy to claim either an improvement or regression. The shader adds a small number of calculations only for grass fragments; it performs no per-frame allocation or texture regeneration.

## 8. Regression test results

All Godot processes used explicit 120-second timeouts; the graphical capture/benchmark used 240 seconds.

| Check | Result |
| --- | --- |
| Full project import and script parse | PASS; no script/import failure |
| Main-scene graphical startup | PASS |
| Phase G1 focused validator | PASS |
| C4A renderer configuration/replacement validator | PASS |
| C4B renderer factory validator | PASS |
| Phase 5D terrain/chunk validator | PASS |
| Phase A water validator | PASS |
| Phase 3G cliff structural validator | PASS |
| Phase 6A decoration validator | PASS |
| Phase 6B environmental-object validator | PASS |
| Phase 7B.1 save/load validator | PASS |
| Phase G1 graphical capture | PASS; 12 distinct PNGs |
| `git diff --check` | See final hand-off result |

The editor import emitted only the known non-fatal isolated settings safe-save warning and nested `_reference/project.godot` warning.

Focused coverage verifies identical seed/coordinate output, different seed offsets, positive and negative seam continuity, retirement/recreation consistency, approximate 70% coverage, monotonic density, wider transitions with increased softness, unchanged legacy atlas under rollback, non-grass isolation, renderer replacement, and save-schema isolation.

## 9. Comparison screenshot locations

All generated files are ignored under `.artifacts/`.

| Configuration | 1.0× | 2.31× |
| --- | --- | --- |
| Existing appearance | `.artifacts/g1_legacy_seed84521_z1_0x.png` | `.artifacts/g1_legacy_seed84521_z2_31x.png` |
| 70% clear / 35% density | `.artifacts/g1_clear70_density35_seed84521_z1_0x.png` | `.artifacts/g1_clear70_density35_seed84521_z2_31x.png` |
| 50% clear / 35% density | `.artifacts/g1_clear50_density35_seed84521_z1_0x.png` | `.artifacts/g1_clear50_density35_seed84521_z2_31x.png` |
| 85% clear / 35% density | `.artifacts/g1_clear85_density35_seed84521_z1_0x.png` | `.artifacts/g1_clear85_density35_seed84521_z2_31x.png` |
| 70% clear / 15% density | `.artifacts/g1_clear70_density15_seed84521_z1_0x.png` | `.artifacts/g1_clear70_density15_seed84521_z2_31x.png` |
| 70% clear / 60% density | `.artifacts/g1_clear70_density60_seed84521_z1_0x.png` | `.artifacts/g1_clear70_density60_seed84521_z2_31x.png` |

The shared fixture contains deterministic trees, bushes, ground tufts, rocks, resource objects, and grass boundaries against dirt, stone and sand. The manifest and performance data are in `.artifacts/g1_capture_manifest.json`.

## 10. Recommended default settings

Retain the requested experimental defaults:

- Enabled: `true`
- Clear-area coverage: `0.70`
- Detail density: `0.35`
- Cluster scale: `0.004`
- Transition softness: `0.12`
- Clear-area residual density: `0.04`
- Detail seed offset: `48131`

The 70/35 comparison gives substantially more breathing room while retaining visible dense regions and isolated marks. The 50% coverage option remains noticeably busy, while 85% approaches an overly uniform surface. At fixed 70% coverage, 15% density makes dense regions too faint and 60% begins to recreate the original noise within those regions.

## 11. Remaining limitations

- Grass mark recognition depends on the catalogued source-art luma threshold and clear colour. Replacing `art/grass.png` with a materially different palette should include retuning those two metadata values.
- Coverage is statistical over broad terrain, not exact inside small camera views.
- The high-frequency retention lattice has a large finite period; the independently varying cluster field limits visible repetition but does not make the retention hash mathematically aperiodic.
- Shader-level float noise is deterministic for stable coordinates and renderer conditions, but exact cross-GPU bit identity is not guaranteed.
- Visual acceptance remains subjective. The implementation and requested target are available, but the generated comparisons should be reviewed before treating the experimental defaults as a permanent art baseline.

No authoritative terrain, biome, elevation, collision, picking, streaming ownership, save schema, cliff, water, runtime art asset, `main.tscn`, `_reference`, Git history or remote state was changed.
