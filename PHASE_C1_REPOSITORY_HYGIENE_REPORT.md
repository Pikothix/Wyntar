# Wyntar Phase C1 Repository Hygiene Report

Date: 2026-10-20

Branch: `main`

Starting commit: `473f0f97f074b8863cd4d25bb79e8df5de67ac60`

## Scope and preservation checkpoints

Phase C1 was limited to generated evidence, machine-local validation state, capture output paths, and repository scanning rules. No gameplay, terrain generation, rendering, save format, scene, shader, or runtime asset implementation was changed.

The pre-existing `main.tscn` working-tree change was preserved byte-for-byte. Its SHA-256 remained `286009DA3A044DC452E6C8D2546F42D25869BF03B013775F72DFA95170AB5933` before and after C1.

The `_reference` gitlink and nested checkout were not modified. The parent gitlink remains `6ee33aa6d4f2f87d23841dc212b11b8fbf6ea64c`; the nested checkout remains at the same commit with the same 857 status entries and the same compact status hash (`44D3134CE04BF1025509D801092E36CFF578BA53FE9A5FB27743AC77E84F6D55`). Its removal remains deferred to a separately approved task.

## 1. Files removed from Git tracking

The cleanup uses ordinary index operations only. No history was rewritten and no working evidence was deleted.

| Category | Entries | Action |
| --- | ---: | --- |
| `screenshots/**` generated captures, manifests, benchmark JSON, `.import` products, and historical RAR | 2,461 | Removed from the index; retained locally and externally archived |
| `.codex_appdata/**` and `.codex_godot_appdata/**` logs, cache, editor state, and shader cache | 19 | Removed from the index; ignored as machine-local state |
| `phase5d_validation.log` | 1 | Removed from the index; retained locally and archived |
| Three accidental root pager artifacts | 3 | Removed from the index and working tree after exact target verification |
| **Total** | **2,484** | |

The pager artifacts were:

- `cn                                            54 +-`
- `e 3C fix cliff corner gaps and side returns`
- `ter)`

All three were 16,653-byte copies with SHA-256 `6DF37BA28AD637B76417EA3E55E48AA10B304920C8FC858977B4AC6BA4E37B36`.

## 2. Files preserved in the external archive

Archive location: `G:/Sim/Wyntar_Archive/2026-10-20_473f0f97_phase_c1/`

| Preserved group | Files | Bytes |
| --- | ---: | ---: |
| Full repository `screenshots/` tree | 2,461 | 635,233,330 |
| Tracked Codex/Godot local state | 19 | 4,491,969 |
| Tracked root validation log | 1 | 302 |
| Adjacent `G:/Sim/phase3g*.log` evidence | 20 | 2,978 |
| **Total archived files** | **2,501** | **639,728,579** |

The archive retains the original directory structure under `repository/`, including all PNG captures, JSON manifests, benchmark JSON, `.import` metadata, and the unexplained RAR file.

Archive inventories:

- `ARCHIVE_MANIFEST.csv`: unified path, size, SHA-256, archived path, archived size, archived SHA-256, and verification result for all 2,501 files.
- `MANIFEST.csv`: repository evidence records.
- `ADJACENT_LOG_MANIFEST.csv`: adjacent Phase 3G logs.
- `REPORT_LINK_MAP.csv`: 235 historical Markdown screenshot references mapped to archived files.
- `VERIFICATION_SUMMARY.json`: initial repository archive verification summary.

## 3. Archive verification results

Every archived file was compared to its source using file size and SHA-256. All 2,501 unified manifest rows passed; there were zero mismatches. The external archive remained readable after the Git index cleanup.

The 235 screenshot paths referenced by historical Markdown reports all resolved to preserved archive entries. Historical report text was intentionally left unchanged; `REPORT_LINK_MAP.csv` provides the durable mapping without rewriting old reports.

## 4. New Git and Godot hygiene rules

`.gitignore` now narrowly excludes:

- generated contents under `/screenshots/`, while retaining `screenshots/.gdignore`;
- generated contents under `/.artifacts/`, while retaining `.artifacts/.gdignore`;
- root machine-local `/.codex_appdata/` and `/.codex_godot_appdata/`;
- root-level validation logs via `/*.log`.

The patterns do not exclude production scripts, runtime textures, shader files, scenes, source tests, Godot UID files, third-party notices, or approved documentation assets.

Trackable `.gdignore` markers were added to `screenshots/` and `.artifacts/` so Godot does not scan historical or newly generated evidence. The 44 capture, comparison, and benchmark scripts that wrote to `res://screenshots/` now use the single ignored output root `res://.artifacts/`. Only output locations changed; validation and capture logic did not.

