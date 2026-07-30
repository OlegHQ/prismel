# Asset loading and ownership

## Goals

Sketch asset loading should be easy, deduplicated, path-stable, and impossible
to accidentally leak in the normal lifecycle.

## Cache

`Assets.create ~root ()` owns four typed caches:

- images keyed by resolved path;
- fonts keyed by resolved path and point size.
- audio samples keyed by resolved path;
- streamed music keyed by resolved path.

Relative paths resolve beneath `root`; absolute paths remain absolute. Loading
the same key returns the same borrowed resource. Errors include the asset kind,
resolved path, and backend message.

`Assets.preload` accepts a list of typed requests and attempts all of them,
returning every error. It intentionally performs SDL decoding/upload on the
initial domain. `Assets.preload_parallel` implements a safe two-phase variant:
image bytes are read concurrently through `Parallel`, then decoded and uploaded
in request order after joining on the initial domain. Font/audio requests stay
on the initial domain. Error order matches request order.

## Ownership

The cache owns returned images and fonts:

- callers must not call `Image.destroy` or `Font.destroy` on borrowed values;
- `Assets.clear` releases all current resources but leaves the cache usable;
- `Assets.destroy` releases resources once and invalidates the cache;
- using a destroyed cache raises `Invalid_argument`.

For the common case, use `Sketch.run_assets`:

```ocaml
let init assets _frame =
  Assets.image_exn assets "images/character.png"

let view _assets character _frame =
  Scene.[clear Color.black; image character ~at:(40, 40) ()]

let () =
  ignore
    (Sketch.run_assets ~root:"assets"
      ~init
      ~update:(fun _assets model _frame -> model)
      ~view ())
```

The helper always destroys its cache through `Sketch.run_state ~on_stop`,
including when user initialization raises.

## Hot image iteration

`Assets.create ~watch:true` records file modification stamps. `Assets.refresh`
reloads changed images on the initial domain and swaps the new texture and
dimensions into the existing borrowed `Image.t`. This stable identity means a
model initialized once continues to draw the new file. `Sketch.run_assets
~watch:true` refreshes before each user update and retains the previous valid
texture when decode fails.

The headless integration test overwrites a cached PNG with a differently sized
image, refreshes it, and verifies both object identity and new dimensions.
Font/audio hot replacement remains separate because their active playback and
render-cache lifetimes need different handoff rules.

## Future decode extensions

Future background decoders must return plain CPU-owned buffers. They may not
touch SDL_image, SDL_ttf, renderers, textures, or cache tables. Main-domain
polling turns completed buffers into borrowed render resources. Cancellation
and invalidation must remain structured; detached domains are not permitted.
