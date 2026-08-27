# Native-next process/link boundary — 2026-08-27

## Current closure

The current `Scene_ogpu_renderer` is a private module of the monolithic
`prismel` library. Linking that module therefore links the same archive that
depends on `tsdl`, `tsdl-image`, `tsdl-ttf`, `tsdl-mixer`, `tsdl_gfx`, and the
legacy `runtime` library. The legacy runtime itself links the SDL2 packages.

The SDL3 presenter is correctly isolated as
`runtime_sdl3_raster2_presenter -> sdl3`, while
`ogpu_metal -> ogpu + metal` has no SDL dependency. A new executable cannot
currently combine `Scene_ogpu_renderer`, `ogpu_metal`, and the SDL3 presenter
without also pulling the legacy Prismel/Runtime SDL2 closure into that same
process. Such an executable would violate the migration's symbol-isolation
rule even if it happened to link on one machine.

`tools/native_next_link_gate.ml` pins this fact and rejects that unsafe
composition. It also proves that the two independently selectable foundations
remain clean: `ogpu_metal` has no SDL edge and the SDL3 presenter has no
Prismel/SDL2 edge.

## Smallest safe next refactor boundary

The next atomic extraction is a private, target-neutral scene execution
library below `prismel`, containing the prepared OGPU draw payload and only the
scene value/lowering types it consumes. Its dependency closure must be
`raster2 + ogpu`; it must not depend on `prismel`, `runtime`, Tsdl, SDL3, or
Metal. The existing private `Scene_ogpu_renderer` becomes a compatibility
adapter over that library.

Only after that extraction is independently tested may a native-next
executable compose:

```
scene execution -> ogpu -> ogpu_metal -> metal
                               ^
SDL3 presenter -> sdl3 --------|  (borrowed Metal layer only)
```

Runtime then owns the process choice. Legacy and native-next executables remain
separate Dune compositions; no in-process comparison target is permitted.
Extracting only `Scene_ogpu_renderer.ml` is insufficient because its public
inputs and lowering dependencies are currently modules of the SDL2-linked
`prismel` archive.
