# Wyntar — L2 Visual Verification and Diagnostic

Date: 2026-10-24  
Engine: Godot 4.7.2 stable Mono, OpenGL Compatibility  
GPU: NVIDIA GeForce RTX 3080  
Viewport: 1280 × 720

## Scope and ownership

This task verifies the existing L2 camera-to-shader path and its practical visual effect. It adds a read-only, reversible gameplay diagnostic and a matched capture/measurement harness. It does not alter `cliff_procedural.gdshader`, terrain or cliff geometry, material/elevation authority, streaming, collision, gameplay, or persistence.

C4J coverage, C4K sidewall occlusion, the accepted organic LEGACY silhouette, and all four cliff rendering modes remain unchanged. The pre-existing dirty working tree was preserved; no reset, discard, commit, or push was performed.

## 1. Live zoom-to-shader pipeline

The live pipeline is functioning as designed:

1. `CameraController` emits its scalar zoom after wheel changes, reset, and restored state.
2. `Main._on_camera_zoom_changed()` forwards that value to `TerrainRenderer.set_cliff_shader_lod_zoom()`.
3. `TerrainRenderer` evaluates the smooth L2 mapping once per zoom event.
4. The resulting `detail_level` is written to four source materials, four contact-shadow materials, and the organic combined-geometry material.
5. Existing and newly streamed chunks reference those same nine shared resources.

The new `TerrainRenderer.get_cliff_shader_lod_diagnostics()` reads the uniform back from the actual shader materials rather than reporting only the intended renderer state. All nine resources matched at every tested zoom.

| Camera zoom | Calculated LOD | Applied renderer value | Actual shader value | LOD-disabled actual |
|---:|---:|---:|---:|---:|
| 100% | 1.000 | 1.000 | 1.000 | 1.000 |
| 50% | 0.515 | 0.515 | 0.515 | 1.000 |
| 25% | 0.244 | 0.244 | 0.244 | 1.000 |
| 12.5% | 0.200 | 0.200 | 0.200 | 1.000 |

This rules out a missing zoom signal, stale renderer value, resource replacement, or uniform propagation failure.

## 2. Reversible gameplay diagnostic

Pressing **F5** toggles a small display showing:

- current camera zoom and percentage;
- calculated LOD for that zoom;
- renderer-applied value;
- value read back from the shader material;
- shared-material count and whether all values match.

The display is off by default and remains visible in both compact and expanded HUD modes. It is read-only and does not rebuild chunks, duplicate resources, or change LOD state.

![L2 live F5 diagnostic](.artifacts/l2_visual_verification/l2v_gameplay_diagnostic_zoom_025.png)

## 3. Matched visual captures

The verification fixture is the same deterministic mixed-material, three-elevation, water-contact region used by L2. C4J and C4K were enabled. Camera position, zoom, water time, viewport, geometry, and streaming state were held constant within each pair.

### 100%

| LOD disabled | LOD enabled |
|---|---|
| ![100 percent disabled](.artifacts/l2_visual_verification/l2v_disabled_zoom_100.png) | ![100 percent enabled](.artifacts/l2_visual_verification/l2v_enabled_zoom_100.png) |

The images are pixel-identical because 100% maps to full detail.

### 50%

| LOD disabled | LOD enabled |
|---|---|
| ![50 percent disabled](.artifacts/l2_visual_verification/l2v_disabled_zoom_050.png) | ![50 percent enabled](.artifacts/l2_visual_verification/l2v_enabled_zoom_050.png) |

### 25%

| LOD disabled | LOD enabled |
|---|---|
| ![25 percent disabled](.artifacts/l2_visual_verification/l2v_disabled_zoom_025.png) | ![25 percent enabled](.artifacts/l2_visual_verification/l2v_enabled_zoom_025.png) |

### 12.5%

| LOD disabled | LOD enabled |
|---|---|
| ![12.5 percent disabled](.artifacts/l2_visual_verification/l2v_disabled_zoom_013.png) | ![12.5 percent enabled](.artifacts/l2_visual_verification/l2v_enabled_zoom_013.png) |

The artifact folder also contains matched cliff-only images, ground-only images, and exact cliff masks at every zoom. The complete measurements are in `.artifacts/l2_visual_verification/l2_visual_verification_manifest.json`.

## 4. Cliff-confined pixel differences

For each zoom, a solid diagnostic render of the main faces, C4J coverage, and C4K sidewalls produced a conservative cliff footprint. Normal enabled/disabled images were then compared only inside that footprint. Because hidden underlays are included, the reported cliff screen fraction is an upper bound on visible cliff-face coverage.

| Zoom | Cliff footprint | Changed cliff pixels | Change >4/255 | Change >8/255 | Mean RGB difference | RMS difference | Outside mask |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100% | 13.07% | 0.00% | 0.00% | 0.00% | 0.000/255 | 0.000/255 | 0 |
| 50% | 23.93% | 13.12% | 2.03% | 1.79% | 0.401/255 | 1.947/255 | 0 |
| 25% | 16.05% | 15.33% | 2.98% | 2.40% | 0.518/255 | 2.177/255 | 0 |
| 12.5% | 13.97% | 15.00% | 3.13% | 2.46% | 0.498/255 | 2.050/255 | 0 |

The maximum local differences reach 28–46 RGB levels, but they occur in sparse cracks, grain, and erosion features. Across the complete cliff footprint, the average change remains below 0.52 of one 8-bit colour level. No pixels outside the cliff footprint changed.

## 5. Is the effect perceptible?

L2 is technically active but is not meaningfully perceptible during normal gameplay.

