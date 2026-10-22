# Phase G5 — Stochastic Terrain Detail

## Outcome

Phase G5 replaces the visibly tiled fine-detail layer on sand, dirt, stone, and
mud with deterministic world-space procedural detail. Large uninterrupted dirt
and stone regions no longer expose recognizable diagonal, horizontal, diamond,
or checkerboard repetition at 100%, 150%, or 200% zoom.

The established material palettes and broad G4 colour variation remain. Grass
continues through G1–G3 exactly, snow and gravel remain unchanged, and water and
cliff materials were not modified. Disabling G5 restores the exact G4 shader
path.

## Root-cause analysis

Every terrain surface source is 32×32 pixels. The four visual variants for each
material are not different texture layouts: the factory generates them by
applying tint, brightness, and contrast to the same source image. Consequently,
every variant retains every fleck at the same coordinate and the shader's broad
variant blend cannot decorrelate the fine-detail layout.

Direct palette and pixel-frequency inspection found:

| Material | Repetitive source feature | Representative repeated colour | Pixels per 32×32 tile |
|---|---|---:|---:|
| Sand | Regular sparse dark grains | `#a48758` | 22 identical darkest pixels |
| Dirt | Dark pores/speckles | `#453429` | 44 identical darkest pixels |
| Stone | Horizontal flecks and short clusters | `#59656c` | 123 identical darkest pixels |
| Mud | Dark pores | `#423e3c` | 22 identical darkest pixels |
| Gravel | Dense stones | `#5f5853` | 140 identical dominant dark pixels |

These coordinates repeat every 32 world pixels in both axes. Their diagonal or
horizontal arrangement makes the repetition visible across large regions.

G4 moved the sample coordinate with a continuous low-frequency phase warp. It
removed hard tile edges, but it could not remove the motif: each 32×32 copy
still contained the same constellation of marks. The warp merely bent the
constellation into waves, particularly on stone and gravel. This is why G4's
image difference was measurable while the repetition remained perceptually
obvious.

## Prototypes and rejected approaches

The G5 work started from G4's retained results rather than discarding them.

1. G4's per-tile mirroring prototype was already known to create tile-edge
   discontinuities on stone and gravel and was not revived.
2. Sampling the existing texture with a stronger continuous warp was rejected
   because it made the repeated constellations curve more visibly.
3. The first procedural reconstruction used the shader's existing sine hash.
   Compatibility-renderer float precision created a broad diagonal probability
   bias, visible as triangular grain coverage. That prototype was rejected.
4. The retained implementation uses a bounded polynomial hash for G5 only. It
   produces evenly distributed world-pixel candidates without a regular cell
   grid or sine precision bands.

## Implementation

### Shared rendering path

The existing shared terrain shader and material factory remain the only surface
rendering system. G5 adds no nodes, draw passes, textures, or per-chunk CPU work.

For an eligible material, the shader:

1. keeps the existing broad variant-tint delta;
2. replaces the source tile's fine-detail colour with the catalog's established
   base palette colour;
3. applies restrained broad and per-pixel palette variation in absolute world
   coordinates;
4. places material-specific detail pixels with a deterministic polynomial hash;
5. blends the reconstructed result using the material intensity control.

World pixels and seed inputs are bounded before hashing, preserving precision at
large streamed-world coordinates. Sampling is quantized to world pixels, so the
result does not swim during camera movement or zoom. Material masks and alpha
remain on the original universal-mask path.

When G5 is enabled, the G4 coordinate-warp calculation is skipped for that
material rather than accumulated underneath the replacement. When G5 is
disabled, no G5 colour or detail calculation affects the result and the shader
uses the prior G4 path exactly.

### Material-specific detail

| Material | Base palette | Detail treatment | Default intensity |
|---|---|---|---:|
| Sand | `#e4c381` | Sparse single-pixel grains with restrained fine colour variation | 0.95 |
| Dirt | `#8a6343` | Irregular single- and two-pixel grains in both axes | 1.00 |
| Stone | `#909ba0` | Sparse one- to three-pixel horizontal mineral flecks | 1.00 |
| Mud | `#815e48` | Fewer, subdued single and paired pores | 1.00 |

The catalog also supplies material-specific detail colour, density, and palette
variation. These are rendering metadata, not authoritative terrain data.

Snow was evaluated and left unchanged because its low-contrast surface is
already visually restrained. Gravel was evaluated and left unchanged because
procedurally replacing its dense stone field would materially change its
established identity; a convincing gravel correction requires new or larger
source art. Both decisions follow the requirement not to process a material
when the visual result is worse.

### Configuration and rollback

`Main` exposes:

- `stochastic_terrain_detail_enabled`;
- per-material enable switches for sand, dirt, stone, and mud;
- per-material intensity controls.

