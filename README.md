# Wyntar

Wyntar is a Godot 4.7 top-down terrain and world-simulation prototype. Its current vertical slice combines deterministic chunked terrain, paintable material and elevation overrides, cliffs, water, procedural vegetation and environmental resources with versioned development saves. The simulation owns authoritative state; rendering derives the visible world from it.

The project is still under active development. Its organic and directional cliff experiments and enhanced water controls are evaluation surfaces rather than production-ready visual systems. Wyntar supports only the top-down presentation path; the former oblique prototype was retired in Phase C3.

## Open and run

1. In standard Godot 4.7, choose **Import** and select `project.godot`.
2. Run the main scene with **F6**, or run the project with **F5**.
3. Use the collapsible **World Editor** toolbar to select material or elevation editing, a circular or square brush, and brush diameters of 1, 3, 5, 7 or 11 logical cells. **[** and **]** resize the brush. Left-drag applies the selected tool; movement is interpolated between sampled cells so fast strokes do not leave gaps. In material mode, right-drag restores generated material. In elevation mode, choose Raise, Lower, Set Height, Flatten (which samples its target when the stroke begins), or Restore Generated; right-drag remains a quick Lower action. Raise and Lower affect each cell at most once per stroke. **1–8** continue to select water, sand, dirt, grass, stone, snow, mud and gravel, while **H** switches material/elevation mode.
4. **Ctrl+Z** undoes one completed stroke and **Ctrl+Y** or **Ctrl+Shift+Z** redoes it. A new edit after undo clears the redo branch. **R** opens a confirmation dialog for resetting all sparse edits; the confirmed reset is itself one undoable transaction. History retains the latest 50 transactions and is intentionally in-memory only.
5. Pan with **WASD**, the **arrow keys**, or middle-mouse drag. Use the mouse wheel to zoom toward the cursor and **Home** to reset the camera. **P** compares procedural elevation on/off without discarding edits. **G** overlays the grid, **V** compares texture variation on/off, **O** compares organic boundaries on/off, **D** toggles procedural ground details, and **T** toggles larger environmental objects. **F2** switches between compact and expanded HUDs, **F3** shows streaming diagnostics, **F4** shows the selected logical cell plus its four affected dual-grid cells, and **F6** overlays authoritative elevation colours and face extents. Editor controls block painting behind the interface.
6. **Ctrl+S** safely writes the single development slot, and **Ctrl+L** validates and loads it. The expanded HUD shows saved, loaded, unsaved-change and error status.

Wyntar uses the Godot 4.7 GL Compatibility renderer. For compatibility with saves created before the project rename, `user://` intentionally remains rooted at the legacy `Godot/app_userdata/Universal Mask Terrain` directory. The active save remains `user://saves/quicksave.json`; its format and filename are unchanged.

## Project layout

- `scripts/` contains simulation owners, controllers, deterministic generators, save/load code and rendering adapters.
- `scripts/procgen/` contains the locally adapted, deterministic presentation generators used by environmental objects.
- `art/` contains runtime terrain textures.
- `shaders/` contains required runtime shaders.
- `tests/` contains tracked validation, benchmark and capture scripts.
- `.artifacts/` is the ignored output location for newly generated captures, benchmark JSON and validation evidence.
- Historical Phase C1 evidence is preserved outside the repository under `G:/Sim/Wyntar_Archive/`; see `PHASE_C1_REPOSITORY_HYGIENE_REPORT.md` and its archive manifest for the exact snapshot.

## Development workflow

Keep authoritative changes in the simulation owners, request them through controllers/UI, and treat rendering as derived presentation. After a focused change, run the matching headless validator with standard Godot 4.7, launch the main scene when presentation or startup is affected, and run `git diff --check`. Generated evidence belongs in `res://.artifacts/`, not in runtime asset directories.

The current presentation goal is readable top-down 2D terrain. Organic cliff geometry, unified contours and directional projection are available as experimental controls. The committed scene enables directional/unified experiments, while Phase 3G still records unresolved corner/sliver quality and recommends visual approval before treating directional projection as an accepted default. Experimental water enhancement is also controlled independently and does not own gameplay state.

