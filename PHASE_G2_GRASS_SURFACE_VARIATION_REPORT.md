# Phase G2 — Grass Surface Variation Report

## Status on resumption

The interrupted session had already completed the repository safety check,
diagnosed the repeating source phase, and added the initial G2 shader,
configuration, validation, and capture-harness changes. No G2 report or final
capture set existed yet. The first resumed capture run exposed excessive light
texture marks in that initial correction; those settings were rejected and the
implementation was tuned before final validation.

The repository started this phase at commit `6450236` (`Phase G1: add
deterministic clustered grass detail`). Existing user changes to `main.tscn`,
the `_reference` worktree, and the unrelated untracked pager file were present
before G2 and were not modified, reverted, staged, or committed.

## Confirmed root cause

The grass source is a 32×32 repeating texture. The terrain shader sampled the
base and all colour variants with the same exact world-space UV phase:

```glsl
vec2 tiled_uv = (world_position + vec2(16.0)) / 32.0;
```

The variants alter tint, brightness, and contrast but retain that identical
spatial layout. Low-frequency variant interpolation therefore changes colour
without breaking the repeating texture phase. G1 selectively suppresses dark
marks, so it improves mark distribution but intentionally does not address the
underlying background phase.

This was confirmed in the fixed-camera zoom capture. At zoom 2.31, one 32-pixel
source repeat is approximately 74 screen pixels. The before image has a strong
luminance-error trough at that shift (`0.02054`), versus `0.03377` after the G2
correction. The 64% increase in mismatch indicates that adjacent source periods
are no longer near-identical.

The cause is presentation sampling, not terrain generation, chunk construction,
texture filtering, or G1's cluster field.

## Implementation

G2 remains inside the existing shared terrain material architecture:

- Grass receives a deterministic continuous UV warp derived from absolute
  world-pixel coordinates and the existing world seed. This breaks the exact
  32-pixel phase without selecting phases per tile or per chunk.
- Two smooth world-space fields add broad and restrained fine green variation.
- Colour variation is applied to background pixels. G1-retained dark marks are
  left intact; G1-suppressed marks are treated as background.
- The factory explicitly enables G2 only for the catalog's grass material.
  Dirt, sand, water, and all other terrain materials remain on their previous
  shader paths.
- Runtime setters update the one shared grass material. They do not rebuild
  chunks, create nodes or textures, or change draw-call count.
- Disabling G2 restores the exact prior G1 texture-coordinate and colour path.
- G2 settings are presentation preferences and are deliberately excluded from
  authoritative generation/save configuration.

No terrain authority, generation, elevation, collision, picking, editing,
water, cliff, or persistence implementation was changed.

## Parameters and defaults

| Parameter | Default | Purpose |
|---|---:|---|
| `organic_grass_color_variation_enabled` | `true` | Independent G2 rollback switch |
| `grass_broad_variation_scale` | `0.0015` | Scale for broad world-space colour and phase variation |
| `grass_color_variation_strength` | `0.055` | Broad low-contrast green shift |
| `grass_fine_variation_strength` | `0.018` | Restrained smaller-scale green shift |

Existing G1 defaults remain unchanged: 70% clear-area coverage, 35% dense-area
detail retention, cluster scale `0.004`, transition softness `0.12`, residual
density `0.04`, and seed offset `48131`.

## Visual comparison

Twelve controlled 1280×720 captures were generated under `.artifacts/` with
identical before/after cameras. The matrix covers:

- grass-only at zoom 1.0 and 2.31;
- grass beside dirt and sand;
- a camera centred exactly on a 32-cell chunk boundary;
- G1 enabled and disabled;
- world seeds `84521` and `13579`.

Primary review pair:

- `.artifacts/g2_before_seed84521_g1on_meadow_z1_0x.png`
- `.artifacts/g2_after_seed84521_g1on_meadow_z1_0x.png`

High-zoom review pair:

- `.artifacts/g2_before_seed84521_g1on_meadow_zoom_z2_31x.png`
- `.artifacts/g2_after_seed84521_g1on_meadow_zoom_z2_31x.png`

Boundary and neighbouring-material review:

- `.artifacts/g2_after_seed84521_g1on_chunk_boundary_z2_31x.png`
- `.artifacts/g2_after_seed84521_g1on_dirt_sand_z1_0x.png`

The complete matrix and camera/seed metadata are recorded in
`.artifacts/g2_capture_manifest.json`. Visual review confirms that the exact
checkerboard repeat is disrupted, broad transitions remain subtle, dirt and
sand are unchanged, and no chunk seam appears in the boundary-centred view.
The G1-disabled pair confirms that G2 is an independent correction rather than
a density change. The second-seed pair confirms a distinct stable result.

## Determinism and chunk continuity

`tests/phase_g2_validation.gd` mirrors the shader's warp, broad, and fine fields
on CPU. It verifies:

- identical seed and world coordinate reproduce identical values;
- a different world seed changes the representative field;
- both sides of shared chunk coordinates evaluate identically;
- forward and reverse chunk-construction orders produce identical samples;
- only grass receives the G2 factory enable;
- rollback does not rewrite the atlas or alter any G1 parameter;
- runtime controls do not invalidate streamed chunks;
- renderer recreation reproduces material state;
- G2 settings do not enter authoritative save configuration.

## Performance

A bounded 360-frame matched benchmark was run in Godot 4.7 Compatibility mode
on an NVIDIA GeForce RTX 3080 with decorations and environmental objects
disabled:

| Mode | Average frame | P95 | Average draw calls | Static memory |
|---|---:|---:|---:|---:|
| G2 disabled | 0.630 ms | 0.803 ms | 1.0 | 59.536 MiB |
| G2 enabled | 0.595 ms | 0.723 ms | 1.0 | 59.538 MiB |

The small timing difference is normal run-to-run variance; this sample does not
show a measurable regression. G2 adds smooth-noise arithmetic to grass
fragments, but adds no draw calls, nodes, or per-chunk resource allocations.

## Validation results

All checks used Godot `4.7.stable.official.5b4e0cb0f` with a 120-second timeout
per invocation where applicable.

| Check | Result |
|---|---|
| Full project import and script parse | PASS |
| Main-scene startup | PASS |
| Focused G2 validator | PASS |
| G2 graphical capture/benchmark | PASS — 12 captures |
| G1 grass regression | PASS |
| C4A renderer configuration | PASS |
| C4B renderer factories | PASS |
| Terrain/elevation regression (Phase 5D) | PASS |
| Chunk streaming/lifecycle regression (Phase 1G) | PASS |
| Save/load regression (Phase 7B1) | PASS |
| Water regression (Phase A) | PASS |
| Cliff regression (Phase 3G) | PASS |
| `git diff --check` | PASS |

## Files changed

- `scripts/main.gd`
- `scripts/terrain_renderer.gd`
- `scripts/terrain_surface_factory.gd`
- `shaders/terrain_variation.gdshader`
- `tests/phase_c4a_renderer_configuration_validation.gd`
- `tests/phase_g2_validation.gd`
- `tests/phase_g2_validation.gd.uid`
- `tests/phase_g2_capture.gd`
- `tests/phase_g2_capture.gd.uid`
- `PHASE_G2_GRASS_SURFACE_VARIATION_REPORT.md`

Generated, ignored review artifacts are under `.artifacts/g2_*`.

## Known limitations and follow-up

- The original 32×32 texture remains deliberately recognizable. G2 disrupts
  its phase rather than replacing Wyntar's existing grass art.
- Fragment cost increases only on the shared grass material because the
  correction evaluates additional smooth-noise fields. The bounded desktop
  benchmark is clean; very low-end/mobile GPU review remains prudent if that
  platform becomes a target.
- Final aesthetic acceptance remains a human visual-review decision. The
  independent enable switch provides immediate rollback without data changes.

No commit or push was performed.
