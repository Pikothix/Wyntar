# Phase C4F — Grid-Aligned Cliffs, Rounded Rims and Elevation Readability

## Decision

The C4F grid-first boundary prototype is implemented behind
`grid_aligned_cliff_rim_enabled`, but it is **disabled by default and should not
replace C4E.1 yet**.

The prototype proves that cell-edge tracing removes the cliff mesh's diamond
footprint, produces bounded four-pixel bevels, keeps east/west faces readable,
and gives the rim and face one canonical boundary. Matched visual review also
shows that the existing elevated surface still uses its older dual-grid/masked
silhouette. On isolated cells, L-shapes, water contacts, and natural terrain,
that surface can visibly detach from the new square rim. Enabling C4F now would
therefore exchange one silhouette defect for a more obvious surface/rim split.

## 1. Why the C4E.1 silhouette distorts

C4E.1 begins from four elevation samples and runs a marching-squares lookup in
`OrganicCliffMeshBuilder._unified_contour_segments()`. Crossings are placed on
the midpoint of each 32-pixel cell edge. A lone occupied sample consequently
produces four diagonal midpoint crossings: its reconstructed boundary is a
diamond before shading or projection is applied.

Additional bounded transforms then amplify the effect:

- canonical edge endpoints can move by up to 5 px from world-keyed contour
  noise;
- each path midpoint can move by another 5 px, with a forced 2 px bow on
  vertical segments;
- the independently generated surface mask can add roughly 3 px of encoded
  relief and about 6 px of alpha displacement;
- C4E uses a 14 px crest underlap to cover the combined disagreement;
- south-facing projection extends by one configured elevation step (32 px in
  the prominent profile), while near-vertical returns receive only 5 px of
  lateral area.

This explains the reported symptoms:

- isolated cells are diamonds because the source contour connects edge
  midpoints around one occupied sample;
- near-vertical faces become thin because a screen-vertical crest projected in
  screen Y has almost no area;
- diagonal direction changes create pointed wedges because independently
  extruded path segments meet at a displaced midpoint;
- surface, rim, and face boundaries disagree because the elevated surface and
  cliff geometry do not consume one canonical boundary;
- water contacts expose the disagreement clearly because the contrasting water
  removes the visual camouflage supplied by similar ground materials.

The visible displacement is large relative to the 32 px cell: endpoint and
midpoint variation each reach 15.6% of cell size, the combined surface/contour
agreement envelope reaches 14 px (43.8%), and a prominent south face reaches a
full cell of apparent depth.

## 2. Proposed shared-boundary architecture

The production migration should derive one presentation boundary from the
authoritative elevation halo for each elevation threshold:

1. Classify cell occupancy from immutable authoritative elevation samples.
2. Remove edges shared by two occupied neighbours.
3. Link the remaining cardinal edges into deterministic chunk-local loops using
   absolute lattice coordinates.
4. Apply bounded corner treatment to each loop. Convex corners may bevel or
   round by at most a configured fraction of the 32 px cell; concave corners
   must retain exact shared endpoints.
5. Rasterize the elevated surface coverage from that loop.
6. Generate the perimeter rim from the same loop.
7. Generate direction-aware cliff faces from the same loop and level interval.

The boundary and its world-keyed points are presentation data. `TerrainWorld`
continues to own elevation and material state; the renderer reads it, and UI,
collision, picking, saves, and simulation do not consume the visual boundary.

The current prototype implements steps 1–4, 6, and 7 inside the existing
chunk-batched builder. Step 5 requires a deliberate migration of the elevated
surface factory/mask input. That is the minimum broader work needed for a
convincing result; increasing underlap or adding another local gap patch would
not solve it.

## 3. What was implemented

- Added the presentation-only `grid_aligned_cliff_rim_enabled` switch through
  `Main`, `TerrainRenderer`, `TerrainChunkBuildJob`, and
  `TerrainChunkRenderer`.
- Preserved the existing C4E.1 builder exactly when the switch is disabled.
- Added cardinal cell-edge extraction directly from the existing 34×34
  immutable elevation/material halo.
- Removed internal edges between neighbouring cells at each elevation level.
- Added 4 px convex bevels (12.5% of cell size); concave joins keep exact grid
  endpoints.
- Generated both the 3 px rim strip and the supporting face strip from each
  canonical boundary segment.
- Used low-side normals for directional projection: south-facing segments can
  use the full configured height, while north/east/west remain bounded to a
  readable 6 px minimum depth. Bevel normals interpolate naturally at corners.
- Retained material source selection, including shoreline/stone variants, and
  the existing combined cliff shader roles.
- Added focused structural validation, the complete visual fixture matrix, and
  a matched dense graphical benchmark.

No authoritative elevation, terrain generation, collision, picking, save
schema, chunk ownership, water mask, or G1–G6 surface-material behaviour was
changed. `main.tscn` remains on C4E.1 because the new switch defaults to false.

## 4. Before/after visual comparisons

