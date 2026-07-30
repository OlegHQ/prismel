## Graphics Module (2D Drawing API)

The Graphics module is responsible for all on-screen drawing of shapes, images, and text. It provides an **immediate mode** style drawing API: the user calls drawing functions each frame (typically in their `draw` callback), and those functions issue drawing commands to the window. There is no retained scene graph; if something should persist on screen, the user calls the draw function for it every frame (this is analogous to how one draws in Processing or openFrameworks’ draw loop).

**Drawing Primitives:** The module offers functions to draw basic shapes. Key functions include:

- `Graphics.clear : Color.t -> unit` – Fill the entire screen (or current rendering target) with the specified color. This is usually called at the start of each frame to clear the old frame’s contents (unless the user is drawing on top for a specific effect). Under the hood, this sets the renderer’s draw color and clears the renderer. Example: `Graphics.clear Color.black` makes the background black for the new frame.

- `Graphics.set_color : Color.t -> unit` – (Optional convenience) Set the current color for subsequent drawing calls. This would affect primitives drawn without an explicit color parameter. However, in our design, most functions expect an explicit `~color`, so using `set_color` is not usually necessary except for stateful style. We include it for completeness (mirroring stateful APIs like OpenGL’s current color), but idiomatic usage is to pass colors directly to draw calls.

- **Points and Lines:**

  - `Graphics.point : x:int -> y:int -> ?color:Color.t -> unit` – Draw a point at logical `(x, y)`. If no color is given, uses the current draw color (default white if never set). Points are rarely used except for low-level plotting or debugging.
  - `Graphics.line : x1:int -> y1:int -> x2:int -> y2:int -> ?color:Color.t -> unit` – Draw a line segment from `(x1, y1)` to `(x2, y2)` in the given color. The line is one logical unit thick by default. SDL scales its raster coverage to the backing framebuffer.
  - If needed, we might also have `Graphics.polyline : points:(int*int) list -> ?color:Color.t -> unit` to draw a series of connected lines, but the user can also just call line in a loop for that.

- **Rectangles and Squares:**

  - `Graphics.rect : pos:(int*int) -> w:int -> h:int -> ?color:Color.t -> ?filled:bool -> unit` – Draw a rectangle with top-left corner at `pos` and logical width `w`, height `h`. By default, `filled:true` (so it draws a filled rectangle). If `filled:false`, it draws only the one-logical-unit outline.
  - For a square specifically, user can just pass equal w and h or we might provide an alias `Graphics.square` for clarity, but that’s not strictly necessary.

- **Circles and Ellipses:**

  - `Graphics.circle : center:(int*int) -> radius:int -> ?color:Color.t -> ?filled:bool -> unit` – Draw a circle with given center and radius. If `filled:true` (default), draw a filled disk; if false, draw the circumference. Since SDL2 doesn’t have a native circle, our implementation will approximate a circle (for the outline, using midpoint circle algorithm or similar to draw points or short lines; for filled, perhaps radial lines or an algorithm to fill). For moderate radius this is fine. The user should be aware extremely large circles might have performance costs due to many points. (We could also consider using a textured approach or an extension library for perfect circles, but that is an internal detail.)
  - `Graphics.ellipse : center:(int*int) -> rx:int -> ry:int -> ...` could be provided for non-uniform ellipses, though it can be approximated by scaling the coordinate system or using a circle and scaling it via transform.

- **Triangles and Polygons:**

  - `Graphics.triangle : p1:(int*int) -> p2:(int*int) -> p3:(int*int) -> ?color:Color.t -> ?filled:bool -> unit` – Draw a triangle connecting the three points. Filled uses a rasterization (like two half-triangles or scanline fill), outline uses three lines.
  - `Graphics.polygon : points:(int*int) list -> ?color:Color.t -> ?filled:bool -> unit` – Draw a closed polygon connecting the list of vertices. If filled, we’d need to triangulate or use SDL_RenderGeometry (if available). This is a more advanced feature; we might initially implement a simple convex fill or leave complex fills out of scope. Outlines are straightforward (draw line between each consecutive pair and from last back to first).

All these functions take an optional `?color`. If provided, that color is used just for that call. If not provided, the current drawing color (set by `Graphics.set_color`) is used. For clarity and functional style, we encourage always providing the color, so you don’t depend on any hidden state. In examples and documentation, we will typically show the `color:` parameter being used.

**Coordinate System:** Coordinates are integer **logical points**, with the
origin `(0, 0)` at the top-left of the logical window. X increases to the right
and Y increases downward. If the configured window is `w × h`, its normal
drawing and pointer coordinates range from `0` to `w - 1` and `0` to `h - 1`
regardless of native display density. Negative or out-of-bounds geometry is
clipped rather than rejected.

