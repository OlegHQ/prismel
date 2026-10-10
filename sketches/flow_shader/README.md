# flow_shader

Rays Lisp as a shader language: one per-pixel kernel, written in Lisp, runs on the GPU
and is shown live next to the graph editor's view of the very same kernel.

A panel is four kernels (`grad`, `haze`, `ring`, `core`) composited by alpha in that order, and the white-core panel adds a fifth, `rim`, a thin red-orange bump outside the ring. A `warp` parameter bends the band coordinate so bands can widen to the right. Each is
a stepped echo: x is quantized into bands, and every band to the right is a smaller or taller,
fainter copy whose centre has moved right and whose ring colour drifts. Six `panel` calls give
different bands, radii and palettes; `t` animates drift, breathing and hue as GPU uniforms. One
kernel holding all four zones would exceed the 64-register packed program, so the zones are layers.
The graph overview is `motion` → six named panels → `result`, with a separate background.
The panels start as compact cards: select one to edit its named macro inputs in the inspector,
press `o` to reveal its rows, and `v` to preview it. Open `motion` to inspect drift, breathing,
sway and hue and their per-panel uniforms. Open `ember` to inspect its extra rim layer.
The shader arithmetic includes `pow` and `sin`; the display kernels run through the GPU lane.
Run: `dune exec sketches/flow_shader/main.exe`. Edit a card in the graph and the picture follows.
