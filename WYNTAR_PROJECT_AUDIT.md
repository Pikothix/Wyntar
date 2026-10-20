# Wyntar Project Architecture, Code, and Repository Hygiene Audit

Audit date: 2026-10-20

Scope: tracked repository at `a657842` plus relevant local/ignored files

Classification: Existing System Audit — research, analysis, and cleanup planning only

## 1. Executive summary

Wyntar already has a sound authority boundary for its intended top-down game: `TerrainGenerator` deterministically derives base cells, `TerrainWorld` owns mutable terrain/elevation overrides, `ResourceStateManager` owns sparse mutable resource state, renderers consume those states, UI/controllers request changes, and `WorldSaveService` serializes authoritative state rather than render caches. That foundation should be kept.

The simplest viable target architecture is therefore the existing **top-down `TerrainWorld` + chunk build job + chunk renderer path**, with the accepted organic cliff path reduced to one production configuration. A new world model, 3D terrain system, or oblique renderer is not required.

The main problems are concentration and accumulated experiment scaffolding:

- `scripts/terrain_renderer.gd` is 2,605 lines, 135 functions, and owns generation setup, authority façade methods, chunk scheduling, editing invalidation, save import/export adapters, resource state, five atlas/material factories, top-down rendering, organic cliffs, legacy cliffs, and oblique presentation.
- `scripts/main.gd` is 1,121 lines and combines bootstrap/configuration, camera/input, editing orchestration, resource interaction, save-world replacement, HUD creation, debug display, and editor UI construction.
- The organic cliff feature is a stack of six interacting switches plus a three-value height profile, while a fully populated legacy cliff path remains available as fallback. The code is testable, but the number of simultaneous paths is disproportionate to the desired single top-down presentation.
- The repository contains 2,461 tracked screenshot/evidence files using 605.81 MiB. They represent more than 99% of tracked working-tree bytes. The Git pack is 514.02 MiB.
- Tracked Godot/editor caches add 4.28 MiB. Three accidental files are identical captures of a `less` help screen. A 29.55 MiB RAR, a duplicate `New folder/`, and 129 duplicate payload groups are in `screenshots/`.
- `_reference` is a gitlink to the separate Isolony repository but has no `.gitmodules` entry. Its local checkout is heavily dirty and is not a reproducible dependency. It also sits inside the Godot project without a `.gdignore`.
- Project identity is still `Universal Mask Terrain` in `project.godot:13`, `project.godot:25`, `README.md:1`, and `scripts/main.gd:864`; this conflicts with Wyntar.
- The project is GDScript-only, but `project.godot:23-25` contains a .NET assembly setting. A tracked historical log records `.NET: Assemblies not found`.
- There is a material configuration contradiction: the Phase 3G report says not to promote directional projection (`PHASE_3G_DIRECTIONAL_CLIFF_REPORT.md:211-225`), while committed `main.tscn:8` enables it. The current uncommitted scene additionally enables prominent height, enhanced water, and a demo overlay.
- Phase 3H is unfinished by design: `PHASE_3H_SHARED_BOUNDARY_ARCHITECTURE.md:7` calls it investigation only, and line 628 confirms implementation has not begun.

Estimated cleanup opportunity:

- **Immediate working-tree reduction:** about **610 MiB** by stopping Git tracking of generated evidence, caches, logs, and accidental pager files after preserving an approved reference set.
- **Immediate object-store limitation:** a normal cleanup commit will not remove the existing 514 MiB from clone history. History rewriting is a separate, high-risk decision and is not required to clean future checkouts.
- **Code simplification:** retire the 675-line oblique subsystem and its shader after approval; then collapse cliff rollback/experiment switches around one accepted top-down configuration. Exact code deletion should follow regression consolidation, not precede it.

Recommended first cleanup phase: **C1 — repository hygiene**, because it is architecture-neutral, reversible, and removes the largest source of noise and project scanning cost without touching terrain authority, saves, camera behavior, or production visuals.

## 2. Audit boundary and working-tree state

No production file was changed by this audit. The only added file is this report.

Pre-existing state at audit start:

| Target | State | Treatment in this audit |
|---|---:|---|
| `main.tscn` | Modified | Preserved; committed and working-tree settings are reported separately. |
| `_reference` | Dirty gitlink worktree | Preserved; no nested files were changed. |
| Untracked non-ignored files inside repository | 0 | None. |
| Ignored files | 2,469 under `.godot/`, about 494.65 MiB | Treated as generated import/cache data, not cleanup output. |
| Adjacent `G:/Sim/phase3g*.log` files | 20 files, about 3 KiB total | Relevant local historical evidence outside the repository; recommend archive/delete outside this Git cleanup after approval. |

The current `main.tscn` working-tree additions are at lines 7-16. They enable the elevation demo, enhanced water, prominent cliff height, hide cliff overlays/shadows, and double decoration/environment density. These are user changes and must not be reset by cleanup work.

## 3. Repository size and file inventory

### 3.1 Tracked inventory

The repository tracks 2,787 entries. Regular tracked files use approximately 611.79 MiB. `_reference` is a gitlink and therefore has no regular-file size in this total.

| Category | Tracked entries | Approx. size | Assessment |
|---|---:|---:|---|
| Screenshots/generated evidence (`screenshots/**`) | 2,461 | 605.81 MiB | Historical/generated; dominant cleanup opportunity. |
| Godot/tool caches and logs | 20 | 4.28 MiB | Generated; should not be tracked. |
| Documentation/reference images | 24 | 0.61 MiB | Keep active docs; archive milestone reports selectively. |
| Tests and benchmarks | 188 | 0.51 MiB | 93 GDScript test programs, 1 shader fixture, and 94 UID files. |
| Production/runtime code | 38 | 0.39 MiB | 19 GDScript files plus UID files, excluding procgen and oblique. |
| Procedural asset-generation code | 20 | 0.07 MiB | 10 GDScript files plus UID files. |
| Accidental pager artifacts | 3 | 0.05 MiB | Confirmed redundant. |
| Experimental oblique code | 6 | 0.02 MiB | 3 GDScript files plus UID files. |
| Runtime terrain assets (`art/**`) | 16 | 0.02 MiB | Required textures and import metadata. |
| Shaders | 6 | 0.02 MiB | 3 shaders plus UID files. |
| Third-party notice | 1 | 0.001 MiB | Legally required; keep. |
| Scene/project resources | 2 | 0.001 MiB | `main.tscn` and `project.godot`. |
| Repository metadata | 1 | 0.0001 MiB | `.gitignore`. |
| External reference gitlink | 1 | gitlink | Broken/unreproducible as a submodule; see §8. |