## Architecture
* `scripts/terrain_catalog.gd` — terrain IDs, priorities, liquid metadata, source art and data-driven visual variant definitions.
* `scripts/decoration_catalog.gd` — data-only decoration registry: stable IDs, materials, height ranges, densities, variants, visual scale/offset and shoreline/cliff rules.
* `scripts/decoration_placement.gd` — pure coordinate-hash and cluster-based selection shared by cached chunk builds and live paint refreshes.
* `scripts/environment_object_catalog.gd` — data-only tree, bush, rock and debris definitions, including environmental rules, visual roots, footprints and reserved future collision metadata.
* `scripts/environment_object_placement.gd` — pure absolute-coordinate selection, regional clustering, footprint validation and order-independent exclusion.
* `scripts/environment_object_renderer.gd` and `environment_object_layer.gd` — chunk-owned anchor collections combined into globally sorted elevation batches so canopies can cross chunk boundaries without clipping.
* `scripts/terrain_generator.gd` — deterministic material IDs and independent procedural elevations from the seed and absolute world-cell coordinates, including the optional original material demo.
* `scripts/terrain_world.gd` — authoritative material and integer-elevation lookups with separate sparse override dictionaries and validated portable snapshot APIs.
* `scripts/world_editor_controller.gd` — transient brush/tool state, interpolated strokes and bounded command history; it submits state transitions without owning terrain data.
* `scripts/world_save_service.gd` — versioned JSON validation, serialization, temporary-file writes, backup recovery and compatibility checks; it does not own simulation state.
* `scripts/terrain_renderer.gd` — shared material and cliff atlases, budgeted chunk loading/unloading, overlap-aware picking and batched cross-chunk edit refreshes.
* `scripts/terrain_chunk_build_job.gd` — resumable plain-data preparation: cached 34×34 material/surface-height halos plus precomputed ground, raised-surface, directional rim, wall and shadow slots.
* `scripts/terrain_chunk_renderer.gd` — the four original ground layers plus lazily created, chunk-local batched elevation, wall, shadow and directional-rim layers.
* `scripts/main.gd` — paint requests, camera controls, streaming bounds and the fixed screen-space HUD.
* `scripts/cursor_overlay.gd` — logical-cell selector, visible-region grid and optional affected-cell debug view.
* `shaders/terrain_variation.gdshader` — seed-stable world-space texture variation plus shared organic boundary geometry.
* `art/*.png` — 32×32 sample base textures. Replace them with your own source textures; you do **not** draw transitions by hand.

### Add a new terrain
1. Add `art/clay.png` (32x32 or another resolution; it will be resized to 32×32 at runtime).
2. Append `{"id": 8, "name": "Clay", "priority": 27, "texture_path": "res://art/clay.png"}` to the catalog. A single texture remains valid; optionally add a `variants` array using the existing entries as examples.
3. The renderer automatically generates Clay's 16 masks and shared visual resources; no grass-to-clay, sand-to-clay, etc. atlas sheets are needed.
4. To paint it in the demo, expand `_unhandled_key_input()` in `main.gd` to offer a key/menu entry beyond the initial eight examples. Gameplay code can call `terrain.set_world_cell(Vector2i(x,y), 8)` directly.

### How masks combine
Each *dual-grid* tile samples the four world cells under its corners (TL, TR, BL, BR), with weights `8,4,2,1`. It finds up to four different materials and sorts them by **priority**.

It draws a full **base material**, then for each successive material draws the union of all corners at its priority *or above*. For a cell containing Water, Sand, Grass, Snow, the stack is:
- Water: `1111` opaque.
- Sand: mask containing Sand+Grass+Snow corners.
- Grass: mask containing Grass+Snow corners.
- Snow: mask containing Snow corners.

All 16 masks are generated by the **same bilinear contour formula** so coverage remains nested and holes cannot expose the background. Textures and priorities are independent. The 4×4 atlas layout uses mask indices 0–15 in left-to-right, top-to-bottom order.

