# Phase 1G — Terrain Streaming Stability and Resource Cleanup

## Task Classification

Existing System Extension — targeted performance investigation and optimisation.

## Files Changed

- `scripts/terrain_renderer.gd`
- `scripts/terrain_chunk_build_job.gd`
- `tests/phase1g_validation.gd`
- `tests/phase1g_benchmark.gd`
- `tests/phase1g_lifecycle_probe.gd`
- `tests/phase1g_capture.gd`
- `tests/phase1g_visual_compare.gd`
- `screenshots/phase1g_lifecycle_probe_before.json`
- `screenshots/phase1g_lifecycle_probe_after.json`
- `screenshots/phase1g_benchmark_headless.json`
- `screenshots/phase1g_benchmark_graphical.json`
- `screenshots/phase1g_visual_comparison.json`
- 32 `screenshots/phase1g_*.png` comparison captures.

## Confirmed Root Cause

The outlier was the deferred recursive release of complete retired chunk subtrees,
not Phase 1F geometry preparation, chunk finalisation, environment batching, or the
act of calling `queue_free` itself.

The isolated probe removed twelve fully populated chunks without constructing
replacements. Submitting visibility changes and `queue_free` calls took 2.889 ms,
but the next frame took 25.331 ms while Godot released 456 chunk-owned nodes (607
nodes before, 151 after). These nodes include populated `TileMapLayer` children,
`MeshInstance2D` children and their `ArrayMesh` references. Static memory fell from
81.439 MiB to 53.969 MiB, confirming that the stall coincided with resource release.

The probe disables decoration and environmental generation and does not enable the
optional oblique renderer. It therefore also excludes environmental batch rebuilds
and oblique cleanup as necessary causes of this outlier. Phase 1F measurements had
already bounded geometry work below roughly 3 ms and chunk finalisation below 1 ms.

## Optimisations Implemented

### Bounded retirement

- Unloaded and invalidated chunks are removed from live ownership immediately and
  hidden immediately, so stale presentation cannot remain visible.
- Retired nodes enter a presentation-owned cleanup queue instead of recursively
  releasing every child in one frame.
- Cleanup processes one chunk and at most eight direct child nodes per frame. The
  empty parent is released only after its children have drained.
- Cancelled partial-build renderers use the same cleanup path.
- Terrain revisions, geometry revisions and halo snapshots are erased when a chunk
  leaves live ownership.
- Queue depth, retired count, submission CPU and worst submission quantum are exposed
  in the existing scheduler metrics. The queue is not a cache; every entry is hidden
  and progresses toward destruction.

### Safe mode-switch snapshot reuse

- The scheduler retains the already sampled 34x34 material/elevation halo for each
  loaded chunk. This is bounded to loaded presentation chunks and erased on unload or
  full terrain invalidation.
- Presentation-only cliff mode changes seed organic rebuild jobs from that immutable
  snapshot, eliminating 13,872 repeated material queries and 13,872 repeated height
  queries for the twelve-chunk benchmark.
- Terrain edits advance a separate terrain revision. A snapshot with an older terrain
  revision is rejected and the replacement job samples authority again.
- Existing geometry revisions still reject stale completion, and the previous valid
  mesh remains visible until atomic replacement.

No terrain generation, geometry profile, mesh algorithm, material calculation,
projection, persistence format, gameplay system, or Phase 2 renderer changed.

## Paired Performance Results

All paired results use the same process, engine, terrain fixture, camera state and
three-run sequence. The baseline switches the renderer to Phase 1F recursive chunk
release; the Phase 1G run restores bounded child cleanup.

### Streaming

| Metric | Headless baseline | Headless Phase 1G | Graphical baseline | Graphical Phase 1G |
|---|---:|---:|---:|---:|
| Mean average frame | 6.980 ms | 6.902 ms | 5.900 ms | 6.121 ms |
| Mean p95 | 6.927 ms | 6.956 ms | 7.414 ms | 7.966 ms |
| Mean p99 | 7.231 ms | 7.135 ms | 8.711 ms | 9.050 ms |
| Worst frame | 29.062 ms | 15.839 ms | 35.126 ms | 21.312 ms |
| Mean scheduler CPU | 347.047 ms | 340.637 ms | 327.747 ms | 329.331 ms |
| Replacement-ready range | 151–157 frames | 150–154 frames | 143–149 frames | 145–148 frames |

The primary worst-frame outlier fell 45.5% headless and 39.3% graphically. The work
is deliberately spread over more frames, so the graphical p95/p99 rose by about
0.55/0.34 ms. Total scheduler CPU was 1.8% lower headless and 0.5% higher graphically,
which is effectively unchanged relative to run-to-run variation. This is not a claim
that resource destruction disappeared; its frame-time distribution improved.

