# Phase 3G — Directional cliff visibility and depth

Date: 2026-10-20  
Classification: Existing System Extension  
Disposition: **Bounded alternative demonstrated; visual acceptance NOT achieved. Stop for architectural review.**

## 1. Confirmed diagnosis

The Phase 3F report, both Phase 3E documents, the contour builder, chunk renderer,
incremental job, terrain renderer, main integration, terrain masks and terrain/cliff
shaders were inspected before production changes.

- Top surfaces move upward by `elevation * height_step`. Camera zoom does not
  change this convention; the viewing direction is fixed, not a rotatable 3D camera.
- Phase 3E orients paths with high terrain on the left. It nevertheless extrudes
  **every** path vertically downward, regardless of the low-side normal.
- A crest begins at the threshold's projected position. Wall coverage spans
  from crest minus 2 pixels to crest plus height-step plus 1 pixel. Contact bands
  span height-step minus 3 through height-step plus 1 on qualifying south-facing
  non-shoreline paths. There is no separate unified crest mesh.
- All threshold bands in a square are batched at that square's highest elevation.
  The accepted face layer is `max_elevation * 8 + 3`, while upper surface slots
  are `elevation * 8 + [0..3]`. Thus rear-facing rock can draw over the high surface
  instead of being occluded by it. The extrusion is into the high side for a
  north-facing boundary, and onto the lower side for a south-facing boundary.
- East/west paths have little projected area. Existing midpoint bows and a
  one-pixel degenerate extrusion fallback manufacture some side-facing area.
  These were preserved, not replaced by new corner caps.
- Doubling the profile from 16 to 32 doubles the underlying overlap problem;
  it does not change which side is high.
- Top alpha and cliff geometry are NOT the same contour. The top uses a bilinear
  four-corner field, sinusoidal atlas wobble, and world-space shader noise.
  The cliff uses separately hashed edge crossings, midpoint displacement and
  saddle pairing. Shared samples do not imply identical boundaries.

The supplied request references a user lake screenshot but supplies neither that
image nor its saved cell data/coordinates. **The original lake's elevations cannot
be verified from this task's inputs.** No claim is made that its entire rim was
incorrect. The reproduction fixture explicitly sets water (material 0) to height
0 and sand (material 1) to height 2. A second fixture sets both to height 0.
The latter produces no cliff. No production material/elevation was changed.

## 2. Smallest directional alternative

`Main.directional_cliff_projection_enabled` defaults to false.
`TerrainRenderer.set_directional_cliff_projection_enabled(bool)` schedules
revision-gated replacements and restarts pending stream jobs using existing
mechanisms. Old complete meshes remain visible until replacement commits.
The height default remains 16 and all Phase 3F profiles remain available.

When enabled with unified contours:

1. Keep every existing face vertex and index, including the hidden rear faces.
   There is no directional alpha fade, discarded triangle, narrowed face, new
   cap, or additional node.
2. Put the face batch at `max_elevation * 8 - 1`: below its upper terrain but
   above lower terrain. Upper surfaces now actually occlude covered rock.
3. For each local contour piece `d`, derive the low-side normal
   `n = normalize((d.y, -d.x))`. Existing vertex shading receives
   `0.84 + 0.12 * max(0, n.y) + 0.02 * n.x`.
   This favours south-facing faces and distinguishes east from west.
4. Preserve absolute-world geological shader coordinates, crest/toe positions,
   existing contact-band opacity and all batching.

Projected area naturally scales with height and the contour's horizontal extent.
Vertical side paths are foreshortened; rear-facing faces are mostly hidden by high
terrain; south-facing faces retain their full height. Curvature is evaluated on
the existing two local path pieces, not a new contour traversal. Adjacent height
thresholds retain Phase 3E's maximum-elevation batching.

This is deliberately an **occlusion/shading alternative**, not a new geometrically
complete directional clipping model. Per-piece shading is not a smooth-normal
solver. Mixed-height occlusion still lacks per-fragment ownership.

## 3. Files changed in Phase 3G

Production:

