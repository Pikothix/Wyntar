# Phase G6 — Remaining Terrain Texture Repetition

## Scope and recovered work

Phase G6 is a presentation-only extension of the existing shared terrain and
cliff material paths. On resumption, the working tree already contained the G6
configuration transfer, snow/gravel reconstruction, water reconstruction,
cliff pigment reconstruction, a focused validator, and a capture harness. The
project imported successfully, but the focused validator stopped on a stale
test-only call to `TerrainWorld.get_override()`. No G6 captures or report had
been produced.

The resumed work preserved that implementation, replaced the invalid assertion
with material/elevation override-count checks, made the capture harness fail
honestly when no framebuffer is available, ran the visual matrix using the
Compatibility renderer, completed the regression suite, and produced this
report. Existing `main.tscn`, `_reference`, and G1–G5 changes were not edited or
reverted.

## Root-cause findings

### Gravel

`art/gravel.png` is a 32×32 tile whose high-contrast particles recur at the
same offsets. Repeating it in absolute world UVs produces a dense diagonal
particle lattice. G4 phase warping changes local phase but cannot remove motifs
that are embedded in the source tile.

G6 replaces only gravel pigment with a deterministic world-pixel field. Sparse
hash-selected anchors grow into one-, two-, and occasional three-pixel
fragments in several directions. Independent tone selection and broad, low-
amplitude colour drift retain the coarse rocky palette without a placement
grid. Material masks, alpha, variants, and terrain authority are unchanged.

### Snow

`art/snow.png` contains a faint diagonal/diamond highlight lattice. Its low
contrast makes the pattern subtle at 100%, but the exact 32-pixel recurrence is
clear at 150% and 200%.

Snow uses a separate restrained reconstruction: broad world-space drift, very
low-amplitude per-pixel grain, and rare pale grains. It does not use the gravel
fragment model. The result remains bright and smooth rather than reading as
sand or gravel.

### Water

The base 32×32 water art remains present beneath the normal liquid branch.
Existing calm tinting retains part of that source colour, so the source diamond
pattern survives even though bands, macro variation, shoreline response, and
animation are already world-space. The optional glint extension is disabled by
default and was not the root cause.

G6 replaces only the tiled base pigment with two static, smooth world-space
fields before the existing liquid animation is applied. Wave phase, shimmer,
shoreline masks, depth response, and optional glints remain unchanged. No
per-frame random input is used, so the correction itself cannot swim or snap.

### Cliff faces

The cliff shader sampled dirt or stone with
`source_uv = (world_pixel + 16) / 32`. Its larger facets, strata, weathering,
and cracks were already deterministic world-space features, but they modulated
the repeatedly sampled source pigment instead of replacing it. The result was
a visible 32-pixel micro-fleck texture over otherwise non-repeating geology.
This was a texture-detail issue, not a contour or geometry defect.

G6 reconstructs only the initial dirt/stone pigment from bounded world-space
fields, then passes it through the existing facet, strata, crack, shoreline,
lip, side-return, and contact-shadow logic. Atlas alpha and geometry still own
the silhouette. Cliff geometry, height projection, contours, picking, and
collision were not changed.

## Implementation and configuration

The renderer remains the owner of runtime presentation configuration. The
factories translate catalog/config data into shared shader parameters, and the
shaders render it. Terrain generation and persistence do not read G6 state.

Defaults:

| Target | Enabled | Strength | Technique |
| --- | ---: | ---: | --- |
| Snow | yes | 0.90 | smooth drift plus restrained grain |
| Gravel | yes | 1.00 | irregular multi-pixel fragments |
| Water | yes | 1.00 | static world-space base-pigment reconstruction |
| Cliff faces | yes | 0.95 | world-space dirt/stone pigment reconstruction |

Snow and gravel share a global `remaining_terrain_detail_enabled` rollback and
also have independent enable/strength controls. Water and cliff faces each have
independent enable and strength controls. Disabling a target switches its
shader branch off and restores the G5 input path exactly; no chunk rebuild is
required. G1 grass and G5 sand/dirt/stone/mud eligibility are unchanged.

## Visual comparison

Matched captures use seed 84521, identical fixtures/cameras, and zooms 1.0,
1.5, and 2.0. Every comparison places the G5 baseline on the left and G6 on the
right. A second seed (13579) was captured for every target.

