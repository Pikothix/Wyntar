# Phase G7 — Terrain Surface Noise Refinement

## Outcome

Phase G7 reduces uniform high-contrast microdetail on dirt, stone, mud, and
gravel while preserving the G5/G6 world-space reconstruction. The reviewed
defaults produce broad quiet regions separated by irregular detail clusters.
Material palettes, broad tonal variation, pixel edges, transitions, and the
distinctly busier gravel treatment remain intact.

`terrain_noise_refinement_enabled` is the exact A/B switch. Disabling it skips
all G7 density, contrast, clear-area, and clustering calculations and restores
the original G6 mark distribution. Individual material settings are exposed in
Main's Inspector and travel through the R3 terrain-rendering configuration.

This is presentation-only. No terrain generation, cell data, elevation, cliff
geometry, save data, or gameplay ownership changed.

## Root causes

The visible noise came from several layers rather than one parameter:

1. The original 32×32 textures contain fixed dark pixels: dirt has 44 darkest
   pixels, stone 123, mud 22, and gravel 140 per source tile. G5/G6 correctly
   replace these repeated coordinates while enabled, so they are the baseline
   problem only when those reconstruction paths are disabled.
2. G5 generated independent world-pixel anchors for dirt, stone, and mud. Dirt
   then extended some anchors horizontally or vertically; stone extended more
   of them into two- and three-pixel mineral marks. Their placement was
   deterministic and non-repeating, but spatially near-uniform.
3. G6 gravel used a separate set of hard-coded world-pixel anchor rates and
   neighboring fragment rules. This retained material identity but kept a high
   density of isolated high-contrast fragments.
4. G5/G6 broad and fine palette variation remains as a low-contrast background
   layer. It was not the main source of black flecks, but it compounded the
   perceived activity beneath the detail pixels.
5. G4 coordinate warping is inactive while a G5/G6 reconstruction branch is
   active, so overlapping G4 and G5/G6 detail was not the cause.

G7 therefore changes mark distribution and contrast rather than blurring or
fading the completed surface.

## Materials changed

- Dirt: fewer retained anchors, large clear regions, occasional compact groups.
- Stone: fewer tiny marks while preserving longer horizontal mineral features.
- Mud: sparse pores plus subtle irregular broad darkening in wet-detail regions.
- Gravel: reduced isolated fragments while remaining more detailed than dirt.

Sand, snow, grass, water, cliff rendering, and terrain boundaries do not opt in
to G7. Natural-scene matched captures confirm their output remains unchanged.

## Before and after settings

The G6 baseline had full contrast, no clear-area mask, and no cluster field.
Density values below are multipliers over the existing G5/G6 rates; they do not
replace the catalog's material identity values.

| Material | G6 detail source | G6 density / contrast | G7 density | G7 contrast | Clear area | Cluster scale |
|---|---|---:|---:|---:|---:|---:|
| Dirt | G5, base density `0.028` plus paired grains | `1.00 / 1.00` | `0.70` | `0.68` | `0.55` | `0.006` |
| Stone | G5, base density `0.034` plus mineral runs | `1.00 / 1.00` | `0.85` | `0.72` | `0.45` | `0.005` |
| Mud | G5, base density `0.020` plus paired pores | `1.00 / 1.00` | `0.65` | `0.55` | `0.60` | `0.004` |
| Gravel | G6, base anchor probability `0.053` plus fragments | `1.00 / 1.00` | `0.85` | `0.72` | `0.35` | `0.008` |

Clear regions retain 10% of the adjusted dirt/stone/mud rate and 25% of the
adjusted gravel rate. This prevents hard empty bands while making the cluster
field visibly meaningful. The focused distribution test measures more than a
50% reduction in representative dirt anchors and at least a threefold density
separation between reviewed quiet and detailed regions.

## Visual comparisons

Every image uses world seed `84521`, the same camera cell, and the same zoom on
both sides. Left is the G6 baseline; right is G7 refined. The capture is a
600×600 center crop per side.

