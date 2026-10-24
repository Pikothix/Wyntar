# Wyntar — Phase L1 Cliff Rendering and Zoom/LOD Investigation

## Executive recommendation

**Recommendation: boundary correction first, shader LOD second, geometry LOD third.**

The current cliff renderer has no active zoom-driven LOD. Camera zoom changes the visible world rectangle and therefore the number of streamed chunks, but it does not reach cliff materials or mesh construction. The cliff shader has a reserved `detail_level` uniform, yet no runtime code sets it; it stays at its default `1.0`. Geometry is generated at one fixed detail level per enabled cliff mode.

The existing surface-to-cliff boundary mismatch is more important than LOD. It causes the isolated-elevation diamond, detached rims, narrow side slivers, visible gaps, and conspicuous water-contact failures. Shader fading can reduce distant noise, but it cannot make inconsistent boundaries agree. Geometry simplification before boundary ownership is corrected would create a second set of silhouettes that must later be reconciled.

After boundary correction, a material-only LOD is the smallest safe improvement: preserve broad colour/facets and major geological beds, continuously fade cracks, one-pixel pigment reconstruction, micrograin, and small erosion/weather marks. This can reuse and extend the existing shared-material control path without rebuilding meshes.

Geometry LOD is not the first performance lever. At 12.5% zoom, the measured natural view contained 32,448 cliff triangles but approximately 7,047 total draw calls and averaged 34.608 ms/frame. The dominant far-view scaling problem is that the visible/wanted chunk rectangle grows with inverse zoom and every chunk retains the full set of TileMap/presentation layers. A cliff-only topology reduction would help pathological dense elevation fields and build CPU, but would not by itself solve far-zoom draw submission or streaming breadth.

## Scope, repository state, and evidence labels

The investigation used the authoritative working tree at `G:\Sim\universal_mask_terrain_godot47`, Godot 4.7.2 Compatibility, and the current uncommitted C4E–C4F, R1–R3, and G7 work. No rendering, generation, shader, scene, save, or runtime configuration was changed. A temporary measurement harness exercised existing code and produced `.artifacts/l1_cliff_lod_measurements.json` plus two distant-view captures. The temporary harness is not part of the deliverable.

The initial working tree was already dirty. Notable existing changes included `main.tscn`, `project.godot`, the requested renderer/builder scripts, `terrain_variation.gdshader`, multiple validation scripts, and prior phase reports. Those changes were preserved.

This report uses these labels:

- **Confirmed — source:** directly traced in the current Wyntar or external-reference source.
- **Confirmed — measured:** observed in the recorded Godot 4.7.2 run on the current machine.
- **Confirmed — visual:** observed in the captured output.
- **Inference:** a recommendation or likely consequence that was not directly measured.

## 1. Current LOD capability inventory

| Capability | Current state | Evidence |
|---|---|---|
| Camera zoom range | `0.001` to `166.0`, multiplicative wheel steps of `1.15` | Confirmed — source, `camera_controller.gd` |
| Cursor-centred zoom | Zoom preserves the world point under the pointer | Confirmed — source |
| Zoom-to-streaming | Main recomputes the camera-visible world rectangle every frame and passes it to `TerrainRenderer` | Confirmed — source |
| Zoom-to-cliff-material | Absent | Confirmed — source |
| Cliff shader detail control | `detail_level` exists, defaults to `1.0`, and affects only three detail families | Confirmed — source |
| Runtime `detail_level` updates | None found in renderer, factories, settings, scenes, or tests | Confirmed — source |
| Shader LOD transition | None | Confirmed — source |
| Cliff geometry LOD | None | Confirmed — source |
| Geometry rebuild on every zoom step | No; only visibility bounds are recomputed | Confirmed — source |
| Geometry creation when zooming out | Yes, for newly wanted chunks | Confirmed — source and measured |
| Chunk retirement when zooming in | Yes, outside the unload margin, through a bounded retirement queue | Confirmed — source and measured |
| Other Wyntar material LOD | None found | Confirmed — source |
| Environment-object LOD | None found; objects are globally batched by elevation, with visibility as an all-or-nothing switch | Confirmed — source |
| LOD diagnostics | Geometry/build counters exist; GPU frame time is unavailable in the current harness | Confirmed — source and measured |

The existing `detail`-named controls in `terrain_variation.gdshader` are content/style switches, not camera LOD. They are not driven by zoom and use fixed world-pixel fields. Environmental objects similarly have no distance or zoom tier.