Average graphical draw calls during streaming were unchanged (about 548 in both
paired cases). Visible readiness remained 25–27 frames. The three baseline streams
ended at 80.762–80.769 MiB and the three Phase 1G streams at 80.769–80.775 MiB. Final
node/resource counts returned to 607/38, with no monotonic memory or object growth.

### Isolated retirement

The original twelve-chunk release produced a 25.331 ms first frame. Bounded child
release reduced the isolated worst frame to 11.738 ms and returned to the same final
151 nodes and 38 resources after 72 cleanup frames.

### Mode replacement

| Metric | Fresh-snapshot baseline | Cached-halo Phase 1G |
|---|---:|---:|
| Headless mean CPU | 168.920 ms | 104.343 ms |
| Graphical mean CPU | 167.061 ms | 105.791 ms |
| Headless wall time | 434–449 ms | 269–276 ms |
| Graphical wall time | 441–454 ms | 267–293 ms |
| Additional halo queries | 13,872 + 13,872 | 0 + 0 |

Mode-switch CPU fell about 37%. This removes the Phase 1F total-CPU regression while
preserving incremental per-frame work, cancellation and deterministic output.

### Stress cases

- Rapid camera movement: 16.939 ms worst headless and 20.374 ms graphical; all
  cancelled jobs and twelve queued retirements drained.
- Eight repeated edits: 6.917 ms worst headless and 8.329 ms graphical; the final
  replacement tail completed in four frames or fewer.
- Chunk finalisation remained below 0.7 ms in the recorded paired runs.

## Visual Comparison

The Phase 1G capture reused all 32 Phase 1E/1F fixtures and camera frames.

- 24 of 32 Phase 1G/Phase 1F screenshots are byte-identical, including all focused
  cliff geometry, multi-elevation, return, and positive/negative boundary fixtures.
- The same eight natural-water and shoreline captures that varied in Phase 1F vary
  again because of renderer/time-sensitive water pixels. Natural captures differ by
  at most one channel value; shoreline captures by at most nine.
- No cliff silhouette, contour endpoint, material band, faceting, contact shadow or
  seam changed. Geometry algorithms and shader calculations were not modified.

See `screenshots/phase1g_visual_comparison.json` for every paired result.

## Validation

Passed:

- Normal `main.tscn` startup for 120 frames.
- Phase 1A validation.
- Phase 1B validation, including positive/negative seams and editing.
- Phase 1D validation, including unified lips, returns and contact-shadow seams.
- Phase 1E validation, including refined signed seams and editing.
- Phase 1F validation, including deterministic incremental equivalence, cancellation,
  repeated edits, atomic replacement and pending mode changes.
- Phase 1G validation, including bounded retirement, hidden retiring chunks, bounded
  halo storage, revision-gated reuse and stale-job cancellation.
- Phase 7C.4 validation.
- Phase 7C.5 validation.
- Three repeated paired streams, three paired mode replacements, rapid camera
  movement, repeated edits and cleanup-to-steady-state checks.
- 32 graphical screenshot captures and visual comparison.
- Custom trailing-whitespace check across all changed text files.

`git diff --check` was attempted but is unavailable because the supplied project
directory is not a Git working tree.

## Ownership

- `TerrainWorld` remains authoritative for terrain and elevation.
- `TerrainChunkBuildJob` owns discardable preparation state and can consume a valid
  presentation snapshot without becoming terrain authority.
- `TerrainRenderer` owns visibility, scheduling, revisions, bounded loaded-chunk halo
  snapshots and retirement of presentation nodes.
- `TerrainChunkRenderer` continues to render and atomically replace complete meshes.
- UI, persistence, terrain generation and gameplay ownership are unchanged.

## Remaining Risks and Phase 3A Recommendation

- The largest graphical rapid-movement frame is still about 20–21 ms. Removing that
  residual would require incrementally clearing cells inside individual populated
  `TileMapLayer` resources or pooling chunk layers. That is a larger lifecycle design
  with memory and correctness risks, so it was not introduced speculatively.
- Bounded retirement temporarily retains hidden nodes. The tested twelve-chunk queue
  drains in 72 frames and showed no steady growth, but substantially larger view
  distances should be reprofiled before raising streaming radii.
- Spreading release raises graphical p95/p99 slightly even though it substantially
  lowers the worst frame. The current eight-node quantum is a measured compromise.
- Halo reuse is intentionally limited to unchanged presentation rebuilds. Edit-heavy
  workloads still pay fresh sampling, as required for correctness.

Recommendation: ready for a small Phase 3A procedural-vegetation vertical slice,
provided it follows the existing bounded, cancellable scheduler and uses batched
presentation nodes. Do not attach vegetation lifetime to individual cells, and include
its resource release in the retirement benchmark before broad content expansion.