Organic mode stores that common scalar contour field in the shared atlas and adds a small seed-stable value-noise offset in the shader. The lookup is quantised to absolute world pixels, keeping magnified edges crisp and continuous across tile and chunk boundaries. Every material uses the same noise coordinates and offset; because one scalar is added to every nested mask, subset ordering, corner identity and full foundation coverage are preserved. Toggling **O** only changes a shared shader parameter and does not rebuild chunks or alter terrain data.

### Elevation and cliffs
Elevation is an integer world field independent of material IDs. Phase 5B supports levels 0–3 through `TerrainWorld.MIN_ELEVATION` and `MAX_ELEVATION`; one height level projects a surface upward by 16 visual pixels. The generator combines a low-frequency regional field with a deliberately limited detail field, then applies configurable thresholds to create broad integer plateaus, valleys and stepped slopes. It samples absolute world coordinates, so the result is deterministic across positive and negative chunk boundaries.

`TerrainDemo` exposes procedural elevation enablement, maximum generated height, regional/detail frequencies, detail strength, three level thresholds and a flatness bias. The default seed `84521` produces lowlands and levels 1–3 around the reset view. Pressing **P** changes only the generated base field and requeues visible chunks through the existing frame-budgeted scheduler. Sparse player height overrides remain authoritative across that rebuild, chunk unloading and reloads.

The height-zero terrain still uses exactly the original four composition layers. Elevated materials retain the same four composition slots, priority sorting, 16 masks, texture variation and organic geometry as ground terrain. Lazy per-height presentation adds a shadow layer, a south-facing wall layer and a narrow side-return layer before the four surface layers. No cell owns a node or sprite.

South-facing exposed drops are assembled from shared 32×16 dirt/stone wall tiles, with one tile per authoritative surface-height step. Phase 5C expands the shared atlas with deterministic wall variations, upper ledge highlights, restrained strata and cracks, darker lower edges, cap shading and a short cast-shadow tile. Phase 5D replaces the former west/east-only side-return decision with one cached directional classification: north, west and east exposure plus south-wall context all derive from the same surface-height halo. Northern boundaries receive a restrained upper-rim/contact band; wider low-contrast side returns connect to wall endpoints without creating full-height east/west faces. Liquid-contact variants add a narrow wet contact band and omit cast shadows over open water. All styles remain shared resources and join across chunk borders.

Water is identified by `liquid` metadata in `terrain_catalog.gd`, not by renderer-side material IDs. `sea_level` defaults to 0. `TerrainWorld` continues to own the authoritative material and ground-elevation fields, while `get_surface_elevation()` derives the render surface: liquid is projected at the configured sea level and land uses its stored ground elevation. Generated water that previously inherited levels 1–3 from the independent height noise therefore renders consistently at level 0 without flattening generated data or sparse height overrides. Painting water onto raised ground similarly creates sea-level water while preserving the ground height beneath it; painting land back reveals that height. Height editing over water edits the preserved ground/seabed and the HUD reports both values. Elevated lakes are deliberately deferred rather than inferred from ground height.

The optional **F6** diagnostic draws authoritative render-surface levels 0–3 as blue, green, amber and magenta projected cells. South-facing drops receive darker overlays matching their authoritative face rectangles, so the derived liquid-aware surface field can be compared directly with rendered walls without changing material or ground-height data.

### Procedural ground decorations
Phase 6A adds presentation-only details without changing authoritative terrain or save data. `decoration_catalog.gd` contains definitions for grass tufts, tiny flowers, low shrubs, dirt stones, dry sprigs, sand pebbles, rock fragments, stone flecks, snow drifts, exposed stones, wet vegetation, shoreline reeds, gravel pebbles/debris and cliff-top tufts. Water has no ordinary decoration definitions.

