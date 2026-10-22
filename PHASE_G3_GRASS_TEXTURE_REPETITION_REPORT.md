# Phase G3 — Grass Texture Repetition Report

## Result

Phase G3 substantially removes the diagonal/diamond lattice visible in the
default G1+G2 grass at 100%, 150%, and 200% zoom. The correction is grass-only,
deterministic in world space, seamless across chunks, stable through streaming,
and independently reversible without changing G1 or G2 state.

The repository remained at commit `6450236` (`Phase G1: add deterministic
clustered grass detail`). Existing uncommitted G2 work, `main.tscn`, the
`_reference` worktree, and unrelated files were preserved. No commit or push
was performed.

## Root cause

`art/grass.png` is a 32×32 pixel source whose light meadow pixels contain a
strong directional arrangement. All four catalog variants use that same image
and only alter tint, brightness, and contrast. The shader repeats those samples
with nearest filtering, so the directional structure becomes a regular
diagonal/diamond lattice over a large grass area.

G1 reduces the dark-mark population in deterministic clusters, but deliberately
does not replace the light source background. G2 smoothly displaces the source
UV by up to several pixels and changes broad colour. That breaks exact
phase-to-phase identity, but a smooth displacement can only bend and shift the
local diagonal arrangement; it cannot remove the pattern encoded inside every
32×32 source period. This is why G2 is enabled and functioning while the
checkerboard remains visible at 100% zoom.

The masked atlas is not the cause. It supplies terrain-edge coverage while RGB
comes from the repeated visual textures. Chunk construction is also not the
cause: identical absolute-world sampling reproduces the lattice across every
chunk.

## Alternatives evaluated

### Per-tile rotation or mirroring

Deterministically rotating or mirroring each 32×32 tile changes diagonal
direction, but creates a new square transform grid and risks visible edge
discontinuities. It trades the existing checkerboard for another cell-aligned
pattern and was rejected.

### Multi-sample stochastic tiling

Triangular/hex stochastic tiling can hide repetition by blending multiple
randomly transformed samples. In this shader it would multiply the base and
variant texture fetches and blend nearest-filtered pixel marks, reducing
pixel-art clarity. That cost and softness were unnecessary for this source.

### Larger generated texture

A baked macro-texture assembled from transformed source tiles reduces repeat
frequency but adds startup generation, extra texture memory, a new macro
period, and likely tile-edge artifacts. It was not the smallest safe solution.

### Selected: deterministic background reconstruction

G3 retains the source texture for dark grass marks, including all G1 decisions,
but reconstructs the light meadow background from the established catalog
`grass_clear_color`. A restrained stochastic palette shift uses one smooth
field plus one pixel-level hash at quantised absolute world coordinates.

This directly removes the part of the source that encodes the visible lattice
while preserving the grass palette, G1 marks, broad G2 colour variation, and
nearest-neighbour pixel character. It avoids additional texture samples and
does not introduce tile- or chunk-aligned regions.

## Implementation

### Configuration

`main.gd` adds one presentation control:

| Parameter | Default | Purpose |
|---|---:|---|
| `grass_texture_repetition_correction_enabled` | `true` | Enables G3; disabling it bypasses the branch and restores exact G2 output |

Main transfers the value to `TerrainRenderer` before the renderer enters the
tree. The renderer includes it in the terrain-surface factory configuration and
provides `set_grass_texture_repetition_correction_enabled()` for immediate
runtime comparison. The setting remains outside authoritative generation and
save configuration.

### Grass-only material ownership

`TerrainSurfaceFactory` enables the shader uniform only when the catalog
definition opts into clustered grass detail. All non-grass materials receive
`0.0` and remain on their previous shader paths.

### Shader behaviour

The existing G1 luma mask and suppression result determine background weight:

- retained dark marks keep their source art;
- G1-suppressed marks count as background;
- light source pixels are blended 86% toward the reconstructed palette;
- G2 broad and fine colour variation is applied afterward unchanged.

The grain field is seeded from the existing world seed and evaluated on
floor-quantised world pixels. It therefore cannot swim during camera movement
or zoom. Chunk order does not enter the calculation.

Disabling G3 skips this entire branch. No texture, atlas, G1 control, or G2
control is rewritten, so rollback is exact.

## Visual comparison

The capture camera is centred on world-cell X `12000`, an exact 32-cell chunk
boundary. Decorations, objects, and elevation are disabled only in the capture
fixture so the surface can be judged directly.

