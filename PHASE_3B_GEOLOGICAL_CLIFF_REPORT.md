# Wyntar — Phase 3B Geological Cliff Material Prototype

Date: 2026-10-19

Engine: Godot 4.7.2 stable Mono, Compatibility renderer, NVIDIA GeForce RTX 3080

Evidence labels used below:

- **Verified**: established by source inspection, a validation result, a capture manifest, or a measured benchmark.
- **Visual observation**: judged from the saved before/after captures.
- **Untested expectation**: designed behaviour that still needs a stronger runtime or player-facing check.

## 1. Task classification

Existing System Extension — procedural cliff material and visual validation.

This phase implements Stage 0 and Stage 1 from `CLIFF_IMPROVEMENT_PLAN.md`. It does not begin connected-contour geometry work.

## 2. Files changed

Production:

- `shaders/cliff_procedural.gdshader`

Test and evidence infrastructure:

- `tests/phase3b_capture.gd`
- `tests/phase3b_benchmark.gd`
- `screenshots/phase3b_baseline_capture_manifest.json`
- `screenshots/phase3b_prototype_capture_manifest.json`
- `screenshots/phase3b_benchmark_graphical.json`
- 18 baseline PNGs and 18 matching prototype PNGs under `screenshots/phase3b_*`

No terrain, mesh-builder, chunk-renderer, scene, save, or authority file changed.

## 3. Summary of shader improvements

### Broad geological facets

**Verified:** the previous two dense box lattices were replaced with a lower-frequency rotated world-space plane field. Plane placement is derived from `world_position` and `seed_offset`; it does not use chunk-local UVs. The existing five-step tonal ramp still quantises the result.

**Visual observation:** the exposed front faces now form fewer, larger tonal regions at 1x and 3x. This is clearest in the stone three-level and isolated-formation captures. The planes are deliberately subdued at 0.5x so the cliff silhouette remains the primary read.

### Irregular strata

**Verified:** layers now use:

- absolute world coordinates;
- slowly warped vertical placement;
- deterministic 176-pixel thickness regions;
- different dirt and stone thickness ranges;
- rare 144-pixel fault offsets;
- deterministic 88-pixel broken-band regions;
- a stable per-bed tone identity.

The fields do not restart at tiles, chunks, or stacked face rows. Stone receives stronger beds; dirt receives softer bed variation.

### Sparse cracks and dirt erosion

**Verified:** stone face-role fragments can receive a deterministic fracture in selected 112x96 world-space cells. The function has a fixed amount of work: one bent principal line and one gated short branch. It performs no procedural neighbourhood search and creates no nodes or meshes.

**Verified:** dirt faces do not use the stone fracture network. They receive only a subtle erosion/damp modulation derived from existing broad and fine fields.

**Visual observation:** fractures are sparse enough that not every small face contains one. They are most legible at 3x and do not become a dense high-frequency texture at ordinary gameplay scale.

### Crest, contact, and shoreline treatment

**Verified:** the existing 3-5 pixel lip role now receives a restrained dark-brown crest accent rather than a black outline. Side returns retain their directional darkening. Existing role-3 contact-shadow geometry is unchanged and remains the only strong non-shoreline foot shadow.

**Verified:** shoreline colour is less uniformly applied than before. A restrained cool wet tint is modulated by the existing world-space macro field. It does not add another contact-shadow layer.

### Zoom-aware detail hook

**Verified:** the shader exposes `detail_level`, defaulting to `1.0`. It scales cracks, dirt erosion, and fine weather variation; broad facets and strata remain present. No camera integration or geometry LOD was added.

## 4. Baseline capture details

`tests/phase3b_capture.gd` generates both evidence sets from the same code path. It accepts only `baseline` or `prototype`, and records each run in a manifest.

Common configuration:

| Setting | Value |
| --- | --- |
| World seed | 84521 |
| Viewport | 1280x720 |
| Zooms | 0.5x, 1x, 3x |
| Standard projection | Enabled |
| Oblique presentation | Disabled |
| Procedural cliff material | Enabled |
| Organic cliff geometry | Enabled |
| Unified components | Enabled |
| Refined silhouettes | Enabled |
| Controlled fixture extent | 58x36 cells |

Scenarios and camera cells:

| Scenario | Camera cell | Coverage |
| --- | ---: | --- |
| `natural_gameplay` | `(0, 0)` | Unmodified generated terrain, decorations, and objects |
| `positive_seam_diagonal` | `(16384, 8192)` | Long stone diagonal across positive X/Y chunk boundaries |
| `winding_convex_concave` | `(16480, 8192)` | S-shaped dirt edge, convex spur, concave notch |
| `materials_three_level_shoreline` | `(16576, 8192)` | Broad three-level dirt/stone faces meeting water |
| `isolated_raised_formation` | `(16672, 8192)` | Small one-, two-, and three-level raised formations |
| `negative_seam_diagonal` | `(-16384, -8192)` | Long dirt diagonal across negative X/Y chunk boundaries |