Code volume:

| Code set | Scripts | Lines |
|---|---:|---:|
| Core production/runtime scripts | 19 | 9,305 |
| Procedural sprite generators | 10 | 1,364 |
| Oblique experiment | 3 | 675 |
| Test programs | 93 | 13,522 |

The test code is larger than the production code because each development phase retained validators, capture harnesses, and benchmarks.

### 3.2 Screenshots and generated evidence

`screenshots/` contains:

| Type | Files | Approx. size |
|---|---:|---:|
| PNG captures | 1,211 | 574.81 MiB |
| PNG `.import` sidecars | 1,211 | 1.20 MiB |
| JSON benchmarks/manifests/comparisons | 38 | 0.24 MiB |
| RAR archive | 1 | 29.55 MiB |

The largest phase families are Phase 3G (274 entries, 52.45 MiB), Phase 3F (202, 41.71 MiB), Phase A water (152, 40.01 MiB), Phase 7C.4 (224, 35.57 MiB), and Phase 3E (147, 34.28 MiB).

Hashing all non-`.import` evidence found **129 exact duplicate payload groups**, comprising 301 files and **79.06 MiB reclaimable** if one copy per group is retained. This is only a lower bound; near-duplicate captures were not image-compared.

Unusually large items:

| Target | Size | Finding |
|---|---:|---|
| `screenshots/New folder.rar` | 29.55 MiB | Unexplained archive inside generated output; not runtime-referenced. Inspect contents before removal. |
| `.codex_godot_appdata/Godot/cache/editor_doc_cache-4.7.res` | 3.12 MiB | Generated Godot editor documentation cache. |
| `screenshots/phase7c_after_dense_stone_gravel_0_5x.png` | 1.34 MiB | Largest individual PNG. |
| `screenshots/New folder/` | 102 files, 29.95 MiB | Duplicate-looking historical folder; multiple contents hash-match top-level files. |
| `.godot/` (ignored) | 2,469 files, 494.65 MiB | Normal generated project cache; remains ignored. |
| `_reference/` local checkout | 468 files, 29.37 MiB | Separate dirty Isolony checkout, not regular tracked content of this repository. |

The seven commits show evidence accumulating with each feature phase. The initial commit added 1,719 files; later Phase 3E and Phase A commits added 277 and 663 files respectively. This confirms that the screenshot set is milestone evidence rather than a runtime asset library.

### 3.3 File classification details

**Production code:** top-level scripts excluding the three oblique scripts; all are reachable through `main.gd`, `terrain_renderer.gd`, their preloads, or tests.

**Scenes/resources:** one minimal `main.tscn`; project nodes and UI are otherwise constructed in code.

**Shaders:** `terrain_variation.gdshader`, `cliff_procedural.gdshader`, and experimental `oblique_terrain.gdshader`.

**Procedural systems:** `terrain_generator.gd`, placement/catalog scripts, `terrain_chunk_build_job.gd`, `organic_cliff_mesh_builder.gd`, and `scripts/procgen/**`.

**Runtime assets:** eight `art/*.png` textures and their import metadata.

**Tests/benchmarks:** `tests/**`; source should remain until a permanent suite supersedes it.

**Documentation:** `README.md`, `CLIFF_IMPROVEMENT_PLAN.md`, phase reports, architecture investigation, and upgrade brief.

**Logs/temp:** `.codex_appdata/**`, `.codex_godot_appdata/**`, `phase5d_validation.log`, and adjacent Phase 3G logs.

**Historical prototypes:** oblique scripts/shader/tests, old capture matrices, `CODEX_UPGRADE_BRIEF.md`, and milestone reports.

**Third party/provenance:** `THIRD_PARTY_NOTICES.md`, README source links, and `_reference` Isolony gitlink.

**Unknown/redundant:** the RAR until inspected and three pager-capture files.

## 4. Architecture overview

### 4.1 Ownership map

| Data/responsibility | Owner/modifier | Readers | Renderer | Persistence |
|---|---|---|---|---|
| Base terrain material/elevation rules | `TerrainGenerator` (`terrain_generator.gd:29-118`) | `TerrainWorld` | None directly | Generation config only |
| Mutable material/elevation overrides | `TerrainWorld` (`terrain_world.gd:13-15`, `28-141`) | Renderer/build jobs/controllers | Top-down/oblique renderers | `TerrainWorld.export_override_snapshot()` |
| Derived water visibility/surface elevation | `TerrainWorld` query policy (`terrain_world.gd:60-87`) | build jobs, renderer, editor picking | Terrain shader/layers | Underlying material/elevation only |
| Chunk demand/build scheduling | `TerrainRenderer` (`terrain_renderer.gd:187-198`, `260-427`) | build jobs/chunk renderer | `TerrainChunkRenderer` | Never saved |
| Prepared chunk arrays | `TerrainChunkBuildJob` (`terrain_chunk_build_job.gd:34-115`) | `TerrainRenderer`, `TerrainChunkRenderer` | Disposable chunk batches | Never saved |
| Organic cliff geometry | `OrganicCliffMeshBuilder`; jobs own in-progress state | chunk renderer | chunk mesh batches | Never saved |
| Decorations/environment placement | deterministic placement/catalog code | jobs and environment renderer | chunk/global batches | Generated baseline not saved |
| Resource deviations/inventory/time | `ResourceStateManager` | interaction controller, renderer, UI | `EnvironmentObjectRenderer` reflects state | Sparse resource snapshot |
| Edit history/strokes | `WorldEditorController` | `main.gd` UI | Requests renderer refresh after authority change | Only resulting world state |
| Save encoding/validation/I/O | `WorldSaveService` | `main.gd` | None | Versioned JSON + temp/backup |
| Camera/HUD/input | `main.gd` | controllers/renderer façade | Presentation only | Optional camera state |

The required authority rule is respected: UI requests edits, `TerrainWorld`/`ResourceStateManager` mutate authoritative state, renderers rebuild derived state, and saves contain authority rather than render caches.

### 4.2 Execution flow

