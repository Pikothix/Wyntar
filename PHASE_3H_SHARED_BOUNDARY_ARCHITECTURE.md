# Wyntar — Phase 3H-A: Shared Terrain/Cliff Boundary Investigation

Date: 2026-10-20

Task classification: Documentation

Status: Investigation and proposed design only. **Phase 3H-B requires approval.**

## 1. Recommendation

Choose **B, bounded to elevation-boundary squares**: derive one deterministic,
unprojected terrace partition and its interfaces from the existing presentation
height samples. Use that partition for both boundary-adjacent top coverage and
cliff geometry. Keep ordinary interior TileMaps, material definitions, geological
shading, chunk streaming, authoritative terrain, generation and saves.

Pair shared coverage with **per-height-band depth ordering**, bounded resolution
of overlapping wall fragments, and **one revision/commit for tops and cliffs**.
Those are necessary parts of the solution, not optional polish.

Do not:

- Port GPU noise to the cliff builder and assume the problem is solved.
- Reuse independent Phase 3E paths at every threshold without proving nesting.
- Cover defects with a wider brown or terrain-coloured ribbon.
- Replace the whole renderer, introduce conventional 3D, or store a world contour graph.

This is larger than a shade/z-index adjustment but smaller and more maintainable
than maintaining two incompatible silhouettes plus growing repair rules. Its
correctness is supported by the proposed invariants below; its performance and
visual acceptance remain **unproven until Phase 3H-B**.

“Authoritative top-mask” in option A means the existing *visual* silhouette.
Neither that mask nor the proposed partition is gameplay authority.

## 2. Evidence and scope

Read the Phase 3E approach/report, Phase 3F report and Phase 3G report. Inspected
the current sampling, surface preparation, atlas/shader, mesh construction,
projection, layer assignment, edit invalidation and replacement paths. Reviewed
the saved Phase 3G lake and mixed-height comparison images.

Key source anchors, relative to this repository (line numbers at investigation):

| Source | Relevant implementation |
| --- | --- |
| `scripts/terrain_world.gd:60` | Presentation surface elevation and visible liquid/material |
| `scripts/terrain_chunk_build_job.gd:218` | Streamed halo sampling |
| `scripts/terrain_chunk_build_job.gd:351` | Four-corner render-square samples |
| `scripts/terrain_chunk_build_job.gd:482` / `:506` | Ground and exact-height top masks |
| `scripts/terrain_chunk_renderer.gd:529` | Immediate edited top rebuild, same mask semantics |
| `scripts/terrain_renderer.gd:2519` / `:2542` | Mask atlas and scalar field |
| `shaders/terrain_variation.gdshader:63` | Projected world coordinates and final alpha |
| `scripts/organic_cliff_mesh_builder.gd:115` / `:255` | Isolated fallback and threshold contours |
| `scripts/organic_cliff_mesh_builder.gd:362` / `:382` | Saddle pairing and contour displacement |
| `scripts/organic_cliff_mesh_builder.gd:489` / `:517` | Wall/contact-band extrusion |
| `scripts/terrain_chunk_renderer.gd:436` / `:790` | Face and top depth policy |
| `scripts/terrain_renderer.gd:567` | Edit dependency sets and deferred cliff jobs |
| `scripts/terrain_renderer.gd:1152` / `:1314` | Height profiles and editor projection |

Historical qualifications:

- The Phase 3E report says its toggle is disabled by default. Current
  `main.tscn:40` enables unified contours. Preserve the current checkout, not the
  historical statement.
- Phase 3G remains disabled by default; baseline height remains 16.
- Earlier statements that sharing four samples guarantees top/crest alignment
  are too strong. Source code establishes shared inputs, **not shared geometry**.
- Passing Phase 3G's unchanged-vertex tests proves preservation of wall geometry,
  not watertight final compositing.
- The original user's lake save/coordinates remain unavailable. The known
  reproduction uses water at surface height 0 and sand at height 2.

## 3. Exact current data and coordinate trace

### 3.1 Authority and ownership