The controlled cases disable decorations and environment objects after the natural view is captured. Both manifests record exact camera world positions, zooms, rendering flags, engine version, display server, fixture descriptions, and output paths.

## 5. Before-and-after screenshot paths

Full reproducibility records:

- [Baseline manifest](screenshots/phase3b_baseline_capture_manifest.json)
- [Prototype manifest](screenshots/phase3b_prototype_capture_manifest.json)

Compact visual comparison index:

| View | Baseline | Prototype |
| --- | --- | --- |
| Natural 0.5x | [PNG](screenshots/phase3b_baseline_natural_gameplay_0_5x.png) | [PNG](screenshots/phase3b_prototype_natural_gameplay_0_5x.png) |
| Natural 1x | [PNG](screenshots/phase3b_baseline_natural_gameplay_1_0x.png) | [PNG](screenshots/phase3b_prototype_natural_gameplay_1_0x.png) |
| Natural 3x | [PNG](screenshots/phase3b_baseline_natural_gameplay_3_0x.png) | [PNG](screenshots/phase3b_prototype_natural_gameplay_3_0x.png) |
| Three-level shoreline 0.5x | [PNG](screenshots/phase3b_baseline_materials_three_level_shoreline_0_5x.png) | [PNG](screenshots/phase3b_prototype_materials_three_level_shoreline_0_5x.png) |
| Three-level shoreline 1x | [PNG](screenshots/phase3b_baseline_materials_three_level_shoreline_1_0x.png) | [PNG](screenshots/phase3b_prototype_materials_three_level_shoreline_1_0x.png) |
| Three-level shoreline 3x | [PNG](screenshots/phase3b_baseline_materials_three_level_shoreline_3_0x.png) | [PNG](screenshots/phase3b_prototype_materials_three_level_shoreline_3_0x.png) |
| Winding corners 1x | [PNG](screenshots/phase3b_baseline_winding_convex_concave_1_0x.png) | [PNG](screenshots/phase3b_prototype_winding_convex_concave_1_0x.png) |
| Positive seam 3x | [PNG](screenshots/phase3b_baseline_positive_seam_diagonal_3_0x.png) | [PNG](screenshots/phase3b_prototype_positive_seam_diagonal_3_0x.png) |
| Negative seam 3x | [PNG](screenshots/phase3b_baseline_negative_seam_diagonal_3_0x.png) | [PNG](screenshots/phase3b_prototype_negative_seam_diagonal_3_0x.png) |
| Isolated formation 3x | [PNG](screenshots/phase3b_baseline_isolated_raised_formation_3_0x.png) | [PNG](screenshots/phase3b_prototype_isolated_raised_formation_3_0x.png) |

The manifests contain the remaining paths. Existing Phase 1G, Phase 2B, and Phase 7C evidence was not overwritten.

## 6. Visual assessment

1. **Do cliffs look more geological?** **Visual observation: modestly yes.** Larger face-scale tones and less uniform beds improve the front-face read. The unchanged tile-derived silhouette still dominates long diagonals.
2. **Are broad rock planes identifiable?** **Visual observation: yes at 1x and 3x.** Stone shows stronger plane changes than dirt. At 0.5x the planes compress into broad value grouping rather than noise.
3. **Are strata coherent across multiple cells?** **Verified by implementation and supported by captures.** Beds use absolute world coordinates and do not restart at 32-pixel tile boundaries. No static restart is visible at positive or negative chunk seams.
4. **Are cracks sparse and natural-looking?** **Visual observation: sparse, with limited evidence.** Their low selection rate avoids a crack on every tile, but the current captures do not provide enough large exposed stone area to judge every seed shape. Additional art review may tune their darkness or frequency.
5. **Is 32-pixel tile repetition less dominant?** **Visual observation: reduced on exposed cliff faces, not removed globally.** Top terrain textures are outside this shader and retain their original cadence.
6. **Do dirt, stone, and shoreline cliffs remain distinguishable?** **Visual observation: yes.** Stone keeps angular cool planes and fractures; dirt remains warmer and softer; shoreline faces retain a restrained cool wet cast.
7. **Does the result remain readable at 0.5x?** **Visual observation: yes.** Fine detail does not overwhelm the silhouette. Broad form remains visible.
8. **Were seams, shimmer, or artefacts introduced?** **Verified for static seams:** none are visible in positive or negative boundary captures, and Phase 1B/7C.4/7C.5 seam validations pass. **Untested expectation for shimmer:** still captures cannot prove temporal stability; a dedicated animated pan at fractional camera positions was not recorded.

