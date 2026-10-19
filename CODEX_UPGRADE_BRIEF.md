# Codex Upgrade Brief — Universal Mask Terrain (Godot 4.7)

## Project and working agreement

Upgrade the existing Godot 4.7 project in this folder incrementally. **Do not replace the renderer wholesale with Godot's built-in terrain-connect autotiling, nor rewrite the project as a new demo.** Read `README.md` and the existing scripts before modifying anything:

- `scripts/main.gd`: paintable demo, input and HUD; currently positions terrain at half the viewport size.
- `scripts/terrain_catalog.gd`: eight material IDs, priorities, and `art/*.png` paths.
- `scripts/terrain_renderer.gd`: authoritative terrain-ID dictionary and four `TileMapLayer` display slots; precomputes 16 masked tiles per material; builds a fully opaque base and nested priority masks.
- `scripts/cursor_overlay.gd`: paint cursor and a grid overlay currently hardcoded to a finite region.

Keep the starter's original visual character, materials and ability to paint. **All materials must still align with no transparent gaps, discontinuities, or pair-specific transition art.** Keep the four-corner dual-grid model: TL, TR, BL, BR bits `8,4,2,1`. A display cell encounters at most four distinct materials. The displayed base is opaque and higher materials use nested coverage masks. No global one-`TileMapLayer`-per-material architecture.

Make commits or otherwise checkpoint work at each milestone. Give a concise summary, changed files, tests performed, and known limitations. **Implement one phase at a time; do not begin the next phase without approval. Start with Phase 1.**

## Phase 1 — Usable camera and input (implement first)

Add a `Camera2D` with smooth, reliable map exploration. Controls:

- `WASD` and arrow keys pan at a frame-rate-independent speed, with movement adjusted for zoom.
- Hold middle mouse and drag to pan (do not paint while panning).
- Mouse wheel zooms **toward the cursor**, ideally multiplicatively, with configurable min 0.5x, max 3.0x, and ~1.15 zoom factor; prevent zoom overshoot.
- `Home` resets camera position to the demo center and zoom to 1x.
- Preserve left mouse drag to paint, right mouse drag to restore grass, number keys 1–8, `G` grid, `R` reset.
- Keep HUD independent of camera transforms using `CanvasLayer`; clicks on HUD never paint through it.
- Paint targeting must remain correct after zoom, pan, and viewport resize. Use coordinate conversion rather than manual offsets.
- Remove viewport-centering hacks where appropriate; the terrain should have a stable world origin.
- Make the grid draw across the currently visible camera region, not the original fixed 45×25 map.
- Provide a small unobtrusive zoom readout or `+`, `-`, `Reset` controls if straightforward.

**Acceptance:** Can zoom into a boundary and paint exactly under the pointer at 0.5x, 1x, and 3x. Middle-drag and WASD pan without changing cells. HUD stays put. The demo still opens and the original materials remain unchanged.

## Phase 2 — Infinite deterministic chunk streaming

Introduce a world manager, seeded terrain generator, chunk data store, and chunk renderers. Suggested initial chunk dimensions: `32×32` world cells. Keep the seed exposed/configurable. Use the existing demo landscape only as an optional starting feature, while creating broad, natural regions around it. Support positive and **negative** world coordinates correctly using floor division.

- Load/generate chunks covering the actual visible camera bounds plus a configurable buffer, accounting for zoom and viewport size. Unload visual nodes well outside the buffer; avoid thrashing at boundaries.
- Generate terrain from **absolute world coordinates and a fixed seed**, so chunks are identical regardless of load order or travel path. Consider multi-scale `FastNoiseLite` for biome selection.
- Rendering may use four `TileMapLayer`s **per loaded chunk**, sharing one cached `TileSet` / material atlas set; never regenerate those atlases for each chunk.
- Keep `TileMapLayer` cell coordinates chunk-local to avoid the engine's signed 16-bit serialized-cell-coordinate limit on large worlds. Position chunk nodes using world coordinates.
- Fetch neighboring world IDs via the generator/overrides for the 1-cell seam halo rather than relying solely on currently loaded chunk objects. Update both sides when an edge cell changes.
- Maintain player-painted overrides in an authoritative world-data layer, separately from procedurally generated data. Painting must survive unload and reload, including in-session persistence. Provide an explicit reset of overrides. Saving to disk can be added if practical, or identified as a follow-up.
- Batch cell generation/rebuilds and avoid rewriting every cell or clearing every chunk every frame. Budget work per frame or use safe background generation with main-thread scene updates.
- Add optional diagnostics: visible chunk count, loaded chunk count, camera world position, render/update time.

