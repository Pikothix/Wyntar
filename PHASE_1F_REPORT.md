# Phase 1F — Incremental Procedural Cliff Mesh Construction

## Task Classification

Existing System Extension — chunk-streaming performance optimisation.

## Recovery Summary

The interrupted work contained a partial refactor of `organic_cliff_mesh_builder.gd`
and `terrain_chunk_build_job.gd`: resumable buffer state and bounded cell processing
had been started, but it was not yet connected to streaming, editing, mode changes,
atomic scene commits, validation or benchmarks. The partial work also needed a
dependency-cycle cleanup and compilation checks.

The valid resumable builder work was preserved. The remaining scheduler, lifecycle,
presentation, profiling and validation work was completed in place.

## Files Changed

- `scripts/organic_cliff_mesh_builder.gd`
- `scripts/terrain_chunk_build_job.gd`
- `scripts/terrain_chunk_renderer.gd`
- `scripts/terrain_renderer.gd`
- `tests/phase1e_validation.gd`
- `tests/phase1f_validation.gd`
- `tests/phase1f_benchmark.gd`
- `tests/phase1f_capture.gd`
- `tests/phase1f_visual_compare.gd`
- `screenshots/phase1f_benchmark.json`
- `screenshots/phase1f_benchmark_headless.json`
- `screenshots/phase1f_benchmark_graphical.json`
- `screenshots/phase1f_visual_comparison.json`
- `screenshots/phase1f_*.png` (32 comparison captures)
- `PHASE_1F_REPORT.md`

## Original Bottleneck

Phase 1E prepared ordinary terrain data incrementally, then synchronously called
`OrganicCliffMeshBuilder.build()` during chunk finalisation. For every chunk that call:

1. Re-read the complete 34×34 material and surface-height halo.
2. Classified all 1,024 cells.
3. Generated all southern walls, lips, returns and contact-shadow contours.
4. Appended every vertex, color and index.
5. Created all `ArrayMesh` resources.
6. Cleared and attached the replacement mesh layers.

The same whole-chunk path ran synchronously for edits and mode switches. The 12-chunk
Phase 1E fixture spent 115.774 ms in organic geometry and a refined-mode switch blocked
the caller for 116.857 ms.

## Incremental Scheduling Architecture

- `TerrainChunkBuildJob` remains the owner of plain-data chunk preparation.
- Initial streaming geometry reuses that job's existing immutable 34×34 halo; it no
  longer performs a second set of 1,156 height and 1,156 material callbacks.
- `OrganicCliffMeshBuilder` exposes create/process/finalise operations. Each process
  call advances a stable row-major cell index by at most the scheduler quantum and
  appends only new work to retained per-elevation buffers.
- The existing visible-first chunk queue and frame deadline process the new stage.
- Loaded-chunk edits use organic-only `TerrainChunkBuildJob` replacements in the same
  scheduler. They sample one bounded halo, leave the previous valid mesh visible, and
  atomically commit only after all buffers and mesh resources are complete.
- Per-chunk revisions invalidate repeated edits and mode changes. A result can commit
  only when its captured revision is still current.
- Unloading cancels both stream and replacement jobs. Mode changes restart pending
  stream jobs so their captured configuration cannot be applied under a newer mode.
- `ArrayMesh` creation and `MeshInstance2D` attachment remain on the main thread. No
  cell-level rendering nodes were introduced; the maximum remains three component
  batches for each of three elevation levels.

The simulation, editing, terrain generation and persistence boundaries are unchanged.
All added state is discardable presentation preparation.

## Performance Results

Tests used Godot 4.7.2 Compatibility, the same 12-chunk dense Phase 1E fixture, a
24-cell work quantum and a 2.5 ms scheduler budget. Headless results provide the
closest comparison with the saved Phase 1E baseline; a Windows/OpenGL pass records
real draw calls.

| Metric | Phase 1E | Phase 1F |
|---|---:|---:|
| Organic build CPU, 12 chunks | 115.774 ms | 91.847 ms incremental preparation/resource work |
| Duplicate organic halo queries | 13,872 height + 13,872 material | 0 during initial streaming; existing samples reused |
| Mode-switch caller stall | 116.857 ms | 1.290 ms enqueue |
| Worst organic work in one frame | synchronous whole switch | 2.802 ms headless / 2.985 ms graphical |
| Worst chunk finalisation | organic build included in finalisation | 0.439 ms headless / 0.414 ms graphical |
| Headless streaming p95 / p99 | not captured by Phase 1E harness | 6.921 / 7.245 ms |
| Headless mode-switch p95 / p99 / worst | synchronous 116.857 ms call | 6.920 / 8.355 / 8.355 ms |
| Visible chunks ready | not captured | 24 streaming frames; 10 mode-switch frames |
| All streamed chunks ready | not captured | 946.741 ms headless / 663.960 ms graphical |
| Edit refresh | 11.386 ms synchronous | 41.403 ms headless over 6 frames; old mesh retained |
| Steady memory | 75.289 MiB | 75.749 MiB headless (+0.460 MiB) |
| Steady draw calls | baseline harness was headless | 514 graphical |