1. **Startup.** `project.godot:14` loads `main.tscn`, whose root uses `scripts/main.gd`. `main.gd:144-232` creates/configures `TerrainRenderer`, cursor, editor, resource controller, save service, camera, HUD, and editor UI.
2. **World generation.** `TerrainRenderer._ready()` builds shared render resources, then creates/configures `TerrainGenerator` and `TerrainWorld` (`terrain_renderer.gd:201-249`). Six cached `FastNoiseLite` instances provide deterministic absolute-coordinate material/elevation fields (`terrain_generator.gd:21-27`, `61-108`).
3. **Terrain authority/elevation.** `TerrainWorld` returns generated values unless sparse overrides exist (`terrain_world.gd:22-57`). Water surface height is derived without destroying stored ground elevation (`terrain_world.gd:60-87`).
4. **Chunk streaming.** Every frame, `main.gd:448-455` sends the camera-visible rectangle to `TerrainRenderer.update_visible_world_rect()`. The renderer computes visible/wanted/unload ranges and queues jobs (`terrain_renderer.gd:366-427`). `_process()` time-slices sampling, organic geometry, tile placement, finalization, and retirement (`terrain_renderer.gd:260-363`).
5. **Terrain rendering.** `TerrainChunkBuildJob` produces packed terrain/mask arrays. `TerrainChunkRenderer.populate_prepared_quantum()` submits those to shared `TileMapLayer` groups. `terrain_variation.gdshader` supplies texture variation, organic alpha boundaries, and optional animated water.
6. **Cliff rendering.** The build job always prepares legacy cliff cells/edge metadata. When organic geometry is enabled, `OrganicCliffMeshBuilder` additionally builds chunk/elevation meshes. The chunk renderer atomically swaps ready meshes and uses legacy faces/components while organic output is unavailable (`terrain_chunk_renderer.gd:292-395`, `873-903`).
7. **Water.** Catalog material 0 is liquid. `TerrainWorld` resolves liquid visibility against `sea_level`; the shared terrain shader animates it only when the experimental water flag is enabled (`terrain_renderer.gd:1063-1103`).
8. **Environmental objects.** Catalogs define data; deterministic placement computes anchors/variants; `TerrainChunkBuildJob` prepares arrays; the global `EnvironmentObjectRenderer` batches them. `ResourceStateManager` overlays sparse designation/depletion/regrowth state.
9. **Editing/interaction.** `main.gd` translates input to picks; `WorldEditorController` validates and batches requested changes; `TerrainRenderer.apply_world_edit_states()` applies authority changes first and then deduplicates affected render dependencies (`terrain_renderer.gd:472-506`). Resource actions go through `ResourceInteractionController` to the authoritative manager.
10. **Save/load.** `WorldSaveService` captures a versioned snapshot, validates before and after temporary-file write, rotates backup, and loads with recovery (`world_save_service.gd:16-160`). `main.gd:631-710` constructs a fresh renderer, imports validated authority, rebinds UI/controllers, and retires the old renderer.

### 4.3 Coupling and responsibility findings

#### `main.gd`

`main.gd` should remain the composition root, but currently also owns four separable concerns:

- configuration transfer to renderer (`main.gd:144-200`);
- runtime input/camera/edit orchestration (`main.gd:235-488`);
- save reconstruction and rebinding (`main.gd:598-738`);
- programmatic HUD/editor UI construction (`main.gd:839-1116`).

The duplicated renderer configuration in `_ready()` and `_replace_world_from_snapshot()` (`main.gd:146-199`, `638-670`) is the most concrete drift risk. This should eventually become one explicit presentation/runtime configuration transfer owned by the composition layer. Do not move authority into UI code.

#### `terrain_renderer.gd`

The renderer is an orchestration façade and a factory for almost every visual resource. The name understates its ownership. Major responsibility clusters are:

- authority façade/edit invalidation (`447-1017`);
- feature/toggle API and picking (`1051-1451`);
- streaming/job lifecycle (`260-427`, `1455-1683`);
- environment object rebuilds (`1690-1818`);
- tileset/material/atlas creation (`1819-2605`).

Future separation should be conservative: first retire unused presentation modes, then extract only clearly cohesive factories/schedulers. Splitting it before reducing feature paths would spread the toggle matrix across more files without reducing complexity.

## 5. Rendering feature and toggle inventory

“Committed default” includes `main.gd` export defaults plus overrides in committed `main.tscn`. “Working-tree default” includes the current uncommitted `main.tscn`.

| Feature | Script default | Committed default | Working-tree default | Active/dependencies | Assessment |
|---|---:|---:|---:|---|---|
| Texture variation | On | On | On | Shared terrain materials | KEEP. Core top-down presentation. |
| Organic terrain boundaries | On | On | On | `terrain_variation.gdshader` masks | KEEP. Core target behavior. |
| Enhanced animated water | Off | Off | **On** | Liquid materials only; no authority/save effect | KEEP capability pending visual approval; fold into normal water settings if accepted. |
| Procedural cliff material | On | On | On | Legacy and organic cliff materials | KEEP. Accepted Phase 3B material. |
| Organic cliff geometry | On in `main.gd` | On | On | Gates all later organic cliff modes | KEEP as target cliff path. |
| Unified cliff components | On | On | On | Requires ready organic geometry; replaces legacy lip/shadow components | KEEP with target path; remove rollback branch only after regressions. |
| Refined cliff silhouettes | On | On | On | Organic builder option | CONSOLIDATE into accepted geometry once rollback no longer needed. |
| Connected cliff contours | On | On | On | Organic builder option; predecessor to unified contours | Likely superseded fallback; retain until unified path accepted and tests consolidated. |
| Unified cliff contours | Off in script | **On in scene** | On | Requires organic geometry; Phase 3D fallback retained | Active Phase 3E prototype. Report says accepted prototype, but production promotion history is not documented in one decision record. |
| Directional cliff projection | Off in script | **On in scene** | On | Affects unified contour depth ordering | Configuration conflict: Phase 3G report explicitly says do not promote. Revert/accept only by user decision. |
| Cliff height profile | Baseline 16 px | Baseline | **Prominent 32 px** | Surfaces, objects, picking, cliffs | Phase 3F recommends baseline; working-tree prominent is experimental and must be preserved until reviewed. |
| Cliff edge overlays | On | On | **Off** | Legacy edge layers or organic component meshes | Diagnostic/presentation control; consolidate after final cliff mode. |
| Cliff shadows | On | On | **Off** | Legacy shadow layers or organic component meshes | Same as overlays. |
| Oblique presentation | Off | Off | Off | Separate renderer/shader; hides top-down chunks and global objects | ARCHIVE/REMOVE candidate after approval. Conflicts with top-down target. |
| Organic oblique refinement | Off | Off | Off | Only meaningful when oblique is enabled | Remove with oblique subsystem. |
| Legacy top-down cliff faces/components | Always prepared | Fallback | Fallback | Used during organic rebuild and rollback | Keep until atomic organic lifecycle has a replacement fallback; then remove deliberately. |
| Procedural vegetation | On | On | On | Chooses procedural versus legacy cached atlas | KEEP visuals; legacy atlas is a measurable rollback cost. Consolidate after acceptance. |

