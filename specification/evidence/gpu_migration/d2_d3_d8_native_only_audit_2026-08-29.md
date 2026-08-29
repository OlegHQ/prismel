# D2/D3/D8 native-only audit — 2026-08-29

Audit base revision: `21c9e3fbe2f9681f6bebb70a83173a8349355512`
(`Stage native Scene2 layers once`). This record is committed with the D8
removal described below. The worktree also contained concurrent Scene2 changes,
so this is a focused local gate record rather than D7 clean-tree qualification.

## D2 token classification

The exact token-aware command frozen in `NEW_GPU_STUFF.md` returned 22 lines.
Every line belongs to one of the two permitted pinned-SDK exception families:

- Seven Metal `MTLDevice.headless` capability mapping/inventory lines:
  `lib/metal/metal.mli`, `lib/metal/metal.ml` (two),
  `lib/metal/metal_bridge.mm`, `tools/metal/classification.ml`, and
  `lib/metal/generated_api_inventory.json` (two).
- Fifteen unused generated SDL3 property values in
  `lib/sdl3/generated_inventory.json`:
  `SDL.texture.create.opengl.texture`, `_uv`, `_u`, `_v`;
  `SDL.texture.opengl.texture`, `target`, `texture_uv`, `texture_u`,
  `texture_v`, `tex_h`, `tex_w`; `SDL.window.create.opengl`; and the UIKit
  OpenGL `framebuffer`, `renderbuffer`, and `resolve_framebuffer` properties.

There were no unclassified production, build, package, test, example, sketch,
or tool matches. No whole generated file or SDL_image WebP API was excluded.

## D3 dependency and built-artifact linkage

The dependency description was captured without building:

```sh
opam exec --switch=. -- dune describe external-lib-deps --format=sexp
```

It contained 5,172 lines describing 624 targets. The external OCaml dependency
set was exactly `compiler-libs.common`, `digestif`, `domainslib`,
`dune-configurator`, `ppxlib`, `threads`, `unix`, and `yojson`. Searches for
SDL2, Tsdl, OpenGL/libGL, Raster2/OGPU-Raster2, Wap/web/browser/Wasm, and common
server stacks returned zero lines.

A read-only `otool -L` sweep covered all 724 already-built `.exe`, `.cmxs`,
`.dylib`, and `.so` artifacts under `_build/default`. The forbidden SDL2, Tsdl,
OpenGL/libGL, Raster2, and Wap search returned zero lines. Representative
`examples/basic/main.exe` and `sketches/shattered_cube/main.exe` linked Metal,
QuartzCore, SDL3, and the used SDL3_image/ttf/mixer extensions plus ordinary
Apple system frameworks and runtime libraries. The native runtime qualification
executable linked Metal, QuartzCore, and SDL3; the SDL3 ownership executable
linked SDL3 only beyond system runtime libraries.

This refresh confirms the current dependency description and already-built
artifact set. The earlier `d3_native_link_audit_2026-08-29.md` remains the fresh
release-build sweep; this focused record does not replace D7's final clean
double build and matrix lanes.

## D8 selector and fallback removal

The audit found one concrete fallback: public `Sdl3.Rgba_presenter` called
`SDL_CreateRenderer(window, NULL)` and `SDL_RenderPresent`. Its renderer could
be selected through SDL renderer policy, and its history identified it as the
retired Raster2/headless presenter adapter. The safe module, private raw
externals, C implementation, release-queue/window-dependent plumbing, and
presenter fixture were deleted completely.

`test/native_only_rendering.ml` is now a durable negative gate. It rejects SDL
renderer creation/presentation, SDL GL/Vulkan window surfaces, dynamic loading,
generic backend flags, and the exact retired `PRISMEL_RENDER_TARGET`,
`PRISMAL_RENDER_TARGET`, headless/web aliases, and legacy test renderer
selectors. It requires the production chain `SDL_Metal_CreateView` ->
`Ogpu_metal.Backend.create` -> `Runtime_next.create` ->
`Runtime_next_orchestrator.create`, and proves its reject path with an injected
SDL renderer call.

Focused release verification:

```sh
opam exec --switch=. -- dune runtest --profile release lib/sdl3
opam exec --switch=. -- dune build --profile release \
  @test/runtest-native_only_rendering
```

The SDL3 ownership/event/failure/Metal tests, generated-inventory check, and
100,000-cycle surface/window stress passed. The native-only source gate passed
with its negative fixture.