`TerrainRenderer` owns the runtime presentation state and updates the shared
materials in place. Runtime switching does not invalidate chunks. G5 settings
are intentionally excluded from generation and save configuration.

## Visual comparisons

The Godot 4.7 graphical harness generated 36 matched captures and 18 side-by-side
comparisons. The left half is G5 disabled (the G4 baseline); the right half is
G5 enabled. Seed, camera, terrain, material boundaries, and zoom are identical.

Primary dirt comparisons:

- `.artifacts/g5_compare_dirt_seed84521_z1_0x.png`
- `.artifacts/g5_compare_dirt_seed84521_z1_5x.png`
- `.artifacts/g5_compare_dirt_seed84521_z2_0x.png`

Primary stone comparisons:

- `.artifacts/g5_compare_stone_seed84521_z1_0x.png`
- `.artifacts/g5_compare_stone_seed84521_z1_5x.png`
- `.artifacts/g5_compare_stone_seed84521_z2_0x.png`

Sand and mud have corresponding `z1_0x`, `z1_5x`, and `z2_0x` comparisons.
Snow and gravel comparison captures confirm that their G5 material path remains
disabled. Mixed materials with elevation and cliff edges are captured in:

- `.artifacts/g5_disabled_mixed_elevation_seed84521.png`
- `.artifacts/g5_enabled_mixed_elevation_seed84521.png`

An alternate-seed stone capture is stored as
`.artifacts/g5_enabled_stone_seed13579_z1_5x.png`. Full capture metadata is in
`.artifacts/g5_capture_manifest.json`.

Manual visual review found:

- dirt's diagonal/checkerboard speckle field is removed and replaced with
  irregularly spaced grains of varying one- and two-pixel size;
- stone's repeated rows and identical fleck clusters are removed while sparse
  horizontal mineral marks retain a rocky pixel-art character;
- sand retains fine, subtle grain without a visible tile phase;
- mud retains subdued pores without excessive noise;
- no new regular grid or broad probability band is visible;
- material boundaries, elevations, and chunk boundaries remain continuous;
- detail remains crisp and stationary at 100%, 150%, and 200% zoom;
- streaming away and returning reproduced the captured pixels exactly.

## Performance

Matched 240-frame measurements were taken in the same mixed-material fixture on
the Compatibility renderer and NVIDIA GeForce RTX 3080:

| Mode | Average frame | p95 | p99 | Average draw calls | Static memory |
|---|---:|---:|---:|---:|---:|
| G4 baseline | 1.076 ms | 1.454 ms | 1.613 ms | 110 | 88.6269 MiB |
| G5 enabled | 1.105 ms | 1.536 ms | 1.643 ms | 110 | 88.6291 MiB |

The measured average cost was 0.029 ms (approximately 2.7%) in this fixture.
Draw calls were unchanged. The 0.0023 MiB memory difference is measurement noise;
G5 allocates no textures, nodes, or per-chunk resources. G4 warp noise is skipped
when G5 replaces it, avoiding redundant shader work.

## Validation

All bounded tests used Godot 4.7 stable.

| Check | Result |
|---|---|
| Full project import and script parse | PASS (exit 0; isolated Windows editor settings emitted a safe-save warning) |
| Main-scene startup | PASS |
| Focused G5 deterministic/detail validation | PASS |
| G5 graphical capture and benchmark | PASS — 36 captures, 18 comparisons |
| G1 clustered grass | PASS |
| G2 grass surface variation | PASS |
| G3 grass repetition correction | PASS |
| G4 material phase correction | PASS |
| C4A renderer configuration | PASS |
| C4B renderer factories | PASS |
| Terrain generation/elevation (Phase 5D) | PASS |
| Chunk streaming/lifecycle (Phase 1G) | PASS |
| Save/load (Phase 7B1) | PASS |
| Water rendering (Phase A) | PASS |
| Cliff rendering (Phase 3G structural) | PASS |
| 32-pixel repetition test | PASS — feature coordinates do not repeat at source period |
| Stream-away/return | PASS — pixel-exact |
| Excluded material uniforms | PASS — grass, water, snow, and gravel remain outside G5 |
| Draw-call parity | PASS — 110 in both modes |
| `git diff --check` | PASS |

The import warning concerns safe-saving a temporary isolated Windows editor
settings file. Project scanning, script registration, runtime startup, and all
validators completed successfully.

## Remaining limitations

- The procedural layer deliberately replaces the four materials' original fine
  fleck layout. Their base palette and characteristic feature type remain, but
  exact source-pixel placement is available only through G5 rollback.
- Gravel retains its existing repetition. Correcting it convincingly requires a
  larger or genuinely stochastic gravel asset and was not forced into this
  phase.
- Snow retains its subtle source pattern because processing did not offer a
  clear improvement.
- Cliff-face materials use a separate resource and shader path and were not
  modified.