Each world cell is a potential authoritative anchor. A stable hash of the world seed plus `decoration_seed_offset`, absolute signed coordinates and decoration ID selects anchors and variants without advancing shared random state. A low-frequency interpolated hash field controls clustering, while registry rules test ground elevation, visible surface elevation, liquid neighbours and cliff proximity. Candidate anchors are hash-thinned before full rule evaluation, avoiding a visible lattice while bounding preparation cost and maximum density. The same pure selection function is used when material or elevation painting refreshes nearby cells, including across chunk boundaries.

All variants are generated once as small palette-matched pixel-art tiles in one shared atlas. Each chunk uses at most one `TileMapLayer` per visible elevation, never one node per decoration. Layers are populated through the existing budgeted scheduler and draw above their surface but below higher projected terrain. **D** changes layer visibility only; placement data remains cached, so toggling does not rebuild material, elevation or chunk data. Inspector controls expose enablement, global density, clustering strength and seed offset.

Phase 6A.5 separates terrain preparation, decoration selection and decoration TileMap submission into independently measured scheduler passes. Cluster lattice samples are reused within each chunk, empty chunks do not create decoration layers, and paint edits resample one bounded neighbourhood before refreshing only the edited anchor and its four rule-dependent cardinal neighbours. These changes preserve absolute-coordinate placement and environmental rules. The atlas silhouettes use slightly stronger outlines, contrast and deterministic size variation without increasing definition density. The default compact HUD reports material, editing mode, elevation, zoom and decoration visibility; **F2** retains access to the complete controls and diagnostics.

### Procedural environmental objects
Phase 6B adds presentation-only trees, bushes, rocks and debris. The registry includes small and large deciduous trees, conifers, dead trees, small and leafy bushes, dry and shoreline shrubs, small and large boulders, rocky outcrops, exposed stone groups, fallen logs, stumps and deadwood. Each definition states its compatible materials and elevations, footprint, exclusion distance, regional clustering, atlas variants, visual root and future collision footprint. No object is placed in open water; shoreline vegetation explicitly requires adjacent liquid, and wide objects require every footprint cell to share a valid material and liquid-aware render surface.

Placement is derived only from the world seed, `environment_object_seed_offset`, signed absolute anchor coordinates and authoritative terrain samples. A sparse anchor hash bounds candidate work, smooth category-wide regional fields form coherent woodland, scrub and rocky areas, and a stable priority hash resolves nearby candidates independently of chunk load order. The owning chunk is always the chunk containing the root anchor. Build jobs sample a one-cell outer margin so a wide object also suppresses small ground details in neighbouring chunks. Painting recomputes the bounded exclusion neighbourhood and refreshes only ground-detail cells whose occupied state changed.

Large objects use a single shared 96×96 pixel-art atlas generated from the established terrain palette. Chunks retain only compact anchor arrays; four global elevation-aware `Node2D` batches perform root-based Y ordering across all loaded chunks. This lets trunks and canopies cross chunk seams while retaining correct same-height overlap and remaining below higher projected terrain. There are no per-object `Sprite2D` nodes. The Inspector exposes enablement, density and seed offset, **T** changes presentation visibility without rebuilding placement, and **F3** reports object totals, categories, preparation and batch-submission timings.

Phase 8A replaces the tree, boulder and berry-bush placeholders with adapted Isolony procedural generators. Deciduous, conifer and dead-tree profiles; rounded, tall, flat and blocky rocks; and rounded, wide and upright fruiting bushes retain their source algorithms and deterministic seed variation. The adapted generator stack lives under `scripts/procgen/` without global `class_name` registrations, so it does not collide with other Godot projects or introduce Isolony's `WorldState`, `ChunkManager`, resource nodes or gameplay systems. Dry shrubs and debris retain the existing local artwork.

The renderer prewarms only the finite variants declared by the environmental-object catalog. All 54 variants occupy one 5184×96 shared atlas; 41 are Isolony-generated tree, rock or berry-bush variants. A world-space anchor still selects only an existing catalog variant through the unchanged Phase 6B placement hash. Camera movement, chunk unloading and reloads reuse the same atlas texture and never generate another sprite. Nearest-neighbour filtering, 96×96 cells, compact chunk anchor arrays and the four global elevation batches remain unchanged.

