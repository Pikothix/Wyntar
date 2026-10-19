# Phase 7C Report

## Root causes found before implementation

1. The height-zero universal-mask compositor sorted every corner material only
   by material priority. It did not exclude materials whose rendered surface
   belonged to a raised elevation band. A raised sand, grass, or stone corner
   could therefore enter the sea-level stack and bleed through a water/cliff
   transition.
2. Water used the ordinary terrain shader with the same tiled source sampling,
   variation ramp, and noise character as ground. Catalog metadata identified
   water as liquid for height/cliff logic, but did not describe a liquid visual
   profile.
3. North/east/west cliff cues used broad, low-alpha fades. Their softness read
   as a compositing seam instead of the upper lip of a drop.
4. All materials shared broadly similar variation strengths and frequencies.
   Tint variants changed tone, but calm materials still exposed the repeating
   32-pixel source pattern too strongly.

## Implementation

- Liquid presentation is catalog-driven. A liquid can define its surface and
  shoreline styles, calmness, pattern frequency, shimmer and optional motion,
  depth-effect strength, and optional emissive strength. These are visual-only
  properties and are ready for a future lava material without adding lava
  gameplay.
- The shared terrain shader now has an inert-for-land liquid branch. Water uses
  low-frequency world-space bands, subtle optional motion, restrained
  shoreline highlights, a calmer tint blend, and nearest-neighbour sampling.
- Ground composition now admits a corner material only when that corner's
  authoritative rendered surface height is zero. Raised materials remain in
  their matching elevation bands. Both streamed preparation and live edit
  refresh use the same rule.
- Southern cliff faces and their liquid contact bands are unchanged. The
  north/east/west overlay atlas now uses a short stepped shadow/highlight lip
  instead of a broad fade, with narrow side returns into southern walls.
- Material-specific variation was rebalanced: water, sand, and snow are calmer;
  grass uses broader tonal clumps; dirt and mud are quieter; stone and gravel
  retain stronger texture variation.
- Chunk preparation now records liquid-surface and cliff-lip preparation costs
  as subsets of the existing mask/cliff work.

## Visual captures

`screenshots/phase7c_before_*.png` and `screenshots/phase7c_after_*.png`
contain matched 1280x720 captures at 0.5x, 1x, and 3x for:

1. large water body and shoreline;
2. water against sand;
3. water against grass;
4. water beside cliff boundaries;
5. the height-overlap regression fixture;
6. north/east/west cliff lips plus a southern wall;
7. dense stone/gravel;
8. calm sand/snow.

The 24 baseline and 24 updated images use identical authoritative fixture data,
camera coordinates, viewport size, and zoom.

## Performance

Measured with Godot 4.7.2, compatibility renderer, 1280x720, vsync disabled,
60 samples per mode on the implementation machine:

| Mode | Average | P95 | P99 | Worst | Scheduler overruns |
| --- | ---: | ---: | ---: | ---: | ---: |
| Static view | 1.995 ms | 2.175 ms | 2.964 ms | 2.964 ms | 0 |
| Camera-only streaming | 3.253 ms | 5.987 ms | 7.861 ms | 7.861 ms | 30 |
| Shoreline-heavy | 1.999 ms | 2.349 ms | 2.396 ms | 2.396 ms | 0 |
| Dense cliffs | 0.718 ms | 0.851 ms | 0.907 ms | 0.907 ms | 0 |
| Editing near liquid | 0.730 ms | 0.867 ms | 1.003 ms | 1.003 ms | 0 |
| Save/load regeneration | 4.209 ms | 3.912 ms | 88.823 ms | 88.823 ms | 36 |

Across 56 prepared chunks, average measured preparation was 11.924 ms per
chunk and worst was 16.172 ms. The liquid-surface subset averaged 0.6153 ms,
all cliff preparation averaged 1.0231 ms, and the cliff-lip subset averaged
0.4838 ms. Static memory was 80,608,688 bytes. The cumulative scheduler-overrun
counter was 229 after all fixture construction, streaming, editing, and reload
work. Overruns remain bounded by the existing incremental scheduler; the
save/load spike is synchronous authoritative snapshot parsing/import followed
by regeneration, not per-frame liquid shader work.

## Compatibility and regression results

- Phase 5D cliffs and shorelines: pass.
- Phase 6A decorations: pass.
- Phase 6B environmental objects: pass.
- Phase 7A editing and undo/redo: pass.
- Phase 7B.1 validation: pass.
- Phase 7B.1 fresh save and fresh load round trip: pass.
- Phase 8A procedural Isolony visuals: pass.
- Phase 8B resource state and regrowth: pass.
- Phase 7C focused validation: pass.

No serialized material IDs, elevation ownership, resource IDs, or save schema
were changed.

## Remaining limitations

- Liquid depth is presently a subtle visual modulation, not a simulated depth
  field. The catalog field is reserved for future depth-aware presentation.
- Optional liquid motion is time-based presentation and is intentionally not
  simulation-deterministic; the spatial pattern, terrain IDs, and chunk results
  remain deterministic.
- Save/load regeneration still has a one-frame synchronous spike in this
  benchmark. Moving save import to a staged workflow would be broader scheduler
  architecture work and is outside Phase 7C.
