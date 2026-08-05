# Runtime and rendering targets

Prismel separates application semantics, runtime lifecycle, and browser
transport into three libraries:

```text
examples ──► procedural ──► pdk ──► prismel ──► runtime ──► wap
   │              │          ▲          │           │
   ├────────────► geom ───────┘          │           └──► tsdl
   ├────────────► pxui ──────────────────┘
   └────────────────────────────────────► prismel
```

- `prismel` owns `Sketch`, `Scene`, resources, renderer logic, and translation
  into public `Event`/`Input` values.
- `prismel.runtime` selects a target, initializes and shuts down SDL
  subsystems, presents frames, and joins browser events to the initial domain.
- `prismel.wap` is Prismel-agnostic. It owns the HTTP/WebSocket server,
  browser shell, WebGL presentation, bounded frame transport, uploads, and
  token-protected runtime assets. Browser audio and input-region commands cross
  the boundary as typed values; their JSON/wire encoding remains inside Wap.
  Runtime imports Wap; Wap never imports Prismel or Runtime.
- `prismel.pdk` owns target-independent packed geometry, topology, attributes,
  groups, deterministic CPU kernels, and the terminal conversion to
  `Prismel.Mesh.t`. It does not import Geom, Procedural, Runtime, Wap, SDL, or
  browser code.
- `prismel.geom` owns ergonomic mathematical/curve/polygon APIs and explicit
  adapters. Mesh generation and topology operators migrate into Pdk so Geom
  and Procedural share one compute core; Pdk never imports either layer.
- `prismel.procedural` owns immutable SOP graphs, cook contexts, diagnostics,
  incremental evaluation, and bounded session caches. It may import Pdk, Geom,
  and Prismel, but never Runtime or Wap. Its output reaches every render target
  through the existing `Pdk.Geometry.t -> Prismel.Mesh.t -> Scene3` path.

PDK kernels and procedural cooks are ordinary target-neutral CPU work. They may
use Prismel's reusable `Parallel` pool over disjoint packed ranges, but all SDL
and renderer work still joins on the initial domain. There is no headless- or
web-specific procedural renderer and no geometry protocol in Wap.

## Target selection

`PRISMEL_RENDER_TARGET` is authoritative. The accepted values are:

| Value | Behavior |
|---|---|
| `native`, `desktop`, `sdl`, `opengl` | visible OpenGL-backed SDL window, native GPU Scene3, accelerated SDL 2D |
| `headless`, `software` | hidden SDL dummy window, software renderer, dummy audio |
| `web`, `browser`, `webgl` | hidden SDL software renderer plus browser server |

The `PRISMAL_RENDER_TARGET` spelling requested by deployment environments is
accepted as an exact alias. `PRISMEL_WEB=1`/`PRISMAL_WEB=1` and
`PRISMEL_HEADLESS=1`/`PRISMAL_HEADLESS=1` are shorthands. Legacy `HEADLESS`
remains a final compatibility fallback and accepts `1`, `true`, `yes`, or `on`
case-insensitively. An explicit render target always wins over shorthands.

The checked-in `.env` selects `PRISMEL_RENDER_TARGET=headless`. Examples:

```sh
PRISMEL_RENDER_TARGET=native dune exec examples/basic/main.exe
PRISMEL_RENDER_TARGET=headless dune exec examples/basic/main.exe
PRISMEL_RENDER_TARGET=web dune exec examples/basic/main.exe
```

`Sketch.render_target`, `Sketch.is_headless`, and `Sketch.is_web` expose the
selection without making application code inspect the environment.

## Native and headless lifecycle

Runtime initializes SDL video, audio, and events, followed by SDL_image and
SDL_ttf. Prismel initializes SDL_mixer after Runtime starts and shuts it down
before Runtime stops. Window, renderer, event, texture, font, and audio work
remains on the initial OCaml domain.

