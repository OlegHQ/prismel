## Image Module (Images and Textures)

The Image module handles loading, storing, and basic manipulation of raster images (bitmap graphics). It works with SDL’s image library (SDL_image, via Tsdl_image) to support common file formats (PNG, JPEG, BMP, etc.) and integrates with SDL’s textures for efficient drawing.

**Image Type:**

```ocaml
type Image.t = {
  texture : Sdl.texture;   (* SDL texture handle *)
  width : int;
  height : int;
}
```

The `Image.t` record contains an SDL texture (an accelerated image stored on the GPU) along with its dimensions. We keep width and height cached so we don’t have to query the texture (which we could with `Sdl.query_texture`) repeatedly.

We will treat `Image.t` opaquely in the interface (no direct manipulation by user; they use our functions).

**Loading Images:**

- `Image.load filename : (Image.t, string) result` – Loads an image from disk into an `Image.t`. It returns `Error msg` if loading fails (e.g., file not found or unsupported format, with `msg` describing the error). Under the hood:

  1. Use Tsdl_image to load the file into an `Sdl.surface` (software image in RAM). For example, `Img.load "file.png"`.
  2. If successful, get the surface’s width, height.
  3. Create an `Sdl.texture` from that surface: `Sdl.create_texture_from_surface renderer surface`.
  4. Free the surface to reclaim memory.
  5. Package the texture into `Image.t` and return.
     If any step fails, retrieve SDL error with `Sdl.get_error` (Tsdl returns it in `Error (`Msg e)`format automatically) and return`Error e\`.

  This means an `Image.t` is tied to the SDL renderer it was created with (the current window’s renderer). If we had multiple windows with separate renderers, an image would need separate textures for each. But in our design, one renderer, so it’s fine.

- `Image.load_exn filename : Image.t` – like load but raises an exception with message on failure. Provided for convenience (some might prefer to not handle result every time when prototyping).

- We might also allow creating an empty image:

  - `Image.create ~width ~height ~color:Color.t option -> Image.t` – create a blank image (maybe filled with given color or transparent if none). Implementation: create an SDL_Surface of given size with RGBA format, maybe fill it, then create texture. This is useful for drawing to it off-screen or manual pixel editing.

**Saving Images:**

- `Image.save image filename : (unit, string) result` – Save the image to disk (format by filename extension). We can use SDL_image’s saving functions for PNG or BMP. Not all formats can be saved by SDL_image (I think it supports BMP and maybe PNG if built with libpng). We’ll at least support PNG or BMP. Implementation: we might need to get the pixel data out of the texture. SDL provides `Sdl.render_read_pixels` to read from current render target (which could be the window). However, reading from a texture not currently set as render target might require copying. Simpler: we could have stored the surface originally, but we freed it. Alternatively, we can call `Sdl.create_surface_from` the texture, or use `Sdl.lock_texture` if possible. These steps can be complex and slow. Perhaps we’ll not emphasize save in core or limit to simple cases (like we could track an internal surface for each image if we intend to allow pixel ops and saving).
- Possibly skip implementing save for now, or only implement if Tsdl_image offers a direct `Img.save_png surface filename`.

**Drawing Images:**
We already covered in Graphics: `Graphics.draw_image (img: Image.t) ~pos` uses the `img.texture` and calls `Sdl.render_copy` with no src (meaning entire image) and a dest rect at pos with size = image’s width,height. If scaling is needed, we can allow user to specify a different dest rect.

**Pixel Access:**
One might want to get or set individual pixels of an image (e.g., for image processing or generating dynamic textures). Accessing pixels on the GPU (texture) is slow. The typical way is to manipulate an SDL_Surface (CPU copy) and then re-upload as texture.
Potential approaches:

- We keep an `Sdl.surface` inside Image.t as well (like openFrameworks has ofPixels and ofTexture; ofImage wraps both). That doubles memory usage but allows easy pixel ops. The user could call `Image.lock img` to access a pixel array, then `Image.unlock img` to update texture.
- Or simpler, provide:

  - `Image.to_pixels img : (int * int * int * int) array array` or a Bigarray of bytes. This would read back pixels from the texture (with `Sdl.render_read_pixels` or if we saved the surface originally, just get them from there). This is an expensive operation if done frequently, but fine for a snapshot.
  - `Image.get_pixel img (x,y) : Color.t` – we can do a slow path: if we have no surface, call `Sdl.render_read_pixels` for a 1x1 region, but that's very slow. Ideally, we encourage the user to not do per-pixel calls on GPU textures frequently.
  - `Image.set_pixel img (x,y) color : unit` – similar issues; better to manipulate a surface.

Given complexity, we might either:

- Document that this version of the framework is not optimized for per-pixel operations on images; if needed, consider storing your own array of pixel data and constructing a new Image from it.
- Or implement a basic approach: keep the original surface around if `Image.lockable` or on user request.

For specification brevity, we can say:

- The framework currently provides limited direct pixel access. `Image.to_surface` could return an SDL_surface or pixel array if needed. Pixel-level manipulation might be added in a future iteration.

**Memory management:**

- `Image.destroy img : unit` – Frees the SDL texture (and any surface if we stored one). The user should call this when they no longer need an image to release GPU memory. If they forget, the resources will be freed when the program exits (SDL will free textures on renderer destruction), but for long-running apps or if loading many images dynamically, it’s important. After `destroy`, using that Image.t in draw would be invalid (we could mark texture = None or something to avoid accidental use).
- We might also use finalizers: call `Sdl.destroy_texture` in a GC finalizer for Image.t if not already destroyed. But finalizer timing is uncertain, so explicit destroy is better.
- The Sound module similarly might have a destroy for sound.

**Use Case Examples:**

_Loading and displaying an image:_

```ocaml
match Image.load "player.png" with
| Ok player_img ->
    state.player_image <- player_img
