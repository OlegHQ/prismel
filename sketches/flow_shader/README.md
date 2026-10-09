# flow_shader

Rays Lisp as a shader language: one per-pixel kernel, written in Lisp, runs on the GPU
and is shown live next to the graph editor's view of the very same kernel.

The kernel `glow` is a stepped-echo glow: x is quantized into bands, each band shifts the
blob centre and scales its radius, and a three-layer palette colours the falloff. Four
`image/map` calls use it with different bands, radii and palettes; `t` animates the drift
and the breathing as a GPU uniform. It uses only operators the packed GPU kernel supports
(`+ - * / mod max`), so the measured placement picks Metal at 256².
Run: `dune exec sketches/flow_shader/main.exe`. Edit a card in the graph and the picture follows.
