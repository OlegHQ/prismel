# Images and native textures

`Image.t` is an opaque, explicitly owned image resource. It preserves logical
width and height, RGBA8 content, stable identity, and a generation counter
inside the private resource layer. Public code never receives an SDL3 surface,
Metal texture, OGPU handle, or native pointer.

## Construction and loading

```ocaml
val load : string -> (Image.t, string) result
val load_exn : string -> Image.t
val create : width:int -> height:int -> ?color:Color.t -> unit -> Image.t
val get_width : Image.t -> int
val get_height : Image.t -> int
val get_size : Image.t -> int * int
val destroy : Image.t -> unit
```

`Image.load` reads a still image with SDL3_image and copies the decoded result
into tightly packed RGBA8 storage. Supported formats follow the qualified
SDL3_image build. Missing files, malformed data, invalid dimensions, and native
allocation failures return contextual errors without publishing a partial
resource. `load_exn` is the prototyping convenience that raises on the same
error.

`Image.create` allocates a checked RGBA8 image and initializes every pixel to
the supplied color, or transparent black by default. Dimensions must be
positive and their byte cardinality must fit the supported integer range.

Decode and native-resource work execute on the initial domain. Parallel asset
preparation may read ordinary file bytes, but SDL3_image decode and Metal upload
join back to the initial domain.

## Drawing and snapshots

The high-level path is pure scene construction:

```ocaml
Scene.image image ~at:(x, y) ~scale:2. ~angle ()
```

`Scene.image` records image identity and generation in the immutable scene.
The effect boundary resolves that snapshot into a checked OGPU sampled resource
and retains it through Metal command completion. The `Low.Graphics` compatibility
functions `draw_image`, `draw_sub_image`, and `draw_image_ex` record into the
same native command path; they do not own a second renderer.

`Canvas.to_image` returns a new owned image snapshot. Internal stable-identity
copying can refresh an existing same-sized image without allocating another
wrapper. Native readback is explicit through `Canvas.capture`; ordinary image
drawing never reads pixels back from the GPU.

## Watched assets

`Sketch.run_assets ~watch:true` tracks source stamps between frames. A
successful reload replaces content while preserving the borrowed `Image.t`
identity and advancing its generation. Decode failure preserves the last valid
pixels and generation. This makes watched images safe to retain in immutable
models and bounded caches.

Values borrowed from `Assets.t` are destroyed by the asset owner. Directly
loaded or created images are owned by the caller and belong in
`Sketch.run_state ~on_stop`:

```ocaml
let on_stop model = Image.destroy model.sprite
```

Destruction is idempotent. Stale resource use is rejected at the checked native
boundary, and command completion retains submitted resources long enough for
in-flight GPU work.

## Performance contract

Image storage is packed rather than a boxed per-pixel OCaml structure. Stable
identity plus generation-based invalidation lets renderer caches reuse unchanged
uploads. Changing content invalidates only the affected resource generation;
unreachable or destroyed images do not keep native textures alive indefinitely.
