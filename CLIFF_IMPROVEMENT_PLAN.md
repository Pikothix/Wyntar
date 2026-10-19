# Wyntar Cliff System Audit and Improvement Plan

Date: 2026-10-19

Engine: Godot 4.7.2

Scope: presentation-only cliff geometry, materials, projection, streaming, editing, tests, captures, and benchmarks

## Executive decision

Retain Wyntar's current top-down 2D projection and its existing terrain renderer. The current architecture is already capable of a substantially better cliff treatment without changing authoritative terrain, save data, editing, or chunk ownership. The best route is to evolve the existing chunk-batched organic cliff path, not replace it and not promote the experimental oblique renderer.

The current organic mesh is real polygon geometry, but it is not yet a genuinely free-form terrain contour. It reconstructs presentation from tile-derived height discontinuities, gives full vertical area only to southern drops, and adds bounded noise, caps, lips, and narrow returns around those cell-derived shapes. It therefore changes the silhouette locally while preserving a recognisably rectangular/stair-stepped source topology.

The immediate visual opportunity is material work: coherent face-scale strata, sparse branching cracks, larger facet groups, a thin inked crest, and restrained toe occlusion. This can be prototyped entirely in the existing cliff shader and rolled back with the existing `procedural_enabled` switch. Geometry should then advance from independent cell faces to connected level-contour runs inside `OrganicCliffMeshBuilder`, still driven by the immutable chunk halo and absolute world-coordinate hashes.

## Evidence labels

- **Verified** means directly established by current code, current project data, a current screenshot, or a validation run in this audit.
- **Visual observation** means visible in the project's saved PNGs or the referenced showcase, but is not a claim about the reference project's internal implementation.
- **Hypothesis** means a proposed explanation or expected visual result that requires an A/B prototype to confirm.

## Reference target