## 2. Zoom-to-renderer data flow

```text
wheel input
  -> CameraController.zoom_toward_screen_point()
     -> Camera2D.zoom and position change
     -> zoom_changed(float)
        -> Main._on_camera_zoom_changed()
           -> HUD label only

every Main._process()
  -> CameraController.get_visible_world_rect()
  -> TerrainRenderer.update_visible_world_rect()
     -> visible chunk rectangle
     -> wanted rectangle (+ load margin)
     -> unload rectangle (+ unload margin)
     -> create/discard/reorder chunk jobs

No branch forwards zoom to:
  cliff ShaderMaterial -> detail_level
  TerrainChunkBuildJob -> geometry density
  OrganicCliffMeshBuilder -> contour/profile resolution
```

### What happens when the camera zooms

**Confirmed — source:** `CameraController` changes `Camera2D.zoom`, adjusts position to keep the pointer anchor stable, forces scroll update, and emits `zoom_changed`. `Main` receives the signal only to update the HUD. Independently, `Main._process()` computes the visible world rectangle every frame. `TerrainRenderer.update_visible_world_rect()` returns early if the visible chunk minimum and maximum are unchanged.

When the chunk bounds do change, the renderer:

1. Computes visible, load-margin, and unload-margin rectangles.
2. Rebuilds `_visible_chunks` and `_wanted_chunks` dictionaries.
3. Hides/removes loaded chunks outside the unload rectangle and queues incremental retirement.
4. Cancels jobs outside the wanted rectangle.
5. Creates jobs for wanted but unloaded chunks.
6. Prioritises visible jobs, then distance to the visible centre.

### Does zoom regenerate cliffs unnecessarily?

**Confirmed — source:** changing zoom inside the same visible chunk bounds does not rebuild geometry. This was also observed at 350%, 200%, and 100% zoom: the same 16 loaded chunks and 12,484 vertices remained, and transitions settled in one frame with effectively no streaming CPU.

**Confirmed — source:** zooming out legitimately creates full-detail geometry for newly wanted chunks because there is no coarser representation. Zooming in retires only chunks outside the larger unload margin; hysteresis deliberately retains others. This avoids boundary flapping but can leave more loaded geometry than the current wanted set.

**Measured example:** after zooming from 12.5% to 50%, 56 chunks were retired, but 48 remained loaded for 24 wanted chunks. Subsequent 100% and 350% views still retained 36 chunks for 16 wanted chunks because they remained inside the unload rectangle.

## 3. Existing shader detail controls and shader LOD feasibility

### Current cliff shader feature map

| Feature | Current implementation | Controlled by `detail_level`? | Recommended far-distance behaviour |
|---|---|---:|---|
| Broad source colour | Dirt/stone source pigment, optional reconstructed base | No | Keep |
| Broad colour regions | Macro noise at `0.018` scale and large rotated facet field | No | Keep; optionally reduce contrast slightly only at extreme overview |
| Geological strata | World-space warped beds, roughly 11–21 world pixels thick, with fault offsets and broken sections | No | Keep major bed identity; soften narrow bed joints as they become sub-pixel |
| Broad facets | World-space plane groups | No | Keep; they preserve rock mass/readability |
| Fine tone/grain | `fine` noise at `0.071`, source texture micrograin, and reconstructed per-pixel hash | No | Fade first |
| Fine cracks/fractures | Rare 0.65–1.15 world-pixel geological cracks | Yes | Fade first; already wired to the uniform |
| Dirt erosion streaks | Fine/macro thresholded streaks | Yes | Fade first; already wired |
| Weathering variation | Macro weather field | Partly | Retain broad wet/dry regions; fade only small contrast variation |
| Shore wetness | Macro wet patches | No | Keep broad shoreline cue; do not erase water contact identity |
| Rim/side/shadow roles | Encoded geometry-role shading | No | Keep; these carry silhouette and depth |

`detail_level` currently does exactly three things:

- blends weathering from neutral to the macro weather field;
- scales stone cracks;
- scales dirt erosion streaks.

It does **not** suppress the shader's fine contribution to tone, texture-detail reconstruction, source micrograin, geological bed joints, fine role shading, or any geometry. The existing uniform is therefore reusable as the first control but insufficient as a complete shader LOD.

### Aliasing and visual noise