Feature dependency order for cliffs is effectively:

`procedural material` → `organic geometry` → `unified components` → `refined silhouettes` → `connected contours` → `unified contours` → `directional projection` + `height profile`.

The flags are not independent. Later modes often retain earlier algorithms as fallbacks inside the same builder, so exposing every historical phase as a production setting makes invalid or misleading combinations possible.

## 6. Oblique presentation assessment

The oblique subsystem comprises:

- `scripts/oblique_projection.gd` (253 lines);
- `scripts/oblique_terrain_mesh_builder.gd` (173 lines);
- `scripts/oblique_terrain_renderer.gd` (249 lines);
- `shaders/oblique_terrain.gdshader`;
- Phase 2A/2B tests and captures.

It is instantiated unconditionally at startup (`terrain_renderer.gd:250-257`) but hidden by default. Enabling it hides top-down chunks and the environmental-object renderer, rebuilds separate meshes, changes visible-bound calculation, picking, projected polygons, and edit rebuild behavior (`terrain_renderer.gd:366-376`, `627-630`, `1246-1277`, `1363-1436`). It does not own authority or save data.

Unique functionality worth preserving before retirement:

- deterministic projection/picking contracts;
- presentation isolation from authority;
- tests for projection rollback and edit refresh;
- ideas for directional wall visibility.

Reasons not to retain it in production:

- the intended game is top-down;
- it duplicates terrain mesh/material/picking/streaming presentation work;
- environment objects are hidden rather than integrated;
- the existing cliff plan already concluded that standard top-down projection is the better production path (`CLIFF_IMPROVEMENT_PLAN.md:194-210`);
- no runtime feature depends on it when disabled.

Recommendation: preserve a final tagged commit/report and the useful pure projection tests, then archive/remove the three scripts, shader, preloads, renderer branches, and Phase 2 capture/benchmark harnesses in C3. Do not remove it before a top-down picking/edit/save smoke suite passes.

## 7. Code quality and redundancy findings

### 7.1 Confirmed statically unreachable private helpers

The following private helpers have no call sites in production scripts or tests. Godot lifecycle/reflection names were considered; none of these is an engine callback.

| Target | Evidence | Risk/next action |
|---|---|---|
| `scripts/main.gd:458-459` `_screen_to_world_cell()` | Only declaration; all callers use `_screen_to_world_pick()`. | Low-risk REMOVE after parse/input smoke. |
| `scripts/main.gd:477-488` `_paint_height_cell_once()` | Only declaration; current painting is owned by `WorldEditorController`. `_last_height_paint_cell` is now only used by this helper and reset logic. | Low-risk REMOVE helper and orphan state after editor regressions. |
| `scripts/terrain_chunk_renderer.gd:823-834` `_ensure_organic_cliff_mesh_layer()` | Only declaration; `_assign_organic_meshes()` uses `_ensure_organic_component_mesh_layer()`. | Low-risk REMOVE after cliff suite. |
| `scripts/terrain_renderer.gd:1703-1717` `_sample_decoration_neighbourhood()` | Only declaration; current refresh path passes caches directly. | Low-risk REMOVE after decoration/editor tests. |

### 7.2 Statically unused public/test-facing methods — investigate, do not call dead yet

These have no repository call sites, but public methods may be used by editor tooling or external/manual scripts:

- `ResourceStateManager.get_snapshot_by_id()` (`resource_state_manager.gd:38`);
- `TerrainChunkRenderer.rebuild_organic_cliffs()` (`terrain_chunk_renderer.gd:292`), documented as a synchronous direct/test entry point;
- `TerrainRenderer.configure_procedural_elevation()` (`terrain_renderer.gd:712`);
- `TerrainRenderer.clear_player_overrides()` (`terrain_renderer.gd:792`);
- `TerrainRenderer.get_variant_texture_count()` (`terrain_renderer.gd:1300`);
- `WorldEditorController.cancel_stroke()` (`world_editor_controller.gd:83`).

Classify these as CONSOLIDATE/investigate. Search external tooling and run the permanent suite before deletion.

### 7.3 Duplicated or overlapping logic

| Finding | Exact locations | Assessment |
|---|---|---|
| Renderer configuration copied in two flows | `main.gd:146-199`, `main.gd:638-670` | Confirmed duplication and drift risk; one line already reads the live renderer for directional state while adjacent lines read `main.gd` fields. Consolidate in C4. |
| Unique/sort mask source IDs duplicated | `terrain_chunk_build_job.gd:773-780`, `terrain_chunk_renderer.gd:771-778` | Confirmed near-identical algorithm. Keep local until legacy/live-refresh paths are consolidated; then share within the terrain-rendering boundary only. |
| Prepared-build and direct-refresh terrain/cliff algorithms overlap | `_prepare_ground_surface()`/`_prepare_elevated_surfaces()`/`_prepare_cliff()` in `terrain_chunk_build_job.gd:482-753`; `_place_ground_surface()`/`_place_elevated_surfaces()`/`_refresh_local_cliff_cell()` in `terrain_chunk_renderer.gd:548-668` | Intentional dual paths for streamed builds versus live edits, but behavior can drift. Prefer immutable prepared data for both only if benchmarks prove edit latency acceptable. |
| Five cliff mode setters repeat rebuild/restart loops | `terrain_renderer.gd:1122-1198` | Consolidate only after reducing the flag set; a generic flag framework now would be premature abstraction. |
| Legacy and organic cliff rendering coexist | `terrain_chunk_renderer.gd:292-500`, `596-668`, `790-903` | Required current rollback/atomic fallback, but the largest long-term rendering duplication. Remove only after one accepted cliff path and replacement-lifecycle regression. |
| Procedural and legacy vegetation atlases are both generated | `terrain_renderer.gd:1969-2030` | Explicit Phase 3A rollback; report measures about 2.32 MiB extra texture memory and startup generation. Retire legacy atlas after visual approval. |
| Runtime atlas drawing lives in orchestration class | `terrain_renderer.gd:1819-2605` | Cohesive extraction candidate after C3; not an authority problem. |