- Gravel: `.artifacts/g6_compare_gravel_seed84521_z1_0x.png`,
  `z1_5x.png`, and `z2_0x.png`. The repeated diagonal particle lattice is gone;
  the replacement remains crisp and rocky at all three zooms.
- Snow: `.artifacts/g6_compare_snow_seed84521_z1_0x.png`, `z1_5x.png`, and
  `z2_0x.png`. The diamond lattice is removed without increasing contrast.
- Water: `.artifacts/g6_compare_water_seed84521_z1_0x.png`, `z1_5x.png`, and
  `z2_0x.png`. The fixed base lattice is removed while the established colour
  and animated highlights remain.
- Cliff faces: `.artifacts/g6_compare_cliff_seed84521_z1_0x.png`, `z1_5x.png`,
  and `z2_0x.png`. Repeated micro-flecks are removed; broad planes, beds,
  fractures, lips, and face shading remain readable.
- Mixed elevated terrain: `.artifacts/g6_disabled_mixed_elevated_seed84521.png`
  and `.artifacts/g6_enabled_mixed_elevated_seed84521.png` cover adjacent
  materials and elevation.

Water was additionally captured at fixed times 0.0, 2.0, and 6.0 seconds in
both modes. The G6 base field remains stationary while the existing wave layer
changes with time. Shoreline and elevated/mixed fixtures show no new mask seam.
The manifest at `.artifacts/g6_capture_manifest.json` records 34 captures and
15 side-by-side comparisons.

Visual inspection, rather than image-difference magnitude alone, was the
acceptance criterion. All four changes were retained because they clearly
remove their source pattern without replacing it with another recognizable
grid.

## Determinism, streaming, and performance

- A streamed gravel view was captured, unloaded by moving 192 cells away, and
  revisited: pixel-exact match.
- A fresh Godot process regenerated representative snow, gravel, water, and
  cliff captures: all four SHA-256 image hashes matched exactly.
- Seeds 84521 and 13579 produce different but deterministic fields.
- All calculations use absolute world pixels with bounded hash coordinates;
  there is no camera-relative input, per-cell state, or per-frame randomness.
- G5 baseline: 1.766 ms average, 2.451 ms p95 over 240 frames.
- G6 enabled: 1.951 ms average, 2.711 ms p95 over 240 matched frames.
- Average draw calls: 209 in both modes.
- Static memory: 85.838 MiB baseline and 85.840 MiB enabled.

The measured cost is approximately 0.185 ms average on an NVIDIA RTX 3080 with
Godot's Compatibility renderer. G6 adds no draw calls, nodes, per-chunk
textures, or CPU pixel generation.

## Validation

Godot 4.7 (`4.7-stable.official`) was used with bounded 90-second process
timeouts.

- Full project import and script parse: pass. Windows emitted the existing
  isolated-appdata safe-save warning; the process exited successfully.
- Main-scene startup: pass.
- G1, G2, G3, G4, G5, and focused G6 validators: pass.
- C4A renderer configuration and C4B renderer factory validators: pass.
- Terrain/chunk streaming (`phase5d`): pass.
- Terrain/elevation (`phase1g`): pass.
- Water regression (`phase_a_water_validation`): pass.
- Cliff structural regressions (`phase3f`, `phase3g`): pass.
- Save/load (`phase7b1`): pass.
- `git diff --check`: pass; only existing LF-to-CRLF notices were printed.

The focused G6 validator confirms material eligibility, shader uniform transfer,
exact branch rollback, and that toggles do not mutate material or elevation
overrides. The C4A validator now covers the Main-to-renderer G6 configuration
transfer.

## Known limitations and follow-up

- Water retains the established animation model. Its sparse highlights can be
  more or less visible at a given animation phase; G6 intentionally does not
  redesign wave timing or the optional glint system.
- Cliff pigment is corrected, but contour overlaps or silhouette issues remain
  geometry concerns and belong in a separate cliff phase. None were treated as
  texture repetition here.
- The fragment cost is small in the matched benchmark but measurable. Lower-end
  Compatibility hardware should be sampled before changing these defaults for
  a shipping performance tier.
- The correction is shader/presentation state and is intentionally absent from
  save schemas.

No commit or push was performed.
