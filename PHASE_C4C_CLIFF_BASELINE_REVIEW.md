# Phase C4C — Cliff Visual Baseline Review

## 1. Current effective cliff configuration

Phase C4B is present at `314f9e2 Phase C4B: extract renderer resource factories` and was `HEAD` when this evaluation began. The pre-existing working tree contained modified `main.tscn`, modified `_reference`, and an unrelated untracked pager file. Those items were treated as protected inputs.

The production scene was inspected but not changed. Its effective cliff configuration differs from several script defaults:

| Setting | `main.gd` default | `main.tscn` override / effective value |
| --- | --- | --- |
| Procedural cliff materials | Enabled | No override; enabled |
| Organic cliff geometry | Enabled | No override; enabled |
| Unified cliff components | Enabled | No override; enabled |
| Refined silhouettes | Enabled | No override; enabled |
| Connected cliff contours | Enabled | No override; enabled |
| Unified cliff contours | Disabled | Enabled |
| Directional cliff projection | Disabled | Enabled |
| Cliff height profile | Baseline (16 px) | Prominent (32 px) |
| Edge overlays | Enabled | Disabled |
| Shadows | Enabled | Disabled |

`main.gd` remains the configuration hand-off point. `TerrainRenderer` owns presentation state and rendering resources; `OrganicCliffMeshBuilder` constructs presentation geometry. The authoritative terrain model, editing, picking and persistence ownership were not moved.

## 2. Supported configuration matrix

| Combination | Status | Reason |
| --- | --- | --- |
| Organic geometry + connected contours | Supported | Stable, deterministic organic segment path. It preserves the clearest coverage in the comparison fixtures. |
| Organic geometry + unified contours | Supported but visually experimental | Marching-squares contours are deterministic, but local top alpha and projected faces can disagree at corners and mixed heights. |
| Unified contours + directional projection | Supported but visually experimental | Directional depth ordering applies to unified organic faces and suppresses much rear-edge clutter, but does not remove all slivers or shared-boundary mismatches. |
| Connected contours + directional projection | Misleading | The directional face-depth policy is implemented for unified contours. Enabling it with connected-only contours does not provide the advertised comparison. |
| Unified contours without organic geometry | Misleading / not a useful baseline | Unified contour construction is an organic mesh feature; isolated cases may internally fall back. The legacy TileMap path is not equivalent. |
| Moderate or prominent height with organic geometry | Supported | Projection and picking respond to the selected 24/32 px step. Visual defects are magnified as height increases. |
| Moderate or prominent height with legacy TileMap cliffs | Misleading | The legacy path is calibrated around the 16 px baseline and is not a matched substitute for organic projection. |
| Unified cliff components with overlay/shadow visibility toggles | Supported | Component resources remain available for atomic rebuild/fallback behavior; visibility may be controlled independently. |

## 3. Controlled comparison methodology

The evaluation harness is `tests/phase_c4c_cliff_baseline_capture.gd`. It builds fixed fixtures without editing `main.tscn` and sets every relevant cliff flag explicitly for each run.

- Godot 4.7 stable, Compatibility renderer, 1280×720 viewport.
- Fixed seed `84521`, fixed camera centers and fixed zooms (`1.0×` and `2.31×`).
- Water animation time fixed to `0.0`; lighting and renderer settings held constant.
- Terrain generation, decoration and environmental objects disabled except for the dedicated context capture.
- Orientation fixture covers north/south/east/west edges and inner/outer corners.
- Water/seam fixture includes signed chunk-boundary coordinates and land/water contact.
- Mixed-height fixture covers multiple elevation steps and two zoom levels.
- Context fixture retains deterministic vegetation and environmental objects near cliffs.
- Each mode writes a JSON manifest containing its settings and image list.

The output is reproducible at the input/state level. GPU raster output is not promised to be byte-identical across different drivers or hardware. On the evaluation machine, the four overlay/shadow states were byte-identical.

## 4. Curated screenshot index

All 19 PNGs and 12 manifests are ignored under `.artifacts/`; none should be committed.

### Contours

- `.artifacts/c4c_contours_connected_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_contours_unified_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_contours_connected_water_signed_seam_seed84521_z2_31x.png`
- `.artifacts/c4c_contours_unified_water_signed_seam_seed84521_z2_31x.png`

### Directional projection

- `.artifacts/c4c_directional_off_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_directional_on_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_directional_off_water_signed_seam_seed84521_z2_31x.png`
- `.artifacts/c4c_directional_on_water_signed_seam_seed84521_z2_31x.png`

### Height profiles