### 7.4 Noise, materials, and allocation

- Terrain noise objects are configured once and reused (`terrain_generator.gd:21-27`); there is no repeated per-cell noise allocation to remove.
- Placement systems intentionally recompute deterministic hashes from absolute coordinates. This is preferable to persisted generated state and should remain deterministic.
- Shared shader materials, tilesets, and atlases are reused across chunks. Per-cell nodes are avoided.
- The major avoidable startup work is creation of rollback atlases/renderers that are disabled in production. Retire those paths only after acceptance, rather than micro-optimizing the active deterministic algorithms.

### 7.5 Compatibility branches and obsolete debug support

- The legacy Phase 5A demo remains in `terrain_renderer.gd:763-790` and is off in committed configuration but on in the working tree. It is historical showcase data, not required by procedural generation.
- Generation bypass flags at `terrain_renderer.gd:91` and `94` are benchmark hooks; keep them internal/test-only or move them behind a test harness in C6.
- Water animation time override (`terrain_renderer.gd:1086-1091`) is a useful deterministic capture hook; keep it test-facing.
- Extensive profiling counters in `terrain_renderer.gd:131-183` support current benchmarks. Reduce only when a permanent benchmark schema is chosen.

## 8. Screenshots, logs, dependencies, and Git hygiene

### 8.1 Recommended repository structure

```text
docs/
  architecture/       active architecture and decisions
  milestones/         compact historical phase reports
  reference/          small approved visual reference set
tests/
  regression/         permanent deterministic tests
  fixtures/           source-controlled test inputs/baselines
  benchmarks/         benchmark programs, not generated results
art/                   runtime assets only
scripts/               runtime code only
.artifacts/            ignored generated captures/logs/json (or external CI artifacts)
```

Do not keep generated capture matrices under `res://screenshots/`. Test scripts should write to `user://`, a command-line-provided output directory, or an ignored `.artifacts/` directory. Keep only a small, explicitly curated reference set in `docs/reference/`.

### 8.2 Specific `.gitignore` additions proposed for C1

```gitignore
# Local Codex/Godot execution state
/.codex_appdata/
/.codex_godot_appdata/

# Generated test evidence
/.artifacts/
/screenshots/**/*.png
/screenshots/**/*.png.import
/screenshots/**/*.json
/screenshots/**/*.rar

# Validation logs
/*.log

# Local external reference checkout, after removing the broken gitlink
/_reference/
```

If selected images remain under `screenshots/`, use explicit negations for a curated `screenshots/reference/` subdirectory instead of ignoring all screenshots. Do **not** globally ignore `*.import`: runtime asset import settings under `art/` are valid project metadata.

### 8.3 Files to stop tracking after approval

- `.codex_appdata/**`;
- `.codex_godot_appdata/**`;
- `phase5d_validation.log`;
- generated `screenshots/**` except the approved reference subset;
- the three pager artifacts named `cn…54 +-`, `e 3C fix cliff corner gaps and side returns…`, and `ter)`;
- `screenshots/New folder.rar` after contents are inspected and any unique evidence is extracted;
- `screenshots/New folder/**` after hash/semantic review;
- `_reference` gitlink after the dirty checkout is preserved outside this repository or converted into a deliberate documented dependency.

The three pager artifacts are byte-identical SHA-256 payloads and contain the terminal `less` help screen with backspace formatting. They have no project references and are confirmed safe-removal candidates.

### 8.4 `_reference` and provenance

`_reference` is mode `160000` at commit `6ee33aa` from `https://github.com/Pikothix/Isolony.git`, but the parent repository has no `.gitmodules`. Fresh clones therefore cannot reproduce or initialize it as a normal submodule. The local checkout reports a large set of deleted tracked files plus untracked replacements and must be treated as user work until preserved.

Nine `scripts/procgen/**` files are nearly identical to their Isolony counterparts, consistent with the README's “adapted Isolony” statement. Because both repositories identify the same owner, this is provenance rather than a demonstrated third-party license breach. Still, record the source commit in documentation before removing the gitlink.

The only explicit third-party code-technique notice is `THIRD_PARTY_NOTICES.md` for Procedural Almanac's MIT-licensed water technique. Keep it. README links to Xerako and an alternative dual-grid plugin as sources/inspiration; no plugin/addon or package is installed in this repository.

### 8.5 Git LFS assessment

Git LFS is not recommended. The bulk is reproducible generated evidence that should not be versioned at all, and the runtime assets are tiny. Moving 600 MiB of generated captures into LFS would preserve repository clutter and operational overhead rather than solve ownership. A curated reference set can remain in normal Git.

## 9. Godot project configuration findings

| Finding | Evidence | Impact | Recommendation |
|---|---|---|---|
| Obsolete project identity | `project.godot:13`, `project.godot:25`, `README.md:1`, `main.gd:864` | Builds/user-data/HUD use “Universal Mask Terrain,” not Wyntar. | Rename coherently in C2 after deciding whether old `user://` saves must migrate. |
| Unused .NET setting | `project.godot:23-25`; no `.cs`, `.csproj`, or `.sln` | Mono runs can report missing assemblies; needless packaging ambiguity. | Remove `[dotnet]` in C2 after confirming no planned C# integration. |
| Renderer | `project.godot:15`, `29-30` | GL Compatibility is consistent with pixel-art/older GPU target. | KEEP unless target hardware changes. |
| Main scene | `project.godot:14` → `main.tscn` → `main.gd` | Valid simple entry point. | KEEP. |
| Input map absent | no `[input]` section; `main.gd:322-410` handles keycodes directly | Controls are not remappable and D is both camera-right and a decoration toggle on key press. | Define named actions in a later UI/input task; not required for C1. |
| Autoloads | none | No hidden global authority. | KEEP this property. |
| Editor plugins/addons | none | No plugin dependency or packaging risk. | KEEP. |
| Export configuration | no `export_presets.cfg` | Reproducible packaging is not configured. | Add only when a target platform/build task is approved. |
| UID files | 129 UID files; 0 orphaned and 0 sources missing UID | Resource identity is internally paired. | KEEP. |
| Import sidecars | 1,266 non-`.godot` `.import` files; none orphaned | Most belong to historical screenshots; runtime art sidecars are valid. | Remove screenshot sidecars with archived captures; keep runtime imports. |
| Resource-tree pollution | `_reference` lacks `.gdignore`; `screenshots/` is under `res://` | Godot scans/imports unrelated project/evidence data. | Move/archive outside project or add scoped `.gdignore` during C1. |