The resource definitions reserve presentation-independent metadata: resource category, harvestable/collectable intent, yield, depletion/regrowth capability, interaction footprint and the stable-ID strategy `world_seed_anchor_definition`. Phase 8B's authoritative simulation-owned state manager keys sparse records by world seed, root anchor and definition ID. The renderer receives derived presentation snapshots; the renderer, catalog and UI do not own or mutate resource state.

### Harvestable resource state

Phase 8B implements that boundary through `ResourceStateManager`. Stable IDs combine the world seed, signed root-anchor coordinates and definition ID. Procedural resources remain implicit until their state differs from the generated baseline, so merely streaming an infinite world does not populate a persistent resource dictionary. Sparse records contain designation, availability, remaining quantity and berry regrowth deadlines; the same validated completion method serves the debug action and future colonist work. The prototype inventory owns non-negative wood, stone and food totals independently of rendering.

Press **Q** to switch between terrain editing and resource interaction. In resource mode, left-click selects and inspects a resource without painting terrain, **E** designates it, **C** cancels the designation, **Esc** clears selection and **F8** is the clearly marked debug action that instantly completes a designated harvest. Trees and loose rocks disappear after completion and cannot credit inventory twice. Berry bushes remain rooted, use a prewarmed berry-free atlas variant while unripe, and become ripe after the configured simulated-time duration. Their cosmetic berry pixels do not determine authoritative food yield.

Resource visuals remain part of the four global elevation batches. Selection and designation markers are drawn by those batch layers without per-resource nodes. Tree and rock removal reuses the bounded environmental-object refresh path so occupied footprints and ground decorations update. Terrain edits that invalidate a procedural anchor cancel its designation but retain depletion/regrowth state; restoring terrain therefore restores unaffected resources with the same ID and cannot resurrect a harvested resource. Regrowth checks only the sparse changed-state set when the next scheduled deadline is reached, including while the owning chunk is unloaded.

The twelve berry-bush variants also have prewarmed unripe counterparts. The bounded shared atlas therefore contains 66 cells at 6336×96 pixels in Phase 8B; its size remains fixed during selection, harvesting, camera streaming and regrowth.

### Persistent world foundation

Phase 7B.1 stores one development save at `user://saves/quicksave.json`. The portable JSON root contains `format_version`, procedural-rules and object-catalog compatibility IDs, world ID/display name, every deterministic generation setting, optional camera state, sparse material/elevation overrides, sparse resource deviations, designations, simulated time, berry deadlines and wood/stone/food totals. Signed coordinates are explicit `x`/`y` integers and stable resource IDs are validated against the saved seed, anchor and definition ID. Generated cells, objects, atlas textures, chunks and other render caches are never serialized.

`WorldSaveService` captures state only through the terrain and resource owners' export APIs. Loading parses and validates the whole file before a new `TerrainRenderer` is configured. The replacement receives the saved generation configuration before it enters the scene tree, imports authority before streaming, and only then replaces the active world. This discards old chunk work and editor history while keeping rendering derived from simulation state. A rejected file never reaches the replacement step.

Saving writes and flushes `quicksave.json.tmp`, reloads and validates it, validates and copies the previous destination to `quicksave.json.bak`, and then performs an explicitly checked replacement. The implementation does not claim an atomic rename on every filesystem. If installation or final validation fails, it attempts recovery from the known-good backup and reports the error. Phase 7B.1 intentionally provides one fixed slot only; browsing, renaming, deleting and managing multiple worlds remain deferred to Phase 7B.2.

The older Phase 5A hand-authored showcase remains available through `include_elevation_demo`, but is disabled by default so Phase 5B's seeded landforms are visible. The reproducible Phase 5B captures use the default seed and a single temporary manual height override at `(5, 4)`: `screenshots/phase5b_procedural_elevation_0_5x.png`, `phase5b_procedural_elevation_1x.png`, and `phase5b_procedural_elevation_3x.png`.