TerrainWorld owns cell materials, ground elevations and overrides. Surface
sampling is not always raw ground elevation: visible liquid uses the sea-level
surface, and exposed liquid substrate can use another visible material without
changing the cell's authoritative material.

TerrainRenderer supplies `get_world_visible_cell` and
`get_world_surface_elevation` to the normal rendering jobs; raw ground elevation
is also sampled for other presentation consumers. Any replacement must use the
same visible-material/surface-height inputs, particularly around water.

The build job owns a temporary 34x34 halo for a 32x32 chunk. For halo index
`(a,b)`, the sampled world cell is `32*C + (a-1,b-1)`. Top and organic geometry
preparation read this snapshot. Chunk renderers own the resulting disposable
TileMaps and mesh batches. Nothing here is saved as authoritative terrain.

### 3.2 Render-square coordinates

Let `C` be chunk coordinates, `l=(x,y)` a local render-square index,
`q=32*C+l`, `s` the selected pixel step (16,24,32), and `e` an elevation.

The four samples are:

```
q+(-1,-1)   q+(0,-1)      bits 8,4
q+(-1, 0)   q+(0, 0)      bits 2,1
```

The dual render square has unprojected origin `O=32*q-(16,16)` and size 32x32.
Chunk position is `1024*C`. Top layers have local position
`(-16,-16-e*s)`. Thus an atlas pixel centre `(i+0.5,j+0.5)` is displayed at:

```
p = O + (i+0.5,j+0.5) - (0,e*s)
```

Camera transformation/zoom follows this projection; it is not part of the
contour function. Top shader `MODEL_MATRIX` coordinates already contain the
elevation displacement.

### 3.3 Top coverage

At each height, source materials are sorted by catalog priority. For a source
with priority cutoff `k`, a corner enters the mask iff:

```
corner.surface_height == e AND corner.material_priority >= k
```

This is **exact-height** membership, including ground at e=0. Up to four
overlaid material slots are emitted per height. The synchronous edited-cell
path duplicates these semantics.

The reusable 16-case atlas evaluates at pixel centres:

```
u=(i+0.5)/32; v=(j+0.5)/32
F = bilerp(mask corner bits, u, v)
    + 0.07*sin(6*pi*u)*sin(4*pi*v)
```

The RGBA8 atlas encodes clamped F in red (8-bit quantisation); its alpha is the
source texture alpha multiplied by `smoothstep(0.43,0.57,F)`.

With organic boundaries enabled, the shader derives another displacement:

```
P = floor(projected_world_position) + (0.5,0.5)
N = 2 * smooth_value_noise(P*frequency + seed_offset) - 1
alpha = smoothstep(0.43,0.57,atlas_red + N*strength) * base_texture_alpha
```

It blends this with atlas alpha according to the organic toggle. Default shader
strength/frequency are 0.08/0.035; renderer settings supply the actual values.
The seed offset excludes material ID, which keeps same-position material
subsets coherent. It does **not** remove differences between differently shifted
height layers.

Consequences:

- A top edge is a soft alpha transition, not one stored line.
- Noise is evaluated in **projected** coordinates. At the same unprojected
  point, changing e or s changes its noise phase.
- Source-alpha, 8-bit field storage, and the 0.43–0.57 transition affect coverage.
- Within one height, material subsets have related masks; across heights,
  separate exact-height masks are not a complete geometric partition.

### 3.4 Cliff coverage

For each threshold `h=1..max(corner heights)`, Phase 3E uses
`corner.surface_height >= h`, not `== h`. It looks up marching segments in a
16-case table. Ambiguous masks 6/9 use a world-cell/seed **and level-dependent**
hash to choose connectivity.

Each edge crossing starts at a square-edge midpoint. Canonical absolute-world
edge coordinates drive bounded broad/fine integer noise (96/32-pixel spacing).
Crossing offsets are rounded and clamped to +/-5 pixels. Neighbouring squares
calculate the same edge point without consulting each other.