| Error msg ->
    print_endline ("Failed to load image: " ^ msg);
    (* handle error, perhaps set a default image or exit *)
```

Then in draw:

```ocaml
Graphics.draw_image state.player_image ~pos:(state.player_x, state.player_y);
```

This will put the top-left of the image at the player's position.

_Scaling or sub-images:_

```ocaml
(* Draw a thumbnail (scaled down) of an image *)
Graphics.draw_sub_image state.photo
    ~src_rect:(0,0, state.photo.width, state.photo.height)
    ~dst_rect:(50,50, state.photo.width / 4, state.photo.height / 4);
```

This draws the photo quarter-size at (50,50).

_Pixel manipulation scenario (if we had support):_

```ocaml
(* Generate a simple procedural image: e.g., a gradient *)
let img = Image.create ~width:256 ~height:256 in
for y = 0 to 255 do
  for x = 0 to 255 do
    let c = Color.rgb x y ((x+y)/2) in
    Image.set_pixel img (x,y) c
  done
done
(* Now img has a cool gradient pattern *)
```

This would be slow in pure OCaml if done pixel by pixel unless we can directly manipulate an array. If performance needed, one might get the Bigarray pointer and do it in C or something. But as a spec demonstration, it shows intention that one can create images procedurally. We may mention that for large pixel ops, linking with an optimized library or using bigarrays is advisable.

**Integration with Sound or Other:**
Not much, except if an image is loaded for an icon or something. It stands mostly independent but is used by Graphics.

**Thread Safety:**

- Loading images should be done on main thread because it uses SDL functions that may not be thread-safe (especially creating texture involves the renderer).
- If user wants to load in background, they'd have to use SDL_image to load to surface in a thread (which might be okay since that’s just decoding file), then push a task to main to create texture. We don’t manage that; we assume images are loaded in init or a safe time.

**Performance:**

- Creating a texture from a surface is fairly fast for moderate image sizes but can be noticeable if many large images are loaded at once. If a user needed to stream images (like video frames or something), ideally use one texture and update its pixels with `update_texture` each frame, but that’s advanced.
- Drawing images with SDL’s renderer is very efficient (it uses GPU acceleration). The limiting factor is fill rate and memory bandwidth on GPU for huge images or many draws, but for typical usage it's fine. The user can draw images in every frame (like sprites) with little overhead beyond the actual pixel rendering on GPU.

**Memory:**

- Each texture uses GPU memory proportional to width*height*4 bytes. If many large images are loaded, user should be mindful to destroy ones not in use.
- We might mention: Maximum texture size depends on GPU (often 8192 or 16384). If an image exceeds that, SDL_CreateTexture may fail. We should catch that error if it occurs and mention in Error message. Perhaps also mention that extremely large images might need tiling or scaling down before loading.

**Conclusion:**
The Image module simplifies image handling by abstracting away the SDL surface/texture dance. The user mostly deals with a straightforward `Image.t` after loading, which they can then draw. It follows the functional style (the user doesn’t mutate Image.t aside from through provided functions). We emphasize error handling (no crashing on missing file, but returning an Error) and resource management (the need to free images when appropriate). This enables developers to incorporate graphics into their OCaml creative projects similarly to how they would in openFrameworks (where ofLoadImage gives you an ofImage you can draw).
