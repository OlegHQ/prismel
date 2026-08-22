# SDL3 binding contract

The SDL3 bindings are ordinary Dune libraries under `lib/sdl3`,
`lib/sdl3_image`, `lib/sdl3_ttf`, and `lib/sdl3_mixer`.  They do not load
functions dynamically and they do not execute OCaml from a native callback.
The generated symbol inventories describe the pinned native headers; the
ownership-aware `.mli` files are the only API available to Runtime.

## Thread classes

Every public operation belongs to one of the following classes.  Runtime must
not bypass these classifications through `Private_raw`.

| Class | Public operations | Enforcement |
| --- | --- | --- |
| Pure or any-thread query | error printers; generated `Version` facts; `Version.validate`; `Version.linked`, `revision`, and extension version queries; `Thread.is_initial_domain`; `Thread.is_sdl_main_thread`; `Display.id`; immutable handle generations and modes; `Event.mouse_delta`; TTF installed-font path discovery; dropped-release counters | These either do no native work or call an SDL function whose pinned header says it is safe from any thread.  They never acquire or destroy a resource. |
| Initial OCaml domain and SDL main thread | core `Init`, `Display` except `id`, `Window`, `Clipboard`, `Text_input`, event polling/waiting, `Surface`, `Metal_view`, and explicit release draining; all image decode, TTF init/font, and mixer init/mixer/audio/track operations | The safe entry point checks both `Domain.is_main_domain` and `SDL_IsMainThread` before its native call and returns `Wrong_domain` on failure. |
| Any-domain deferred release | GC finalizers for windows, Metal views, surfaces, fonts, mixers, audio values, and tracks | A finalizer only appends an opaque release token to a bounded mutex-protected queue.  It never calls SDL.  The initial-domain safe boundary drains children before parents. |
| Blocking initial-domain call | `Sdl3.Event.wait` with a nonzero timeout and `Sdl3.Window.sync` | The stubs release the OCaml runtime system only around `SDL_WaitEventTimeout` or `SDL_SyncWindow`.  The wait timeout is copied by value, the reusable event union stays in native storage, and a synchronized window remains rooted and cannot be destroyed from another domain.  No OCaml heap pointer is retained by SDL, and the runtime is reacquired before copying or returning anything to OCaml.  A zero event timeout does not release the runtime system. |

`Init.initialized` is deliberately a result-returning initial-domain query:
the pinned SDL header marks `SDL_WasInit` as not thread-safe.  Extension init
queries follow the same safe-boundary rule even when their current state is
also mirrored in OCaml.

Handle inspection such as `destroyed` is diagnostic only.  It does not make
concurrent ownership mutation valid; create/use/destroy operations remain in
the initial-domain class.

## Callback policy

The core, image, TTF, and mixer stubs install no application callback and
contain no `caml_callback*` call.  Events are polled into one reusable native
`SDL_Event` union.  Image and font results are returned synchronously as copied
CPU bytes.  Mixer device work remains inside SDL_mixer; Prismel supplies no
OCaml audio callback.  A future native callback must use a bounded native
queue, contain no OCaml value, and be drained on the initial domain before it
can enter the safe API.

## Ownership and errors

Owned native handles have explicit idempotent destruction and a generation.
Access after destruction returns `Destroyed`; a parent with live children
returns `Parent_has_dependents`.  Borrowed strings and event payloads are
copied before returning.  Each fallible stub copies native error text into its
result before the safe layer can issue another SDL call.  Dimension, stride,
length, numeric-range, and embedded-NUL checks happen before native allocation
or decoding.

The constructor/decoder failure matrix is executable, not inferred from happy
paths:

| Boundary | Injected failure |
| --- | --- |
| `Init.init` | nonexistent SDL video driver in an isolated process |
| `Window.create` | video subsystem absent, plus invalid dimensions and embedded-NUL title |
| `Surface.create_rgba` / `of_rgba` | cardinality overflow, invalid dimensions, short stride, and short source |
| `Metal_view.create` | dummy-video window without a native Metal layer |
| SDL3_image file/byte decoders | missing file and malformed input with an explicit hint for every supported still format |
| `Font.open_file` and system discovery | missing/empty font path, invalid size, and invalid `PRISMEL_UI_FONT` |
| device/memory mixer creation | nonexistent audio driver and invalid sample-rate/channel facts |
| audio file/byte/synthesis creation | missing/malformed/empty input and invalid frequency/amplitude/duration |
| `Track.create` | destroyed parent mixer |

Native error strings are copied into immutable OCaml error records before the
next native call; the failure tests retain an error across a subsequent
version query and compare it exactly.

The binding tests run the wrong-domain matrix, a blocking-wait system-thread
probe, copied event traces, parent/child teardown, stale access, malformed
input, and 100,000-cycle ownership stress.  `tools/bench_sdl3.exe` reports the
FFI call count, wall time, OCaml allocation, collection counts, heap size, and
dropped release tokens for the same lifecycle categories.

## Extension parity fixtures

SDL3_image conformance decodes all 19 still-image formats enabled by the pinned
stable distribution: AVIF, BMP, CUR, GIF, ICO, JPEG, JPEG XL, ILBM, PCX, PNG,
PNM, QOI, SVG, TGA, TIFF, WebP, XCF, XPM, and XV.  Each fixture is decoded by
path and from copied bytes into tightly packed RGBA8.  Separate fixtures cover
alpha, exact EXIF orientation, malformed input for every decoder, and the
atomic watched-reload rule: failure preserves the borrowed wrapper, previous
surface, pixels, and generation; success changes content and generation while
preserving the borrowed wrapper.  Animation formats are outside Prismel's
existing still-image API and are not silently advertised by this binding.

SDL3_ttf conformance discovers an installed platform UI font with
`PRISMEL_UI_FONT` override semantics, then covers empty text, UTF-8, family and
style names, metrics, RGBA rasterization, mutation, and 72/144-DPI rendering.
A Runtime-shaped CPU-raster cache proves borrowed identity, immediate mutation
invalidation, and destructive least-recently-used eviction at exactly 256
entries.  The renderer-local OGPU texture cache will retain the same key and
bound when the high-level Font adapter switches.

SDL3_mixer conformance covers copied-memory and file-backed sound/music loads,
device and memory mixers, play, loops, gain, fades, pause/resume, stop, dummy
headless playback, generated PCM, parent/child ownership, and an invalid-driver
device failure.  Wap's integration test streams every typed sample/music
command through an authenticated WebSocket and checks the exact bounded wire
encoding, preserving web mirroring without putting protocol strings in the
mixer or Runtime-facing audio API.