**Confirmed — source:** the shader quantises to `floor(world_position)`, uses nearest-filtered repeating textures, creates one-world-pixel hash detail, and has no `fwidth`, derivative-aware filtering, or screen-footprint control. Cracks are close to one world pixel wide. These features become sub-pixel below 100% zoom and cannot be temporally or spatially stable in screen space even though their world coordinates are deterministic.

**Confirmed — visual:** `.artifacts/l1_cliff_zoom_0_25.png` and `.artifacts/l1_cliff_zoom_0_125.png` show world-locked large forms, but fine pigment becomes dense single-pixel speckle. At 12.5%, many cliff faces reduce to thin dark contours; narrow cracks and strata appear intermittently rather than as readable geology. Camera motion was not captured as video, so temporal shimmer is a strong source-based inference rather than a directly measured motion result.

### Recommended shader transition

Use one continuous material detail factor shared by all cliff materials. Derive it from projected world-pixel or projected cell size, clamp it, and apply a smooth transition with no discrete material swap. The exact thresholds should be selected by capture review, not hard-coded from this investigation.

Suggested ordering:

1. Fade reconstructed one-pixel pigment hash and source micrograin.
2. Fade cracks and small erosion fractures using the existing `detail_level` path.
3. Fade narrow weather streaks and fine tone noise.
4. Antialias or soften the narrow edge of strata while retaining broad bed identity and tint.
5. Preserve broad facets, broad colour regions, shoreline wetness, rim shading, and the cliff silhouette.

World-space sampling should remain unchanged so details do not swim during pan/zoom. Only their amplitude/edge width should respond continuously to projected footprint. This preserves pixel-art readability: distant cliffs should read as a few stable value groups, not as averaged grey noise.

## 4. Geometry and performance measurements

### Method

- Godot 4.7.2 stable, Windows display server, OpenGL Compatibility, NVIDIA RTX 3080.
- 1280×720 viewport, VSync disabled.
- Current production cliff path from `main.tscn`: organic geometry, unified components, refined silhouettes, connected and unified contours, directional projection, prominent 32 px height step, grid-aligned C4F prototype disabled.
- Decoration and environment-object generation disabled to focus the streaming run on terrain/cliffs.
- Fixture build time is the median of seven synchronous calls to the existing `OrganicCliffMeshBuilder` for one 32×32 chunk.
- Frame time is process-frame wall time, matching the project's existing benchmarks. It is not a dedicated GPU timer.
- Draw calls are Godot's total draw-call monitor and include all visible terrain/water/cliff presentation, not cliffs alone.
- Full machine-readable results: `.artifacts/l1_cliff_lod_measurements.json`.

### Single-chunk geometry cases

| Fixture | Description | Vertices | Triangles | Faces | Mesh surfaces | Median build |
|---|---|---:|---:|---:|---:|---:|
| Sparse | Four isolated level-1 cells | 192 | 96 | 16 | 1 | 2.823 ms |
| Dense elevation changes | Repeating 0–3 height field | 36,624 | 18,312 | 3,479 | 3 | 102.008 ms |
| Large continuous formation | 24×24 level-2 plateau | 1,560 | 780 | 192 | 1 | 8.643 ms |
| Multi-level | Nested level-1/2/3 terraces | 1,780 | 890 | 216 | 3 | 11.119 ms |
| Shoreline | Level-2 stone formation beside water | 960 | 480 | 144 | 1 | 5.963 ms |

**Confirmed — measured:** cost follows boundary complexity much more strongly than occupied area. The dense alternating-height case emitted about 23.5 times as many triangles as the large continuous formation and took about 11.8 times as long to build. Large coherent plateaus are cheap because only their exposed boundary contributes cliff faces.

The fixture builder reports one mesh surface per occupied render elevation, so cliff mesh draw-call potential is already batched well. The current builder emits two vertices per triangle in these tested unified-contour results because quads are independently expanded rather than vertex-shared; changing that would be a separate mesh-format optimisation, not LOD.

### Natural terrain across zoom

These figures are one measured outward-and-return sequence. Timing is environment-sensitive; topology and chunk counts are deterministic for the recorded state.

