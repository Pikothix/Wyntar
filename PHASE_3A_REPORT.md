# Phase 3A — Procedural Vegetation Vertical Slice

## Task Classification

Existing System Extension — procedural environmental asset generation and rendering.

## Files Changed

Production:

- `scripts/main.gd`
- `scripts/terrain_renderer.gd`
- `scripts/environment_object_renderer.gd`
- `scripts/environment_object_layer.gd`
- `scripts/procgen/environment_object_sprite_factory.gd`

Validation and evidence:

- `tests/phase3a_validation.gd`
- `tests/phase3a_benchmark.gd`
- `tests/phase3a_capture.gd`
- `screenshots/phase3a_tree_family_showcase.png`
- `screenshots/phase3a_existing_tree_assets_ab_1_0x.png`
- `screenshots/phase3a_procedural_tree_assets_ab_1_0x.png`
- `screenshots/phase3a_natural_gameplay_forest_1_0x.png`
- `screenshots/phase3a_benchmark_headless.json`
- `screenshots/phase3a_benchmark_graphical.json`
- `PHASE_3A_REPORT.md`

## Reused Environmental Architecture

The project already contained deterministic procedural tree generation in
`proc_trees.gd`, palette/profile data in `tree_profiles.gd`, catalogued tree
identities in `environment_object_catalog.gd`, coordinate-seeded placement in
`environment_object_placement.gd`, and four elevation-sorted global draw
batches in `environment_object_renderer.gd`. Phase 3A therefore extends that
path instead of creating another placement, caching, or node system.

TerrainWorld remains authoritative. Placement still chooses an existing
definition and bounded variant from stable world coordinates and the world
seed. The presentation seed is derived from that definition/variant identity,
so equivalent appearances share one atlas cell. Chunk-owned object data still
enters and leaves the existing global batches through the Phase 1G bounded
retirement path. No tree owns a scene node.

## Procedural Generation

The reused deciduous generator constructs a tapered trunk and recursive branch
skeleton, then builds an asymmetric connected crown from three-to-six lobes.
Seeded crown proportions, lean, lobe positions, foliage layers, rim shaping,
trunk dimensions, branches, and restrained palette variation create structural
rather than scale-only differences.

The reused conifer generator constructs three-to-six independently varied,
overlapping branch tiers around a tapered trunk. Seeded tier count, width,
height, spacing, taper, lean, shade, and trunk exposure produce distinct
silhouettes. Both families remain pixel-quantised and use the existing
coordinated trunk/foliage palette profiles.

Phase 3A adds a quantised south-east ground shadow to procedurally generated
tree atlas cells and alpha-composites the generated tree over it. Nearest-neighbour
atlas rendering, the existing root anchor, and elevation-sorted batches remain
unchanged.

The cache is fixed and bounded: 14 catalogued tree appearances are generated
once into the existing 66-cell shared atlas. A second fixed atlas replaces only
the tree cells with the legacy assets. `procedural_vegetation_enabled` swaps
these atlas resources without rebuilding chunks, changing placement, or adding
save data. Both texture instance IDs remained stable across repeated switches
and streaming; runtime rasterisation count was zero.

## Visual Results

- The isolated fixture shows 12 deciduous and 12 conifer seeds at 100% scale.
- Automated silhouette checks found at least 10 distinct alpha structures in
  each 12-member family and verified same-sized outputs with different alpha
  signatures, excluding scale/recolour-only variation.
- The curated A/B uses identical object IDs, variants, anchors, terrain, and
  camera position. Only the procedural presentation setting changes.
- The forest/gameplay fixtures show both families together, beside a cliff and
  on two elevation bands. The normal gameplay capture uses the existing
  terrain-aware placement pipeline.
- Manual inspection confirmed readable family resemblance, meaningful crown
  and tier differences, correct root contact, coherent shadows, and unchanged
  top-down terrain/cliff presentation.