Path orientation samples an undeformed bilinear occupancy field and swaps
endpoints so the high side is on the left. One interior midpoint receives
separate world-space noise, rounds to pixels and is clamped three pixels inside
the square. Near-vertical pieces can receive a level-dependent +/-2-pixel bow.
These computations use **unprojected** world coordinates.

The three points then receive `(0,-h*s)` and integer rounding. Walls extend
from -2 to `s+1` relative to this crest. The nominal toe is therefore the same
unprojected path at height h-1, with one extra pixel of overlap. Contact strips
use `[s-3,s+1]`, only on qualifying south-facing non-shoreline source paths, and
remain in the face batch. A degenerate projected segment may receive a one-pixel
horizontal extrusion. Geological shader world coordinates are presentation
coordinates; there is no separate surface-boundary authority in that shader.

An isolated high owner instead routes through Phase 3D. Unified squares touching
an isolated sample are skipped. The predicate returns false on the outer halo
border because it cannot inspect all four neighbours there.

### 3.5 Occlusion and lifetime

Top slots draw at `e*8+[0..3]`. Every wall band in a square is put in the batch
for that square's **maximum corner height**, even if the band itself is lower.

- Phase 3F face z: `max_height*8+3`.
- Phase 3G face z: `max_height*8-1`.
- Neither sorts by the band's actual vertical interval or per-fragment depth.

A band at h=1 in a square containing height 3 can consequently draw above a
height-2 terrace. An adjacent square can assign the corresponding band another
z group. Changing the single offset cannot resolve every such relationship.

Edits refresh affected dual top cells immediately, then schedule cliff rebuilds.
Phase 3G toggle replacement keeps an old complete cliff mesh until the new one
commits, but that is not a joint top-and-cliff edit transaction. Height-profile
changes likewise reposition tops before incremental wall replacement completes.
These are possible transient mismatch windows, separate from settled slivers.

Editor picking uses projected rectangular cells and south-face rectangles,
not the rendered organic contour. Existing brush polygons are rectangular.
An approved boundary integration must distinguish logical cell-selection
semantics from optional exact visible-surface hit testing.

## 4. Causes: confirmed versus not yet isolated

| Finding | Evidence/status | Implication |
| --- | --- | --- |
| Exact-height tops versus cumulative-threshold cliffs | Confirmed directly in both paths | Matching noise alone cannot make mixed-height interfaces agree |
| Different functions, topology, quantisation and soft alpha | Confirmed | Two surfaces do not share an exact crest even at one height |
| Projected top noise versus unprojected cliff noise | Confirmed | Changing height/profile changes relative silhouette alignment |
| All bands assigned square maximum depth | Confirmed | Lower wall bands can cover legitimate intermediate terraces |
| Level-salted saddles and vertical bows | Confirmed inputs differ by level | Identical binary masks across bands are not guaranteed identical interior paths/topology |
| Isolated fallback mixed with unified contour squares | Confirmed | A shared model cannot silently keep two unrelated boundary definitions |
| Halo-edge isolated predicate lacks context | Confirmed code asymmetry | Seam-specific visual impact needs a targeted fixture; not claimed proven here |
| Immediate tops/deferred cliffs | Confirmed lifecycle | Can cause temporary mismatch during editing; not an explanation for every settled image |
| Source alpha/filtering/large-coordinate GPU precision | Possible additional contributors | Measure separately; no driver/raster precision defect established |
| Particular sliver caused by one particular triangle | Not isolated | Requires surface-ID/depth diagnostic captures, not just colour screenshots |

Analytic counterexample: for corner heights `[0,1,2,3]`, at u=v=0.5 each
exact-height bilinear field is 0.25, while cumulative threshold fields are
1.0,0.75,0.5,0.25 at thresholds 0,1,2,3. Wobble is zero at that mathematical
centre. With zero organic strength, each exact-height top alpha is zero there.
The exact-height masks therefore do not partition the unprojected square.
This is an algebraic counterexample, **not a claim that the same screen pixel
is uncovered after all height projections and walls are composed**.

