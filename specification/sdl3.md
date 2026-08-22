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
| Pure or any-thread query | error printers; generated `Version` facts; `Version.validate`; `Version.linked`, `revision`, and extension version queries; `Thread.is_initial_domain`; `Thread.is_sdl_main_thread`; `Display.id`; immutable handle generations and modes; `Event.mouse_delta`; dropped-release counters | These either do no native work or call an SDL function whose pinned header says it is safe from any thread.  They never acquire or destroy a resource. |
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

The binding tests run the wrong-domain matrix, a blocking-wait system-thread
probe, copied event traces, parent/child teardown, stale access, malformed
input, and 100,000-cycle ownership stress.  `tools/bench_sdl3.exe` reports the
FFI call count, wall time, OCaml allocation, collection counts, heap size, and
dropped release tokens for the same lifecycle categories.
