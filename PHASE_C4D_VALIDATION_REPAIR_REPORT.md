# Phase C4D — Validation Repair Report

Date: 2026-10-21

Task classification: Existing System Maintenance — Test Compatibility and Regression Repair

Starting branch and commit: `main` at `45d5b25` (`Phase C4C: evaluate cliff rendering baselines`)

## 1. Original failure

`tests/phase7c4_validation.gd` failed to parse during a full Godot editor import because `_test_profile_function()` called the removed renderer helper `TerrainRenderer._cliff_boundary_offset(style, x)` three times.

Phase C4B moved legacy cliff atlas construction out of `TerrainRenderer` and into `CliffResourceFactory`. The equivalent profile calculation now belongs to `scripts/cliff_resource_factory.gd` as `CliffResourceFactory._boundary_offset(style, x, width)`. Restoring the old renderer method would have duplicated factory behavior and weakened the ownership established by C4B.

## 2. Changes made

Only `tests/phase7c4_validation.gd` was changed:

- Added a preload for `res://scripts/cliff_resource_factory.gd`.
- Replaced the three stale `TerrainRenderer._cliff_boundary_offset(...)` calls with `CliffResourceFactory._boundary_offset(..., 32)`.
- Preserved the original assertions for zero-valued left/right endpoints and the `0..2` pixel-quantized profile range across all four styles.
- Retained `TerrainRenderer` in the validator because `_test_atlas_geometry()` still instantiates the renderer to verify the integrated cliff atlas exposed to runtime rendering.

No production API was restored or added. No rendering, gameplay, terrain generation, shader, scene, persistence, or save-schema behavior changed.

## 3. Updated API references

| Previous reference | Updated reference | Owner after C4B |
| --- | --- | --- |
| `TerrainRenderer._cliff_boundary_offset(style, 0)` | `CliffResourceFactory._boundary_offset(style, 0, 32)` | `cliff_resource_factory.gd` |
| `TerrainRenderer._cliff_boundary_offset(style, 31)` | `CliffResourceFactory._boundary_offset(style, 31, 32)` | `cliff_resource_factory.gd` |
| `TerrainRenderer._cliff_boundary_offset(style, x)` | `CliffResourceFactory._boundary_offset(style, x, 32)` | `cliff_resource_factory.gd` |

The explicit width preserves the original 32-pixel atlas-cell assumption while exercising the current factory implementation directly.

## 4. Targeted stale-reference search

The test suite was searched against all helper methods removed from `terrain_renderer.gd` by commit `314f9e2`, including terrain atlas, cliff atlas, boundary/inset, material, mask, coverage, and atlas-position helpers.

The only directly related stale production-method calls were the three `_cliff_boundary_offset` references in Phase 7C4. The `_coverage` text match in Phase 6A is its own validator method and is unrelated. No additional test repair was required.

## 5. Validation results

Validation used Godot `4.7.stable.official.5b4e0cb0f` with an isolated local application-data directory. Every Godot process had an explicit 120-second timeout.

| Check | Result |
| --- | --- |
| Full project import and script parse (`--headless --editor --quit`) | PASS; no script/import failure |
| Main-scene startup, Compatibility renderer (`--quit-after 3`) | PASS |
| Repaired Phase 7C4 validator | PASS |
| C4A renderer configuration validator | PASS |
| C4B renderer factory validator | PASS |
| Phase 3G cliff structural validator | PASS; visual acceptance remains separate by design |
| Phase 7B.1 save/load validator | PASS |
| `git diff --check` | See final hand-off result |

The full editor import emitted two unrelated environmental messages: a non-fatal editor-settings safe-save warning and the expected warning that the nested `_reference/project.godot` is ignored. It emitted no parse errors after the repair.

## 6. Remaining stale tests

No remaining tests were found calling renderer methods removed by Phase C4B.

## 7. Ownership and protected state

The repair follows the C4B ownership boundary: cliff resource generation remains in `CliffResourceFactory`, while `TerrainRenderer` retains runtime integration and the generated resource references.

The pre-existing changes to `main.tscn`, the `_reference` gitlink checkout, and the unrelated untracked pager artifact were preserved. No commit or push was performed.