Likewise, identical shared endpoints prove neither non-crossing interior paths
nor correct occlusion. Phase 3G images visibly contain residual thin brown
fragments, but do not by themselves identify whether every fragment is mask,
depth, fallback, or a combination.

## 5. Options

### A — Fit cliffs to the existing top masks

Would require evaluating the actual mask/alpha boundary for each material,
height and profile, including atlas quantisation, wobble, shader noise and
texture alpha. CPU reimplementation of GPU sine/hash noise is not a guaranteed
bitwise equivalent. GPU readback adds synchronisation and lifecycle complexity.
Selecting alpha=0.5 alone does not close the soft transition.

Even perfect matching of each top outline does not specify what connects two
non-partitioning exact-height regions, or fix wall depth assignment. Adding
explicit inter-region fills and ownership rules eventually becomes B under a
less useful interface.

Useful as a diagnostic baseline; not recommended as the final solution.

### B — Shared deterministic boundary and terrace partition

One CPU-owned presentation description supplies both top coverage and vertical
interfaces. It defines regions, topology and sample ownership, not merely a
noise helper or list of edge endpoints. Boundary-square tops consume it directly;
GPU noise may colour those tops but may not independently displace their outside
alpha. Flat/interior material transitions keep the accepted renderer.

Recommended. More initial work than C, but eliminates rather than conceals the
inconsistent definitions. An exact preservation of all old edge pixels is not
promised; acceptance must assess the bounded silhouette changes.

### C — Narrow stitching/coverage layer

A chunk-batched collar could cover small raster cracks where top and wall already
agree on topology. It cannot reliably bridge arbitrary exact-height gaps, resolve
different saddle connectivity, or decide which intermediate terrace occludes a
face. A large collar changes perceived terrain area and reproduces raised rims.

A final subpixel coverage rule is reasonable *after* B establishes a common
boundary. C alone is not a complete solution.

### Comparison

Ratings are design estimates, not new benchmarks.

| Criterion | A: fit existing masks | B: shared boundary squares | C: stitches alone |
| --- | --- | --- | --- |
| Architectural complexity | Medium initially; high once GPU parity and multi-height fills are included | Medium/high but explicit, bounded responsibilities | Low initially; exception rules grow quickly |
| Determinism | CPU/GPU agreement problematic | Strong with integer inputs, fixed topology and canonical intersections | Deterministic patches possible; coverage still ambiguous |
| Chunk independence | Possible if exact shader inputs are reproducible | Canonical world-edge keys; bounded read-only neighbourhood | Local patches possible; corners/junctions need coordination rules |
| Runtime edits | Recompute profile-dependent outlines; synchronise tops/walls anyway | Single revision/commit; reverse dependency bounds explicit | Extra patch invalidation; can display stale repairs |
| Memory | Dense alpha copies/readback costly; sparse caching possible | Sparse boundary polygons; no full-resolution coverage atlas required | Small until collars become wide or duplicated |
| CPU/GPU performance | Dense sampling or readback risk | More boundary build work/vertices; measurable and budgetable | Extra fill/overdraw and batches |
| Visual potential | Closest old tops; unresolved multi-height semantics | Exact shared interfaces and meaningful terrace coverage | Good for tiny cracks; poor for topology/depth defects |
| Regression risk | Low initial surface change, high subtle mismatch risk | Concentrated in boundary-square coverage/material composition | Low initial changes, high residual defect risk |
| Sufficient by itself? | No | With depth and lifecycle rules below | No |

## 6. Proposed bounded B design

### 6.1 Shared partition construction

One proposed pure boundary builder, called from existing jobs, receives visible
corner materials/heights, absolute square key, seed and boundary version. It
owns no mutable world state. It returns unprojected fixed-precision geometry,
terrace labels and shared interfaces. Height step is a projection input later.

Use one **common piecewise-linear subdivision** of each transition square.
A fixed 4-pixel sampling lattice is an initial prototype budget, not an accepted
quality/performance result. Uniform-height squares take an immediate fast path.
Each small triangle uses the same connectivity at every height.