The prototype improves material hierarchy, but overall cliffs still appear blocky because face ownership and silhouette topology remain tile-derived. That is a geometry limitation; it was not addressed in this phase.

## 7. Validation results

All commands used Godot 4.7.2 stable Mono.

| Validation | Result | Coverage |
| --- | --- | --- |
| Godot editor parse | PASS | Project and GDScript parse |
| Graphical OpenGL shader compilation | PASS | Shader rendered during both capture and benchmark runs |
| Phase 1A | PASS | Material ownership, source classes, rollback, atlas preservation, node count, authority snapshot |
| Phase 1B | PASS | Determinism, positive/negative seams, batched geometry, editing rebuild, rollback |
| Phase 1D | PASS | Lips, returns, contact shadows, shoreline encoding |
| Phase 1E | PASS | Refined multi-level edges and negative-boundary batches |
| Phase 1F | PASS | Incremental scheduling and presentation replacement |
| Phase 1G | PASS | Halo cache, cancellation/revision lifecycle, bounded retirement |
| Phase 7C.4 | PASS | Multi-level, water-contact, corner, seam, and atlas regressions |
| Phase 7C.5 | PASS | Latest geometry and seam regression matrix |
| `git diff --check` | PASS | Whitespace/error check |

**Verified:** terrain authority is unchanged, the rollback switch still reaches every cliff material, edit-triggered rebuilds remain valid, cancellation/streaming validations pass, and no geometry-production file changed. Consequently, the shader adds no geometry vertices, triangles, nodes, or feature-specific draw calls.

## 8. Performance comparison

`tests/phase3b_benchmark.gd` inherits the Phase 1G benchmark helpers and duplicates its exact fixture and sampling sequence while writing a new Phase 3B result. The original Phase 1G JSON remains untouched.

Comparison against the saved same-machine Phase 1G graphical result:

| Metric | Phase 1G saved baseline | Phase 3B prototype | Change |
| --- | ---: | ---: | ---: |
| Streaming mean average frame | 6.121 ms | 8.840 ms | +44.4% |
| Streaming mean P95 | 7.966 ms | 11.170 ms | +40.2% |
| Mode-switch mean average frame | 7.041 ms | 9.714 ms | +38.0% |
| First streaming-run average draw calls | 549.95 | 549.22 | -0.13% |
| Steady static memory | 82.013 MiB | 82.202 MiB | +0.23% |

**Verified:** the measured frame-time comparison does not meet the 10% target. Draw calls and memory are effectively unchanged, and the geometry CPU lifecycle remains the same ownership path, so the likely new cost is fragment-shader work and/or run-to-run GPU/host variance.

This is not a perfect controlled material-only comparison: the Phase 1G baseline is a previously saved run rather than an immediately adjacent run of the old shader. The Phase 3B run's paired legacy-retirement samples were also slower than their saved Phase 1G counterparts, which indicates meaningful environment/run variance. That variance prevents assigning the entire delta to this shader, but it does not justify claiming the target was achieved. The authoritative result for this phase is: **performance target unverified and currently measured above budget**.

Evidence: [Phase 3B graphical benchmark](screenshots/phase3b_benchmark_graphical.json).

## 9. Known limitations

- The geometry silhouette remains cell-derived and visibly stair-stepped on long diagonals.
- The shader has no normalised per-face height coordinate. The crest can use the existing lip role, but exact face-foot shading cannot be added without extending mesh attributes. This phase therefore preserves contact-shadow geometry and uses restrained world-space shoreline wet patches rather than pretending to know the foot position.
- Crack frequency is intentionally low; some fixtures contain no clearly visible crack at a given seed.
- `detail_level` is fixed at its shader default. Camera zoom does not update it yet.
- Static screenshots validate seams but not temporal shimmer during subpixel camera movement.
- The saved-baseline performance delta exceeds budget and needs a closer material-only GPU comparison.
- The shader cannot remove blockiness caused by cardinal exposure ownership or create geological contour landmarks.

## 10. Recommended next step

Do not begin connected-contour geometry yet.

First, perform one isolated Phase 3B follow-up: profile and tune the geological shader against an immediately adjacent old-shader run using the exact Phase 1G fixture, while preserving the current A/B image set. Acceptance should require:

- no more than 10% steady-state frame-time regression in repeated adjacent runs;
- unchanged draw calls, nodes, and geometry counts;
- retention of the broad facet and irregular-bed improvement;
- a short animated fractional-camera pan confirming no shimmer;
- explicit art approval of crack frequency at 1x and 3x.

Only after material appearance and cost are accepted should the architect decide whether to authorise the separate connected-contour geometry stage.