The capture harness produced 40 C4E.1 frames, 40 C4F frames, and 40 side-by-side
comparisons at 100%, 175%, 250%, and 350% zoom. Before is left and C4F is right.
Representative files:

- `.artifacts/c4f_compare_one_cell_3_5x.png`
- `.artifacts/c4f_compare_l_plateau_2_5x.png`
- `.artifacts/c4f_compare_water_contact_1_75x.png`
- `.artifacts/c4f_compare_natural_terrain_1_0x.png`
- `.artifacts/c4f_c4e1_capture_manifest.json`
- `.artifacts/c4f_c4f_capture_manifest.json`

Positive observations:

- large outer silhouettes follow the cell grid rather than wandering around
  marching-square midpoints;
- cardinal edges remain visually present on all four sides;
- the rim and face have no internal endpoint disagreement;
- east/west faces no longer collapse into the C4E.1 near-vertical sliver case;
- water-contact faces are straight and materially coherent.

Failed acceptance points:

- the elevated top remains diamond/organic while the C4F rim is square;
- isolated and small-cluster caps visibly detach from the face/rim;
- some concave L-shape locations expose ground between the old surface mask and
  new boundary;
- north/east/west faces read as mechanically boxed at high zoom;
- large natural terrain becomes more grid-readable but less visually coherent
  because the surface and cliff use different silhouette languages.

## 5. Single-cell and small-cluster results

The structural result is correct: a one-cell boundary contains four 24 px
cardinal segments plus four 4 px bevels, retains a 32×32 bounding footprint,
and emits no degenerate triangles. Two adjacent cells and 2×2 blocks omit all
shared internal edges. Repeated builds are byte-deterministic.

The rendered result is not yet acceptable. The one-cell top cap remains on the
old diamond-like mask while the new two-level rim/face forms a square stack.
The visual therefore resembles separated blocks rather than one small raised
platform. The same mismatch is visible, though less strongly, on 2×2, 3×3,
L-shaped, and narrow-strip fixtures.

## 6. Remaining gaps and limitations

- The elevated surface does not consume the grid boundary. This is the primary
  blocker and the reason the prototype remains disabled.
- Per-cell extraction produces correct shared endpoints but not yet linked
  contour loops. Loop linking is needed to generate joined face feet without
  overdraw and to support genuinely rounded multi-segment corners.
- Face and rim quads overlap intentionally so the rim shader role wins at the
  crest. This adds topology and overdraw but does not add draw calls.
- GPU frame time is unavailable from the Godot Compatibility performance
  monitor used by the existing harness; the report does not invent a value.
- The capture fixtures exercise positive and negative world-space generation
  elsewhere in the existing regression suite, but the new visual matrix itself
  is primarily placed at large positive coordinates plus natural origin terrain.

## 7. Performance and regression results

Matched dense fixture, 1280×720, Godot 4.7.2 Compatibility, NVIDIA RTX 3080,
three runs and 720 steady samples per mode:

| Metric | C4E.1 | C4F prototype | Change |
|---|---:|---:|---:|
| Mean steady frame | 2.793 ms | 2.796 ms | +0.003 ms |
| Steady p95 | 3.601 ms | 3.549 ms | -0.052 ms |
| Average draw calls | 605 | 605 | 0 |
| Vertices | 32,200 | 36,856 | +14.5% |
| Triangles | 16,100 | 18,428 | +14.5% |
| Mesh nodes | 36 | 36 | 0 |
| Mean streaming frame | 5.363 ms | 5.367 ms | +0.004 ms |
| Mean streaming CPU total | 349.927 ms | 286.513 ms | -18.1% |
| Worst streaming frame | 18.121 ms | 18.919 ms | +0.798 ms |

The streaming CPU reduction is not treated as a guaranteed improvement because
separate scheduled runs are sensitive to cache and process timing. Geometry and
draw-call counts are the stable comparison. Full results are in
`.artifacts/c4f_grid_cliff_benchmark.json`.

Validation passed:

- Godot 4.7.2 project import and script parse;
- main configuration propagation;
- C4F topology, determinism, and chunk-coordinate boundary checks;
- C4E and C4E.1 focused regressions;
- Phase 1G streaming/lifecycle;
- Phase 3E unified contours, Phase 3F height/determinism, Phase 3G direction;
- Phase 7B.1 save/load and Phase 7C.5 cliff structure;
- water validation;
- C4B renderer factories;
- G1, G2, G3, G4, G5, and G6 validation;
- 80 source captures and 40 matched comparisons;
- matched graphical benchmark;
- `git diff --check`.

## 8. Recommendation

Do **not** replace C4E.1 with the current C4F prototype. Keep
`grid_aligned_cliff_rim_enabled` false.

The next C4F iteration should not add another mesh-side gap patch. It should
first move elevated-surface coverage onto a shared boundary artifact, then link
cell edges into deterministic contour loops and derive the surface, rim, and
faces from those loops. Re-run the same isolated-cell and L-shape comparisons
before considering default enablement. If that migration is not approved, the
new prototype should remain a comparison-only path and C4E.1 should remain the
production renderer.