Native mode creates a compatibility OpenGL context for fixed-pipeline `Scene3`
and an OpenGL-backed accelerated SDL renderer for composable 2D/PXUI drawing.
The native 3D path performs vertex transforms, clipping, depth/stencil,
lighting, culling, blending, primitive rasterization, and configured window
MSAA on the GPU. It flushes queued SDL work before issuing direct OpenGL draws
through SDL's own renderer context; later 2D nodes then compose PXUI/text into
that same presented backbuffer. Each raw pass saves SDL's server/client state,
binds the fixed-pipeline program and client-memory buffers explicitly, disables
inherited 2D texturing, and restores SDL's shader/VBO bindings before 2D drawing
resumes. Packed flat/smooth mesh views are bounded to
the current and previous procedural mesh so slider-driven topology replacement
cannot retain an unbounded trail.

The first accelerated tranche accepts untextured fixed-pipeline scenes.
Textures, typed `Shader3`, shadows, fog, and separate-specular scenes currently
emit one explicit diagnostic and use the software reference. Removing that
transitional native fallback requires a typed GPU representation for those
features; it must not be achieved by silently changing public shader semantics.
Headless and web modes set SDL's dummy video/audio drivers before initialization
and require the software renderer. Neither mode needs a display server,
monitor, GPU, or OpenGL context, and neither turns drawing into no-ops.

Runtime performs presentation after `Scene.render`. It synchronizes `Time`'s
vsync knowledge with the renderer configuration, so fixed-FPS sketches do not
spin when a target has no real vsync source.

## Web target

Web mode binds an HTTP/WebSocket server to `0.0.0.0`; the default port is 8080.
`PRISMEL_WEB_PORT` (or `PRISMAL_WEB_PORT`) selects another port, including `0`
for an ephemeral test port. `PRISMEL_WEB_MAX_FPS` defaults to 60 and bounds
framebuffer readback/network cadence independently of a faster simulation.
`PRISMEL_WEB_MAX_MBIT` defaults to 2 and adds a target payload budget: large or
incompressible updates reduce presentation cadence instead of consuming mobile
traffic at the raw framebuffer rate. `PRISMEL_WEB_MAX_PIXELS` defaults to
921600 and bounds the server framebuffer while preserving the full viewport as
logical coordinates; for example, a 1920×1080 viewport uses a 1280×720 backing
framebuffer. All variables accept the equivalent `PRISMAL_` spelling.

The server-side renderer remains authoritative. This is deliberate: Prismel's
SDL2_gfx paths, native text/image decoders, software 3D shaders, depth/stencil,
post-processing, Canvas behavior, and PXUI all retain one implementation and
therefore the same output. A direct js_of_ocaml build would require replacing
all SDL and C-stub boundaries and would create a second renderer with different
coverage.

For every connected browser:

1. Prismel renders normally into the hidden software framebuffer.
2. Runtime reads native RGBA8 pixels directly into a pooled Bigarray.
3. Wap compares against the latest frame, suppresses exact duplicates, and
   losslessly QOI-encodes compressible full frames or changed rectangles.
4. Each browser has at most one unacknowledged frame. Once the browser presents
   and acknowledges it, Wap sends a sequential 44-byte-header patch or the
   newest complete 28-byte-header frame when that browser skipped the patch's
   base. Socket buffers therefore cannot accumulate stale rendered frames.
5. The browser decodes into reusable storage, uploads patches into one
   persistent, linearly filtered WebGL texture with `texSubImage2D`, and draws
   one full-screen strip from an antialiased context on the next animation
   frame. Canvas 2D `putImageData` is the compatibility fallback.

Browser pointer coordinates are mapped back into logical sketch points before
transport. Coalesced pointer samples are retained in chronological order but
batched into one WebSocket message, preserving freehand fidelity with less
protocol and thread overhead. Pointer capture, mouse buttons, motion, wheel, keyboard press and
release, UTF-8 text, IME composition, focus loss, and resizable viewport facts
join the same ordered `Frame.events` stream as SDL events. Browser file drops
up to 16 MiB are bounded in transit, written to a temporary file, emitted as
`Event.FileDropped`, and removed after `on_stop` returns.