At lattice samples, evaluate binary cumulative occupancy fields for h=1..3:

```
F_h = bilerp([corner_height >= h]) + one common bounded world-space bias
S_h = { F_h >= 0.5 }; S_0 = whole square; S_4 = empty
R_h = S_h minus S_(h+1)       for h=0..3
```

The common bias must be independent of h, material, chunk origin, profile and
build order. Use deterministic integer-derived noise; do not clone the GPU
sine hash. Boundary samples must depend only on shared edge samples and the
absolute edge key; interior perturbation cannot move an adjoining edge.
Pin authoritative sample corners to their classifications and bound perturbation.

Why this is tractable:

- Binary inputs are nested. Non-negative bilinear/triangle interpolation and
  the same additive bias preserve `F_(h+1) <= F_h`.
- Therefore S sets are nested and R regions partition the square.
- Within each common triangle, each F is affine. R_h is obtained by clipping
  that triangle against at most two half-planes. This avoids an unbounded
  general-purpose polygon union or world-scale contour traversal.
- A direct 0-to-3 boundary has identical fields at levels 1,2,3: interfaces
  coincide and intermediate terraces have zero area. Do not invent terraces
  where no such height is present.
- Mixed-height fields can separate, yielding explicit intermediate top regions
  rather than independently clipped masks with unowned spaces.

Construct intersections once with canonical keys and reuse them in tops, wall
bands and adjacent squares. Proposed precision is 1/256 of an unprojected pixel,
using fixed-point/rational predicates where topology is decided. **Do not round
every consumer independently to whole pixels.** Quantisation must preserve
nesting and topology: merge coincident vertices, retain shared IDs, remove
zero-area primitives, and validate after snapping. If snapping violates an
invariant, reject that build in diagnostics; do not silently insert a patch.

The lattice, quantisation and tie rule are part of the versioned presentation
contract. Final resolution must be selected by the acceptance/performance gate.
Do not substitute a finer unbounded grid when a fixture fails.

### 6.2 Consume the same regions without replacing all terrain rendering

For a square with multiple heights:

- Suppress its old independently masked top tiles in the experimental mode.
- Emit its R_h top patches into chunk-batched surface meshes at height h.
- Use the same R_h boundary vertices for the crest/toe of threshold wall bands.
- Keep existing TileMaps for uniform-height squares and material transitions
  without elevation changes.
- At boundaries of a patched square, canonical shared samples and the
  neighbouring uniform square must agree; no duplicate opaque top seam.

This boundary-mesh adapter is preferred over a full chunk coverage texture.
It reuses material textures/variation while avoiding a per-chunk 1024x1024
RGBA mask (4 MiB GPU payload, plus CPU/staging copies, before padding/mipmaps).
It does require a bounded top-mesh rendering path and appropriate material
parameters; that is an explicit scope item, not “no renderer change.”

Material priority is pigment composition **inside** R_h, not structural opacity.
Use an opaque base from a deterministic valid material at that height, then
clip existing priority overlays to R_h. Do not multiply structural coverage by
another independently displaced outside mask. Keep material provenance and
visible-liquid rules; never use a new fake gameplay material as a gap filler.
The choice of pigment at newly owned transition pixels must be deterministic
and included in visual review. Uniform same-height water/sand remains unchanged.

All top patches remain chunk/material/height batches, never nodes per square or
segment. A texture-based adapter is a fallback design requiring separate memory
approval if boundary meshes cannot meet performance targets.

### 6.3 Projection, directional visibility and depth

Apply the same `p -> p-(0,h*s)` to shared vertices, with s=16,24,32.
The boundary identity does not change with s. Do not add separate shader alpha
displacement, artificial vertical bows or lateral degenerate-wall width.
An exactly edge-on wall has zero projected area; connected top coverage, not
a manufactured ribbon, closes that silhouette.

Emit threshold wall h over vertical interval [h-1,h], and assign:

```
top at h-1  <  wall band h  <  top at h  <  wall band h+1
```

The existing eight-slot spacing can express this (`wall h: h*8-1`), but the
batch must be indexed by **h**, not the square's maximum height. Once R_h is a
valid partition, an intermediate terrace covering a lower band is correct
occlusion, not a ribbon to be defeated by promoting the entire drop.

Keep actual coverage for hidden/rear faces initially. Directional shading may
use Phase 3G's normal convention. A near lake bank faces north into the lake;
a far lake bank faces south. Cardinal map position alone is not classification.
Contact shadows must be attached to the same toe and valid receiver, not repeat
across internal bands. Debug validation must work with shadows entirely off.

**Band ordering alone is not a complete depth buffer.** Multiple walls in the
same band can overlap on screen, especially narrow formations. Do not rely on
triangle append order, chunk load order or material batch order. The proposed
bounded remedy is CPU clipping of farther projected fragments against nearer
overlapping fragments before batching:

- Derive a linear depth along a wall from its vertical interpolation.
  At the same projected Y, larger unprojected Y means larger continuous height
  and nearer geometry in this fixed projection. Use explicit deterministic
  ties for coplanar/shared edges.
- Split only at projected overlap boundaries/depth ties; keep fragment
  ownership with its originating square/chunk.
- Use a spatial index over the small projected neighbourhood, not all chunk
  polygons against all other polygons.
- Include neighbouring chunks' canonical input-derived geometry as read-only
  occluders even if their render nodes are not loaded.

This step must first be checked against an independent depth/coverage oracle.
It is a bounded algorithm, but its CPU cost is a major unmeasured risk. If
general polygon complexity or costs exceed the gate, stop; do not introduce
an implicit depth-buffer renderer rewrite.

### 6.4 Neighbourhood and memory bounds

Local boundary generation still needs only four corner samples. Occlusion is
a separate larger dependency: the largest displacement is 3*32=96 pixels.
A conservative proposed input margin is
`ceil(MAX_ELEVATION*s/TILE_SIZE)+1` cells (maximum four), including dual-square
sample context. Prove the exact inclusive bounds in B before using them.

A simple maximum 42x42 snapshot instead of 34x34 has 608 extra samples:
approximately 3,040 additional raw bytes for one int32 material and one byte
height stream, excluding containers and other existing sample streams. Keeping
the maximum margin at all profiles simplifies invalidation; tighter asymmetric
bounds are an optional later optimisation, not a prerequisite.

Do not confuse this small halo increase with total memory: boundary top meshes,
intersection records, clipping scratch buffers and staged old/new batches are
the dominant uncertain costs. Use packed storage, reuse bounded scratch space,
discard temporary regions after finalisation, and cache only loaded chunk data.
Measure peak bytes including replacement overlap, not just steady allocations.

### 6.5 Editing, jobs and presentation ownership

TerrainWorld mutation APIs remain unchanged. Changes invalidate all square
records that sample the edited cell and all receiver/occlusion chunks whose
bounded candidate neighbourhood includes them. Enumerate this reverse dependency
explicitly; the current cliff-cell offset list is not sufficient evidence.

Build top patches, cliff bands, visibility fragments and relevant material data
from one immutable input revision and setting version. Commit them together.
Keep the prior complete presentation until ready; do not update one half first.
For an edit spanning a chunk edge, retain the old affected presentation group
until all affected chunks' replacements are ready, then swap in one frame.
Do not make neighbours wait indefinitely for unloaded render nodes.

Height-profile and mode changes also require synchronized projected surface,
wall, decoration/object and cursor updates. Cancellation must reject stale
results after edit, undo/redo, regeneration, profile changes or unload.

Picking keeps authoritative cell identity. The B plan should preserve current
rectangular brush semantics and validate projection; if precise visible-edge
picking is needed, use the shared presentation record as a hit-test aid and
map back to authoritative cells. Do not let meshes become editable terrain state.

## 7. Required formation behaviour