- `.artifacts/c4c_height_baseline_mixed_orientation_height_seed84521_z1_0x.png`
- `.artifacts/c4c_height_baseline_mixed_orientation_height_seed84521_z2_31x.png`
- `.artifacts/c4c_height_moderate_mixed_orientation_height_seed84521_z1_0x.png`
- `.artifacts/c4c_height_moderate_mixed_orientation_height_seed84521_z2_31x.png`
- `.artifacts/c4c_height_prominent_mixed_orientation_height_seed84521_z1_0x.png`
- `.artifacts/c4c_height_prominent_mixed_orientation_height_seed84521_z2_31x.png`

### Overlays and shadows

- `.artifacts/c4c_components_none_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_components_overlay_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_components_shadow_orientation_corners_seed84521_z2_31x.png`
- `.artifacts/c4c_components_both_orientation_corners_seed84521_z2_31x.png`

### Vegetation/environment context

- `.artifacts/c4c_vegetation_context_vegetation_context_seed84521_z1_0x.png`

## 5. Contour comparison

**Connected contours** produce the strongest present-day baseline. Straight faces remain legible, coverage is predictable, corner joins are comparatively clean, and the water boundary remains readable. The cost is a more rectangular/stair-stepped silhouette, especially along upper boundaries and turns. East/west continuity is less organic than the unified result.

**Unified contours** produce visibly smoother, rounder silhouettes and better apparent continuity around broad exterior turns. That gain is outweighed in the evaluated fixtures by thick projected rock bands, triangular overlap patches, narrow slivers, and disagreement between the top surface boundary and cliff faces. The water/seam fixture makes these defects particularly clear. The signed seam itself remains deterministic, but a deterministic seam does not make the surrounding projection visually correct.

Trade-off: unified contours are the stronger long-term shape language, but connected contours are the stronger shippable baseline until top alpha and projected faces share one boundary representation.

## 6. Directional projection comparison

The valid comparison used unified contours and the prominent profile, matching the configuration where the directional depth policy has an effect.

Directional projection **off** renders strong depth around all directions but produces heavy rear/north bands, internal rings, and overlapping faces over top surfaces. Directional projection **on** removes much of that rear/internal clutter and improves the main south-facing wall. It also weakens some rear height cues and leaves thin horizontal/triangular slivers and mixed-height mismatches.

Trade-off: directional projection is a meaningful mitigation for unified contours, not a cure for their shared-boundary defects. It should remain disabled in a connected-contour baseline and should not be promoted as an independent general-purpose flag.

## 7. Height profile comparison

| Profile | Visual result | Trade-off |
| --- | --- | --- |
| Baseline, 16 px | Most compact and readable at both zooms; least overlap and best camera economy. | Shallower depth cue. |
| Moderate, 24 px | Clearer vertical separation and a plausible alternative for selected scenes. | More face overlap and more screen space consumed. |
| Prominent, 32 px | Strongest depth cue. | Magnifies thick bands, slivers and mixed-height mismatch; reduces useful framing without a compensating readability gain. |

The vegetation/context capture confirms that nearby objects remain positioned consistently with the tested presentation, while also showing that taller projected boundaries compete more strongly with object silhouettes. Baseline is the safest permanent value. Moderate is the only credible alternate after boundary defects are resolved. Prominent is not recommended.

## 8. Overlay and shadow comparison

The four states—neither, overlay only, shadow only, and both—produced identical PNG SHA-256 values in the preferred connected/baseline fixture. No readability improvement or clutter difference was visible because these optional components produced no raster delta in that steady-state fixture.

This result does **not** justify deleting component resources or fallback paths. Their rebuild/fallback role is distinct from steady-state appearance. For a permanent baseline, keeping both visibility flags disabled is the smallest evidence-backed presentation choice, while retaining the existing resource construction and lifecycle behavior until separately validated.

## 9. Known rendering defects

1. Unified contours can place projected faces across the top surface, producing triangular patches and broad rock bands.
2. Unified top alpha and local face contours can disagree at inner corners, mixed heights and water contacts.
3. Directional projection reduces rear-edge clutter but leaves thin seam/sliver artifacts and weakens some north-facing depth cues.
4. Increasing cliff height magnifies the same defects rather than resolving them.
5. Connected contours remain visibly stair-stepped and less organic around non-southern turns.
6. Overlay/shadow controls had no visible effect in the controlled steady-state fixture; their behavior during live chunk replacement was not visually captured here.
7. A full editor import finds a stale parse error in `tests/phase7c4_validation.gd`, which still calls removed `TerrainRenderer._cliff_boundary_offset()` methods. This is outside C4C and was documented rather than fixed.

## 10. Technical validation

Every validation process had an explicit 120-second timeout; the graphical benchmark had a 240-second timeout.