**Acceptance:** Pan across 20+ chunks, including negative coordinates, without finite-world edges. Return to the same place and see identical terrain and retained edits. At all chunk boundaries and at four-material junctions, no transparent holes, repeated edge artifacts, or misaligned corners. Loaded visual chunk count is bounded by viewport size and buffer.

## Phase 3 — Texture variation and material definitions

Keep existing `art/*.png` as placeholders. Support multiple **seam-compatible** texture variants per material, plus optional configurable tint, detail intensity, density, and variation seed. Avoid a dependence on specific texture packs.

- Select variations deterministically using world-space coordinates and seed; returning to a chunk must not reshuffle visuals.
- Keep the geometric mask separate from the source textures.
- Prefer textures or world-space sampling strategies that avoid visible seams from random variants; don't just pick unrelated full-cell textures with incompatible borders.
- Cache/precompute masked atlas variants as needed; do not regenerate every time a chunk is painted or streamed.
- Support additional material IDs without modifying other material definitions or drawing pairwise transition sprites.
- Validate material IDs and priority ordering; reject collisions or provide stable deterministic tie-breaking.

**Acceptance:** Large fields show more variety without seam discontinuities; painting and chunk reloads don't alter unrelated tiles; adding a ninth terrain definition is documented and works.

## Phase 4 — Organic shared boundaries

Replace the repeated per-tile sinusoidal wobble in `_coverage()` with a **shared, continuous, deterministic world-space contour perturbation** (noise/warp) keyed to absolute world coordinates and seed. Preserve the fundamental nested-coverage guarantee.

- All material layers at a single dual-grid cell must use the **same** contour field and thresholds; never compute separate random jitter for each material pairing.
- Edge noise must be consistent across neighboring display tiles and across chunk seams, including at negative coordinates.
- Clamp detail amplitude / shape so the masks stay readable and avoid pinholes, transparent cracks, or isolated pixel artifacts.
- Offer an `organic_edge_strength` parameter and a way to toggle the effect for comparison.
- Retain the ability to use pixel-crisp nearest filtering, with controlled alpha softness if desired.

**Acceptance:** Grass/sand/stone/snow junctions remain fully covered and aligned at every zoom. Borders vary naturally across the map rather than repeating the same curve every 32 pixels. Shape remains stable when chunks unload/reload.

## Phase 5 — Material-specific decoration

Add separate deterministic decorative visuals, not changes to the core shared masks. Suggested examples:

- Grass: tufts, small flowers, scattered blades.
- Sand: pebbles, subtle ripples; occasional edge debris.
- Dirt: scattered grit.
- Stone: cracks and loose rocks.
- Snow: sparse icy flecks.
- Water: optional shoreline foam or small ripples.
- Mud and gravel: sparse material-appropriate details.

Support per-material density and art references, optional slope/edge-aware placement, a global enable/disable setting, and seeded position/rotation/variant. Respect rendering order. Avoid decorating water as solid ground. Rebuild decorations for edited cells and unloaded/reloaded chunks; avoid large numbers of individual nodes if batching through sprites/multimesh/draw calls is more efficient.

**Acceptance:** Details remain stable while moving away and returning, adapt to terrain painting, and do not hide gaps or compromise pixel precision.

## Verification and reporting

At the end of **each** phase:

1. Run Godot's headless editor/import smoke check when a Godot binary is available; if not, clearly say it was unavailable rather than claiming tests passed. Run any available GDScript/static tests.
2. List changed files and controls. Explain any deviation from the acceptance requirements.
3. Confirm the existing eight materials and painting features still work. For chunk phases, explicitly test negative coordinates and all four-material junctions.
4. Make project changes only, not unrequested external GitHub changes; stop after the completed phase for review.

## Initial instruction to Codex

> Open this existing Godot 4.7 project. Read `CODEX_UPGRADE_BRIEF.md` and inspect the actual scripts. Implement **Phase 1 (Camera and Input)** only, preserving the current universal-mask terrain algorithm and the existing painting demo. Run the available tests and summarize the files changed and how I can verify zoom-to-cursor, panning and painting in Godot. Do not start Phase 2 until I approve.
