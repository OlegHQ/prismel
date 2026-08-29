# Prismel Native Metal Infrastructure Plan

## Status and authority

This is the authoritative GPU migration plan. Prismel now targets **native
Metal on Apple-Silicon macOS only**. There is no headless, browser, web, Wap,
SDL software-renderer, Raster2, OGPU-Raster2, OpenGL, SDL2, or Tsdl fallback.

The migration completes only when every gate below is green on one final clean
commit, legacy code/dependencies are deleted, and named evidence is recorded.
Compilation or one rendered frame is not completion evidence.

## Decision and scope

Prismel has four native layers:

1. SDL3 bindings for the macOS window, events/input, high-DPI facts, audio,
   image/font services, and the Metal-view bridge.
2. Audited bindings for Metal and QuartzCore.
3. `ogpu`, the small OCaml-owned descriptor/ownership abstraction.
4. `ogpu_metal`, the sole rendering and presentation backend.

Supported release is Apple Silicon, macOS 14+. The required matrix is M1 at the
deployment floor, M1 on the pinned current SDK/runtime, and M3+ on that runtime
for hardware ray-tracing coverage. Metal 4 remains capability-gated. A machine
without a compatible Metal device/surface returns a typed startup error; it
never falls back to CPU rendering or browser transport.

The binding inventory remains the non-deprecated pinned-SDK Metal surface,
QuartzCore `CAMetalLayer`, optional separately-linked MetalFX, and SDL3 APIs
used by Prismel. SDL3 GPU is inventoried but is not Prismel's renderer.

## Compatibility contract

`Sketch`, `Frame`, `Scene`, `Scene3`, `Canvas`, `Image`, `Font`, `Audio`,
`Event`, `Input`, and public geometry/procedural/UI APIs retain their native
source behavior. SDL2 escape hatches are the declared major-version low-level
break; fake SDL2 types are forbidden.

The former headless/web contracts are removed, including `PRISMEL_RENDER_TARGET`,
`PRISMAL_RENDER_TARGET`, and `HEADLESS` target selection. Native Metal capture
and readback remain supported.

## Native dependency graph

```text
examples / sketches / pxui / procedural / pdk
                         |
                         v
                      prismel ----------------> ogpu
                         |                        ^
                         v                        |
                      runtime -----------> ogpu_metal --------> metal
                         |
                         +----> sdl3 / sdl3_image / sdl3_ttf / sdl3_mixer
```

Runtime alone combines SDL3's Metal view and `ogpu_metal`. Prismel records
through `ogpu`; no public path receives raw SDL or Metal pointers. `sdl3`,
`metal`, and `ogpu` stay below Runtime/Prismel; `ogpu_metal` imports neither.

`raster2`, `ogpu_raster2`, `wap`, Wap/SDL raster presenters, Web/Headless
Runtime providers, and their tests/tools are legacy scheduled for deletion,
not alternate implementations.

## Runtime and renderer design

Runtime has exactly one lifecycle: initialize SDL3 on the initial domain,
create a high-DPI Metal view, borrow its `CAMetalLayer`, create the
`ogpu_metal` device/surface, translate SDL3 events, acquire/present drawables,
drain completion/deferred release, then tear down GPU resources before the
view/window/SDL.

Prismel lowers immutable scenes into private native render work: clips and
transforms, solid/textured geometry, paths, glyph atlas quads, Scene3
meshes/materials/lights, and offscreen dependencies. Metal is its sole
consumer. Functional shaders require typed MSL/IR support or return a typed
unsupported-feature error; they never execute in a software fallback.

Canvas, Image, Font, and capture use owned Metal textures/buffers with explicit
lifetime rules. Caches are bounded by stable identity and release before device
or surface destruction.

## Phases

### 1. SDL3 and Metal foundations

Maintain generated inventory/provenance, ABI/layout checks, immediate SDL error
capture, main-thread enforcement, event/DPI correctness, SDL3 extension
ownership and Metal/QuartzCore coverage. S1-S8 and
M1-M10 remain mandatory.

### 2. OGPU and Metal backend

Qualify generational handles, device identity, validation, explicit resource
destruction, bounded submission/deferred-release queues, render/compute/blit
passes, presentation, typed native extension, and measured capabilities.
O1-O9 remain mandatory.

### 3. Native renderer/resource migration

Migrate all 2D, PXUI, text, images, Canvas, capture, Scene3, and audio-facing
resource paths to native Metal. Preserve native fixtures/tolerances. Stable
meshes upload once; caches/handles remain bounded. No comparison backend remains
after the atomic switch.

### 4. Atomic native switch and deletion

Switch every public execution path to native Metal, then delete:

- `lib/raster2`, `lib/ogpu_raster2`, and every Raster2 reference;
- `lib/wap`, browser clients/protocols, and Wap presenters;
- Headless/Web Runtime providers, target selectors, fixtures, and tools;
- SDL2/Tsdl/SDL2_gfx/OpenGL compatibility code, dependencies, comparison paths,
  and compatibility flags.

No switch, dynamic module, profile, or environment flag may preserve a
software/web fallback.

## Qualification gates

### S: SDL3 (S1-S8)

Generated SDL inventory/version/header provenance; ABI/layout/callback safety;
immediate error snapshots; ownership/main-thread rules; ordered logical events;
HiDPI resize/occlusion/recreation; native audio/image/font lifecycle; and
bounded native SDL stress pass on the release matrix.

### M: Metal (M1-M10)

Complete non-deprecated SDK inventory; ABI-conformant raw bindings; typed direct
selectors; ownership/availability/capability rejection; error translation,
threading/destruction, Metal 4, and M3+ ray tracing
pass according to their hardware requirements.

### O: OGPU (O1-O9)

Descriptor validation; stale/cross-device/double-destroy rejection; explicit
ownership; bounded submission epochs; device loss; pass/resource validation;
native-extension synchronization; surface lifecycle; and Metal conformance pass.

### R: native rendering (R1-R12)

R1 API/fixture manifest parity; R2 exact native Scene/Scene3 lowering; R3
native 2D/PXUI/text/material/lighting/fog/shadow/MSAA/Canvas/capture fixtures;
R4 resource ownership/reload/destruction; R5 native-only runtime semantics;
R6 logical-to-drawable Retina/input/viewport correctness; R7 frozen native
pixel tolerances and exact clear/copy/readback; R8 first/second/60th/600th/
post-resize correctness; R9 one stable-mesh upload and bounded batches/caches;
R10 native M1 Basic/PXUI/Canvas/Scene3 visible/hidden performance within the
5% median/10% p95 envelope; R11 shattered-cube one-upload performance; and
R12 30-minute native changing-resource stability with bounded handles/queues/RSS.

### D: deletion and release (D1-D8)

**D1.** Software/web/headless/Raster2/Wap plus SDL2/Tsdl/OpenGL source, tests,
tools, packages, presenters, and compatibility code are deleted.

**D2.** This token-aware scan returns no unclassified production/build/package
match. The final report must list every exact pinned-SDK exception; the only
permitted exception families are Metal's faithfully mapped
`MTLDevice.isHeadless`/`headless` capability and unused OpenGL-named SDL3
properties preserved by the generated full SDL3 inventory. Do not exclude
whole Metal/SDL3 files, ordinary `swap` identifiers, or SDL_image WebP APIs
from the audit:

```sh
rg -n -P '(?<![[:alnum:]_])(?:Raster2|raster2|ogpu_raster2|Wap|wap|Web|web|Headless|headless|Tsdl(?:_image|_ttf|_mixer)?|tsdl(?:_gfx|-image|-ttf|-mixer)?|SDL2(?:_gfx|_image|_ttf|_mixer)?|sdl2(?:-gfx|-image|-ttf|-mixer)?|libSDL2(?:_gfx|_image|_ttf|_mixer)?|conf-sdl2|OpenGL|opengl|libGL)(?![[:alnum:]_])|(?<![[:alnum:]_])gl[A-Z]' \
  dune-project prismel.opam lib test examples sketches tools
```

**D3.** `dune describe external-lib-deps` and `otool -L` show only native SDL3,
Metal, QuartzCore, and used SDL3-extension linkage.

**D4.** A fresh OCaml switch installs/builds native-only dependencies without
SDL2 or browser/server dependencies.

**D5.** Generated/copy provenance and licenses are complete.

**D6.** `AGENTS.md`, backend/API/performance/packaging specs, and examples say
native Metal only.

**D7.** From a clean build, twice: `dune build @all`, `dune runtest`, finite
native runs of every example, native GPU conformance, shattered cube, and the
three OS/GPU matrix lanes pass with no generated diff.

**D8.** No environment variable, hidden flag, profile, or dynamic module can
select browser, web, headless, CPU, SDL2, or OpenGL rendering.

## Evidence and definition of done

Every run records clean Git/executable provenance, command/profile, SDK/OS/
device/display facts, warmup/samples, frame median/p95/p99, CPU/GPU timing,
allocation/promotion/RSS, uploads, draw/pass counts, cache/release counts,
canonical native captures, and validator output. R10 is native-only; old
cross-target cells are deleted.

This plan is complete only when S1-S8, M1-M10, O1-O9, R1-R12, and D1-D8 pass
on one final clean commit; native API/example, runtime shader compilation, sanitizers,
native 30-minute stability, M1/M3+ matrix, and evidence agree; and source,
dependencies, and binaries contain no software rasterizer, headless/web
transport, SDL2, Tsdl, or OpenGL fallback.