## Performance Results

Measured with Godot 4.7 stable on the Windows/OpenGL renderer, over five
streaming routes:

| Metric | Phase 3A | Phase 1G recorded baseline |
| --- | ---: | ---: |
| Average frame | 2.542 ms | 6.121 ms |
| Mean p95 | 4.089 ms | 7.966 ms |
| Mean p99 | 5.387 ms | 9.050 ms |
| Worst frame | 14.935 ms | 21.312 ms |
| Worst chunk finalisation | 0.196 ms | — |

The baseline and Phase 3A fixture routes are not an exact microbenchmark pair,
so the lower Phase 3A frame values are evidence of no observed regression, not
a claimed speed-up from vegetation.

Additional measurements:

- Direct generation of the 24 showcase variants: **211.879 ms** total.
- Full 66-cell procedural plus rollback atlas build: **252.394 ms** at startup.
- Incremental cost of the legacy rollback atlas: **10.858 ms** at startup.
- Runtime texture generation during streaming: **0**.
- Logical cache hit rate after precomputation: **100%**.
- Two bounded 6336×96 RGBA atlases: **4.641 MiB** total.
- Twenty presentation-mode switches: **0.034 ms** total.
- Per-route environment preparation: **89.648–101.041 ms** total across each
  multi-chunk camera route; submission: **12.231–18.832 ms**.
- Visible-route total scene draw calls: **156.5–159.3** average. The renderer
  still uses four environmental CanvasItems; trees do not add per-object nodes.
  Three routes returned zero draw-call samples from the renderer counter and
  were not treated as valid visible draw-call readings.
- Repeated route peak static memory was **60.076 MiB** at most in visible runs;
  final static memory was **59.835 MiB**, with 347 nodes and 33 resources.
  Measurements did not grow monotonically across load/unload cycles.

The one-time procedural atlas build remains synchronous at application startup,
but no procedural generation was added to chunk preparation, finalisation, or
retirement.

## Validation

Passed dedicated Phase 3A checks for:

- identical-seed image determinism;
- distinct-seed silhouette variation;
- five-or-more opaque coordinated colours;
- root anchoring and ground-shadow alpha;
- fixed atlas size, stable cache identities, and zero runtime generation;
- water, terrain, and elevation placement restrictions;
- unchanged authoritative resource snapshots and persistence-facing data;
- streaming ownership, bounded retirement, and cleanup;
- reversible presentation while chunks are loaded.

Regression scripts passed:

- Phase 1A, 1B, 1D, 1E, 1F, and 1G;
- Phase 6B environmental objects;
- Phase 7C.4 and 7C.5;
- Phase 8A procedural generation and Phase 8B resource state;
- Phase 3A validation.

The main scene also completed a 120-frame headless startup/run without parser or
runtime errors. Graphical screenshot capture and the graphical benchmark both
passed. A source scan found no conflict markers or trailing whitespace in the
changed scripts. `git diff --check` could not run because this supplied project
directory is not a Git worktree.

## Known Limitations and Recommendation

- The fixed rollback texture intentionally adds 2.320 MiB so A/B switching is
  immediate and cannot trigger regeneration during streaming.
- All procedural environmental variants, not only trees, were already part of
  the shared atlas startup cost. The 252 ms startup build should be revisited
  only if startup latency becomes a product requirement; moving it into chunk
  work would violate the current bounded, generation-free streaming behavior.
- Fourteen runtime tree appearances are deliberately limited for this visual
  review. Dense forests will repeat at large scales.
- Shadows are baked presentation pixels; they do not react to dynamic lighting.

Recommendation: **stop for visual review as requested**. If the art direction is
accepted, the next environmental slice should add one tightly scoped family
(for example shrubs or deadwood) through the same catalog, fixed atlas, stable
placement identity, and global batch path. Do not expand the tree variant count
or begin a broader biome overhaul until this visual language is approved.