| Check | Result |
| --- | --- |
| C4B renderer factory validation | PASS |
| Phase 3E corner, mixed-height and chunk-seam validation | PASS |
| Phase 3F height, signed seam, runtime projection/picking and rollback validation | PASS |
| Phase 3G directional structural validation | PASS |
| Phase A deterministic water/contact and streaming validation | PASS |
| Phase 5D terrain/chunk validation | PASS; benchmark: 25 chunks, 6.936 ms mean, 8.577 ms P95, 10.712 ms worst |
| Phase 7B1 save/load validation | PASS |
| Graphical editor startup/import | Process exited 0, but not clean: pre-existing `phase7c4_validation.gd` parse errors plus isolated safe-save/dialog warnings |
| `git diff --check` | See final hand-off result; protected pre-existing scene/reference changes were not edited |

The benchmark initially crashed twice inside Godot before script startup when it used the normal roaming application-data location. Re-running with the same isolated application-data location used for capture completed successfully. No benchmark result was taken from a crashed run.

## 11. Performance findings

Matched benchmark: seed `84521`, fixture `phase1g_dense_exact`, 1280×720, Compatibility renderer, NVIDIA GeForce RTX 3080, 3 runs, 240 steady frames per run, 17 shared materials. Values are comparative samples, not platform budgets.

| Mode | Steady mean / P95 | Streaming mean / P95 / worst | Mean draw calls | Geometry: nodes / faces / triangles / vertices | Static memory |
| --- | --- | --- | ---: | --- | ---: |
| Connected + baseline | 3.036 / 4.322 ms | 5.621 / 7.220 / 20.049 ms | 537.9 | 108 / 734 / 18,276 / 33,116 | 81.21 MiB |
| Unified + baseline | 3.113 / 4.653 ms | 5.897 / 7.777 / 19.228 ms | 536.7 | 40 / 3,453 / 17,384 / 34,760 | 80.95 MiB |
| Unified + moderate | 2.999 / 4.534 ms | 5.800 / 7.235 / 18.960 ms | 542.3 | 40 / 3,453 / 17,384 / 34,760 | 80.96 MiB |
| Unified + prominent | 2.971 / 4.007 ms | 5.724 / 7.474 / 19.442 ms | 543.4 | 40 / 3,453 / 17,384 / 34,760 | 80.97 MiB |
| Unified + directional + prominent | 3.563 / 5.550 ms | 5.699 / 7.604 / 25.926 ms | 544.4 | 40 / 3,453 / 17,384 / 34,760 | 80.98 MiB |

The differences are small enough that visual correctness should decide the baseline. Connected/baseline has the best streaming mean and a strong steady result, but uses more mesh nodes. Unified modes reduce node count while increasing face/vertex counts. Directional/prominent had the weakest steady P95 and highest observed streaming worst frame in this sample. Height alone did not change geometry counts in the unified modes; it changes projection positions, not topology.

## 12. Recommended permanent baseline

**Provisional recommendation—approval required:**

- Procedural cliff materials: enabled.
- Organic cliff geometry: enabled.
- Unified cliff components: enabled.
- Refined silhouettes: enabled.
- Connected cliff contours: enabled.
- Unified cliff contours: disabled.
- Directional cliff projection: disabled.
- Cliff height profile: baseline (16 px).
- Edge overlays: disabled.
- Shadows: disabled.

This selects the cleanest current coverage, predictable water contact, smallest camera footprint and a competitive measured cost. It gives up the smoother all-direction silhouette of unified contours. Unified components remain enabled to preserve the established atomic component/fallback ownership even though optional overlay/shadow visibility is disabled.

This is not an approved production decision. No scene override or script default was changed.

## 13. Decisions requiring user approval

1. Approve connected contours as the permanent near-term baseline, accepting its more stepped silhouette.
2. Approve returning the scene from prominent to baseline height.
3. Approve keeping directional projection disabled with the connected baseline.
4. Approve edge overlays and shadows disabled for steady-state presentation while retaining their resources and fallback paths.
5. Decide whether unified contours should remain available as an experimental mode or be targeted for later retirement after the shared-boundary work is reconsidered.

## 14. Proposed follow-up cleanup scope

Only after visual approval:

1. Align scene overrides and script defaults to the approved baseline in a separate phase.
2. Keep simulation, picking and persistence ownership unchanged; update projection-aware picking only if the approved height requires it.
3. Consolidate or retire only flags explicitly covered by the approval; do not remove fallback lifecycle behavior without a dedicated rebuild test.
4. Address the stale Phase 7C4 validation reference separately.
5. If unified contours are retained, treat the shared top/face boundary mismatch as its own architecture task rather than patching individual slivers.

Phase C4C stops here for visual review. No production rendering behavior, runtime art, water behavior, save format, Git history, commit or remote state was changed.
