# Phase C4E — Cliff Gap Diagnosis and Geometry Repair

## Scope and repository state

Phase C4E was performed from `8a76425` (`G1-G6: improve procedural terrain surface rendering`) with the committed C4C and C4D work present in history. Existing changes to `main.tscn`, the `_reference` submodule, and the unrelated untracked file were preserved. The SHA-256 of `main.tscn` remained `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933` throughout the phase.

The repair is presentation-only. It does not change terrain authority, elevation data, saves, collision, picking, water, shaders, or surface generation.

## Diagnosis

### Surface asset and atlas coverage

The terrain-art-size hypothesis was tested independently rather than assumed. All eight terrain source images load as opaque 32×32 images. `TerrainSurfaceFactory` expands every source into a complete 4×4 universal-mask atlas, and each TileMap cell remains a full 32×32 quad. The source artwork therefore does not leave undersized corners or transparent holes.

The visible surface boundary is nevertheless dynamic: `terrain_variation.gdshader` applies an organic alpha displacement to the scalar mask stored in the atlas. At the configured limits, that displayed boundary can move by about six pixels in addition to the atlas mask's roughly three-pixel relief.

### Cliff contour coverage

Unified cliff contours used a separate world-space displacement of up to five pixels and began only two pixels above their independently generated crest. The surface alpha and face crest consequently did not share enough projected coverage. Where the two independent boundaries diverged, the upper surface could not occlude the face and the canvas or lower layer appeared as triangular gaps, narrow slivers, or disconnected northern edges.

The maximum bounded vertical disagreement is approximately:

- 5 px unified-contour displacement;
- 3 px encoded universal-mask relief;
- 6 px maximum organic alpha displacement.

This establishes a 14 px required underlap at the face crest.

### Isolated raised cells

Isolated cells were explicitly diverted from unified marching contours into the older per-cell face path. Neighbouring contour squares containing that isolated sample were then skipped. That hybrid ownership produced the clearest reproduction: the projected surface cap and the legacy face appeared as two disconnected pieces.

### Side faces, ordering, and chunk ownership

Near-degenerate projected side faces used an unsigned one-pixel X fallback even though the caller supplied a five-pixel lateral depth. This could leave east/west returns as slivers. The fallback now uses the signed low-side normal and the requested depth.

Render order was not the root cause. Directional faces intentionally render below elevated surfaces, allowing the surface to occlude the crest underlap. Chunk ownership was also sound: the builder uses a one-cell halo, absolute world-space noise, and canonical shared-edge endpoints. The signed chunk-seam fixture and streaming revisit remained continuous.

## Implementation

`organic_cliff_mesh_builder.gd` now:

- extends unified face crests upward by 14 pixels beneath elevated surfaces;
- keeps the existing contour, face projection, material, and draw-call ownership;
- uses the configured five-pixel signed lateral depth for a truly degenerate side return;
- processes isolated samples entirely through unified marching contours;
- removes the obsolete isolated-sample hybrid fallback and square suppression.

The underlap changes existing vertex positions only. It does not add a cover polygon, mesh surface, node, material, texture, or draw call. Ordinary unified contours retain the same vertex and triangle counts. An isolated two-level cell now correctly emits four unified contour faces per level.

The Phase 3E validator was updated narrowly: it no longer requires a duplicate Phase 3D edge-strip count that existed only because isolated samples accidentally re-entered the legacy path. It still requires unified faces and checks every produced triangle for non-zero area.

## Visual comparison

The deterministic fixture uses seed `84521`, a 1280×720 viewport, the scene's prominent 32 px height profile, unified contours, directional projection, and disabled edge/shadow overlays. It covers:

- straight north/south/east/west edges;
- convex and concave corners;
- diagonal and organic boundaries;
- an isolated raised cell;
- a multi-cell plateau;
- adjacent one-, two-, and three-level terrain;
- dirt/stone faces meeting water;
- a signed chunk seam.

Every fixture was captured before and after at 100%, 150%, and 200% zoom. The 24 matched side-by-side images use **before on the left and after on the right** and are stored as `.artifacts/c4e_compare_<scenario>_<zoom>.png`. Manifests are:

- `.artifacts/c4e_before_capture_manifest.json`
- `.artifacts/c4e_after_capture_manifest.json`

Visual review found:

- the isolated cap and face are connected after the repair;
- northern edges have continuous cliff coverage instead of exposed corners;
- long diagonal faces no longer break into intermittent slivers;
- convex/concave corners contain no exposed background wedges;
- multi-level and water-contact faces remain material-correct;
- the chunk-seam contour is continuous at all three zooms;
- no generic ground-cover geometry or new overlap fins are present.

The after image at the chunk seam was pixel-identical after streaming 160×96 cells away and returning.

## Structural validation

`phase_c4e_cliff_geometry_validation.gd` verifies:

- every terrain source asset is 32×32 and fully opaque;
- an isolated two-level cell emits eight unified faces;
- the isolated face crest overlaps the projected cap;
- cardinal and diagonal fixtures contain no zero-area triangles;
- repeated builds are byte-deterministic;
- canonical crest endpoints agree across a chunk seam.

## Performance

The existing matched C4C benchmark completed on Godot 4.7 Compatibility/NVIDIA RTX 3080. For the active directional/prominent mode it reported:

- 3,461 faces;
- 17,400 triangles;
- 34,800 vertices;
- 9.065 ms mean steady-frame sample;
- 13.660 ms steady p95;
- 10.230 ms mean streaming-frame sample;
- 536.449 ms mean total streaming CPU work across the benchmark workload;
- 543.46 average streaming draw calls.

Compared with the prior C4C evidence, the dense fixture gained only the eight faces, 16 triangles, and 40 vertices needed to render one formerly hybrid isolated two-level feature. Regular contours add no geometry. Draw calls did not increase. Absolute frame timings were not directly comparable because the unchanged connected baseline was also substantially slower during this run; the geometry and draw-call counters are the reliable impact measures.

## Regression results

Godot 4.7 checks were executed with 60-second per-process bounds where applicable.

| Check | Result |
|---|---|
| Full project import and script parse | Pass; one non-fatal editor-cache safe-save warning |
| Main-scene startup | Pass |
| C4E focused geometry validator | Pass |
| C4E graphical matrix and streaming revisit | Pass |
| G1, G2, G3, G4, G5, G6 validators | Pass |
| Phase 3E unified contours | Pass after directly related stale assertion repair |
| Phase 3F height profiles/determinism | Pass |
| Phase 3G directional projection | Pass |
| Phase 1G chunk streaming/lifecycle | Pass |
| Water validation | Pass |
| Phase 7B1 save/load | Pass |
| Phase 7C5 cliff structural validation | Pass |
| C4A renderer configuration | Pass |
| C4B renderer factories | Pass |
| C4C matched cliff benchmark | Pass |
| `git diff --check` | Pass |

## Remaining limitations

The shader and mesh still generate their organic boundary detail independently; C4E makes their bounded overlap watertight rather than introducing a new shared boundary representation. If future configuration expands either displacement beyond its present factory limits, the underlap bound must be reviewed. A true shared pixel contour would be a larger rendering redesign and was intentionally outside this repair.

The ignored `.artifacts/` evidence is not intended for source control. No files were committed or pushed.