- `scripts/main.gd` — disabled inspector setting and runtime replacement preservation.
- `scripts/terrain_renderer.gd` — setting ownership, rebuild scheduling, job configuration.
- `scripts/terrain_chunk_build_job.gd` — immutable setting forwarded to incremental builder.
- `scripts/terrain_chunk_renderer.gd` — complete-batch depth policy and synchronous configuration.
- `scripts/organic_cliff_mesh_builder.gd` — deterministic direction-derived vertex shading.

Evidence:

- `tests/phase3g_validation.gd`
- `tests/phase3g_capture.gd`
- `tests/phase3g_benchmark.gd`
- This report.
- `screenshots/phase3g_{baseline,prominent,directional}_manifest.json`
- 135 PNGs, 45 per mode, under `screenshots/phase3g_*`.
- `screenshots/phase3g_benchmark_graphical.json`

Pre-existing Phase 3F changes, unrelated untracked content, `_reference`, scene
defaults and historical logs were not reverted. No terrain-mask or shader source
was changed in Phase 3G.

## 4. Matched visual evidence

Seed 84521, 1280x720, fixed fixture/camera positions, zooms 1x, 2.31x and 3x.
Liquid animation is frozen in the capture harness. UI, decorations and objects
are hidden equally. Captures wait for replacements and retiring chunks.

The 15 fixtures cover recessed sand lake, equal-height lake, grass plateaus of
one/two levels, three-level stone enclosure, rear- and front-facing diagonals,
winding contours, convex/concave corners, narrow ridges, isolated formations,
mixed heights, snow, and positive/negative chunk boundaries. High-zoom captures
are detail views; some full formations extend outside the viewport.

Primary before/after, both at 32 pixels and 2.31x:

![Phase 3F lake](G:/Sim/universal_mask_terrain_godot47/screenshots/phase3g_prominent_recessed_sand_lake_2_31x.png)

![Directional lake](G:/Sim/universal_mask_terrain_godot47/screenshots/phase3g_directional_recessed_sand_lake_2_31x.png)

Other review pairs:

| Subject | Phase 3F prominent | Directional alternative |
| --- | --- | --- |
| Rear diagonal | [Before](screenshots/phase3g_prominent_long_diagonal_escarpment_2_31x.png) | [After](screenshots/phase3g_directional_long_diagonal_escarpment_2_31x.png) |
| Front diagonal | [Before](screenshots/phase3g_prominent_south_facing_diagonal_2_31x.png) | [After](screenshots/phase3g_directional_south_facing_diagonal_2_31x.png) |
| Mixed heights | [Before](screenshots/phase3g_prominent_mixed_height_junctions_2_31x.png) | [After](screenshots/phase3g_directional_mixed_height_junctions_2_31x.png) |
| Stone enclosure | [Before](screenshots/phase3g_prominent_three_level_cliff_2_31x.png) | [After](screenshots/phase3g_directional_three_level_cliff_2_31x.png) |
| Default lake | [16-pixel baseline](screenshots/phase3g_baseline_recessed_sand_lake_1_0x.png) | [32-pixel alternative](screenshots/phase3g_directional_recessed_sand_lake_1_0x.png) |

Visual assessments, separate from structural verification:

- The lake's near-bank thick rim is substantially reduced, with a substantial
  far-bank wall retained. Bank position is not wall orientation: the far bank
  faces south into the lake; the near bank faces north.
- Enclosed stone cliffs retain a substantial southern wall without the full
  raised northern border.
- The mirrored front-facing diagonal retains a continuous substantial wall;
  the same cannot be achieved for the rear-facing diagonal by a depth-layer
  adjustment. Snow shows the retained southern wall particularly clearly.
- Rear-facing diagonals are largely occluded, but their remaining slivers can
  look broken and do not communicate height convincingly.
- Mixed heights and signed-seam fixtures still reveal narrow triangular/brown
  slivers where top alpha and cliff contours disagree. The visible breaks are
  not evidence of missing wall triangles; the triangles remain behind the top.
- No obvious exposed background was seen in the reviewed captures. This is
  **not a proof** of pixel-watertight coverage or absence of hidden intersections.
  Comparing unchanged mesh coordinates proves only that this alternative does
  not remove coverage or introduce new geometric inversions.

## 5. Validation

