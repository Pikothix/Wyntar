# Wyntar Phase C4B Renderer Factory Report

Date: 2026-10-21

Task classification: Existing System Refactor — behaviour-preserving rendering architecture cleanup

Starting branch and commit: `main` at `71f81ce` (`Phase C4A: consolidate renderer configuration`)

## 1. Files changed

- `scripts/terrain_renderer.gd`
  - Delegates initialization-only terrain, cliff, decoration and environment resource creation.
  - Retains all returned runtime references, renderer configuration, shared-material updates, chunk lifecycle and world interaction.
- `scripts/terrain_surface_factory.gd` and `.uid`
  - Creates terrain materials, visual variants, masked atlases and the terrain `TileSet`.
- `scripts/cliff_resource_factory.gd` and `.uid`
  - Creates legacy cliff wall/edge atlases, shared wall/shadow materials and the organic cliff material.
- `scripts/terrain_detail_atlas_factory.gd` and `.uid`
  - Creates decoration and environment atlas resources, including procedural, unripe and legacy-tree variants.
- `tests/phase_c4b_renderer_factory_validation.gd` and `.uid`
  - Adds focused factory structure, layout, parameter, identity, determinism, replacement and cleanup coverage.
- `PHASE_C4B_RENDERER_FACTORY_REPORT.md`
  - Records the extraction and validation.

The pre-existing `main.tscn`, dirty `_reference` gitlink checkout and untracked pager artifact were not modified.

## 2. Functions extracted

Terrain surface creation moved out of `TerrainRenderer`:

- Shared terrain `TileSet` construction and source registration.
- Terrain shader material creation and parameter initialization.
- Visual variant tint/brightness/contrast generation.
- Universal 4x4 masked atlas generation and mask-field helpers.
- Initial and runtime water-enhancement parameter application.

Cliff resource creation moved out of `TerrainRenderer`:

- Legacy cliff wall and contact-shadow material creation.
- Organic combined-geometry material creation.
- Legacy wall atlas generation.
- Legacy edge/lip/side-return atlas generation.
- Shared material assignment across wall and edge sources.

Detail atlas assembly moved out of `TerrainRenderer`:

- Decoration atlas ordering, texture creation and `TileSet` construction.
- Environment atlas ordering and procedural sprite-factory integration.
- Food-resource unripe variant allocation.
- Procedural and legacy-tree atlas creation and active-atlas selection.
- Atlas metrics and lookup-map production.

The established legacy pixel painters remain private renderer callbacks supplied to the detail factory. Their drawing algorithms were not rewritten, which minimizes visual risk while moving atlas allocation, ordering and resource creation into the factory.

## 3. Responsibilities before and after

Before C4B, `TerrainRenderer` both orchestrated streaming/runtime rendering and directly created all shared rendering resources.

After C4B:

- `TerrainRenderer` owns chunk scheduling, streaming, renderer configuration, runtime resource references, shared parameter updates, world interaction, invalidation and retirement.
- `TerrainSurfaceFactory` creates the terrain surface resource bundle from catalog definitions and an immutable configuration snapshot.
- `CliffResourceFactory` creates the complete legacy/organic cliff resource bundle in one call so wall and edge sources share the same materials.
- `TerrainDetailAtlasFactory` creates decoration/environment atlas bundles while using the existing deterministic procedural sprite factory and legacy painters.

The factories are stateless `RefCounted` scripts. They do not own simulation state, scene nodes, chunk state, authoritative terrain, resource state or persistence.

## 4. Resource ownership and lifetime

Creation order remains terrain surfaces, cliff walls/materials, cliff edges, decorations, then environment objects. The cliff edge wrapper now verifies the edge atlas already created with the cliff bundle; this preserves the original `_ready()` sequence without a second creation pass.

Each renderer creates one bundle during `_ready()` and stores the returned references. Chunk renderers continue to receive those shared resources. Runtime water and cliff toggles mutate the same shared material objects. No factory is called per frame or per chunk.

Renderer replacement creates a fresh resource graph for the replacement renderer, as before. The focused validator confirms the retired renderer is released and the replacement produces deterministic equivalent resources.

## 5. Factory output comparisons

The focused validator checks:

- Terrain source count, sixteen-mask layout and 128x128 atlas dimensions.
- Cliff source count, 32 wall variants plus shadow row, and 1024x32 atlas dimensions.
- Cliff edge 9x15 populated layout and 512x288 atlas dimensions.
- Decoration catalog ordering and total variant count.
- Environment 96-pixel cell layout, definition coverage and unripe lookup allocation.
- Terrain, water and cliff shader references and representative parameter values.
- Terrain tile-to-material identity and cliff-edge-to-wall material identity.
- SHA-256 hashes for terrain, cliff, edge, decoration, procedural-environment and legacy-environment images across independent renderer creation/replacement.

The hash comparison is between two post-refactor renderer lifecycles. Existing phase validators supply the pre-existing behavioural baseline; no pre-refactor binary oracle was added to the repository.

## 6. Validation results

Validation used standard Godot `4.7.stable.official.5b4e0cb0f` with isolated local app-data directories. Every Godot process had an explicit 120-second timeout.

| Check | Result |
| --- | --- |
| Project import and parse | Pass; no script/import failure. The isolated editor run emitted a non-fatal editor-settings safe-save warning. |
| Main-scene startup (`--quit-after 3`) | Pass |
| C4A renderer configuration validator | Pass |
| C4B renderer factory validator | Pass |
| Phase 5D terrain/chunk validator | Pass |
| Phase A water validator | Pass |
| Phase 3G cliff validator | Pass; structural only, as documented by that validator |
| Phase 6A decoration validator | Pass |
| Phase 3A environment/procedural atlas validator | Pass |
| Phase 7B.1 save/load validator | Pass |
| Phase 8B resource interaction validator | Pass |
| `git diff --check` | Pass; only pre-existing line-ending warnings for `main.tscn` and the modified renderer were emitted |

No screenshots or large visual evidence collections were generated. Structural validation does not independently certify visual equivalence.

## 7. Performance and memory differences

The final bounded Phase 5D run completed 25 chunks at 6.427 ms average, 7.260 ms p95, 7.458 ms p99 and 7.458 ms worst. There is no directly comparable same-machine pre-refactor sample in this phase, so no performance improvement or regression is claimed.

The extraction adds only short-lived result dictionaries during renderer initialization. Resource counts, sharing points and creation frequency are unchanged; no per-frame or per-chunk factory allocation was introduced. No dedicated before/after memory measurement was available, so no memory difference is claimed.

## 8. Remaining risks

- Automated checks are structural and deterministic; manual visual inspection remains the appropriate confirmation for terrain, cliffs, water and object appearance.
- Legacy fallback pixel painters remain in `TerrainRenderer` and are passed into the detail factory as callbacks. Moving those algorithms would be a separate small refactor and is not required for resource ownership separation.
- The isolated editor import emitted an editor-settings safe-save warning despite returning success; gameplay/test runs were clean.
- Existing experimental cliff configurations, legacy paths and rendering defaults remain intentionally unchanged.

## 9. Recommended next phase

Review and commit C4B independently. A later architect-approved phase may move the legacy decoration/environment pixel painters into a presentation helper or consolidate cliff experiment flags, but those changes should remain separate from this factory extraction and must retain visual acceptance coverage.
