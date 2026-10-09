# flow_shader

Rays Lisp as a shader language: one per-pixel kernel, written in Lisp, runs on the GPU
and is shown live next to the graph editor's view of the very same kernel.

A panel is four kernels (`grad`, `haze`, `ring`, `core`) composited by alpha in that order. Each is
a stepped echo: x is quantized into bands, and every band to the right is a smaller or taller,
fainter copy whose centre has moved right and whose ring colour drifts. Six `panel` calls give
different bands, radii and palettes; `t` animates drift, breathing and hue as GPU uniforms. One
kernel holding all four zones would exceed the 64-register packed program, so the zones are layers.
Only `+ - * / mod max abs` are used, so the measured placement picks Metal.
Run: `dune exec sketches/flow_shader/main.exe`. Edit a card in the graph and the picture follows.