The SDL renderer logical size always matches the window's logical size. SDL
scales rendered output to the current native framebuffer and filters pointer
events back through that same mapping. As a result, `Scene`, `Graphics`,
`Frame.mouse`, `Input.mouse_pos`, event positions, and PXUI hit testing remain
aligned on both 1× and Retina displays. Application code must not multiply
positions by `Frame.pixel_scale`.

`Frame.drawable_size` exposes the physical renderer output when a pixel-level
algorithm needs it, and `Frame.pixel_scale` is the ratio of native pixels to
logical points on each axis. These values can change when a window moves
between displays. Transformations build on the logical top-left coordinate
system.

**Drawing Images:** The Graphics module works with the Image module to draw images (bitmaps) onto the screen:

- `Graphics.draw_image : Image.t -> pos:(int*int) -> unit` – Draws the given image with its top-left at the specified position. It draws the whole image at its natural size (the image knows its width and height). If the image has transparency (alpha channel), that will be respected (SDL will blend it).
- `Graphics.draw_sub_image : Image.t -> src_rect:(int*int*int*int) -> dst_rect:(int*int*int*int) -> unit` – This allows more control: you can specify a source rectangle within the image and a destination rectangle on screen. This is useful for sprite sheets (drawing only a portion of an image) or scaling images (if the dst_rect size differs from the src_rect size, SDL will stretch the image accordingly). For example, `draw_sub_image sprite ~src_rect:(0,0,32,32) ~dst_rect:(100,100,64,64)` would take the top-left 32x32 block of the image and draw it doubled in size at (100,100).
- If rotation or flipping of images is needed, we may provide an extended function or parameters:

  - `Graphics.draw_image_ex : Image.t -> pos:(int*int) -> ?scale:float -> ?angle:float -> ?center:(int*int) -> ?flip:bool -> unit`. This could wrap SDL_RenderCopyEx, allowing rotation by `angle` (in degrees, about a `center` point, default center is the image center) and flipping horizontally/vertically if needed. This is an advanced usage, so we might include it for completeness but basic usage might not require it.

**Text Rendering:** `Scene.text ?size` is the default high-level text
constructor. It resolves an installed platform UI font (or the path selected by
`PRISMEL_UI_FONT`) and measures `size` in logical points. `Scene.debug_text`
selects the fixed 8×8 SDL2_gfx diagnostic face explicitly.

`Graphics.draw_text` and `Scene.font_text` use a `Font.t`. A font lazily opens a
native raster-size handle for the active renderer density and caches textures
by renderer, content, font state, layout, and raster size. Texture dimensions
are converted back to logical points before drawing. Text therefore keeps the
same layout at 1× and 2× while retaining sharp native-resolution glyphs. Each
renderer keeps at most 256 recently used text textures; empty text is accepted
and draws nothing.

**Transformations (Advanced):** The Graphics module can support changing the coordinate system via transformations:

- `Graphics.push_matrix : unit -> unit` – Save the current transform matrix on a stack.
- `Graphics.pop_matrix : unit -> unit` – Restore the last saved transform.
- `Graphics.translate : dx:int -> dy:int -> unit` – Apply a translation to the coordinate system (so subsequent drawing calls are shifted by (dx,dy)).
- `Graphics.rotate : angle:float -> unit` – Apply a rotation (in radians or degrees) to the coordinate system around the origin (0,0) or possibly around a specified pivot.
- `Graphics.scale : sx:float -> sy:float -> unit` – Scale the coordinate system (sx, sy factors).
- `Graphics.reset_transform : unit -> unit` – Return to the identity transform (undoing all translates/rotates).

These functions allow the user to draw rotated or scaled shapes without manually computing rotated coordinates. For example, one could do:

```ocaml
Graphics.push_matrix ();
Graphics.translate ~dx:cx ~dy:cy;
Graphics.rotate ~angle:(Float.pi /. 4.0);
Graphics.rect ~pos:(-50, -50) ~w:100 ~h:100 ~color:Color.blue;
Graphics.pop_matrix ();
```

This would draw a 100x100 square rotated 45° about its center `(cx, cy)`. We translate the coordinate system to the center point, rotate, draw a square centered at the origin (since we translated, origin corresponds to actual center), then pop the matrix to restore normal coordinates. Internally, these operations multiply a transformation matrix that is applied to all subsequent drawing coordinates. They affect all shapes drawn until popped. This is similar to OpenGL’s matrix stack or Processing’s pushMatrix/popMatrix. It is implemented using our Math.Mat3 under the hood.

For simplicity, many users might avoid explicit transforms and just compute positions manually, but providing this feature can simplify drawing of complex scenes (especially hierarchical scenes or repeated patterns).