Startup/parse validation with Godot 4.7.2 Mono was attempted with isolated writable app-data. Three invocations (editor quit, main-scene run, and script check-only) emitted no parse error but did not terminate within the audit timeout and were stopped. This is not a passing parse result. The scan-heavy `res://` tree and unignored nested project are plausible contributors, but that cause was not isolated. Historical reports also record 4.7.2 runner difficulty (`PHASE_3D_CONNECTED_CONTOUR_REPORT.md:74`, `PHASE_3E_UNIFIED_CONTOUR_REPORT.md:165`).

## 10. Test coverage assessment

### 10.1 Inventory

There are 93 GDScript test programs across 29 phase families, plus one preserved pre-Phase-3B shader fixture. No two test scripts are byte-identical; duplication is primarily inherited harnesses and repeated fixture/orchestration patterns.

Active behavior with strong coverage:

- deterministic terrain/elevation/water derivation: Phase 5D, 7C, 7C.3, Phase A water;
- authority/edit batching/undo: Phase 7A and 7C.3;
- save validation, temporary writes, backup recovery, round-trip, resources: Phase 7B.1 and 7C.3;
- resource state and interaction isolation: Phase 8B;
- deterministic decorations/environment placement/procedural sprites: Phase 6A, 6B, 8A;
- chunk scheduling/retirement/atomic organic replacement: Phase 1F/1G;
- cliff seams, topology, profiles, directional coverage: Phase 1B through 3G;
- oblique projection/picking/rollback: Phase 2A/2B.

Historical/experimental coverage:

- Phase 2A/2B become archive candidates with the oblique renderer.
- Phase 1A-1G and 3C-3G overlap as a chronological cliff ladder. They should be consolidated into one permanent top-down cliff suite, not deleted first.
- Capture scripts and most benchmark scripts are milestone evidence generators. Keep only a small maintained benchmark set; archive the rest with reports.
- Phase 3B and 3B.1 have benchmark/capture coverage but no standalone `phase3b_validation.gd`; the report explicitly relies on later capture/benchmark coverage.
- Phase 6A.5 is benchmark/capture-only.
- Phase 3H has no implementation or test by design.

### 10.2 Critical gaps

- No single command or manifest defines the permanent required regression suite.
- No CI workflow is present.
- There is no fast project configuration/main-scene smoke test separated from graphical capture generation.
- No packaging/export smoke test exists.
- Current committed scene defaults are not checked against approved design decisions; this allowed the Phase 3G directional flag contradiction.
- Visual golden evidence is too large to review routinely; there is no curated, bounded visual oracle.
- Exact Godot 4.7.2 execution remains unverified in this environment.
- Test scripts write generated output back into the tracked `res://screenshots/` tree.

### 10.3 Recommended permanent suite

Run on every relevant change:

1. project parse/main-scene headless smoke;
2. deterministic generator and authority snapshot test (derive from Phase 5D/7C.3);
3. material/elevation editing, undo/redo, and cross-chunk invalidation (Phase 7A/7C.3);
4. save validation, backup recovery, and full authoritative round-trip (Phase 7B.1 + resource round-trip);
5. chunk streaming/retirement/atomic replacement (Phase 1G);
6. one consolidated top-down cliff suite: mixed heights, signed seams, corners, water contact, rollback, current accepted topology, and picking (derive from 3C/3E/3F/3G);
7. decoration/environment placement and streaming ownership (Phase 6A/6B);
8. procedural sprite determinism/bounded atlas reuse (Phase 8A);
9. resource depletion/designation/regrowth/single-credit semantics (Phase 8B);
10. water deterministic controls and authority/save isolation (Phase A water).

Run periodically or before visual releases:

- isolated cliff shader benchmark (`phase3b1_shader_benchmark.gd`);
- one streaming benchmark covering representative dense terrain;
- a curated visual set at 0.5×, 1×, and 3× for natural terrain, signed chunk seam, mixed-height shoreline, and dense vegetation;
- lower-tier GPU/CPU measurements before setting performance targets.

## 11. KEEP / CONSOLIDATE / ARCHIVE / REMOVE classification

### 11.1 KEEP

| Exact target | Evidence/dependencies | Risk | Benefit/tests |
|---|---|---:|---|
| `scripts/terrain_generator.gd`, `scripts/terrain_world.gd` | Clear deterministic generation and authority split | Low | Core intended architecture; protect with generator/snapshot tests. |
| `scripts/terrain_chunk_build_job.gd`, `scripts/terrain_chunk_renderer.gd` | Bounded chunk preparation/submission | Medium | Core streaming; protect seams, cancellation, edit, and budget tests. |
| `scripts/world_editor_controller.gd`, `scripts/world_save_service.gd` | Correct UI-request/authority/save boundaries | Medium | Core editing/persistence; keep Phase 7A/7B.1 regressions. |
| `scripts/resource_state_manager.gd` and resource interaction/render split | Sparse authority independent of visuals | Medium | Correct long-term ownership; keep Phase 8B. |
| catalogs, placement scripts, `scripts/procgen/**` | Data-driven deterministic environment generation | Low/medium | Supports intended vegetation; document Isolony source commit and keep Phase 6A/6B/8A. |
| `art/**`, `terrain_variation.gdshader`, `cliff_procedural.gdshader` | Runtime referenced | Medium | Required visuals; parse, capture, water, cliff tests. |
| `THIRD_PARTY_NOTICES.md` | MIT notice | High if removed | Legal provenance. |
| `tests/fixtures/phase3b_pre_geological_cliff.gdshader` | Isolated A/B benchmark dependency | Low | Keep while shader benchmark remains. |
| `README.md` after identity/update pass | Active user documentation | Low | Update, do not archive wholesale. |

### 11.2 CONSOLIDATE