The detailed profiled headless build split was 64.954 ms for the shared terrain halo,
17.068 ms classification/face decisions, 45.946 ms contour generation, 15.627 ms
packed vertex assembly, 1.205 ms mesh-resource creation and 1.658 ms scene attachment.
The shared halo time is existing terrain preparation, not additional Phase 1F work.

Total CPU and frame impact differ by lifecycle:

- Initial streaming organic work fell from 115.774 ms to about 85–92 ms because the
  duplicate halo read was removed.
- A full organic-only mode replacement used 144.768 ms total CPU across 57 headless
  frames. This is higher than Phase 1E's 115.774 ms synchronous build because it must
  take a fresh edit-safe snapshot and pays resumable-job bookkeeping. The caller stall
  and per-frame geometry spike were nevertheless reduced to 1.290 ms and 2.802 ms.
- The headless stream had a 22.194 ms worst overall frame while organic work in that
  frame remained below 2.811 ms. Repeated runs showed the outlier during mass chunk
  replacement/cleanup rather than cliff geometry; p99 remained 7.245 ms.

This is therefore a frame-spike improvement, not a claim that every lifecycle now uses
less total CPU or reaches readiness sooner.

## Visual Comparison

- Incremental builds made with seven-cell quanta produced byte-identical vertex,
  color and index buffers to the synchronous Phase 1E builder.
- Face/component/vertex/triangle totals are identical on the unedited fixture:
  727 faces, 2,442 edge components, 723 shadows, 28,680 vertices and 16,000 triangles.
- 24 of 32 paired screenshots are byte-identical, including dirt, returns, corners,
  multiple elevations, and positive and negative chunk boundaries at both zooms.
- The eight non-exact images are the natural-water and shoreline pairs in both modes.
  Natural captures differ by at most two channel values; shoreline captures differ by
  at most 12. Both Phase 1D and refined captures change in the same water regions,
  while deterministic cliff buffers remain identical. Visual inspection found no
  changed cliff silhouette, seam, material band or contact point.

## Validation

Passed:

- Normal `main.tscn` startup for 120 frames.
- Phase 1A validation.
- Phase 1B validation.
- Phase 1D validation.
- Phase 1E validation.
- Phase 1F validation.
- Phase 7C.4 validation.
- Phase 7C.5 validation.
- Positive and negative cliff seams.
- Deterministic repeated geometry and byte-identical synchronous/incremental buffers.
- Rapid camera movement and cancellation.
- Edits while preparation is incomplete.
- Repeated edits with stale-result rejection.
- Rendering-mode changes while jobs are pending.
- Rollback to legacy and Phase 1D presentation modes.
- Authoritative terrain isolation.
- No trailing whitespace in changed text files.

`git diff --check` could not run because the supplied project directory is not a Git
working tree. Godot parsing, startup and targeted regressions completed successfully.

## Ownership

- `TerrainWorld` remains authoritative for terrain and elevation.
- `TerrainChunkBuildJob` owns mutable, discardable preparation state.
- `OrganicCliffMeshBuilder` remains a deterministic presentation geometry algorithm.
- `TerrainChunkRenderer` only commits and renders complete presentation batches.
- `TerrainRenderer` owns scheduling, visibility priority, invalidation and revisions.
- UI, persistence and the optional Phase 2A/2B renderers are unchanged.

## Remaining Risks and Recommendation

- Full mode switches and edit-only replacements trade latency for bounded frames. The
  previous valid presentation prevents gaps, but all margin chunks can take roughly
  0.3–0.4 seconds to replace on the benchmark machine.
- Organic-only rebuild total CPU is about 25% above the old synchronous builder. If
  mode switches become frequent gameplay actions, the state representation should be
  profiled for dictionary/bookkeeping overhead before increasing asset workload.
- The repeated 22–25 ms full-stream outlier is not attributed to cliff geometry, but
  chunk teardown/resource cleanup should be profiled separately before calling all
  streaming stalls solved.
- Screenshot deltas over water are raster-level and not geometry-level; deterministic
  mesh equality is the stronger Phase 1F acceptance signal.

Recommendation: ready to begin a small, scheduler-aware procedural environmental-asset
prototype, but not broad asset rollout. Environmental preparation should use the same
bounded, cancellable, revision-checked pattern, and it should not share the cliff work
budget until the chunk teardown outlier and mode-switch CPU overhead are understood.
