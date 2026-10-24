# Wyntar — Phase L2 Zoom-Aware Cliff Shader LOD

Date: 2026-10-24  
Engine: Godot 4.7.2 stable Mono, OpenGL Compatibility  
GPU: NVIDIA GeForce RTX 3080

## Scope and ownership

L2 is a presentation-only extension of the existing cliff shader path. Camera
zoom remains owned by `CameraController`; `Main` forwards zoom events;
`TerrainRenderer` owns the shared cliff materials and computes their presentation
detail; `cliff_procedural.gdshader` renders that detail. `TerrainWorld`, terrain
generation, collision, gameplay state, save formats, the accepted LEGACY cliff
face mesh, and C4J coverage geometry are unchanged.

The worktree already contained uncommitted C4E–C4J, G7, R1–R3, and L1 work.
Those changes were preserved. No reset, discard, commit, push, or unrelated
refactor was performed. LEGACY remains the default cliff mode.

## 1. Existing zoom and shader pipeline

Before L2, `CameraController.zoom_changed` reached `Main` only to update the HUD.
Streaming separately consumed the camera-derived visible rectangle each frame.
The cliff shader's `detail_level` uniform remained at `1.0`, and no zoom event
reached cliff resources.

Cliff resources were already correctly shared:

- four source materials;
- four contact-shadow materials;
- one encoded-source organic mesh material.

Loaded and newly streamed chunks reference those nine resources. This existing
ownership seam permits one constant-cost update per zoom event rather than a
per-frame or per-chunk traversal.

At the L1 baseline, `detail_level` affected weather amplitude, geological cracks,
and dirt erosion streaks. It did not affect source micrograin, reconstructed
one-pixel pigment, fine tone noise, narrow strata joints, or fine crest-lip
variation.

## 2. Implementation

`Main._on_camera_zoom_changed()` now forwards the effective scalar zoom to
`TerrainRenderer.set_cliff_shader_lod_zoom()`. Restored camera state also emits
the same signal, so quick-load/world replacement receives the correct detail
without a separate save-format field.

`TerrainRenderer` computes one continuous detail factor and writes it to the
existing shared materials. It does not inspect loaded chunks, duplicate
materials, rebuild meshes, or touch streaming queues. The current value is also
applied when the renderer creates its shared cliff resources.

The shader now uses the factor to reduce only fine presentation features:

- one-world-pixel source texture grain;
- reconstructed pigment hash detail;
- fine tone noise;
- geological cracks;
- dirt erosion streaks;
- fine weather contrast;
- narrow strata-joint contrast, retaining 55% of the broad bed cue at minimum;
- fine crest-lip variation.

Broad facet groups, macro pigment variation, bed identity, broad rock colour,
shoreline wetness, geometry-role shading, opacity, and silhouette remain.
At `detail_level = 1.0`, the enabled and disabled 100% captures are pixel-identical.

The behavior is reversible through `cliff_shader_lod_enabled`. Disabling it
forces `detail_level = 1.0`, reproducing the pre-L2 fixed-detail rendering without
resource replacement or geometry work.

GRID, UNIFIED, and STYLISED were not given separate behavior. They use the same
shared procedural cliff shader/material owned by `TerrainRenderer`, so the same
presentation-only detail factor safely follows that shared path. Their geometry
selection and mode ownership are unchanged.

## 3. Zoom-to-detail mapping

The configurable defaults are:

| Setting | Default | Meaning |
|---|---:|---|
| `cliff_shader_lod_enabled` | `true` | Enables camera-driven shader detail |
| `cliff_shader_lod_min_zoom` | `0.125` | Detail reaches its lower bound at 12.5% |
| `cliff_shader_lod_full_detail_zoom` | `1.0` | 100% and closer preserve full detail |
| `cliff_shader_lod_min_detail` | `0.20` | Broad structure remains while fine noise is strongly reduced |

For zoom `z`, with far threshold `f`, full-detail threshold `n`, and minimum
detail `m`:

```text
t = clamp((z - f) / (n - f), 0, 1)
eased = t² × (3 - 2t)
detail = lerp(m, 1, eased)
```

This smoothstep curve is continuous and has zero slope at both endpoints.
No discrete tier, material swap, hysteresis, or update threshold is used. The
update happens only on zoom events, and the measured cost is already negligible.

| Camera zoom | Cell size on screen | Detail |
|---:|---:|---:|
| 12.5% | 4 px | 0.200 |
| 25% | 8 px | 0.244 |
| 50% | 16 px | 0.515 |
| 100% | 32 px | 1.000 |
| 175% | 56 px | 1.000 |
| 250% | 80 px | 1.000 |
| 350% | 112 px | 1.000 |

The 100% threshold is justified by preserving the accepted normal view exactly.
The 12.5% minimum corresponds to the measured four-screen-pixel cell view where
one-world-pixel fractures and pigment are well below a stable readable size.
The 25% and 50% captures show a gradual reduction rather than a mode change.

## 4. Visual validation

A deterministic 1280×720 fixture combines dense and broad formations, dirt and
stone faces, three elevations, grass/dirt and stone/sand context, and a direct
water contact. Fourteen matched captures were generated at 12.5%, 25%, 50%,
100%, 175%, 250%, and 350%, with LOD disabled and enabled.

Artifacts:

- Manifest: `.artifacts/l2_cliff_shader_lod_capture_manifest.json`
- Captures: `.artifacts/l2_cliff_shader_lod/`
- Representative 25% pair:
  - [LOD disabled](.artifacts/l2_cliff_shader_lod/l2_disabled_zoom_025.png)
  - [LOD enabled](.artifacts/l2_cliff_shader_lod/l2_enabled_zoom_025.png)
- Representative 50% pair:
  - [LOD disabled](.artifacts/l2_cliff_shader_lod/l2_disabled_zoom_050.png)
  - [LOD enabled](.artifacts/l2_cliff_shader_lod/l2_enabled_zoom_050.png)

Observed results:

- 12.5% and 25% lose most single-pixel speckle and fine fracture contrast.
- 50% retains more geology while reducing fine surface noise.
- broad diagonal strata, macro facets, rock colour, shoreline tint, and level
  separation remain legible;
- grass/dirt, stone/sand, and water contacts remain aligned;
- organic LEGACY silhouettes do not move;
- 100%, 175%, 250%, and 350% enabled/disabled image hashes match exactly;
- changing only the LOD toggle at a fixed camera produces no geometry-count,
  chunk-count, or draw-call change.

The mapping was also sampled monotonically across the transition. Because it is
a smooth polynomial applied to shared uniforms, continuous zoom has no abrupt
state boundary or material replacement that can pop.

## 5. Performance measurements

The graphical benchmark used 120 steady frames for each enabled/disabled state
at 25%, VSync disabled. It measured the shader path rather than claiming a
geometry or streaming benefit.

| Fixture | LOD | Avg frame | P95 | Draw calls | Vertices | Triangles |
|---|---|---:|---:|---:|---:|---:|
| Dense | Disabled | 25.097 ms | 31.238 ms | 4,848 | 79,752 | 39,876 |
| Dense | Enabled | 23.417 ms | 27.290 ms | 4,848 | 79,752 | 39,876 |
| Typical | Disabled | 10.680 ms | 12.655 ms | 1,714 | 35,012 | 17,506 |
| Typical | Enabled | 10.584 ms | 12.933 ms | 1,714 | 35,012 | 17,506 |

The dense timing moved by -6.7% and typical by -0.9%, but these are single
ordered samples with overlapping frame variability and no dedicated GPU timer.
Therefore L2 makes **no performance-improvement claim**. The shader still
evaluates the same broad procedural fields; its demonstrated benefit is visual
clarity.

Confirmed invariant measurements:

- nine shared cliff material resources before and after;
- zero pending chunks after each LOD toggle;
- identical vertices, triangles, faces, and mesh counts before and after;
- identical draw calls within each matched fixture;
- no geometry CPU work during steady toggle samples;
- memory delta about 0.001 MiB, below useful measurement precision;
- 1,000 shared-uniform updates took 2.547 ms total, or 0.002547 ms per update.

The benchmark is `.artifacts/l2_cliff_shader_lod_benchmark.json`.

## 6. Regression results

All runs used bounded Godot 4.7.2 processes.

| Validation | Result |
|---|---|
| L2 mapping/configuration/shared-resource/rollback/streaming test | Pass |
| L2 14-capture matrix | Pass |
| C4E cliff geometry | Pass |
| C4E.1 contour continuity | Pass |
| C4F grid cliffs | Pass |
| C4G renderer modes | Pass |
| C4I ownership/determinism/rollback | Pass |
| C4J full 312-capture matrix | Pass: 0 uncovered pixels after repair; 84,668 before; pixel-exact revisit |
| G1–G7 | Pass |
| R1 camera/streaming | Pass |
| R2 editor/input | Pass |
| R3 configuration | L2 checks pass; exactly five previously documented water-scene failures remain |
| Phase 1G streaming and bounded retirement | Pass |
| Phase 7B.1 save/schema | Pass |
| Fresh-process save | Pass |
| Fresh-process load | Pass |
| Project startup | Pass |
| `git diff --check` | Pass; existing line-ending warnings only |

The C4J matrix covered 13 fixtures × 4 zooms × 3 height profiles × before/after.
It retained zero post-repair uncovered pixels and the pixel-exact streaming
revisit. No coverage gap or silhouette regression was detected.

## 7. Remaining risks

- Frame measurements combine CPU, driver, and GPU work. A GPU capture would be
  needed to make a shader-cost claim.
- The shader reduces amplitudes but does not use derivative-aware filtering.
  Very slow camera motion at extreme overview may still show some residual
  world-pixel shimmer in broad fields.
- The camera permits zoom below 12.5%; detail safely clamps to 0.20, but the L1
  streaming/draw-call scalability risk at extreme zoom remains.
- The five existing R3 water-configuration failures remain intentionally
  separate from L2.

## 8. Recommendation for geometry LOD

Do not proceed directly to cliff-only geometry decimation as a general far-view
solution. L1 showed that distant cost is dominated by visible chunk breadth and
total presentation draw calls, while coherent cliff formations are already
relatively cheap. If a geometry phase is authorised, prototype it only for
high-frequency elevation fields and evaluate it together with an overview
streaming/presentation strategy.

Any later geometry LOD must preserve authoritative terrain ownership, retain the
accepted LEGACY silhouette at replacement boundaries, use asynchronous or
bounded replacement without holes, include hysteresis, and rerun the complete
C4J coverage matrix. L2 should remain the independent reversible shader layer.