| Exact target | Evidence | Dependencies | Risk | Expected benefit | Required regression/further investigation |
|---|---|---|---:|---|---|
| `scripts/main.gd:146-199` and `638-670` | Duplicate renderer configuration | Save reconstruction, scene exports | Medium | Prevent setting drift; smaller composition root | Full save/load, current scene settings; no further architecture decision required. |
| Cliff flags in `main.gd:64-79`, `terrain_renderer.gd:74-85`, setters `1106-1243` | Historical phase stack exposed simultaneously | Builder/job/chunk renderer/tests | High | One explicit accepted top-down mode | User must approve final visual configuration; cliff/picking/edit/streaming suite. |
| Legacy + organic cliff paths in build/chunk renderer | Both populated/maintained | Atomic fallback, rollback tests | High | Major code/path reduction | First prove organic failure/rebuild fallback and approve loss of rollback. |
| `terrain_renderer.gd:1819-2605` | Tileset/material/atlas factories inside scheduler/orchestrator | Catalogs/shaders/art | Medium | Smaller renderer with cohesive visual factory | Startup, atlas determinism, memory, vegetation, cliff tests. |
| `_sorted_unique_ids` duplicates | Confirmed near-identical helpers | Streamed and direct edit paths | Low | Remove drift | Terrain mask/edit test; defer until paths share appropriate boundary. |
| Phase 1/3 cliff tests | Chronological overlapping coverage | Current fallback modes | Medium | Small permanent regression set | Build coverage matrix before deleting any source test. |
| Screenshot output logic across capture scripts | All write to `res://screenshots` | Reports/manifests | Low | Generated evidence stays out of source tree | Capture smoke in ignored/user output. |
| Procedural/legacy vegetation atlases | Both generated for rollback | Phase 3A tests | Medium | Lower startup time/memory | Visual approval + Phase 6B/8A and benchmark. |

### 11.3 ARCHIVE

| Exact target | Evidence | Dependencies | Risk | Expected benefit | Required regression/further investigation |
|---|---|---|---:|---|---|
| `screenshots/**` except approved reference images/data | Historical feature matrices; 605.81 MiB | Phase reports link many filenames | Medium | About 606 MiB cleaner checkout | Select representative images, repair report links, keep results externally. |
| `PHASE_*.md`, `CODEX_UPGRADE_BRIEF.md` | Historical milestone records | Some explain accepted decisions | Low | Active docs become navigable | Preserve Git history; promote lasting decisions into active architecture docs first. |
| `CLIFF_IMPROVEMENT_PLAN.md` after final decision | Superseded in parts by 3B-3H work | Current rationale | Low | Avoid conflicting plans | Extract accepted decision/remaining issue list. |
| Phase 2A/2B tests/captures/benchmarks | Oblique-only | Oblique subsystem | Low after C3 | Removes non-target regression burden | Top-down picking/edit/save smoke before archive. |
| Old phase capture/benchmark harnesses | Milestone evidence generators | Generated output/report reproduction | Medium | Smaller maintained suite | Permanent coverage matrix first. |
| `illustrative_preview.png`, `mask_reference.png` if not retained as docs | Not runtime referenced; illustrative preview is explained in README | Documentation only | Low | Cleaner project import tree | Human visual/document review. |
| `_reference` Isolony checkout/gitlink | Separate repo; no runtime references; broken parent submodule metadata | Procgen provenance | High because local checkout is dirty | Reproducible Wyntar repo; stops nested project scanning | Preserve dirty state, record commit/remote, verify copied procgen files, then user approval. |

### 11.4 REMOVE after approval

| Exact target | Evidence | Dependencies | Risk | Expected benefit | Required regression/further investigation |
|---|---|---|---:|---|---|
| Three pager artifacts (`cn…54 +-`, `e 3C…`, `ter)`) | Byte-identical `less` help captures; no references | None | Low | Remove accidental files | `git diff --check`; no further investigation. |
| `.codex_appdata/**`, `.codex_godot_appdata/**` | Editor settings, shader caches, logs, doc cache | None at runtime | Low | Remove 4.28 MiB machine state | Project parse/startup after clean cache. |
| `phase5d_validation.log` | Generated log; test source remains | Phase 5D report only | Low | Hygiene | Run validator and store output as CI artifact if needed. |
| Confirmed private dead helpers in §7.1 | No static/dynamic/lifecycle call sites found | Nearby orphan state | Low/medium | Remove misleading paths | Targeted editor/cliff/decoration tests + parse. |
| Screenshot `.import` files paired with archived captures | Generated sidecars for non-runtime evidence | Their PNGs only | Low | 1.20 MiB and import noise | Ensure no curated runtime/doc image is included. |
| Exact duplicate evidence copies after reference selection | 129 hash groups, 79.06 MiB reclaimable | Report links may name duplicates | Medium | Less redundant archive | Link audit and human reference choice. |
| `screenshots/New folder.rar` | No runtime reference; unexplained archive | Contents unknown | Medium | 29.55 MiB | **Further investigation required:** inspect contents before removal. |

### 11.5 Not yet safe to remove

- Any authoritative terrain/resource/save code.
- Any runtime `art/*.png`, shader, or import metadata associated with retained runtime assets.
- Legacy cliff fallback before organic replacement lifecycle is proven without it.
- Public methods listed in §7.2 until external/manual call usage is checked.
- Phase 3H document until its proposal is explicitly accepted/rejected.
- Dirty `_reference` content until preserved.
- The user's current `main.tscn` changes.

## 12. Prioritized cleanup roadmap

Each phase is independently reviewable, testable, and reversible by a normal commit/revert.

### Phase C1 — Repository hygiene

1. Preserve the dirty `_reference` checkout independently and record its remote/commit.
2. Choose a small reference image set and benchmark summaries; move them to `docs/reference/` or external release/CI artifacts.
3. Change capture scripts to emit into `user://` or ignored `.artifacts/`.
4. Add scoped ignore rules from §8.2.
5. Stop tracking generated screenshots, screenshot imports, logs, app-data/cache directories, accidental pager files, and approved duplicate/archive material.
6. Add `.gdignore` or move non-runtime archive/reference trees out of `res://`.

Validation: clean clone; Godot 4.7.2 parse/main-scene smoke; selected validators; report links; `git diff --check`; compare tracked bytes/counts.

Reversibility: one hygiene commit; external archive manifest with hashes.
Expected result: approximately 610 MiB smaller active checkout, though old Git history remains large.

### Phase C2 — Project identity and configuration

