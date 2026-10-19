# Phase 7C.3 — Raised Island Editing and Cliff Geometry Correction

## Task Classification

Existing System Extension / Bugfix

## Confirmed cause

The authoritative model already stored material and ground elevation separately. Island creation failed in presentation and interaction:

1. `TerrainWorld.get_surface_elevation()` forced every water-material cell to sea level, regardless of an explicit raised-ground edit. The correct ground height was saved but could never become visible until material was changed.
2. Ordinary picking correctly followed the uppermost projected surface. After a land surface moved upward, however, another click at the same screen coordinate could resolve to a different logical row. That made repeated elevation edits appear unreliable.
3. Cliff edge artwork was still rectangular inside its atlas cell. Full-width north lips did not follow partially occupied organic corner masks, isolated side-only return pixels formed dark fragments, and terminal south walls stayed fully opaque to their rectangular endpoints.

The defects were therefore one derived liquid/material compositing rule, one missing deliberate ground-picking mode, and three presentation-only geometry details. Authoritative coordinates, stored material IDs, stored elevations, and undo transactions were not corrupt.

## Land and liquid semantics

- Material and ground elevation remain independent authoritative fields.
- Painting material does not alter elevation. Elevation tools do not alter material.
- Procedural water remains at the configured liquid plane, preserving world-generation rules.
- An explicit ground-height override on a water-owned cell remains underwater at or below sea level.
- When that explicit ground rises above sea level, liquid remains at sea level and is no longer visible over the cell. Presentation exposes the liquid material's declared substrate (`Water -> Sand`) at the authoritative ground height.
- Lowering the explicit ground to sea level or below reveals water again.
- The derived exposed substrate is not saved and does not change material ID 0. Phase 7B.1's save schema is unchanged.

This is the smallest compatible correction for the current one-material-per-cell model. It cannot remember an arbitrary former seabed material beneath water. A raised water-owned cell therefore exposes the catalog-declared sand substrate until the user paints another material.

## Intended editing workflow

1. Select elevation mode with `H`.
2. Hold `Alt` while editing to target the logical ground coordinate directly, including submerged ground and projected overlaps.
3. Raise the ground above sea level. Water stays at sea level and the sand substrate becomes exposed.
4. Optionally paint the exposed cell with sand or another land material; this does not change height.
5. Lower the cell to sea level or below to submerge it again.
6. Undo and redo preserve the independent material and elevation operations.

Ordinary surface and cliff-face picking remain the default. Alt-ground picking is an explicit editor-only choice and uses the same screen-to-world transform at every zoom.

The compact and expanded HUD now show authoritative material, ground height, visible liquid height (`none` when exposed), and the active target type.

## Cliff geometry findings and corrections

- **Legitimate exposed southern wall:** retained, including multi-level stacks and water contact.
- **Incorrect wall geometry:** terminal wall pixels were rectangular to the cell edge. End caps now alpha-taper so isolated ends do not overhang unsupported terrain.
- **Incorrect depth/occlusion:** raised water-owned ground was drawn at sea level. The derived exposed-substrate query now places the visible surface and its walls at ground height.
- **Duplicate shadow or side-return:** unconnected mid-cell side returns were removed. Side returns remain only where they join a north lip or south wall.
- **Material compositing error:** raised explicit seabed edits now use the visible substrate for masks, cliffs, decorations, environmental placement, and local refreshes while authority continues to report water.
- **Organic corner mismatch:** north lips are clipped to the supported half of corner cells instead of crossing into water.
- **Expected orthographic limitation:** north, east, and west boundaries remain shallow cues; only south-facing drops are full vertical walls.

## Visual evidence

The capture script generated 48 matched PNGs: rendered and F6 elevation diagnostics for eight scenarios at 0.5x, 1x, and 3x.

