# Chromatic Drift

Run `opam exec -- dune exec sketches/chromatic_drift/main.exe`.
This standalone sketch interprets the reference's diagonal coral, purple,
cyan and midnight bands as five animated colored sheets. It does not depend
on Pastel Flow. Rasterization, lighting, texture sampling and blending use
native Metal. Animation starts immediately.

Scroll the panel for 31 controls: noise amplitude/scale, diagonal tilt, band
spacing, glow/diffusion, geometry detail, depth, optional curl/crease shading,
roughness, light direction, grain strength/size, speed, domain warp, secondary
noise, independent band motion, breathing, offset, hue, saturation, exposure,
palette blending, color turbulence/speed, sweeping curvature, broad light pools,
color depth, seed and palette. Four curated
palettes are Afterglow, Lagoon, Ember and Orchid.

“Surprise me” deterministically remixes shape, palette and motion from the next
seed. “New composition” changes only the seed. Reset restores launch defaults
and time. Tab hides controls/status; Escape quits. Save/load buttons use
`_out/chromatic-drift.json` (override with `--settings FILE`). Loading resets time;
saving stores controls, not phase. Bounded displacements keep bands ordered.

The default composition uses unequal sheet widths and a large sweeping curve,
with a warm upper sheet, saturated pink middle sheet and violet lower sheet.
Broad moving color pools and a one-sided luminous crest give the violet sheet
a pale-to-dark rolloff. These are art-directed vertex-color fields, not extra
physical lights or cast shadows. Sweep, radiance and color depth are independent
controls and participate in “Surprise me”.
The finish also uses subtle surface curvature, soft diffuse lighting,
and fine monochromatic grain. Edge curl and crease shading default to zero;
the rejected embossed bright-rim/dark-groove treatment is not the default.
Optional crease shading is an artistic color falloff, not ray-traced occlusion
or shadow mapping. Actual mesh heights and normalized height-gradient normals
supply native directional diffuse/specular lighting. Roughness controls the
fixed-pipeline specular response; it is not a physically based BRDF.

## Geometry and grain

| Detail | Vertices | Triangles | Purpose |
|---|---:|---:|---|
| 1 | 16,125 | 30,720 | Faster motion |
| 2 (default) | 62,965 | 122,880 | Smoother surfaces |
| 3 | 140,525 | 276,480 | Highest detail/export |

`--quality 1..3` sets launch detail. Each sheet is an indexed height field;
shape noise is sampled per column, colors/height are prepared per vertex,
and gradients use local neighbors. Work and auxiliary memory are
O(bands * columns * rows), using exact preallocation. Geometry preparation
is sequential regardless of configured domain count. Only the current scene
is retained by the sketch; renderer caches retain their existing bounded policy.

Grain is a fixed 256×256 seeded noise texture on a four-vertex overlay, replacing
24,000 sparse triangles. A sum of four uniform samples produces a distribution
with softer tails; positive/negative values blend white/black flecks.
The texture is generated only when seed, strength, size or backing height changes.
Metal repeats and bilinearly samples it. Size is measured in native pixels and
updates after resize/Retina density changes. It is static grain, not evolving
film noise; the finite tile can repeat visibly at extreme settings.
`--grain 0..0.8` sets launch strength. No CPU rasterizer is involved.

## Export and validation

```sh
opam exec -- dune exec sketches/chromatic_drift/main.exe -- \
  --export /tmp/drift --frames 120 --seed 42 --palette 0 --quality 2
opam exec -- dune runtest sketches/chromatic_drift
PRISMEL_MAX_FRAMES=12 opam exec -- dune exec sketches/chromatic_drift/main.exe
opam exec -- dune exec sketches/chromatic_drift/main.exe -- --bench --quality 2
```

Export uses a fixed 1/60 second clock and an artwork-only 1080×800 logical
viewport, preserving native backing resolution. It writes PNG sequences, not
video. Noise motion is not a seamless loop. Interactive windows start at
1398×800 including controls. Height-normalized artwork is cropped to the
viewport; extreme ratios beyond 4:1 may expose the clear background.

Pure tests cover deterministic seed/time behavior, parameter sensitivity,
finite geometry, normalized normals, valid indices, exact cardinality at all
three detail levels, bounded grain texture and ordered bands at extreme noise.
Native validation: twelve animated frames with four configured domains; two
PNG frames match byte-for-byte between one/four domains. Grain-on versus
grain-off exports differ, and grain/depth were inspected in native exports.
`dune build @all @doc` and focused tests pass. The previous broad suite run
reported unrelated stale API/SDL manifests, a Metal driver exception and a
macOS 26.4-only constant; that run was stopped after those failures. Existing
unbounded example programs were not launched.

## Performance evidence (2026-09-21)

Apple M1, Darwin arm64, OCaml 5.3.0, Dune development profile, one geometry
domain, five warmed samples per detail setting. Command: the `--bench` command
above with `--quality 1`, `2`, and `3`.

Before this change, 16,125 flat vertices: 5.061–5.357 ms, 245,382–256,077
major words, 55,001–65,696 promoted words, 325,450–356,173 heap words.
The first dense/depth implementation measured 20.026–21.227 ms at detail 2.
Hoisting column noise and fusing temporary color calculations reduced cost.

| Final detail | Build ms | Major words | Promoted words | Observed heap words |
|---|---|---|---|---|
| 1 | 3.326–3.529 | 234,350–240,030 | 43,969–65,779 | 268,903–365,857 |
| 2 | 13.390–13.607 | 1,123,780 | 300,980 | 1,174,029 |
| 3 | 29.813–31.457 | 2,661,286–2,661,300 | 706,702–706,716 | 2,672,624 |

Heap size is not peak live memory. These measurements exclude Metal staging,
GPU execution, presentation, UI, texture preparation and PNG output. They are
not end-to-end FPS claims. Detail 3 favors surface resolution over frame rate.

The subsequent radiant-fold revision adds broad Gaussian color profiles and
unequal widths. Five warmed detail-2 builds measured 17.744–20.087 ms on the
same machine/profile, with 1,123,780 major words, 300,980 promoted words and
1,174,029 observed heap words. The preceding detail-2 baseline was
13.390–13.607 ms. Cardinalities are unchanged. Build/docs, focused tests,
twelve-frame native smoke and two-frame one/four-domain exact PNG comparison
were renewed for this revision. Tests additionally guard against a washed-out
constant light field and verify the three new controls affect the result.