| Formation | Required handling |
| --- | --- |
| Enclosed depression | Closed shared interfaces; far-bank wall visible, near-bank wall occluded by genuine higher top; equal visible heights produce no wall |
| Isolated plateau | Same partition model, not automatic Phase 3D geometry inside the B mode; all four surrounding squares agree on the island; liquid/material authority unchanged |
| Diagonal cliff | Common piecewise-linear contour; no 32-pixel per-cell staircase or independent side returns; front faces retain depth, rear-face invisibility is acceptable when physically correct |
| Mixed-height junction | Nested thresholds, complete R_h regions, shared triple-junction vertices, walls in actual height bands, correct receiver/shadow ownership |
| Narrow ridge / opposing walls | Explicit within-band visibility; zero-area edge-on faces do not require a cosmetic strip; same result independent of batch order |
| Chunk edges/corners | Canonical absolute edge keys and deterministic ties; read-only bounded neighbour inputs; tests at negative coordinates, both axes and four-chunk corners |

A truly rear-facing wall cannot be made prominently visible without changing
the projection or inventing geometry. The acceptance target should be coherent
landmass/top occlusion, not equal rock area in every direction.

## 8. Phase 3H-B plan — approval required

### Gate 0: evidence and oracle, before integration

Add tests/diagnostics only: separate top occupancy, threshold contours,
height-band IDs, continuous depth and final surface-owner views. Use an independent
slow reference ray/depth compositor for small fixtures, with a sentinel background.
Isolate the current slivers and check the proposed partition/visibility math.
Record baseline captures without changing Phase 3E/F/G.

Test all 4^4=256 corner-height combinations (0..3), rotations/reflections,
multiple seeds, ambiguous saddles, direct multi-level drops and isolated peaks.
This is not the full neighbourhood test: include adversarial adjacent squares,
opposing same-band walls and cross-chunk cases separately.

Stop if a fixed local contract cannot satisfy complete partition, nesting and
bounded visibility. Approval to implement B does not authorise a broader renderer.

### Gate 1: pure shared representation

Implement one proposed shared-boundary module plus focused tests. No authority,
save or generator changes. Specify lattice, noise, keys, quantisation, ties and
version. Test area conservation, non-overlap, shared vertex identity, winding,
degeneracy and intersection bounds before connecting graphics.

### Gate 2: bounded rendering adapter

Add boundary-square top batches, per-band cliff batches and bounded overlap
clipping. Integrate with existing builder/job/chunk ownership. Reuse textures
and geological shading; no independent alpha deformation of structural edges.
Uniform squares remain on their existing path. Inspect flat colours and shadows
off before accepting textured output.

### Gate 3: lifecycle and editor integration

Implement shared revision/cancellation and atomic affected-chunk commits.
Update dirty-neighbour bounds. Exercise paint/erase, elevation changes,
undo/redo, regeneration, save/load of unchanged authority, rapid camera motion,
unload during builds, and profile changes while jobs are pending.

### Gate 4: captures, regression and performance

Re-run available Phase 1B–1G, 3C–3G, 7A and 7C.4–7C.5 tests.
There is currently no Phase 1C script. Add B-specific geometry, raster coverage,
depth ownership, reverse invalidation and atomicity tests; legacy passes alone
are insufficient.

### Acceptance criteria

1. R_0..R_3 cover each unprojected square completely without overlapping interiors;
   cumulative regions are nested after quantisation.
2. Crest/toe/shared top vertices are identical by canonical key, not merely
   within an arbitrary gap tolerance. No inverted/nonzero-area self-intersecting
   polygons or unmatched seam edges.
3. Diagnostic raster/depth oracle shows **zero uncovered pixels inside expected
   visible terrain coverage** and no wrong opaque owner; evaluate without a
   full-screen ground fill that could conceal missing geometry.
4. Test at 16/24/32, 1x/2.31x/3x, integer and fractional camera offsets.
   Shared edges have a documented raster fill convention; any antialiasing
   fringe must preserve coverage and cannot be used to hide structural errors.