Godot 4.7 stable (`5b4e0cb0f`):

- Phase 1B, 1D, 1E, 1F, 1G: pass. No Phase 1C validation script exists.
- Phase 3C, 3D, 3E, 3F: pass.
- Phase 7A, 7C.4, 7C.5: pass.
- New Phase 3G structural suite: pass.
- Main integration parses and executes through the capture and existing runtime suites.
- `git diff --check`: pass (pre-existing LF/CRLF conversion warnings only).

Dedicated checks cover compass/diagonal shading, equal-height lake rejection,
deterministic mixed-height regeneration, unchanged full vertex/index coverage,
crest/toe and signed-edge coordinates, repeated runtime toggles/rollback,
unchanged projected brush polygons and picking, and elevation edit/restoration
under the enabled mode. Source coordinates and indices are compared directly
against Phase 3F, not merely counted. No claim is made that these checks validate
the mismatched rasterized top silhouette or manually exercise every editor gesture.

## 6. Performance

Same Phase 1G dense fixture, seed, camera and 1280x720 viewport; Godot 4.7
Compatibility renderer on NVIDIA GeForce RTX 3080. Three streaming runs and
720 steady frames per mode, with vsync disabled. These are local measurements,
not a statistical performance guarantee.

| Metric | Phase 3F 16 px | Phase 3F 32 px | Directional 32 px |
| --- | ---: | ---: | ---: |
| Mean steady frame, ms | 2.787 | 2.946 | 2.934 |
| P95 steady frame, ms | 3.937 | 4.201 | 3.860 |
| Mean streaming frame, ms | 5.477 | 5.606 | 5.586 |
| Mean total streaming CPU/run, ms | 369.882 | 374.140 | 376.756 |
| Worst incremental geometry frame, ms | 3.868 | 3.571 | 3.398 |
| Mean streaming draw calls/frame | 537.46 | 543.05 | 544.21 |
| Vertices | 34,760 | 34,760 | 34,760 |
| Triangles | 17,384 | 17,384 | 17,384 |
| Mesh nodes | 40 | 40 | 40 |

Relative to matched Phase 3F prominent, directional mean frame is -0.42%, P95
is -8.12%, streaming CPU is +0.70%, and streaming draw calls are +0.21%.
The geometry count is unchanged; draw-call means vary slightly with the
number/timing of streaming frames, not a new batching policy. All measured
regressions are below 10% (also against the 16-pixel mode). The principal cost
trade-off is keeping occluded wall geometry rather than adding a clipping system.
The measured differences are too small/noisy to claim an optimisation.

Reproduction scripts:

- `--headless --script res://tests/phase3g_validation.gd`
- `--script res://tests/phase3g_capture.gd -- baseline` (then `prominent`, `directional`)
- `--script res://tests/phase3g_benchmark.gd`

Run with the repository as the Godot project path. Full raw metrics are in
`screenshots/phase3g_benchmark_graphical.json`; manifests record every capture.

## 7. Ownership and stop condition

TerrainWorld alone owns authoritative elevations/materials. The existing editor
mutation APIs remain authoritative; the capture harness writes only controlled
in-memory fixtures. TerrainRenderer owns the presentation setting, jobs read
immutable halo snapshots, and chunk renderers own disposable batches. The setting
is not serialized into authoritative saves. No generator, save format, gameplay,
world-scale traversal, per-segment node, LOD or overhang system was introduced.

**Do not promote this toggle or the prominent profile to defaults.** The visual
definition of done is not met: directional depth is improved, but slivers, corner
points and weak rear-facing height cues remain. A global layer shift cannot make
independently generated top masks and rock contours share one exact crest, nor
resolve every mixed-height overlap.

The smallest feasible alternative is preserved here for review, with Phase 3F
available by disabling the toggle. The requested stop condition is invoked
instead of changing mask generation, terrain depth ownership or camera projection
without an approved design.

Recommended next milestone: architect review of a shared top-surface/cliff
boundary and a bounded mixed-height occlusion policy, using these fixtures as
acceptance cases. Request the original lake save/coordinates to validate that
specific elevation/material relationship. No Phase 3H implementation has begun.