**Backend Behavior:** Under the hood, the Graphics functions call Tsdl’s rendering functions:

- We maintain a reference to the SDL_Renderer (set up in Core after window creation).
- Each draw call sets the draw color (for primitive shapes) or uses textures (for images/text).
- For example, `Graphics.line` calls `Sdl.set_render_draw_color renderer (r,g,b,a)` with the given color, then `Sdl.render_draw_line renderer x1 y1 x2 y2` (which returns a result we should check).
- `Graphics.rect filled` calls `Sdl.render_fill_rect renderer rect` (with an SDL rect struct) if filled, or `Sdl.render_draw_rect renderer rect` if outline.
- `Graphics.circle` has no direct SDL call; our implementation might generate points or use `Sdl.render_draw_points` for the outline, and perhaps multiple `render_draw_line` calls to fill if needed. Performance is considered: for moderate radii (say < 100), this is fine. For large filled circles, it’s a lot of drawing – we note that if performance is an issue, one could precompute a circle in a texture and draw that as an image.
- `Graphics.draw_image` uses `Sdl.render_copy renderer image.texture None (Some dst_rect)` where dst_rect is the image’s width/height at the given position.
- All these calls are batched by SDL’s renderer internally; when we call `Sdl.render_present` at end of frame (Core does this), everything we issued gets displayed. The user doesn’t see intermediate results – they only see the final frame once presented.

**Double Buffering:** SDL’s renderer by default is double-buffered (especially with vsync). This means `Graphics.clear` and other draws operate on a back buffer. `Sdl.render_present` then flips the buffers. The user doesn’t have to manage any of this; we mention it to clarify that one should generally clear and redraw every frame, rather than expecting something drawn to persist automatically (since the back buffer might be fresh each time). If a user does not call `Graphics.clear` and just draws, the previous frame’s contents might remain (if we didn’t clear, SDL’s backbuffer might start as previous frontbuffer depending on driver). To avoid unpredictable results, we always encourage clearing or redrawing the whole scene each frame.

**Z-Order and Overlapping:** Drawing calls issued later in the frame naturally appear on top of earlier ones (since they overwrite pixels). There’s no explicit z-index; draw order = painter’s algorithm. If you draw a background rectangle and then a circle, the circle will appear above. If you reverse the calls, the rectangle will cover the circle. Therefore, the user controls what is in front by ordering the calls in `draw`. This is straightforward and typical for immediate mode rendering.

**Error Handling:** Normally, drawing operations don’t fail under normal conditions (except maybe if renderer is lost). Tsdl functions return a `unit result` which is `Error (`Msg e)`only if an error occurred (e.g., if the renderer or texture is invalid). In our framework, once the window and renderer are set up, draw calls should not error out. We may ignore or log the error if it happens (for example, if`Graphics.line`returned an error, it likely means an invalid renderer or out-of-memory in the driver). Those are fatal conditions in practice, so we might not propagate a result for each draw (for performance and simplicity). Instead, we ensure in Core that the renderer is valid and handle a lost context by reinitializing if needed (this is a rare scenario like device reset on mobile). For general use, one can assume the drawing calls always succeed and thus they return`unit`not`result\`.

**Examples:** A simple usage of Graphics in a user’s draw function:

```ocaml
let draw state =
  Graphics.clear state.background_color;
  Graphics.circle ~center:state.ball_pos ~radius:20 ~color:Color.red;
  Graphics.line ~x1:0 ~y1:0 ~x2:state.ball_pos_x ~y2:state.ball_pos_y ~color:Color.yellow;
  Graphics.draw_image state.sprite ~pos:(state.player_x, state.player_y);
  if state.show_text then
    Graphics.draw_text state.font ~pos:(10, 460) ~text:"Hello!" ~color:Color.white;
;;
```

This clears the screen to `state.background_color`, draws a red circle at the `ball_pos` (assuming that’s an (int\*int) coordinate in state), then draws a yellow line from the top-left (0,0) to the ball’s position (perhaps a trajectory line). It then draws an image (maybe a player sprite) at the player’s position, and if a flag is set, draws some text at the bottom of the window. The order ensures the sprite is drawn after the line and circle, so it will overlay them if overlapping, and text is drawn last on top of everything.

The Graphics module thus provides a straightforward set of operations for the user to compose each frame’s imagery. Internally, it manages the interaction with SDL’s renderer, but those details are hidden unless someone digs into optimizing or extending it.

By keeping the API high-level (draw shapes, images, etc. by specifying what and where), we make creative coding accessible in OCaml, leveraging the strong type system (to avoid mistakes like using a wrong type for coordinates or colors) and without needing the user to write low-level rendering code.