The browser viewport is authoritative: every web canvas fills it and emits a
logical resize even when the desktop sketch has `resizable = false`. The
configured sketch size is only the pre-connection size. Backing pixels may be
smaller than logical points when the viewport exceeds the pixel budget; WebGL
scales that backing texture across the exact viewport. Pointer positions use
the live canvas content rectangle and remain unclamped during pointer capture,
so release-outside and drag-outside semantics are not mistaken for events on a
control at the canvas edge.

PXUI text fields emit pure `Scene.text_input_region` metadata. Runtime sends
the transformed and clipped logical hit regions ahead of frames, allowing the
browser to position and focus a transparent, field-sized textarea synchronously
only when a pointer press lands on a text field. Pending focus survives an older server region snapshot until
the corresponding application update confirms it, preventing the mobile
keyboard from opening and immediately closing. Taps on buttons, sliders, the
canvas, or other non-text controls never summon the keyboard. Pointer
cancellation releases the held button and PXUI drag capture without pretending
the window lost focus or dismissing an active text field. The canvas retains
its pre-keyboard viewport while the textarea is focused, then adopts the latest
viewport after blur. The textarea retains an internal edit snapshot so mobile
autocorrect, replacement, deletion, and composition are translated into exact
`TextInput`/Backspace facts instead of resetting the editor every character.

SDL_mixer remains active through the dummy device to preserve server-side
lifecycle and query semantics. Samples and music are additionally registered
as token-protected Wap assets; ordered playback, volume, loop, fade,
pause/resume, stop, and destruction commands are mirrored to HTML audio in the
browser. Browser autoplay policy may defer playback until the first pointer
gesture, at which point the client resumes pending sounds.

## Web protocol and resource bounds

Wap implements RFC 6455 version 13. Client frames must be masked; server frames
are unmasked. Ping/pong, close, binary fragmentation, payload limits, socket
timeouts, and the standard SHA-1/Base64 upgrade are covered by protocol tests.

- At most 8 WebSocket clients and 64 total concurrent HTTP connections are
  accepted by default.
- The browser input queue is bounded by both count and retained bytes.
- Upload messages are limited to about 16 MiB and queued event data to 32 MiB.
- The pooled frame cache retains at most 16 reusable buffers and 256 MiB, plus
  at most one in-flight frame per bounded client.
- The ordered browser-control ring retains 256 small commands.
- HTTP pages use no-store, assets require the per-process unguessable token
  and support byte ranges for browser audio streaming and seeking,
  and a restrictive Content Security Policy is emitted.

The stable WebSocket API exposes queued bytes but no delivery acknowledgement,
while the less widely available `WebSocketStream` has stream backpressure. Wap
therefore adds an application acknowledgement after presentation. A slow
connection has one in-flight frame and observes the newest complete frame when
ready again. This preserves broad browser support without unbounded socket or
animation queues.

## Verification

`test/test_wap.ml` verifies the RFC handshake vector, target parsing and both
environment prefixes, masked input decoding, authenticated assets, ordered
commands, batched pointer samples, acknowledged fragmented binary frames,
lossless full-frame and patch codecs, exact duplicate suppression, backing-size
fitting, idle cadence, statistics, and intact RGBA bytes.

`test/web_runtime_smoke.ml` starts the real web target on an ephemeral port and
checks rendered framebuffer pixels, synthesized browser audio exposure,
pointer/key/text/wheel/focus ordering, logical resize behavior, per-frame mouse
delta, file upload contents, and temporary-file cleanup. `test/headless_smoke.ml`
continues to cover native framebuffer drawing and deterministic PNG export in
headless mode.