1. Decide migration policy for existing `user://` data before renaming the project.
2. Rename project/HUD/docs from Universal Mask Terrain to Wyntar.
3. Remove unused `[dotnet]` settings if C# is not planned.
4. Add named input actions only as a scoped input task; preserve current bindings.
5. Establish an export preset only for an approved target.
6. Resolve committed-vs-approved cliff defaults; do not overwrite the working-tree experiment.

Validation: old-save migration/recovery decision; main-scene smoke; input/manual camera/editor pass; save/load; package smoke when export is configured.

### Phase C3 — Retire obsolete presentation modes

1. Capture/tag the final oblique prototype and archive Phase 2 documentation/tests.
2. Remove oblique preloads/instance, branches, scripts, and shader after approval.
3. Confirm top-down camera, picking, editing, resources, streaming, and save/load are unchanged.
4. Decide whether the Phase 5A hand-authored elevation demo remains a test fixture or moves out of production.

Validation: top-down visual set, Phase 7A/7B.1/7C.3/8B, main-scene smoke, chunk streaming benchmark.

### Phase C4 — Consolidate rendering architecture

1. Approve one cliff configuration. Current evidence supports top-down organic geometry and procedural material, but directional projection and prominent height are not approved defaults.
2. Collapse accepted cliff phase switches while retaining one temporary rollback boundary.
3. Consolidate duplicated main-to-renderer configuration.
4. Extract atlas/material creation only after modes are reduced.
5. Remove legacy cliff/vegetation rollback work only after equivalent lifecycle and visual coverage exists.

Validation: consolidated cliff suite, signed seams, mixed-height/water contacts, editing during rebuild, save/load, selected visual captures, CPU/GPU benchmark.

### Phase C5 — Procedural generation and asset cleanup

1. Document Isolony procgen provenance and remove the reference checkout from the project tree.
2. Review public statically unused APIs and confirmed dead helpers.
3. Consolidate direct-refresh versus prepared-build algorithms only where measurements and tests justify it.
4. Remove unused documentation images/imports after human review.

Validation: deterministic hashes/images, placement seams, atlas bounds, resource stable IDs, save compatibility, `git diff --check`.

### Phase C6 — Permanent regression suite

1. Create one manifest/runner for the suite in §10.3.
2. Separate validators, graphical captures, and benchmarks.
3. Produce artifacts outside Git.
4. Create a small approved visual oracle and update it only through explicit review.
5. Add CI when a supported runner/environment is available.
6. Archive superseded phase harnesses only after the coverage matrix is complete.

Validation: clean-cache and warm-cache runs on the exact supported Godot version; deterministic repeat; failure exit codes; artifact retention policy.

## 13. Risks and blockers

1. **Unapproved cliff default.** Committed directional projection contradicts its own Phase 3G recommendation. Visual acceptance is required before C4.
2. **Dirty local reference checkout.** `_reference` contains user state that must be preserved before unlinking/moving it.
3. **Unverified Godot 4.7.2 startup.** Audit parse attempts did not terminate; C1 should make clean-cache startup a gate.
4. **Historical report links.** Archiving screenshots will break relative links unless reports are archived with a manifest or links are rewritten.
5. **Git history size.** Removing files in a new commit does not shrink existing pack history. A later history rewrite would require separate explicit approval, coordination, and backup.
6. **Cliff fallback lifecycle.** Legacy layers currently prevent blank/partial cliffs during rebuild. Removing them without a replacement failure policy could create transient visual loss.
7. **Save identity.** Changing `config/name` may change the effective user-data location. Existing quicksaves need an explicit migration/compatibility decision.
8. **Working-tree experiment.** The current `main.tscn` changes may be intentional visual evaluation settings. Cleanup must not normalize them silently.
9. **Phase 3H incomplete.** Shared terrain/cliff boundaries remain a design proposal, not a safe cleanup target. Do not begin Phase 3H-B during cleanup without explicit approval.
10. **Legal/provenance record.** Procedural Almanac's notice is present; Isolony reuse should gain an internal source-commit note before the reference checkout is removed.

## 14. Recommendations requiring approval

Approval is required for each of these decisions before implementation:

1. Approve C1 and choose where historical evidence will live (external archive, release assets, or a separate archive repository).
2. Approve the curated visual reference set; do not let an automated deletion choose artistic evidence.
3. Approve removal of tracked caches/logs and the three confirmed pager artifacts.
4. Authorize preservation and removal/conversion of the broken `_reference` gitlink.
5. Decide whether Wyntar should migrate existing `Universal Mask Terrain` user data when renamed.
6. Decide the production cliff baseline:
   - Phase 3E unified top-down contours or Phase 3D fallback;
   - baseline/moderate/prominent height;
   - directional projection on/off;
   - edge overlays/shadows on/off.
7. Approve retirement of oblique presentation in C3.
8. Approve retirement of legacy cliff and procedural-vegetation rollback paths only after the permanent regression suite passes.
9. Decide whether Git history size warrants a separately planned history rewrite. It is not needed for normal forward cleanup and is outside this audit.
10. Decide whether to proceed with, revise, or reject Phase 3H-B. Current code cleanup must not assume approval.

## 15. Audit validation performed

- Enumerated all 2,787 tracked entries, all non-ignored untracked entries, and all ignored entries.
- Measured tracked/working-tree directory and extension sizes.
- Hashed all screenshot payloads to identify exact duplicates.
- Inspected all production script names, line counts, preloads/resource references, function declarations, export flags, tests, shaders, project configuration, reports, Git history, and repository status.
- Verified 129 UID/source pairs have no orphans and all 1,266 visible `.import` sidecars have source files.
- Verified no autoload, input-map, addon, or editor-plugin sections exist.
- Traced startup, generation, authority, streaming, rendering, cliffs, water, environment objects, editing, resource interaction, and save/load.
- Checked static function references across production scripts and tests; separated engine callbacks/public API candidates from confirmed private dead helpers.
- Reviewed commit history and phase reports to distinguish accepted work, prototypes, generated evidence, and unfinished Phase 3H work.
- Attempted Godot 4.7.2 Mono parse/startup validation with isolated app-data; no parse error was emitted, but runs did not terminate and were stopped. This is recorded as an unresolved validation blocker, not a pass.
- `git diff --check` passed for tracked changes with only the pre-existing `main.tscn` LF-to-CRLF warning; a no-index whitespace check of this new report also passed after formatting cleanup.
