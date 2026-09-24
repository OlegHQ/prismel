# Pastel Flow

A native, procedural reconstruction of the two supplied pastel references:
**Pearl waves** and **Iridescent silk**. The images are visual references, not
textures loaded by the sketch. This is an editable approximation, not a
pixel-exact reproduction.

```sh
dune exec sketches/pastel_flow/main.exe
dune exec sketches/pastel_flow/main.exe -- --preset silk
```

The sidebar has **56 sliders** in five expandable sections. Scroll inside the
panel, drag a slider, or click its numeric value to type. Tab hides the panel;
Escape exits. Preset buttons reset the controls and animation time can be
restarted by relaunching. Animation is off by default.

- Composition: blend folds and waves, zoom, rotate in radians, and pan.
- Pastel field: palette hue, saturation, brightness, diffusion, four color
  weights, field position, and an optional Perlin/fBm field mix (scale +
  detail). Mix 0 keeps the classic gaussian color blobs; mix 1 is pure
  seeded noise weighted by mint/pink/violet/blue. Field controls govern the
  background; the silk sheets also have their own authored color gradients.
- Wave ribbons: count, spacing, width, opacity, bend, frequency, slope, phase,
  vertical placement, independent upper-band bend/slope/phase/intensity,
  edge fading, and secondary ripple.
- Silk folds: position, curvature, tilt, sheet width, neck pinch, upper-sheet overhang and lip height, crease width,
  edge highlight, shadow, and iridescence.
- Finish and motion: seeded microtexture, texture scale, random seed, seeded
  chaos amount, corner shading, global animation speed (0–8), and separate
  wave / fold / color motion rates plus motion chaos. At chaos 0, presets stay
  bit-identical across seeds (aside from grain); raising chaos reshapes the
  field, ribbons, and folds from the seed.

Save/Load controls use `_out/pastel-flow.json`, or `--settings PATH`. An existing
settings file takes precedence over the initial preset. Rendering clamps typed
values to the supported slider ranges, including integer-valued counts and seed.

Export artwork without the UI, at native framebuffer density:

```sh
dune exec sketches/pastel_flow/main.exe -- \
  --preset waves --export /tmp/pastel-waves --size 1000
dune exec sketches/pastel_flow/main.exe -- \
  --preset silk --export /tmp/pastel-silk --size 1000
dune exec sketches/pastel_flow/main.exe -- \
  --animate --frames 120 --export /tmp/pastel-animation
```

`--size` specifies logical points (256–2400), so a scale-2 display produces a
PNG twice that width and height. Export uses the same Metal scene as the window.
A compatible native Metal surface is required. Animation uses a fixed 1/60-second
step, independent of how long frame preparation takes.

Geometry is generated into exactly sized arrays and rasterized by Metal. There
is no CPU rasterizer, image synthesis, or custom backend. Meshes are retained
until a control or animation time changes. Camera identity remains stable across
frames. Space is O(grid vertices + line count × line segments + grain count).
Default waves contain 179,121 vertices; silk contains 121,654. The maximum
supported combined setting is below 600,000 vertices, checked automatically.
The existing bounded renderer caches own GPU uploads.

Validation:

```sh
dune runtest sketches/pastel_flow
dune exec sketches/pastel_flow/main.exe -- --smoke
dune exec sketches/pastel_flow/main.exe -- --preset silk --smoke --domains 4
dune build --force @tools/bench-pastel-flow  # geometry only; no window
```

The finite smoke path changes rotation and texture across eight native frames.
The geometry test checks every slider endpoint, combined extrema, finite
coordinates, valid indices/colors/normals, bounded cardinality, deterministic
rebuilds, and settings round-trips. Three animated PNG frames of both presets
were compared byte-for-byte between one- and four-domain runs.

Measured on Apple M1, macOS 26.2, OCaml 5.3.0, Dune development profile: five
warm geometry builds took 49.3–50.0 ms for waves and 90.9–93.0 ms for silk.
Waves allocated 3.04–3.08 million major words, including 0.89–0.93 million
promoted words; silk allocated 2.09–2.10 million major words, including
0.63–0.65 million promoted words. These are CPU geometry-build measurements,
not GPU timings or sustained FPS. Static frames reuse geometry. Animation and
continuous slider dragging rebuild it and are not claimed to sustain 60 FPS.
An initial waves build took about 122 ms before caching parameter lookup values;
that is an indicative single-build observation, not a controlled benchmark.