| Zoom | Cell on screen | Visible / wanted / loaded chunks | Cliff vertices / triangles | Avg total draws | Steady avg / p95 | Zoom-transition work |
|---:|---:|---:|---:|---:|---:|---:|
| 350% | 112 px | 4 / 16 / 16 | 12,484 / 6,242 | 14 | 0.783 / 1.356 ms | 1 frame; no creation |
| 200% | 64 px | 4 / 16 / 16 | 12,484 / 6,242 | 22 | 0.715 / 0.894 ms | 1 frame; no creation |
| 100% | 32 px | 4 / 16 / 16 | 12,484 / 6,242 | 119 | 1.069 / 1.448 ms | 1 frame; no creation |
| 50% | 16 px | 8 / 24 / 24 | 15,796 / 7,898 | 454 | 2.481 / 3.767 ms | 79 frames; 159.837 ms streaming CPU |
| 25% | 8 px | 24 / 48 / 48 | 29,016 / 14,508 | 1,895 | 10.216 / 13.833 ms | 243 frames; 510.841 ms streaming CPU |
| 12.5% | 4 px | 66 / 104 / 104 | 64,896 / 32,448 | 7,047 | 34.608 / 41.790 ms | 579 frames; 1,229.533 ms streaming CPU |

At 12.5%, visible chunks were incomplete until frame 177 of the transition. The worst sampled transition frame was 86.483 ms. The scheduler bounded its own worst chunk-processing frame to 4.251 ms in this run, but total frame time was dominated by the much larger visible presentation workload. This separates the measured costs as follows:

- **CPU geometry/stream preparation:** explicitly measured by the renderer's counters; 1,229.533 ms accumulated while expanding from 48 to 104 chunks at 12.5%.
- **CPU/GPU presentation combined:** process-frame wall time rose to 34.608 ms steady and draw calls to 7,047. The available monitor cannot split driver submission from GPU execution.
- **GPU time:** unavailable; no value is invented.
- **Memory:** the harness did not produce a clean cliff-only allocation delta, so no memory claim is made.

### Chunk creation and retirement

Zooming outward increased wanted/loaded chunks from 16 to 24, 48, and 104. The scheduler created full-resolution chunk data and cliff geometry for each newly wanted chunk. Zooming back from 12.5% to 50% queued 56 retirements at once; incremental retirement drained them over 225 frames with 1.990 ms total measured retirement CPU. Zooming from 50% to 100% retired another 12 chunks over 45 frames with 0.384 ms retirement CPU.

The unload margin intentionally retained 48 loaded chunks for 24 wanted chunks at 50%, then 36 loaded for 16 wanted chunks at 100%. This hysteresis reduces churn, but it also preserves geometry memory after a far overview.

### Far-zoom scalability

**Confirmed — measured:** far zoom is expensive. Chunk demand grows roughly with visible world area, or approximately `1 / zoom²`, until rounding and margins dominate. At the camera's allowed minimum `0.001`, a 1280×720 viewport theoretically spans about 1,250×704 chunks before margins—roughly 880,000 visible chunks. That state is not practical and was not executed.

The save validator accepts only 0.1–10.0 while the live camera accepts 0.001–166.0. This mismatch is not itself an LOD implementation, but the extreme live minimum exposes an unbounded streaming-risk surface.

### Would geometry LOD provide meaningful benefits?

**Yes, but selectively and not first.** It would materially reduce build CPU for high-frequency elevation fields, where one chunk reached 18,312 triangles and 102.008 ms synchronous build time. It could also reduce some far-view cliff vertices.

It would not solve the principal measured far-view bottleneck on its own:

- 32,448 cliff triangles at 12.5% are modest for the GPU class tested.
- 7,047 total draw calls and 104 wanted chunks are disproportionate to that triangle count.
- TileMap layers, water/surface passes, and per-elevation presentation remain even if cliff contours are simplified.
- Changing geometry detail requires safe replacement/hysteresis and must not reopen boundary gaps.

Geometry LOD should therefore be evaluated only after boundary unification and shader LOD, and together with a broader overview/streaming representation or draw-call strategy.

## 5. Comparison with Cartoon Terrain Studio