### Limits and production notes
- “Unlimited terrain types” means *no pairwise tile explosion*; it isn't literally unlimited memory, IDs or GPU texture resources.
- Only **four** different materials can meet at any one dual-grid display tile, regardless of how many material IDs exist in the game.
- Terrain boundaries share exactly the same mask geometry. Visual qualities (grass tufts, foam, sand spill, biome-specific blending) will require optional secondary decoration or special shaders.
- Generated material and elevation are recreated from the saved seed and generation configuration; only painted differences are stored in the Phase 7B.1 JSON save.
- Chunk preparation and tile population are frame-time-budgeted. `max_chunk_processing_ms` defaults to 2.5 ms, while work-quantum and tile-submission limits bound individual operations. Visible missing chunks are prioritised over the load margin; the larger unload margin still provides hysteresis.
- Each pending build job temporarily uses roughly 100 KiB for material/elevation halos and prepared ground, raised-surface and cliff slots. The cache removes repeated procedural sampling and is discarded when the chunk completes or becomes obsolete.
- Generation remains on the main thread because profiling showed cached sampling fits comfortably inside the frame budget; no worker-thread or scene-tree synchronization complexity was added.
- Texture variation strength and world-space frequency can be tuned on `TerrainDemo`. Variation textures are generated once at startup and shared by every chunk; four 32×32 RGBA8 variants add about 16 KiB of raw texture data per material, excluding engine/import overhead.
- Organic boundaries can be disabled or tuned with `organic_edge_strength` and `organic_edge_frequency` on `TerrainDemo`. The conservative defaults are intended for subtle 32×32 pixel-art contours. The effect adds procedural arithmetic but no texture sample and performs no per-frame CPU rebuild.
- The orthographic projection exposes full camera-facing (south) walls. North/east/west boundaries use shallow directional rim/return cues and remain intentionally flat rather than pretending to be full isometric faces.
- Water uses one configurable global sea level. Per-lake levels, flowing water and water volumes are intentionally outside Phase 5D; supporting them requires explicit liquid-body data rather than overloading the ground-elevation field.
- Phase 6A decorations and Phase 6B environmental-object placement remain derived presentation data. Harvestable deviations are persisted separately by the authoritative resource-state manager; collision and physics remain inactive.
- One small decoration can be selected per logical world-cell anchor. Larger objects use explicit multi-cell footprints and absolute root-anchor ownership, with conservative exclusion that can intentionally leave some natural gaps.
- Ordinary strokes apply authoritative changes and local terrain/cliff/decoration refreshes immediately. Environmental-object chunks are deduplicated and refreshed visible-first at one chunk per frame. Transactions above 96 changed cells stage visual refresh in 32-cell batches; authority and history update immediately, and queued work always rereads the latest state so rapid undo/redo cannot apply stale visuals. Terrain-cell and environmental-object stages alternate instead of sharing one frame. Very large strokes can therefore take several frames to become fully visible.
- Edit history remains session-only and is reset when another world is loaded. Sparse material and elevation overrides are persisted; manually placed environmental objects remain outside the current design.
- Elevation overrides persist across procedural toggles, chunk unloading and Phase 7B.1 save/load, matching material overrides.
- Current variants are deterministic tonal transformations of the existing pixel art. They add colour-region variety but no new material-specific objects or decoration.
- The built-in Godot terrain-connect API expects the necessary terrain combinations in the TileSet; this system deliberately bypasses that requirement.
- `illustrative_preview.png` is generated separately with the same mask formula; it is not a screenshot from the Godot editor.
- Single 32×32 repeated textures are placeholders and can look repetitive. Production needs variations and world-space texturing; edge masking itself is already scalable.
- TileMapLayer cells remain chunk-local, avoiding large absolute map coordinates inside the rendering layers.
- The project has been parsed, run and validation-tested with Godot 4.7.2.

### Sources
- Xerako — https://github.com/Xerako/DualGrid-Bitwise-Multi-TileMapLayer
- Official Godot docs — https://docs.godotengine.org/en/4.7/classes/class_tileset.html
- Alternative plugin — https://github.com/Exonfang/godot-dualgrid-unlimited-adjacent-terrains
