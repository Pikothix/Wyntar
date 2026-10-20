# Phase 3E Unified Contour Approach

## Investigation result

The authoritative height grid is sampled into an immutable 34x34 halo for each
32x32 chunk. Phase 3D still visits each height sample independently: a sample
higher than its southern neighbour emits a full south wall, while lower east or
west neighbours emit separate narrow return ribbons. The shared Phase 3C level
function keeps those pieces watertight, but the ownership model necessarily
produces alternating 32-pixel horizontal walls and vertical returns on a
diagonal boundary.

The elevated top surface already uses the four height samples surrounding each
render tile to select a 16-case scalar-field mask. This means the renderer has a
safe bounded place to improve the contour: the same local four-sample square.
The top masks cross exposed square edges near their midpoints, rather than
following the old owner-cell south edge.

## Bounded prototype

Phase 3E will add a separate presentation-only toggle and preserve Phase 3D as
the disabled baseline. When enabled, the cliff builder will process each local
four-sample square at every elevation threshold:

1. Classify its four corners as at-or-above the threshold.
2. Use a deterministic 16-case marching-squares table to extract zero, one, or
   two contour segments. Ambiguous saddle cases use an absolute-coordinate hash
   to choose one of the two non-crossing pairings.
3. Give every grid-edge crossing a canonical absolute-world edge key. A bounded
   tangent displacement derived from that key changes the midpoint without
   moving it off the shared edge. Neighbouring squares and chunks therefore
   calculate byte-identical endpoints.
4. Insert one pixel-quantised midpoint per segment. Its bounded normal offset
   combines a broad absolute-world field with a smaller rock-edge field. Linear
   interpolation and explicit clamps prevent spline overshoot and
   self-intersection.
5. Extrude the resulting two-piece contour downward by one 16-pixel elevation
   band. Repeating this per threshold gives drops of one to three levels while
   retaining the existing top-down height projection.

The contour face and its restrained south-facing contact band are appended to
the existing per-elevation face batch. The accepted Phase 3B shader supplies
the crest treatment, avoiding a duplicate geometry strip. No contour node or
world-scale contour object is introduced. Incremental work remains one terrain
square at a time.

## Coverage and continuity constraints

- Crest geometry overlaps the upper surface by a small bounded amount and is
  hidden by the existing masked top surface where appropriate. The contour
  crossing stays inside the same four-sample square used by that mask.
- Every endpoint is a pure function of canonical world edge coordinates,
  threshold-independent contour channels, and the world seed. It does not
  depend on chunk origin, traversal order, or neighbouring build completion.
- Each face band and integrated contact band uses the identical extracted path.
  Shared endpoints cannot diverge between components.
- The fixed one-cell halo is sufficient because a square needs only its four
  corners. No smoothing decision reads beyond that square; broad variation is
  sampled analytically from absolute coordinates.
- Mixed-height squares are represented independently per elevation threshold.
  This preserves the authoritative terraces rather than averaging heights.
- Phase 3C and Phase 3D remain untouched behind the Phase 3E toggle. Disabling
  Phase 3E rebuilds the accepted geometry through the existing replacement
  scheduler.

## Deliberate limits

This prototype does not trace or store whole contours, change top-surface mask
generation, redesign materials, add geometry LOD, or change terrain authority.
The local marching representation can smooth repeated diagonal steps and turns,
but it cannot coordinate a curve beyond the analytic world-space field or solve
all saddle topology as a future full contour graph could.