The external review used repository commit [`7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1`](https://github.com/idlerunner00/cartoon-terrain-studio/tree/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1). Cartoon Terrain Studio is a separate 2.5D C#/Godot renderer and is **not** assumed to contain Wyntar/Pixkrieg code.

### Verified source behaviour

- [`docs/ARCHITECTURE.md`](https://github.com/idlerunner00/cartoon-terrain-studio/blob/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1/docs/ARCHITECTURE.md) separates engine-free terrain/chunk/bake logic from Godot scene upload. It uses 28×28-cell bake tiles and 32×32-cell endless-world chunks, with worker-thread generation.
- [`TerrainGeometryDetail.cs`](https://github.com/idlerunner00/cartoon-terrain-studio/blob/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1/src/Render/Environment/TerrainGeometryDetail.cs) has `near` and `overview` geometry profiles. Overview enters when a projected cell is at most 20 CSS pixels and exits only above 26 pixels, providing hysteresis.
- Overview does not simplify authoritative terrain/cliff silhouettes. It caps vegetation blade count at 4 and cliff-dressing density at 0.3. The changed detail profile is namespaced into the content hash.
- [`TerrainTileManager.cs`](https://github.com/idlerunner00/cartoon-terrain-studio/blob/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1/src/Render/Environment/TerrainTileManager.cs) keeps existing exact geometry mounted until asynchronously prepared replacement geometry is ready. It prioritises visible tiles, applies worker backpressure, rejects stale responses by serial/revision/hash, and prunes obsolete plans during rapid traversal.
- [`LookApplier.cs`](https://github.com/idlerunner00/cartoon-terrain-studio/blob/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1/src/Studio/Terrain/LookApplier.cs) updates colour grade, grain, rock texture, strata, moss, weather, water, light, and ink as material/light parameters without rebuilding terrain.
- [`terrain_surface_comic.gdshader`](https://github.com/idlerunner00/cartoon-terrain-studio/blob/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1/shaders/terrain/terrain_surface_comic.gdshader) uses `fwidth`-derived world footprints to fade unresolved surface and wall detail, facets, and geological band edges. Broad material structure remains while fine detail resolves toward its average.
- [`terrain_ground.gdshaderinc`](https://github.com/idlerunner00/cartoon-terrain-studio/blob/7aa76ad58d4a31c4a9441f5718e8c3a31d6349a1/shaders/terrain/terrain_ground.gdshaderinc) separately fades meso and fine ground features according to screen footprint.

### Useful approaches for Wyntar

1. **Projected-size thresholds with hysteresis.** The reference proves a clean separation between continuous shader footprint fading and a coarse geometry-profile switch.
2. **Preserve silhouette geometry in overview.** Its geometry tier removes decorative density, not gameplay-bearing terrain/cliff form. This aligns with Wyntar's need to fix boundaries before simplifying them.
3. **Old-until-ready replacement.** If Wyntar later adds geometry tiers, the current chunk job/revision pattern can adopt the same rule: keep the accepted mesh visible until the replacement is complete.
4. **Derivative-aware shader detail.** `fwidth` makes fading depend on actual projected footprint and render resolution, avoiding a fragile zoom-only threshold.
5. **Live material style controls.** Broad geology and colour can change without a mesh rebuild; Wyntar's shared cliff materials already provide the right ownership point.
6. **Content-hash/profile identity.** If geometry detail changes baked output, the tier must be part of job identity so stale near/overview results cannot overwrite each other.

### Inference, not verified equivalence

Cartoon Terrain Studio's 3D geometry compiler, worker pool, and tile replacement system are substantially broader than Wyntar's strictly top-down CanvasItem renderer. Porting that architecture would violate Phase L1 scope and would be unnecessary. The useful concepts are the transition policy, screen-footprint material filtering, and replacement correctness—not its concrete geometry system.

## 6. Existing cliff defects: what LOD can and cannot improve

| Existing defect | Can shader LOD help? | Can geometry LOD help? | Required correction |
|---|---|---|---|
| Surface-to-cliff boundary mismatch | No; it may reduce contrast but leaves disagreement | No; a second contour can worsen it | One canonical presentation boundary consumed by surface, rim, and face |
| Diamond-shaped isolated elevations | No | Not safely before boundary work | Replace midpoint marching-square silhouette for this case or derive a shared cell/contour boundary |
| Narrow cliff slivers | Only makes them less visible at distance | Potentially, if a correct coarse topology owns the same boundary | Direction-aware face construction and minimum readable projected area |
| Visible gaps | No; fading would conceal evidence, not close geometry | Only if generated from the corrected shared boundary | Boundary/coverage correction and regression tests |
| Water-contact irregularities | Broad wetness should remain; fading cannot fix topology/material ownership | Only after shoreline boundary ownership is correct | Shared boundary plus deterministic water-side classification |

The C4F prototype already demonstrated that grid-aligned rims remove the diamond footprint and narrow side collapse, but it also demonstrated why boundary ownership must be solved as one unit: the old elevated-surface mask detached from the new rim. Enabling C4F or adding LOD around it would exchange one defect for another.

## 7. Missing capabilities

1. A camera/presentation signal that updates shared material LOD controls.
2. A projected-world-pixel or derivative-based detail footprint in the cliff shader.
3. Separate control of fine pigment, cracks, erosion, weathering, strata edges, and broad geological form.
4. A canonical surface/rim/face boundary artifact.
5. Geometry detail profiles with hysteresis and revision-safe old-until-ready replacement.
6. A far-overview streaming/draw strategy; current chunks remain normal full presentation chunks.
7. A practical zoom floor or bounded overview representation.
8. Per-pass draw/triangle counters that isolate cliff, surface, water, and environment costs.
9. Reliable GPU timing for this Compatibility renderer path.
10. Motion captures or temporal image-difference tests for shimmer/aliasing.

## 8. Recommended implementation order

1. **Correct boundary ownership.** Complete the shared surface/rim/face boundary work identified by C4F, keeping simulation elevation authoritative and the boundary presentation-only. Validate isolated cells, narrow strips, concave L-shapes, multilevel formations, signed chunk seams, and water contacts.
2. **Add shader LOD through shared cliff materials.** Route a camera-derived presentation value to `TerrainRenderer`, then to all shared cliff and organic cliff materials. Start by using the existing `detail_level`; extend the shader so fine pigment and fine tone also fade. Do not invalidate chunks for material-only changes.
3. **Use continuous footprint-aware fading.** Prefer derivative/projected-footprint thresholds, with zoom only as a stable global input if Compatibility constraints require it. Preserve broad facets, broad colour, major beds, shoreline identity, rims, and silhouettes.
4. **Re-profile after shader LOD.** Repeat 100%, 50%, 25%, and 12.5% captures and measurements. Shader LOD improves readability and fragment work but will not change active chunks or draw calls; verify that explicitly.
5. **Address overview streaming/draw breadth.** Before cliff geometry LOD, investigate layer/draw consolidation, bounded zoom-out, or a deliberate overview representation. The 7,047-draw result makes this higher leverage than cliff triangle reduction alone.
6. **Prototype geometry LOD only if profiling still justifies it.** Preserve canonical boundaries exactly. Simplify internal contour samples/dressing, not ownership endpoints. Add projected-size hysteresis and keep old meshes visible until revision-matched replacements commit.
7. **Treat dense alternating elevations as the geometry stress case.** It is the measured worst builder input and should gate any claim that geometry LOD is effective.

## 9. Risks and validation requirements

### Risks

- A zoom-only shader threshold can vary with viewport resolution or render scale; projected footprint is safer.
- Discrete material thresholds can visibly pop. Use continuous fades.
- Fading all strata removes geological scale and makes cliffs flat; only narrow bed edges should fade.
- Changing a shared material is correct for one active camera but would need reconsideration if multiple differently zoomed viewports are introduced.
- Geometry-tier changes can race with edit rebuilds, mode changes, chunk retirement, and stale job completion.
- Coarse geometry can reopen chunk seams or surface gaps if it does not reuse the exact canonical boundary endpoints.
- The current extreme minimum zoom can request an impractical number of chunks before any cliff LOD is relevant.
- Total draw calls include non-cliff terrain layers; optimise only after pass-specific instrumentation confirms ownership.

### Required validation

- Script parse and main-scene startup.
- `git diff --check`.
- Material propagation test proving all cliff/shared organic materials receive the same continuous detail value.
- Test proving shader-only LOD does not invalidate or rebuild chunks.
- Matched still captures at 350%, 200%, 100%, 50%, 25%, and 12.5%.
- Pan/zoom motion capture or temporal-difference test for shimmering cracks, grain, and strata.
- Fixed-world-coordinate revisit comparison to verify world-space stability.
- Boundary fixtures: isolated cell, 2×1, 2×2, 3×3, L-shape, narrow strip, large irregular formation, multilevel, shoreline, and natural terrain.
- Positive and negative chunk seams and streaming-away/return determinism.
- Geometry counts/build time on sparse, dense-change, continuous, multilevel, and shoreline fixtures.
- Active/visible/wanted chunk counts, creation latency, retirement queue peak, draw calls, CPU frame time, and GPU time where available.
- Save/load and authoritative terrain tests if zoom bounds or saved camera validation are changed.

## Final decision

**Boundary correction first.** It is a correctness prerequisite and directly addresses every named geometry defect. Then implement shader LOD using the existing shared-material ownership and extend `detail_level` to cover all genuinely fine detail. Defer geometry LOD until the corrected boundary exists and a second profiling pass determines whether cliff topology remains material after the more urgent far-zoom chunk/draw-call problem is addressed.