The [Out of Pixkrieg showcase](https://www.reddit.com/r/proceduralgeneration/comments/1x85755/procedural_generation_in_out_of_pixkrieg/) states that its terrain is derived from the author's earlier 2.5D terrain generator. The showcase's biome comparison visibly uses long, coherent, irregular land contours, narrow rock bands, a controlled common palette, and small-scale wear rather than repeating one obvious cliff unit. This is a **visual observation**, not an inference about its source algorithm.

The author's public [Cartoon Terrain Studio](https://github.com/idlerunner00/cartoon-terrain-studio) is the relevant primary technical reference. Its documentation describes generated meshes, shader-noise materials, an editable terrain painter, an endless 32x32-cell chunk mode, live material restyling, an `organic rock` shape option, and a comic pipeline using one light ramp, hatching, ink outlines, and soft shadows. Its [architecture document](https://github.com/idlerunner00/cartoon-terrain-studio/blob/main/docs/ARCHITECTURE.md) also separates engine-free terrain/chunk generation from Godot mesh submission and styling. The useful lesson for Wyntar is the combination of coherent geometry and a disciplined material language; adopting that lesson does not require copying its 3D renderer.

## Current ownership and data flow

Ownership is sound and should remain unchanged:

| Responsibility | Current owner | Evidence |
| --- | --- | --- |
| Material and elevation authority | `TerrainWorld` | `scripts/terrain_renderer.gd:1-4`, `scripts/oblique_projection.gd:1-4` |
| Chunk visibility, scheduling, revisions, cancellation, halo cache, retirement | `TerrainRenderer` | `scripts/terrain_renderer.gd:168-179`, `240-338`, `346-420`, `1438-1529` |
| Immutable 34x34 sampled chunk halo and resumable preparation | `TerrainChunkBuildJob` | `scripts/terrain_chunk_build_job.gd:1-4`, `11-18`, `196-312` |
| Standard-view cliff mesh construction | `OrganicCliffMeshBuilder` | `scripts/organic_cliff_mesh_builder.gd:1-4`, `53-96`, `99-193` |
| Complete mesh attachment and draw-layer ownership | `TerrainChunkRenderer` | `scripts/terrain_chunk_renderer.gd:1-3`, `31-33`, `328-368`, `744-817` |
| Procedural cliff colour | `cliff_procedural.gdshader` | `shaders/cliff_procedural.gdshader:4-15` |
| Experimental oblique projection and mesh | `ObliqueTerrainRenderer` / `ObliqueTerrainMeshBuilder` | `scripts/oblique_terrain_renderer.gd:1-3`, `scripts/oblique_terrain_mesh_builder.gd:1-3` |

The simulation remains authoritative. Both cliff renderers sample it and build discardable presentation. Edits invalidate presentation, old organic meshes remain visible while replacements are prepared, and a revision check prevents stale jobs from committing (`terrain_renderer.gd:249-271`, `1438-1471`; `terrain_chunk_renderer.gd:328-376`). No proposed stage changes those boundaries.

## Current standard-view geometry

### Elevation projection

Each logical cell is 32x32 pixels and each elevation level shifts its surface upward by 16 pixels (`terrain_renderer.gd:23-26`; `terrain_chunk_renderer.gd:731-740`). The standard view is orthographic/top-down. It does not rotate the grid.

### Primary faces

**Verified:** a full cliff face exists only when a non-liquid owner cell is higher than its southern neighbour (`organic_cliff_mesh_builder.gd:110-141`). The face extends from the owner's projected southern edge to the southern neighbour's projected elevation (`267-288`). A multi-level drop is one continuous face divided into 16-pixel rows, rather than one visible slab per elevation (`287-323`). This is an improvement over the legacy atlas stack documented in `PHASE_7C4_REPORT.md`.

Each 32-pixel-wide face currently has only two horizontal columns because `PROFILE_STEP` is 16 (`organic_cliff_mesh_builder.gd:9-10`, `278-293`). Its top and bottom boundaries are displaced by at most three pixels using absolute-coordinate hashes (`256-264`, `278-285`). Terminal caps receive small horizontal offsets of at most two pixels (`296-315`, `648-652`). Vertices are rounded to integer pixels (`326-350`).

### Top lips and side returns

North exposure creates a 3-5 pixel-deep lip sampled twice across the cell (`399-424`). West and east exposures create narrow ribbons rather than full projected faces (`427-458`). Refined mode replaces four independent 8-pixel return rectangles with a three-point, 16-pixel-step ribbon; its width is 2-7 pixels and may gain one broad formation bulge over a 64-pixel vertical span (`461-573`). The ribbon snaps to an adjoining southern face cap when one exists (`474-500`, `576-588`).

This treatment is intentionally foreshortened. It improves continuity in the top-down view but cannot show true north/east/west wall area. Earlier phase reports explicitly document this constraint (`PHASE_7C2_REPORT.md`, `PHASE_7C3_REPORT.md`, `PHASE_7C4_REPORT.md`).

### Contact shadows

Unified mode creates a separate 3-5 pixel-deep mesh at the foot of each non-shoreline southern wall (`organic_cliff_mesh_builder.gd:157-171`, `591-628`). It follows the same bottom outline and cap logic as the face. Its vertex role and alpha are encoded for the shared material, which mixes it toward a dark brown/black at restrained alpha (`cliff_procedural.gdshader:150-155`). Shoreline walls omit this contact-shadow mesh and instead receive wet material treatment.

### Legacy fallback

The old TileMap path remains available during rollback and while replacement geometry is pending. It stores per-step southern wall cells, separate shadow cells, and classified edge overlays (`terrain_chunk_build_job.gd:524-592`; `terrain_chunk_renderer.gd:517-588`). The current main scene enables procedural materials, organic geometry, unified components, and refined silhouettes, while oblique presentation is off (`main.tscn:7-10`; `scripts/main.gd:56-64`).

## Does the current mesh support genuinely irregular contours?

**Decision: partially, but primarily as cosmetic variation over tile-derived shapes.**

It is genuine mesh geometry: vertex positions, topology, lips, returns, and shadows are generated rather than merely shaded sprites. It is deterministic, integer-quantised, chunk-batched, and seam-safe. However:

1. Exposure is still classified from a cell and its four cardinal neighbours.
2. A primary face is emitted per cell only for a southward height drop.
3. The face's horizontal span remains the cell's 32-pixel interval, except for small terminal-cap offsets.
4. Top and bottom variation moves mostly in screen Y by at most three pixels.
5. North/east/west shape is represented by narrow overlay ribbons, not a common continuous boundary surface.
6. There is no contour tracing, connected-run simplification, curve resampling, erosion notch, overhang, talus, or face-scale landmark placement.

Consequently, the generator can make tile walls less mechanically straight, but it cannot yet turn a blocky elevation footprint into the long, coherent, rounded/eroded contour language visible in the target reference.

## Why the current result can still look rectangular, repetitive, or flat

### Verified geometry causes

- **Low contour sampling density.** Two columns per tile allow only a shallow zig-zag, visible especially at 3x zoom.
- **Cardinal ownership remains visible.** Full face area is south-only; other directions are thin cues. Long diagonals therefore read as steps.
- **Per-cell construction.** Absolute hashes make seams agree, but they do not remove the 32-pixel ownership cadence.
- **Small displacement envelope.** A maximum three-pixel boundary shift is conservative compared with a 32-pixel tile.
- **Returns are narrow by design.** At 2-7 pixels, they describe continuity but not geological mass.
- **No contour-scale features.** There are no deterministic alcoves, buttresses, ledges, fallen fragments, or erosion breaks spanning several cells.

### Verified material causes

- The material is `unshaded`; all depth must come from procedural tone and vertex colour (`cliff_procedural.gdshader:1-2`).
- The facet field is two hashed box lattices. It produces irregular tone regions, but no explicit facet borders or directional normal cue (`38-50`, `105-129`).
- Strata are horizontal world-Y bands with one broad warp. They are continuous across chunks and stacked faces, but remain regular in orientation and spacing (`109-118`).
- There is no current procedural crack function in the shader. Sparse cracks exist only in the legacy CPU atlas RGB, and procedural RGB replacement largely supersedes that colour information (`terrain_renderer.gd:2237-2239`; `cliff_procedural.gdshader:76-161`).
- Dirt and stone mainly differ by facet/strata strength and base texture; they do not have distinct geological structure rules.
- Vertex faceting is a random five-value shade per small quad (`organic_cliff_mesh_builder.gd:316-322`, `655-661`), which can read as noise rather than coherent planes.
- The reference look uses a stronger hierarchy: silhouette/ink first, broad planes second, strata and wear third, fine texture last. Wyntar's repeated 32x32 source textures remain comparatively prominent in saved 3x captures.

### Visual evidence in the repository

- `screenshots/phase1g_refined_natural_gameplay_1_0x.png`: long diagonals still form a stair-step cadence; cliff faces repeat a narrow front strip.
- `screenshots/phase1g_refined_convex_concave_stone_3_0x.png`: the face is visibly a shallow rectangular band with repeated source texture and weak large-scale geological structure.
- `screenshots/phase2b_natural_gameplay_phase2b_after_1_0x.png`: oblique mode creates more wall area but changes the entire map into diamond cells and currently hides environmental batches.
- `screenshots/phase2b_mixed_cliff_fixture_phase2b_after_3_0x.png`: coherent refinement reduces cell-by-cell jitter but large sawtooth edges and broad flat facets remain conspicuous.

## Multi-elevation and chunk-boundary behaviour

### Multiple elevations

The authoritative maximum is three levels. Legacy faces use one 32x16 tile per exposed step (`terrain_chunk_build_job.gd:541-553`). Organic faces instead span directly from the owner elevation to the southern neighbour and subdivide that height internally (`organic_cliff_mesh_builder.gd:267-323`). This removes internal slab seams while preserving the exact authoritative drop.

Edge components are batched by owner elevation. Side-return width uses a clamped 1-3 level drop (`organic_cliff_mesh_builder.gd:435-452`, `473-494`). The shader samples absolute world coordinates, so strata continue vertically through the face rather than restarting per step (`cliff_procedural.gdshader:109-118`).

### Chunk boundaries

Each build job samples a one-cell 34x34 halo around its 32x32 chunk (`terrain_chunk_build_job.gd:11-18`, `206-221`). Geometry hashes use absolute world coordinates, and `outline_offset` is explicitly public for seam tests (`organic_cliff_mesh_builder.gd:256-264`). Adjacent chunks independently derive matching boundary vertices. The renderer also caches sampled halos for presentation-only mode changes and invalidates them by terrain revision (`terrain_renderer.gd:1438-1471`).

This audit reran the positive/negative seam, deterministic buffer, edit rebuild, cancellation, and latest atlas-contact validations successfully. The seam contract is a strong foundation for more sophisticated contours, but any smoothing algorithm must preserve shared absolute edge keys; smoothing a completed polyline independently inside each chunk would break that contract.

## Material evaluation and recommendations

### Keep

- Absolute world-space sampling.
- Nearest filtering and integer/pixel quantisation.
- Encoded material source and component role in vertex colour.
- Separate dirt, stone, shoreline, lip, return, and contact-shadow responses.
- A small stepped value ramp rather than photoreal lighting.
- Existing shared material and one mesh surface per component/elevation.

### Improve

1. **Introduce face-scale strata identity.** Select 2-4 deterministic beds over a multi-level face, vary thickness slowly along X, and occasionally terminate or offset a bed. Avoid one equally weighted line every 10-13 pixels.
2. **Add sparse crack graphs.** Use a low-density world-space seed lattice. From selected seeds, draw one short principal crack plus zero to two branches using distance-to-segment tests. Gate cracks by component role so lips and contact shadows remain clean. Cracks should cross tile and chunk boundaries because seed coordinates are absolute.
3. **Make facet lighting directional.** Derive broad pseudo-facet normals or oriented plane groups from a low-frequency cell field, then quantise their dot product against one fixed top-left light. This will read as form rather than random brightness.
4. **Add an ink hierarchy.** Use a one-pixel dark crest/terminal edge and selected crack accents, not a dark border around every internal quad. Keep the toe softer than the crest.
5. **Separate geology by material.** Stone should favour angular facets, stronger bed breaks, and cooler shadow planes. Dirt should favour softer vertical damp streaks, sparse roots/pebbles, and subtler strata. Shorelines should add a narrow, height-local wet band rather than globally tinting the whole face.
6. **Suppress source-tile repetition on faces.** Retain source textures for palette and micrograin, but reduce their contrast on cliff roles and let world-space macro structure dominate.
7. **Keep details zoom-stable.** Do not add subpixel noise at 0.5x. A material LOD uniform should progressively remove cracks and fine grain before it changes silhouette or broad strata.

## Recommended procedural geometry improvements

All geometry work should remain inside `OrganicCliffMeshBuilder` and consume the build job's immutable presentation halo.

### 1. Connected level-contour extraction

For each elevation threshold, classify the 33x33 grid vertices from the 34x34 height halo and emit deterministic boundary segments where occupancy (`height >= level`) changes. Use a marching-squares-like lookup only as a local contour extractor; keep Wyntar's top-down projection rules:

- southern contour orientations may expand into full wall depth;
- northern and side orientations remain foreshortened rim/return ribbons;
- ambiguous diagonal cases use a stable absolute-coordinate hash or the existing diagonal-support rule;
- each segment is owned by exactly one chunk/cell to prevent duplicates.

This produces connected contour runs without changing the stored tile height field.

### 2. World-keyed contour samples

Represent every contour endpoint by an absolute lattice-edge key: elevation, grid vertex/edge coordinate, and orientation. Compute displacement from that key, never from chunk-local polyline order. Neighbouring chunks then generate identical shared points even if they trace different portions of a run.

Use a two-scale offset:

- a slow formation field spanning roughly 3-7 cells for bays and buttresses;
- a small 4-8 pixel profile for broken rock edges.

Clamp displacement near tight concave corners and one-cell islands to prevent self-intersection or unsupported overhang into unrelated cells.

### 3. Run simplification and resampling

Trace local connected segments into runs, remove redundant collinear points, then resample at a fixed pixel interval. This removes the repeated 32-pixel cadence while keeping integer vertices. Do not use an unconstrained spline: it can overshoot, self-intersect, and disagree across chunks. A bounded corner-cutting or monotone interpolation step based only on shared edge keys is safer.

### 4. Geological face subdivision

Subdivide broad southern walls using coherent landmarks rather than one identical grid per tile:

- vertical buttress boundaries every 48-112 world pixels;
- occasional inset ledges tied to strata boundaries;
- deterministic triangular/quadrilateral facets spanning multiple cells;
- optional small toe fragments emitted into the existing shadow/edge batch, not as nodes.

These are presentation structures. They must never alter collision, picking, reachability, or terrain elevation.

### 5. Corner and small-shape policy

Retain the current classifier's useful small-shape safeguards. One-cell islands, narrow necks, water contacts, and 3-level drops should use a conservative contour profile. Broad formations can use the full geological envelope. This prevents the desired irregularity from reopening the detached-strip and unsupported-cap defects fixed in Phases 7C.2-7C.5.

## Projection comparison and decision

| Question | Standard top-down | Experimental oblique |
| --- | --- | --- |
| Matches current game composition | Yes | No; rotates cells into 64x32 diamonds |
| Current default | Yes | Disabled |
| Full faces | Southern drops only; other directions are cues | All four exposed directions |
| Existing environment presentation | Preserved | Hidden while oblique mode is active (`terrain_renderer.gd:1112-1124`) |
| Geometry per 16-chunk benchmark | 28,680 vertices / 16,000 triangles for the 12-chunk refined cliff fixture (not identical fixture) | 156,328 vertices / 135,508 triangles for 16 chunks |
| Saved build cost | ~83-95 ms total organic work for 12 chunks in Phase 1F graphical streaming | ~540.6 ms toggle/build for Phase 2A; Phase 2B refinement toggle ~1,623 ms |
| Editing integration | Incremental, revision-gated, old mesh retained | Synchronous whole-chunk rebuild in `rebuild_chunk` |
| Visual advantage | Preserves readable overhead colony layout | Stronger height volume and directional face lighting |
| Primary risk | South-facing bias and stepped contours | Major art/composition change, topology cost, occlusion/picking complexity, missing object integration |

**Decision:** retain the standard projection. It is closer to the visible Out of Pixkrieg map presentation than Wyntar's oblique experiment, preserves the current camera/editor/object language, and already has the mature incremental scheduler. Keep oblique as an experimental comparison and a source of ideas for directional face shading and shared-edge geometry; do not make it the production cliff path.

The oblique prototype demonstrates that Wyntar's authority and picking can support another projection, but it does not demonstrate that a 3D or 2.5D replacement is necessary. Its current cost and integration gaps argue against promotion.

## Zoom-aware LOD

### Verified current state

There is no cliff LOD state. `Main` owns camera zoom and passes only the derived visible world rectangle to `TerrainRenderer` (`scripts/main.gd:401-431`). Both organic and oblique builders always emit the same topology. The existing capture suites deliberately inspect 0.5x, 1x, and 3x.

### Recommended minimal support

The architecture can support **material LOD** with little complexity:

1. `Main` passes the current zoom scalar to one renderer setter when zoom changes.
2. `TerrainRenderer` updates a uniform on the shared cliff material(s).
3. The shader uses two or three stable bands with hysteresis: broad tone only at 0.5x, strata/facets at normal zoom, cracks/micrograin at close zoom.
4. Geometry is not rebuilt, so edits, chunk caches, seam logic, and deterministic topology remain unchanged.

Do not implement geometry LOD in the first stages. It would multiply cache/build states, require cross-fading or carefully synchronised swaps to prevent popping, and complicate benchmark interpretation. Current geometry is already bounded to at most three face, three edge, and three shadow meshes per chunk. Reconsider geometry LOD only after profiling the contour prototype at the largest supported viewport and minimum zoom.

## Staged implementation plan

### Stage 0 — Freeze evidence and add a cliff-specific comparison fixture

Changes: test/capture code only.

- Reuse the existing phase capture infrastructure and camera positions.
- Add one deterministic fixture containing a long diagonal, S-curve, concave bay, broad 3-level face, one-cell island, shoreline, and a positive/negative chunk seam.
- Capture 0.5x, 1x, and 3x with material on/off and geometry on/off.
- Record face/component/vertex/triangle counts and geometry CPU separately from total chunk work.

Acceptance:

- Repeated captures use identical authority and camera state.
- Existing Phase 1B/1D/1E/1F/1G and 7C.4/7C.5 validations stay green.
- No save or world-generation changes.

### Stage 1 — First visual prototype: geological material hierarchy

Changes: `shaders/cliff_procedural.gdshader`, capture/validation only.

- Add broad directional facet groups, non-uniform coherent beds, sparse branching cracks, a thin crest accent, and role-specific dirt/stone/shoreline tuning.
- Add a zoom/detail uniform, but keep its first implementation at a fixed default if wiring zoom would enlarge the prototype.
- Reuse the existing procedural-material rollback switch.

Acceptance:

- At 1x and 3x, a blind A/B review can identify broad planes, irregular bed breaks, and sparse cracks without seeing 32-pixel texture repetition dominate.
- At 0.5x, fine cracks do not shimmer or collapse into noise.
- Stacked faces and adjacent chunks show no strata/crack discontinuity.
- Shoreline tint is confined to the foot region.
- No geometry count, authority snapshot, or save output changes.
- Dense-cliff steady-state frame time stays within 10% of the current saved benchmark on the same machine.

### Stage 2 — Connected southern contour prototype

Changes: `organic_cliff_mesh_builder.gd` plus focused tests.

- Trace connected southern face runs at each visible drop.
- Increase profile resolution to 8 pixels on broad formations.
- Add slow world-keyed displacement across several cells.
- Preserve conservative caps on small/narrow shapes.

Acceptance:

- Long diagonals no longer repeat an obvious 32-pixel face cadence at 3x.
- Positive and negative chunk seam vertex sets are identical.
- Repeated and incremental builds remain byte-identical.
- No self-intersections, holes beneath top surfaces, or wall intrusion into unrelated water cells in the focused fixture.
- Organic geometry work remains within the existing ~2.5-3.0 ms per-frame scheduler envelope; old meshes remain visible during rebuild.

### Stage 3 — Unified level-contour rims and corners

Changes: organic builder only; replace current independent north lips/side returns with contour-run ribbons.

- Derive lips and returns from the same contour samples as the southern wall.
- Preserve foreshortening and current z-order.
- Use the existing component-role encoding and shared material.

Acceptance:

- Crest, terminal cap, side return, wall, and toe describe one silhouette.
- One-cell islands and narrow peninsulas do not regain detached dark strips.
- The Phase 7C.2-7C.5 scenario matrix passes at all captured zooms.

### Stage 4 — Face-scale geological facets and restrained fragments

Changes: organic builder and shader; no nodes per feature.

- Build a few multi-cell facet boundaries or buttress landmarks per connected face run.
- Optionally emit a bounded number of toe fragments into existing batches.
- Material consumes stable facet IDs/tones through vertex colour or one additional packed channel.

Acceptance:

- Broad 2-3 level faces have recognisable large planes rather than uniform tiled noise.
- Vertex and triangle growth is capped and documented; target no more than 2x the current organic geometry for the same fixture.
- Draw-call count does not grow with individual fragments.

### Stage 5 — Material LOD and production tuning

Changes: zoom setter and shared shader uniform only unless profiling proves geometry LOD necessary.

- Add hysteretic detail bands.
- Tune style parameters against normal gameplay scenes, not only test cliffs.
- Keep shader defaults deterministic and data-driven through presentation settings.

Acceptance:

- No visible popping while zooming through thresholds.
- 0.5x has a clean silhouette and broad tone; 3x reveals detail rather than enlarged repetition.
- No chunk rebuild occurs solely because zoom changes.

## Performance risks

1. **Contour tracing CPU.** Dictionary-heavy polyline assembly could erase the Phase 1F/1G scheduler gains. Prefer packed arrays, local lookup tables, and resumable row/segment phases.
2. **Larger halo pressure.** A two-cell halo may be useful for stable tangents, but raises samples from 1,156 to 1,296 per chunk. Only adopt it if a one-cell, world-keyed method cannot pass curvature seams.
3. **Vertex growth.** Moving from 16- to 8-pixel samples roughly doubles face-edge samples before new facets. Set explicit fixture budgets.
4. **Main-thread mesh creation.** `ArrayMesh` creation remains on the main thread. Keep one surface per component/elevation and measure finalisation separately.
5. **Shader overdraw and ALU.** Crack distance tests and multi-octave fields can be expensive across large faces. Use sparse fixed-count seeds and material LOD; avoid unbounded loops.
6. **Resource retirement.** Phase 1G proved that releasing complete chunk subtrees caused 20-35 ms outliers. New work must not add nodes per contour, crack, or fragment.
7. **Edit amplification.** Connected runs must remain chunk-local presentation results. Do not rebuild a world-scale contour after one edit; retain the current affected-chunk/revision model.
8. **Visual instability.** Noise tied to local UVs or traced-run order will crawl after edits. All feature identities must use absolute world keys.

## Regression and benchmark requirements

Every geometry stage should run:

- Phase 1B: deterministic organic faces, signed X seams, edit rebuild, rollback.
- Phase 1D: unified lips/returns/shadows, signed seams, material-role encoding.
- Phase 1E: refined signed X/Y seams, bounded halo, editing, rollback.
- Phase 1F: incremental/synchronous equivalence, cancellation, stale-result rejection, atomic replacement.
- Phase 1G: halo-revision safety and bounded retirement.
- Phase 2A/2B: retained experimental renderer remains selectable and deterministic.
- Phase 7C.2-7C.5: small shapes, water contacts, multi-level drops, connected corners, quantisation, atlas contact, and chunk seams.
- Authority snapshot comparison before/after every presentation toggle.
- `git diff --check` and a Godot editor parse.

Benchmark gates should include:

- dense cliffs, long diagonals, and chunk-seam cliffs at 0.5x/1x/3x;
- initial streaming, one-cell edit, large brush, undo/redo, mode change, rapid camera move, and cleanup tail;
- total geometry CPU, worst geometry frame, mesh-resource time, scene-attachment time, visible-ready frame, vertex/triangle totals, draw calls, memory, and retirement queue depth;
- same-machine A/B comparison with the current saved Phase 1G graphical baseline.

Do not use the old Phase 7C.4 total chunk-preparation number as the sole gate. It predates the current organic incremental/retirement work and includes unrelated systems.

## Existing benchmark evidence reviewed

- Phase 7C.4 (legacy atlas era): dense-cliff average 0.827 ms; streaming P99 8.239 ms; average chunk preparation 14.260 ms; cliff preparation 1.2492 ms; edge preparation 0.6662 ms.
- Phase 1E refined organic fixture: 12 chunks, 727 faces, 2,442 edge components, 723 shadows, 28,680 vertices, 16,000 triangles, 115.774 ms synchronous build.
- Phase 1F graphical: roughly 83-95 ms organic geometry work for 12 chunks, worst geometry frame about 2.8-3.0 ms, visible chunks ready at frame 24, and old mesh retained during edit replacement.
- Phase 1G graphical: mode replacement CPU about 105.8 ms using cached halos; streaming worst frame 21.312 ms after bounded retirement versus 35.126 ms baseline; rapid-camera worst 20.374 ms. The remaining worst frames are lifecycle/retirement concerns, not proof of cliff-builder overload.
- Phase 2A: 16 oblique chunks, 156,328 vertices, 135,508 triangles, ~32.4 ms average build per chunk, 540.613 ms toggle/build.
- Phase 2B: unchanged topology, but refined current build average ~84.2 ms per chunk and 1,623.091 ms toggle rebuild in the saved benchmark.

These fixtures are not all identical, so cross-phase totals indicate cost shape rather than exact renderer-to-renderer speed ratios.

## Validation performed for this audit

Using Godot 4.7.2 stable Mono in headless mode:

- Project editor parse: PASS. One warning notes the nested `_reference/project.godot`, which Godot intentionally ignores.
- `phase1b_validation.gd`: PASS.
- `phase1d_validation.gd`: PASS.
- `phase1e_validation.gd`: PASS.
- `phase1f_validation.gd`: PASS.
- `phase1g_validation.gd`: PASS.
- `phase2a_validation.gd`: PASS.
- `phase2b_validation.gd`: PASS.
- `phase7c4_validation.gd`: PASS.
- `phase7c5_validation.gd`: PASS.

The graphical benchmarks were reviewed from their saved JSON/reports rather than rerun. A headless rerun would not be directly comparable to their recorded Windows/OpenGL draw and frame values, and the existing benchmark scripts write into the saved evidence paths. The reference showcase was visually inspected through its embedded video; no claim is made that its private game renderer uses the exact techniques proposed here.

## Recommended first milestone

Implement **Stage 1 only: a shader-only geological cliff material prototype** on the existing standard-view organic meshes.

It is the smallest isolated milestone with a high chance of a substantial visual gain. It touches no authority, save format, picking, editing, chunk topology, or projection; uses the existing rollback switch; and can be judged immediately in the current Phase 1G and 7C.5 screenshot fixtures. The milestone should not include contour extraction, oblique promotion, new nodes, or geometry LOD. If its A/B captures establish the desired palette, facet, strata, crack, crest, and toe hierarchy, that style becomes the target for the connected-contour geometry work in Stage 2.