| Scenario | Rendered | F6 diagnostic |
| --- | --- | --- |
| Empty lake | [rendered](screenshots/phase7c3_empty_lake_rendered_1_0x.png) | [F6](screenshots/phase7c3_empty_lake_f6_1_0x.png) |
| 1x1 raised island | [rendered](screenshots/phase7c3_one_cell_island_rendered_3_0x.png) | [F6](screenshots/phase7c3_one_cell_island_f6_3_0x.png) |
| 3x3 raised island | [rendered](screenshots/phase7c3_three_by_three_island_rendered_3_0x.png) | [F6](screenshots/phase7c3_three_by_three_island_f6_3_0x.png) |
| Irregular island | [rendered](screenshots/phase7c3_irregular_island_rendered_1_0x.png) | [F6](screenshots/phase7c3_irregular_island_f6_1_0x.png) |
| Two-level drop | [rendered](screenshots/phase7c3_two_level_drop_rendered_1_0x.png) | [F6](screenshots/phase7c3_two_level_drop_f6_1_0x.png) |
| Island beside cliff | [rendered](screenshots/phase7c3_island_beside_cliff_rendered_1_0x.png) | [F6](screenshots/phase7c3_island_beside_cliff_f6_1_0x.png) |
| Irregular shoreline cliff | [rendered](screenshots/phase7c3_irregular_shoreline_cliff_rendered_3_0x.png) | [F6](screenshots/phase7c3_irregular_shoreline_cliff_f6_3_0x.png) |
| Lowered and undo-restored | [rendered](screenshots/phase7c3_lowered_then_undo_restored_rendered_1_0x.png) | [F6](screenshots/phase7c3_lowered_then_undo_restored_f6_1_0x.png) |

## Performance

Godot 4.7.2 graphical benchmark, 48 sampled frames per mode:

| Mode | Average | P95 | P99 | Worst | Scheduler overruns |
| --- | ---: | ---: | ---: | ---: | ---: |
| Static lake | 0.553 ms | 0.681 ms | 0.830 ms | 0.830 ms | 0 |
| Camera streaming | 3.120 ms | 5.847 ms | 6.379 ms | 6.379 ms | 28 |
| Large island edit | 1.363 ms | 4.509 ms | 5.314 ms | 5.314 ms | 0 |
| Undo/redo island | 5.002 ms | 6.250 ms | 7.350 ms | 7.350 ms | 0 |
| Save/load regeneration | 4.775 ms | 3.684 ms | 109.062 ms | 109.062 ms | 27 |

The save/load mode's P99 is the one-time regeneration frame. Across 47 profiled chunk builds, preparation averaged 12.608 ms, worst was 16.763 ms, cliff preparation averaged 0.856 ms, static memory was 71.20 MiB, and the full run recorded 214 scheduler overruns. Editing modes recorded no overruns.

## Validation

Passed with Godot 4.7.2:

- Project parse/editor load.
- Phase 7C.3 focused semantics, both operation orders, 1x1/3x3 operations, signed chunk boundaries, negative coordinates, deliberate ground picking, undo/redo, atlas geometry, snapshot round-trip, and unchanged save fields.
- Phase 5D cliffs/shorelines and 25-chunk benchmark.
- Phase 6A decorations and Phase 6B environmental objects.
- Phase 7A editor and undo/redo.
- Phase 7B.1 persistence validation plus fresh-process save and load.
- Phase 7C liquid rendering and Phase 7C.2 shape-aware cliffs.
- Phase 8A procedural environmental objects and Phase 8B harvesting/regrowth.
- 48-image graphical capture matrix.
- Phase 7C.3 graphical performance benchmark.
- Trailing-whitespace scan of every changed text file.

`git diff --check` could not run because this delivered workspace is not a Git repository.

## Remaining risks and perspective limitations

- The one-material cell model exposes the catalog-declared sand substrate, not a separately stored arbitrary seabed material.
- Procedurally generated water intentionally retains prior sea-level behaviour unless its ground receives an explicit elevation override. This prevents Phase 7C.3 from changing procedural world-generation results.
- Orthographic projection cannot show true north/east/west vertical faces. Those directions remain compact continuity cues, and highly jagged coastlines still have a cell-stepped silhouette at high zoom.
- No ramps, entrances, colonists, new liquids, fluid simulation, or decorative water effects were added.
