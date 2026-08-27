# Phase 5 direct API facade audit — 2026-08-27

This audit reconciles the machine-readable Prismel API preservation map with
the SDL2-free facade increments `1d87396`, `df7ec73`, and `cb2f3e4` (including
their already-landed prerequisites).

## Result

- Baseline public modules: 40.
- Direct, byte-identical staged interfaces: 20.
- Implemented/adapted staged interfaces: 9.
- Pending adapted modules: 11.
- Reviewed raw-only Low omissions: 9.

The direct set is:

`Camera`, `Color`, `Compute3`, `Easy_camera`, `Fog3`, `Light`, `Mat3`, `Mat4`,
`Material`, `Math`, `Mesh`, `Node3`, `Noise`, `Parallel`, `Path`, `Quat`, `Rand`,
`Shader3`, `Vec2`, and `Vec3`.

Each `direct` row is now accepted only when all of these mechanically checked
conditions hold:

1. its target is inside `lib/prismel_next_api`;
2. its target `.mli` is byte-identical to `lib/prismel/<module>.mli`;
3. a corresponding staged `.ml` exists; and
4. neither staged source file contains a Tsdl, SDL2, tsdl_gfx, or OpenGL
   dependency token.

The gate includes positive and negative scanner self-tests, so removing the
dependency check or allowing a direct row backed by legacy source fails the
test rather than silently weakening the classification.

## Reproduction

```sh
opam exec -- dune build tools/gpu_migration/phase5_prismel_api_map.exe
_build/default/tools/gpu_migration/phase5_prismel_api_map.exe --root .
```

Observed output:

```text
Phase5 Prismel API map passed: 40 baseline modules = 20 direct + 9 implemented-adapted + 11 pending-adapted + 0 raw-only; 9 exact Low omissions
```

This is preservation evidence for the staged facade only. It does not claim
that the public Prismel library has switched to the facade or that Phase 5
deletion gates are complete.
