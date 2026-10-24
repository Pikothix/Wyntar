# Phase C4E.1 — Cliff Contour Continuity Repair

## Scope and recovered repository state

Phase C4E.1 began from `fe3b13f` (`C4E: repair procedural cliff geometry gaps`). The prior C4E geometry repair and the G1–G6 rendering milestone were present in Git history. Existing modifications to `main.tscn`, the `_reference` submodule, and unrelated untracked content were preserved. `main.tscn` retained SHA-256 `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933`.

The change remains presentation-only. Terrain elevation is still authoritative; the renderer reads it and builds cliff meshes. Simulation, terrain generation, saves, collision, picking, surface materials, water, and cliff height settings are unchanged.

## Deterministic reproduction and diagnosis

The focused fixture uses seed `84521`, world center `(32, -28672)`, a 1280×720 viewport, the prominent 32 px height profile, unified connected contours, and directional projection. Its elevation boundary alternates between diagonal and short constant-X runs and crosses signed chunk boundaries. This reliably reproduced the reported sequence of full diagonal faces interrupted by pointed fragments and apparent grass gaps.

The diagnostic capture draws:

- the authoritative elevation boundary in red;
- raw unified contour paths in cyan;
- shared path endpoints in yellow;
- emitted mesh triangle edges in magenta;
- chunk boundaries in green;
- sampled contour segment IDs in white;
- the final rendered cliff underneath the overlays.

The matching machine-readable diagnostics contain every affected segment ID, world cell, elevation level, marching mask, path coordinates, and per-segment delta. Representative level-two runs include:

| Segment | World cell | Mask | Raw path endpoints |
|---:|---:|---:|---:|
| 185 | `(23, -28673)` | 10 | `(738, -917616)` → `(738, -917584)` |
| 190 | `(23, -28672)` | 10 | `(738, -917584)` → `(734, -917552)` |
| 195 | `(23, -28671)` | 10 | `(734, -917552)` → `(736, -917520)` |
| 201 | `(23, -28670)` | 10 | `(736, -917520)` → `(739, -917488)` |
| 235 | `(28, -28664)` | 10 | `(899, -917328)` → `(896, -917296)` |
| 239 | `(28, -28663)` | 10 | `(896, -917296)` → `(894, -917264)` |
| 243 | `(28, -28662)` | 10 | `(894, -917264)` → `(895, -917232)` |
| 247 | `(28, -28661)` | 10 | `(895, -917232)` → `(896, -917200)` |

These coordinates demonstrate that the elevation samples, marching-square authority, raw path endpoints, and chunk hand-off were continuous before the repair. The discontinuity was introduced only when valid paths were converted to visible face geometry.

### Root cause

Near-vertical crest paths were extruded using the normal downward cliff-height projection. C4E handled an exactly degenerate projected segment by using a five-pixel lateral return, but unified organic paths are deliberately bowed at their midpoint and their canonical endpoints carry bounded world-space displacement. A path that was visually vertical therefore almost never had an exact zero cross product and bypassed that fallback.

The builder emitted two long, extremely narrow projected quads around the bowed midpoint. Their visible portions formed opposing pointed or diamond-shaped fragments. Correct canvas ordering then allowed the elevated surface to occlude most of those edge-on faces, making the spaces between the fragments look like missing cliff faces or exposed grass. This was a mesh-construction and surface-occlusion interaction, not missing terrain data, a material split, or a chunk ownership failure.

### Why C4E was incomplete

C4E correctly added the bounded 14 px crest underlap needed to cover disagreement between surface-alpha and contour displacement, unified isolated-cell ownership, and repaired exactly degenerate side returns. Its visual fixture emphasized monotonic diagonals, cardinal edges, corners, isolated cells, and chunk seams. It did not force several consecutive near-vertical paths whose organic midpoint prevented exact-degeneracy detection. The structural test also required non-zero triangle area, so these technically non-degenerate but visually ineffective triangles passed.

Increasing the 14 px underlap would not repair this topology. The underlap covers the crest; it cannot give an edge-on projected face useful lateral area.

## Correction

For a surface-facing unified contour component, the mesh builder now classifies the complete canonical path before segment extrusion. A path is treated as a side return when:

- its vertical displacement is greater than its horizontal displacement; and
- its endpoint horizontal displacement is no greater than the existing five-pixel lateral depth.

Such a path emits one quad between its canonical endpoints at the existing underlapped crest, returned horizontally by the existing signed five-pixel depth. The artificial midpoint is intentionally omitted for this case: retaining it creates two opposing tips, while the endpoints already preserve deterministic organic drift and are shared across neighboring squares and chunks.