- Side-by-side full-scene pairs at 50%, 25%, and 12.5% appear effectively identical at their normal display size.
- Even the cliff-only 25% pair requires close alternation or magnification to identify changed fracture and grain pixels.
- Only 2–3% of cliff-footprint pixels change by more than 4/255.
- The 25% and 12.5% results are nearly the same despite their different LOD values, showing that the current effect has already reached a visual plateau.

The previous automated result—different image hashes below 100%—was correct but insufficient evidence of a visually useful change.

## 6. What dominates the distant appearance?

Both ground presentation and geometry dominate over the current shader reduction.

### Ground and elevated surfaces

The cliff shader affects the narrow vertical faces, C4J underlay, and C4K sidewalls. It does not simplify the broad elevated top surfaces or surrounding ground rendered by the terrain surface shader. Those surfaces occupy most of the image and retain their speckle, stripes, material boundaries, and colour variation.

Measured mean horizontal neighbour variation was higher on ground-only captures than cliff-only captures at every zoom:

| Zoom | Cliff-only variation | Ground-only variation |
|---:|---:|---:|
| 100% | 2.910/255 | 3.104/255 |
| 50% | 3.114/255 | 4.176/255 |
| 25% | 3.325/255 | 4.186/255 |
| 12.5% | 4.239/255 | 4.671/255 |

This is not a quality judgment about the ground shader; it demonstrates why a sub-one-level change on only the cliff faces is visually masked in the complete scene.

### Geometric silhouette

The organic contour, height steps, material changes, facet boundaries, and projection remain fixed. Approximate mask-boundary pixels rise from 3.81% of the cliff footprint at 100% to 21.37% at 12.5%. At the farthest view, the stable silhouette and height topology therefore contribute much more to the cliff read than sparse internal shader detail.

Within `cliff_procedural.gdshader`, the strongest broad cues are intentionally unaffected or only weakly affected by `detail_level`: broad facets remain at full strength, bed identity remains fixed, and strata joints retain 55% strength at minimum detail. L2 strongly reduces source micrograin, fine noise, cracks, erosion streaks, and weather variation, but those are precisely the features that become sub-pixel or sparse at distance.

## 7. Evidence-based shader recommendations

No shader changes were made in this task. If a more noticeable presentation LOD is desired, the evidence supports a controlled follow-up experiment rather than a geometry change disguised as L2:

1. **Modulate pervasive contrast, not only sparse features.** Add a far-view blend from the final cliff pigment toward its low-frequency material result. A modest target would be 20–35% micro/mid-frequency contrast compression at minimum detail while retaining source colour, geometry shade, shoreline wetness, and material identity.
2. **Reduce the fixed broad terms moderately.** Trial broad-facet strength at 65–75% and bed-identity strength at 70–80% when `detail_level = 0.0`, returning continuously to 100% at normal zoom. Do not remove these cues completely.
3. **Lower the retained strata-joint floor.** The current `mix(0.55, 1.0, detail_level)` leaves a strong high-contrast joint. Test a 0.25–0.35 minimum while preserving broad bed placement.
4. **Use a far-view ramp rather than only amplitude scaling.** The fixed five-step tone ramp can preserve contrast after small input reductions. Blending toward a coarser or lower-contrast ramp at distance should affect more face pixels coherently.
5. **Cross-fade high-frequency samples instead of merely multiplying their output.** A screen-aware/coarser sample path would address shimmer and aliasing more directly. The current shader still evaluates the same fields, so L2 should not be treated as a demonstrated GPU optimisation.
6. **Do not rely on a lower minimum alone.** The far view is already at 0.20 and 25% is at 0.244, yet their measured effect is almost identical. Setting the minimum to zero without changing which terms it controls is unlikely to produce a sufficiently meaningful result.

A follow-up should use the same matched mask metric and target a clearly visible but restrained result—for example, mean cliff difference around 2–4/255 with at least 10% of visible face pixels exceeding 4/255—while retaining material identity and avoiding popping.

## 8. Is geometry LOD the appropriate next step?

For correcting L2 perceptibility, **no**: a small evidence-driven shader contrast pass is the narrower next step. The current result does not show that the organic geometry itself is visually wrong.

For meaningful far-view performance reduction, **geometry or broader presentation LOD now has more potential leverage than the current L2 amplitude controls**, because L2 changes neither triangle counts, draw calls, shader field evaluation, visible chunk breadth, nor top-surface detail. However, a cliff-only geometry LOD may still have limited total-scene benefit because the ground surface and streamed world breadth dominate the distant image. Any future geometry phase should remain a separately authorised prototype with matched silhouette, C4J, C4K, and streaming validation.

## 9. Validation and conclusion

| Check | Result |
|---|---|
| Camera signal reaches renderer | Pass |
| Calculated/applied/actual values agree | Pass at all four zooms |
| All nine shared materials agree | Pass |
| LOD-disabled rollback value | 1.000 at all zooms |
| 25 matched visual/isolation/diagnostic captures | Pass |
| Difference confined to cliff footprint | Pass, zero outside pixels |
| C4G LEGACY/GRID/UNIFIED/STYLISED validation | Pass |
| C4I/C4J coverage ownership validation | Pass |
| C4K sidewall validation | Pass |
| L2 focused validation | Pass |
| Main face/coverage/sidewall geometry changes | None |

**Conclusion:** L2 is correctly wired and deterministic, but its current visual effect is too subtle to be useful at normal gameplay display sizes. The dominant distant read comes from unchanged ground/elevated surfaces and organic geometry, while L2 modifies sparse or already sub-pixel face details. Retain the current implementation as a technically correct rollback-safe baseline, then choose between a targeted shader contrast experiment for perceptual clarity and a separately scoped broader presentation/geometry LOD investigation for performance.