5. North faces do not form full-width brown rims, south faces retain measured
   projected height, and diagonal/corner transitions have no detached fragments.
   Visual review of both material and diagnostic images is mandatory.
6. Positive/negative x/y seams and four-chunk corners match under reversed,
   randomized and delayed load/build order, including changed cells on seams.
7. Profile changes do not alter unprojected boundary topology; regeneration and
   equivalent edited/restored inputs produce identical canonical records.
8. No mixed old/new top-wall generation is displayed during the tested edits and
   toggles. No authority/save changes; legacy mode rollback restores its output.

### Comparison and rollback controls

Propose one separate `shared_boundary_projection_enabled`, default false.
It selects the complete top+wall contract only when unified organic rendering
is enabled. Incompatible combinations should be explicitly rejected or remain
on the complete legacy path, never a mixed renderer.

It takes precedence over directional prototype rendering while retaining the
stored Phase 3G setting for rollback. Disabling it restores exactly the selected
Phase 3E/F/G presentation through a synchronized rebuild. Keep 16 as default.
Do not remove older flags, fallback code or their evidence.

### Deterministic captures

Reuse Phase 3G's seed 84521, 1280x720, frozen water animation, identical camera
coordinates and lighting/material settings; wait for jobs and retirements.
Capture Phase 3F at 16/24/32, Phase 3G at 32, and proposed B at 16/24/32.
Include the 15 Phase 3G scenarios plus:

- Four-height single-square and adjacent-square junctions.
- Saddles with identical masks across multiple levels.
- A one-sample island at halo edges and each signed chunk corner.
- Narrow opposing walls separated by less than 32/64/96 projected pixels.
- Mixed materials including visible liquid versus exposed substrate.
- Diagnostic saturated background, solid ID colours, shadows off.
- Fractional camera positions and a large positive/negative world coordinate.
- Recorded intermediate frames during edits, rollback and profile changes.

Each manifest records seed, input fixture hash, mode, boundary version, height
step, camera, viewport, toggles and completed presentation revision. Compare
full scenes at 1x and detail views at 2.31x/3x. Obtain the original lake save if
available; otherwise label the reproduction honestly.

### Performance and memory gate

Use identical dense Phase 1G fixture `(10200,5100)` and add boundary-heavy
checkerboard/mixed-height, isolated-island and narrow-ridge workloads.
Measure uncapped vsync-off runs on the same machine, with warm-up and randomized
mode order, at least five paired runs and 720 steady frames per mode.

Record mean/P95 frame time, streaming CPU, worst geometry-build frame,
time-to-visible-ready, edit and mode-switch latency, vertex/triangle counts,
mesh nodes, steady/streaming draw calls, CPU allocations, peak replacement memory,
GPU resource payload/upload work, and retirement cost.

Initial acceptance budget: no more than 10% paired regression in mean/P95 frame
time, streaming CPU and worst geometry-build frame against Phase 3F at the same
height, with repeats to distinguish noise. Report Phase 3G comparison too.
Use a provisional additional peak-memory cap of 1 MiB per loaded chunk for
shared-boundary data/meshes/scratch attributable to B, including staging; this is
a proposed budget requiring approval, not a measured estimate. Record geometry
and draw-call growth even when timing passes. Never trade a correctness failure
for meeting the speed budget.

If the bounded adapter cannot meet these gates, report the failing fixture,
cost and smallest necessary design change. Do not silently introduce full
coverage textures, GPU readbacks, world-scale contours or LOD.

## 9. Investigation validation and handoff

This turn used source inspection, existing report/capture review, and the analytic
mask counterexample. No new engine benchmark or rendering-success claim is made.
Only this architecture document was created; production files and prior
Phase 3E/F/G work were left unchanged. `git diff --check` was run for documentation
handoff. A project parse/runtime suite is not necessary for a documentation-only
change; it is explicitly part of the proposed implementation plan.

Decision requested: approve the bounded B scope and its coverage/depth/lifecycle
gates, or revise that scope. **Stop here. Phase 3H-B has not begun.**