Side-by-side files place **G3 disabled on the left** and **G3 enabled on the
right**:

- `.artifacts/g3_compare_seed84521_g1on_z1_0x.png` — 100%, wide area
- `.artifacts/g3_compare_seed84521_g1on_z1_5x.png` — 150%
- `.artifacts/g3_compare_seed84521_g1on_z2_0x.png` — 200%, close view
- `.artifacts/g3_compare_seed13579_g1on_z1_5x.png` — second world seed
- `.artifacts/g3_compare_seed84521_g1off_z1_5x.png` — G1 compatibility

Visual review findings:

- At 100%, the regular diagonal/diamond background disappears and is replaced
  by restrained irregular grain.
- At 150% and 200%, G1 marks remain crisp and readable; the background remains
  pixel-anchored rather than blurred or animated.
- The broad G1 clear/dense regions and G2 colour regions remain visible.
- No vertical seam is visible at the centred chunk boundary.
- Seed `13579` produces a distinct but stylistically consistent background.
- The G1-disabled comparison retains its intentionally dense legacy dark-mark
  lattice; G3 does not alter mark density merely to conceal it.

Individual before/after images, comparison paths, camera data, seeds, zooms,
and benchmark results are recorded in `.artifacts/g3_capture_manifest.json`.

## Determinism, streaming, and lifecycle

`tests/phase_g3_validation.gd` mirrors the stochastic palette field on CPU and
verifies:

- fixed seed and fixed world coordinate reproduce identical values;
- a different seed changes the field;
- shared coordinates agree exactly at chunk seams;
- forward and reverse chunk construction orders produce identical samples;
- only grass receives the G3 enable;
- G3 rollback leaves atlas, G1 controls, and G2 controls unchanged;
- runtime switching does not invalidate streamed chunks;
- renderer recreation reproduces G3 state;
- G3 does not enter authoritative save configuration.

The graphical harness additionally streamed 160 cells away, allowed the
original chunks to retire, returned to the fixed camera, and compared the full
frame. The revisit was pixel-exact (`streaming_revisit_pixel_exact: true`).

## Performance

A bounded 360-frame matched benchmark ran in Godot 4.7.2 Compatibility mode on
an NVIDIA GeForce RTX 3080:

| Mode | Average frame | P95 | P99 | Draw calls | Static memory |
|---|---:|---:|---:|---:|---:|
| G3 disabled | 0.670 ms | 0.905 ms | 1.077 ms | 1.0 | 90.142 MiB |
| G3 enabled | 0.687 ms | 0.952 ms | 1.204 ms | 1.0 | 90.144 MiB |

The observed average difference is approximately `0.017 ms` in this capture.
There are no additional draw calls, textures, nodes, per-cell objects, or
per-chunk allocations. The shader adds one smooth-noise evaluation and one hash
for grass fragments when G3 is enabled.

## Validation

Godot command invocations used a 120-second timeout. Core regressions ran with
Godot `4.7.stable.official.5b4e0cb0f`; the graphical comparison/benchmark ran
with Godot `4.7.2.stable` on the same Compatibility renderer.

| Check | Result |
|---|---|
| Full project import and script parse | PASS |
| Main-scene startup | PASS |
| Focused G3 validator | PASS |
| G3 capture/benchmark | PASS — 10 captures, 5 side-by-side comparisons |
| G2 validator | PASS |
| G1 validator | PASS |
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
- `tests/phase_g3_validation.gd`
- `tests/phase_g3_validation.gd.uid`
- `tests/phase_g3_capture.gd`
- `tests/phase_g3_capture.gd.uid`
- `PHASE_G3_GRASS_TEXTURE_REPETITION_REPORT.md`

Generated review assets are ignored under `.artifacts/g3_*`.

## Remaining limitations

- G3 preserves retained source marks by design. If G1 is disabled, the dense
  legacy mark layout remains visibly directional even though the light
  background lattice is corrected. Changing that would alter mark density and
  violate G1 ownership.
- G3 removes most source-background texture character in favour of restrained
  palette-matched grain. This is the intentional tradeoff that avoids transform
  seams and multi-sample GPU cost.
- The desktop Compatibility benchmark is clean, but very low-end/mobile GPU
  evaluation remains appropriate if that becomes a target platform.
- Final aesthetic acceptance remains a human visual-review decision; the G3
  switch provides immediate exact rollback.
