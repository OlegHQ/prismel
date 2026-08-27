# Phase 5 final facade qualification

This standalone installed-surface fixture exercises the locally actionable
R1/R2/R4/R5/R8 subset through `prismel.prismel_next_api` only. It runs the same
Basic-, panel/PXUI-, Canvas/resource-, and Scene3-style values under default
headless and web target selection at frame labels 1, 2, 60, and 600.

The gate proves deterministic public-value/framebuffer hashes, stable image
identity/generation across repeated lowering, explicit resource/session
teardown, the exact 40-module API map and nine Low omissions, and no worktree
changes below `examples/`. Stable identity/generation is the public evidence
available here; this tool deliberately does **not** claim backend upload-counter
qualification or promote native, atomic-switch, long-run, or external packaging
gates.

The committed deterministic FNV-1a fingerprints are:

- Basic scene sequence: `535e25a21992b801`
- panel/PXUI-like sequence: `29ea844d81e890f0`
- Canvas/image resource IR: `6cfaaeb1e2b33dc4`
- sampled Scene3 color/depth/stencil attachments: `fe1df44e05ef82ba`

Headless and web runs must produce the same four values.
