# Pastel reference sketch

`sketches/pastel_flow` is an isolated native creative-coding experiment. It
reconstructs pastel interference ribbons and iridescent folded sheets using
colored indexed meshes, a fixed orthographic camera, and `Scene.view3d`.
`Sketch.run_state` owns immutable controls, time, and the current scene;
PXUI supplies the scrollable parameter panel and settings serialization.

The two reference compositions are presets in one 56-parameter space. Sampling
computes surface geometry and vertex colors; Metal performs rasterization and
alpha blending. Transparent fringe geometry softens thin ribbon edges. Fold
boundaries are sampled separately so interpolated gradients do not blur across
creases. Small seeded triangles provide a subtle texture approximation.
A randomness amount scales seed-driven jitter across the pastel field, ribbon
lines, and fold silhouette while leaving chaos-0 presets bit-identical aside
from grain. Animation uses a global speed plus independent wave, fold, and
color rates, with optional motion chaos for evolving per-line phase offsets.
The background pastel can blend classic gaussian color blobs with a seeded
Perlin/fBm field (mix/scale/detail); mix 0 preserves the blob look.

No framework API or library boundary changes are required. The art generator is
private to the sketch. It neither loads the supplied reference images nor
introduces an alternative rendering backend. No geometry is rebuilt for an
unchanged static frame. The active scene replaces its predecessor on parameter
or time changes; renderer upload retention uses the existing bounded caches.

The native smoke path always terminates after eight frames and exercises changing
meshes. PNG export uses the full native framebuffer and fixed simulation time.
Pure tests cover control extremes, safe mesh data, repeatability and persistence;
one-/four-domain animated exports are compared exactly. See the sketch README
for commands, measured preparation costs, and fidelity/performance limitations.

Export validation exposed an existing native PNG encoder defect: the first byte
of each scanline was uninitialized. The writer now explicitly selects PNG filter
None for every row before copying RGBA. `test_png_rows` reproduces the old failure
under heap reuse and checks every filter byte, every RGBA byte, stored-DEFLATE
block boundaries, and sixteen identical exports. This fixes malformed and
nondeterministic captures without changing pixel data or the Canvas API.