## 5. Curated reference-image candidates

These are proposals only. No image was designated as a permanent artistic baseline without approval.

| Coverage | Candidate archived file |
| --- | --- |
| Current top-down terrain | `repository/screenshots/phase3g_directional_one_level_grass_plateau_1_0x.png` |
| Organic cliffs | `repository/screenshots/phase3g_directional_winding_cliff_1_0x.png` |
| Cliff-water boundary | `repository/screenshots/phase_a_enhanced_glints_water_adjacent_to_cliffs_1_0x.png` |
| Procedural vegetation | `repository/screenshots/phase8a_comparison_lake_vegetation_1_0x.png` |
| Enhanced water | `repository/screenshots/phase_a_enhanced_glints_large_open_lake_1_0x.png` |
| Positive chunk seam | `repository/screenshots/phase3g_directional_positive_chunk_boundary_1_0x.png` |
| Negative chunk seam | `repository/screenshots/phase3g_directional_negative_chunk_boundary_1_0x.png` |
| Standard zoom | `repository/screenshots/phase3g_directional_long_diagonal_escarpment_1_0x.png` |
| Intermediate zoom | `repository/screenshots/phase3g_directional_long_diagonal_escarpment_2_31x.png` |
| Close zoom | `repository/screenshots/phase3g_directional_long_diagonal_escarpment_3_0x.png` |

Recommended approval step: review these ten images together, then copy only the accepted subset into a deliberately named tracked documentation/reference directory in a separate task.

## 6. Validation results

Validation used standard Godot `4.7.stable.official.5b4e0cb0f`.

| Check | Result |
| --- | --- |
| Godot editor import/project parse | Pass (exit 0) |
| Headless main-scene launch | Pass (exit 0) |
| `tests/phase5d_validation.gd` terrain/chunk generation | Pass |
| `tests/phase3g_validation.gd` directional cliffs | Pass; visual acceptance remains separate by design |
| `tests/phase_a_water_validation.gd` water | Pass |
| `tests/phase7b1_validation.gd` save/load | Pass |
| Static required `res://` dependency presence | Pass; no missing runtime dependency (generated `.artifacts` outputs excluded) |
| Runtime scripts, textures, shaders, main scene, project file, source tests, UIDs, and notices still tracked | Pass |
| `main.tscn` pre-existing change preserved | Pass; exact SHA-256 match |
| `_reference` untouched | Pass; gitlink, nested HEAD, entry count, and status hash unchanged |
| Archive file size and SHA-256 comparison | Pass; 2,501/2,501 |
| `git diff --check` | Pass |

Godot reported the existing nested `project.godot` under `_reference` and ignored that nested folder during import. This is expected from the pre-existing checkout and was not changed during C1.

## 7. Tracked file count before and after

| Metric | Before C1 | After index cleanup | Change |
| --- | ---: | ---: | ---: |
| Git index entries | 2,788 | 304 | -2,484 |

The two `.gdignore` files and this report are new review files and are not included in the current 304-entry index count until deliberately staged. The resulting intended repository set would contain 307 entries after those three additions are accepted.

## 8. Tracked working-tree size before and after

| Metric | Before C1 | After index cleanup | Reduction |
| --- | ---: | ---: | ---: |
| Bytes represented by currently indexed working-tree files | 641,530,145 | 1,788,104 | 639,742,041 (99.72%) |

This measures files addressed by the current Git index. Local ignored evidence still exists under `screenshots/` and the external archive, so the cleanup reduces version-control payload and Godot scanning rather than immediately reclaiming all local disk space.

## 9. Remaining risks

- Permanent reference-image selection still requires artistic approval.
- Historical reports retain their original `screenshots/...` links. They work while the ignored local evidence remains present; `REPORT_LINK_MAP.csv` is the durable archive mapping.
- The dirty `_reference` nested checkout and missing parent `.gitmodules` declaration remain repository hygiene risks. They were explicitly left untouched.
- The ignored local `screenshots/` copy consumes disk space in addition to the verified archive. Removing that local duplicate should be a separate, explicitly approved cleanup after archive review.
- Staged index removals and unstaged C1 edits coexist with the user's pre-existing `main.tscn` change; review should preserve that separation.

## 10. Recommended next cleanup phase

After review and approval of this report:

1. Approve a small permanent visual-reference subset and add only those files to a named documentation/reference directory.
2. Decide separately whether to repair or remove the `_reference` gitlink, after preserving its dirty nested work.
3. Once the external archive has been independently accepted, optionally remove the ignored local `screenshots/` duplicate to reclaim disk space.
4. Keep future captures and benchmark JSON in `res://.artifacts/`; do not reintroduce generated evidence into the runtime resource tree.