All other paths retain the existing projected geometry. The 14 px C4E crest underlap, directional shading, material ownership, chunk halo, world-space displacement, and render ordering are unchanged. No node, material, texture, mesh surface, draw call, save field, or configuration option was added.

## Focused regression coverage

`phase_c4e1_cliff_continuity_validation.gd` directly exercises the previously missed path `(32, 0) → (34, 16) → (32, 32)`.

Before the production correction, it failed because both near-vertical segments used height projection rather than a lateral return. After the correction, it verifies that:

- one continuous four-vertex canonical side-return quad is emitted;
- the return has at least the configured five pixels of horizontal area and no meaningful vertical projection;
- the top edge preserves the canonical shared endpoints; and
- raw contour endpoints remain exactly equal across positive and negative chunk seams.

## Visual comparison

Matched captures were produced at 100%, 150%, and 200% zoom with identical seed, fixture, viewport, camera position, renderer settings, and disabled overlays. In each comparison, **before is on the left and after is on the right**:

- `.artifacts/c4e1_compare_bent_diagonal_1_0x.png`
- `.artifacts/c4e1_compare_bent_diagonal_1_5x.png`
- `.artifacts/c4e1_compare_bent_diagonal_2_0x.png`

The source frames and diagnostics are:

- `.artifacts/c4e1_before_bent_diagonal_<zoom>.png`
- `.artifacts/c4e1_after_bent_diagonal_<zoom>.png`
- `.artifacts/c4e1_before_diagnostic_overlay_1_5x.png`
- `.artifacts/c4e1_after_diagnostic_overlay_1_5x.png`
- `.artifacts/c4e1_before_contour_diagnostics.json`
- `.artifacts/c4e1_after_contour_diagnostics.json`

Visual review at all three zooms confirms that the short vertical portions are continuous five-pixel side bands after the repair instead of pointed internal fragments. The adjoining diagonal faces and organic silhouette remain unchanged. The after capture was pixel-identical after streaming 160×96 cells away and returning.

## Performance

The existing C4C graphical benchmark completed under Godot 4.7 Compatibility on an NVIDIA RTX 3080. The final active directional/prominent workload reported:

- 3,461 faces;
- 16,100 triangles;
- 32,200 vertices;
- 2.633 ms mean steady-frame sample;
- 3.095 ms steady p95;
- 5.203 ms mean streaming-frame sample;
- 338.729 ms mean total streaming CPU work;
- 544.28 average streaming draw calls.

Relative to the committed C4E evidence for the same dense geometry workload, the face count is unchanged and the canonical side-strip construction removes 1,300 triangles and 2,600 vertices (7.47%) by replacing pairs of ineffective segment quads with one path quad. It adds no draw calls. Absolute timing from separate runs is environment-sensitive; the reliable conclusion is that geometry was reduced and the final same-run directional result was effectively equal to the connected baseline (2.641 ms steady and 5.264 ms streaming-frame means).

## Validation results

Godot 4.7 processes used explicit 60-second bounds.

| Check | Result |
|---|---|
| Full project import and script parse | Pass; one non-fatal editor-cache safe-save warning |
| Main-scene startup | Pass |
| C4E.1 focused contour-continuity validator | Pass; confirmed fail-before/pass-after |
| C4E geometry validator | Pass |
| C4E.1 graphical fixture at 100%, 150%, and 200% | Pass |
| C4E.1 streaming-away-and-return pixel comparison | Pass |
| G1, G2, G3, G4, G5, and G6 validators | Pass |
| Phase 3E unified contours | Pass |
| Phase 3F height profiles and determinism | Pass |
| Phase 3G directional projection | Pass |
| Phase 1G chunk streaming/lifecycle | Pass |
| Water validation | Pass |
| Phase 7B1 save/load | Pass |
| Phase 7C5 cliff structural validation | Pass |
| C4A renderer configuration | Pass |
| C4B renderer factories | Pass |
| C4C graphical benchmark | Pass |
| `git diff --check` | Pass |

## Remaining limitations

This repair deliberately targets near-vertical unified surface-facing contour paths. It does not change rear components or diagonal/front faces because those require the existing height projection and showed no corresponding defect. The five-pixel classification bound is tied to the renderer's existing lateral-depth limit; if that limit or the contour displacement range changes, the focused validator and visual fixture should be rerun.

The independently generated surface alpha and cliff contour remain joined by C4E's bounded underlap rather than a shared pixel contour. Replacing them with a single representation would be a larger renderer redesign and is not required for the repaired discontinuity.

The ignored `.artifacts/` evidence is retained locally for visual review. No files were committed or pushed.