| Scenario | 100% | 175% | 250% | 350% |
|---|---|---|---|---|
| Dirt | [compare](.artifacts/g7/g7_compare_dirt_z1_0x.png) | [compare](.artifacts/g7/g7_compare_dirt_z1_75x.png) | [compare](.artifacts/g7/g7_compare_dirt_z2_5x.png) | [compare](.artifacts/g7/g7_compare_dirt_z3_5x.png) |
| Stone | [compare](.artifacts/g7/g7_compare_stone_z1_0x.png) | [compare](.artifacts/g7/g7_compare_stone_z1_75x.png) | [compare](.artifacts/g7/g7_compare_stone_z2_5x.png) | [compare](.artifacts/g7/g7_compare_stone_z3_5x.png) |
| Mixed dirt/stone | [compare](.artifacts/g7/g7_compare_mixed_z1_0x.png) | [compare](.artifacts/g7/g7_compare_mixed_z1_75x.png) | [compare](.artifacts/g7/g7_compare_mixed_z2_5x.png) | [compare](.artifacts/g7/g7_compare_mixed_z3_5x.png) |
| Gravel/mud | [compare](.artifacts/g7/g7_compare_gravel_mud_z1_0x.png) | [compare](.artifacts/g7/g7_compare_gravel_mud_z1_75x.png) | [compare](.artifacts/g7/g7_compare_gravel_mud_z2_5x.png) | [compare](.artifacts/g7/g7_compare_gravel_mud_z3_5x.png) |
| Natural terrain | [compare](.artifacts/g7/g7_compare_natural_z1_0x.png) | [compare](.artifacts/g7/g7_compare_natural_z1_75x.png) | [compare](.artifacts/g7/g7_compare_natural_z2_5x.png) | [compare](.artifacts/g7/g7_compare_natural_z3_5x.png) |

The complete capture metadata is in
`.artifacts/g7/g7_capture_manifest.json`. Manual review found no returning 32×32
tile grid, camera-relative movement, blurred marks, or transition damage. At
normal gameplay zoom, the refined side has substantially quieter dirt and
stone while their palettes and mark shapes remain distinct. At 350%, retained
features remain nearest-neighbor pixel forms.

## Performance impact

Godot 4.7.2 Compatibility renderer, NVIDIA GeForce RTX 3080, 1280×720, 240
frames per state in the same scene:

| State | Average frame | p95 frame | Draw calls | Static memory |
|---|---:|---:|---:|---:|
| G6 baseline | 1.310 ms | 2.751 ms | 142.0 | 92.649 MiB |
| G7 refined | 1.075 ms | 1.347 ms | 142.0 | 92.652 MiB |

The lower G7 times are treated as benchmark variance, not an optimization
claim. The meaningful results are unchanged draw-call count and approximately
0.002 MiB static-memory difference. G7 adds shader arithmetic only to four
existing shared materials and creates no new draw calls or resources.

## Regression results

All bounded checks ran with Godot `4.7.2-stable`:

- Main scene parse/startup: pass.
- Phase G1, G2, G3, G4, G5, and G6 validations: pass.
- Phase G7 focused validation: pass.
- Material eligibility, runtime adjustment, rollback, deterministic
  distribution, and authoritative-state isolation: pass.
- Fixed-camera captures at 100%, 175%, 250%, and 350%: 40 captures and 20
  matched comparisons produced.
- Camera movement, chunk streaming, and revisit: pixel-exact pass.
- Phase 7B1 save/load validation: pass; G7 remains absent from authoritative
  generation/save configuration.
- R3 rendering configuration validation: pass.
- C4E cliff geometry and C4F grid-cliff validations: pass.
- `git diff --check`: pass.

The Mono build emitted its existing `.NET: Assemblies not found` startup
message in this GDScript-only project. Each listed validation completed with
exit code 0 despite that environment warning.

## Remaining issues

- Visual review and performance sampling used one GPU and the Compatibility
  renderer. Other GPUs may produce different timing, though placement uses the
  same bounded deterministic hashes.
- Cluster controls intentionally affect spatial density, not the broad palette
  variation. Extremely low contrast values can make a material deliberately
  flat; the reviewed defaults avoid that range.
- G7 does not alter the legacy source textures. Disabling G5/G6 still exposes
  their original 32×32 dark-pixel layouts by design.

## Recommended defaults

Keep G7 enabled with the tabled values. They give dirt the strongest requested
quiet-area treatment, retain more geological structure on stone, keep gravel
busier than dirt, and replace mud's uniform pores with sparse marks and soft
irregular patches. Use the global toggle for exact G6 A/B comparison and the
material-specific Inspector controls for later art-direction adjustments.
