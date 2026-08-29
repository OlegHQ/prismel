# D1/D2/D8 native-only static renewal — 2026-08-29

Captured at `2026-08-29T18:38:13+02:00` from clean commit
`5d3d90adcb87b0ec0d0b8050cf5b3a5ffec3268d`. This is a current static
renewal, not the final twice-clean D7 release run.

## D1 source deletion

`git ls-files` contains no `raster2`, `ogpu_raster2`, `wap`, SDL2, Tsdl,
OpenGL, headless-renderer, or web-transport source/package path. The sole path
matched by the deliberately broad path search was
`test/sdl3_image_fixtures/sample.webp`; WebP is an SDL3_image decode fixture,
not a web renderer or transport. The top-level `lib/` inventory contains only
the native SDL3, Metal, OGPU/Metal, runtime, Scene, resource, and application
libraries. In particular, `lib/raster2/`, `lib/ogpu_raster2/`, and `lib/wap/`
do not exist.

## D2 exact token scan

The exact token-aware command pinned in `NEW_GPU_STUFF.md` returned only:

- the generated full-SDL3 inventory's OpenGL-named property strings;
- Metal's faithfully mapped `MTLDevice.isHeadless`/`headless` capability;
- the corresponding Metal classification entry.

These are precisely D2's two permitted exception families. There was no
production/build/package hit for a software rasterizer, browser transport,
SDL2/Tsdl, OpenGL implementation, `libGL`, or `gl[A-Z]` call.

## D8 selector and fallback audit

A case-insensitive selector search found no production render-target or
backend selector. `test/native_only_rendering.ml` intentionally names rejected
legacy environment variables and injected SDL renderer/OpenGL symbols as
negative fixtures. Its positive anchors require the sole chain
`SDL_Metal_CreateView` -> `Ogpu_metal.Backend.create` ->
`Runtime_next.create` -> `Runtime_next_orchestrator.create`.

The negative-fixture names are tests of absence, not selectable production
paths. No environment variable, command-line option, profile, or dynamic
module can choose browser, web, headless, CPU, SDL2, or OpenGL rendering.

## Commands

```text
git status --short
git ls-files | rg -i '(^|/)(raster2|ogpu_raster2|wap)(/|$)|sdl2|tsdl|opengl|headless|web'
rg -n -P '<the exact D2 expression from NEW_GPU_STUFF.md>' \
  dune-project prismel.opam lib test examples sketches tools
rg -n 'PRISMEL_RENDER_TARGET|PRISMAL_RENDER_TARGET|HEADLESS|render.target|target.*(web|headless|software|opengl)|backend.*(web|headless|software|opengl)' \
  lib test examples sketches tools dune-project prismel.opam -i
find lib -maxdepth 1 -type d -print | sort
```

This renewal keeps D1, D2, and D8 provisional until the final clean commit's
twice-clean D7 suite re-runs the executable negative gate and all generated
diff checks. It does not change the 37/47 implementation/evidence coverage or
the 11/47 strict-final count.
