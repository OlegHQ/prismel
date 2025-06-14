## Color Module (Color System)

**Data Type:** The Color module defines a `Color.t` type representing an RGBA color. Internally, this can be a record or tuple of four components. We choose a record for clarity:

```ocaml
type Color.t = { r: int; g: int; b: int; a: int }
```

with each component in the 0–255 range. This matches the 8-bit per channel representation common in SDL and many graphics systems (0 = no intensity, 255 = full intensity for that channel). By using ints 0–255, we avoid floating-point rounding issues and align with SDL’s expectations (SDL rendering functions expect bytes for colors).

**Constructors:** The module provides functions to easily create colors:

- `Color.rgb r g b : Color.t` – creates an opaque color with the given red, green, blue values (alpha defaults to 255). For example, `Color.rgb 255 0 0` yields pure red.
- `Color.rgba r g b a : Color.t` – creates a color with all four components specified (including alpha transparency, where 0 = fully transparent, 255 = fully opaque).
- `Color.gray x : Color.t` – convenience for shades of gray (sets r=g=b=x, alpha=255).
- `Color.from_hex hex : Color.t` – if the user has a hex code (e.g., 0xFF00FF for magenta), this function can convert it to a Color.t (treating highest byte as red, next as green, etc.). This is useful when copying colors from design tools or web formats.

**Predefined Colors:** For quick use, the module defines constants for common colors (as `Color.t` values), such as:

- `Color.black`, `Color.white`
- `Color.red`, `Color.green`, `Color.blue`
- `Color.yellow`, `Color.cyan`, `Color.magenta`
- Perhaps a few grayscale levels or others (these are essentially sugar for `Color.rgb ...` calls).

These are provided as easy starting points or for when one just needs a basic color without manually entering values.

**Operations:** Functions to manipulate colors:

- `Color.with_alpha c a : Color.t` – returns a copy of color `c` with the alpha channel set to `a` (0–255). This is useful to adjust transparency of an existing color.
- `Color.to_tuple c : int * int * int * int` – in case one needs to pattern-match or interface with something that expects a 4-tuple.
- `Color.blend c1 c2 ~pct:float : Color.t` – blends two colors linearly by the given percentage (0.0 to 1.0). `pct = 0.0` would yield `c1`, `pct = 1.0` yields `c2`, and `pct = 0.5` a 50/50 mix. This is handy for gradients or transitions.
- `Color.lighten c f : Color.t` – makes color `c` lighter by factor `f` (0.0 to 1.0), blending towards white by that fraction. Similarly, `Color.darken c f` blends towards black.
- `Color.invert c : Color.t` – returns the complementary color (255-r, 255-g, 255-b, same alpha), if needed for effect or contrast.

These operations do not mutate the input color (since `Color.t` is immutable). They return a new `Color.t` instead.

**Usage with Graphics:** All drawing functions in the Graphics module accept a `Color.t` for color parameters. This makes it explicit what the color is, and prevents confusion like passing an integer thinking it’s a color when it might be interpreted differently. For example, `Graphics.clear Color.black` will fill the screen with black. The user can easily tweak colors by using these APIs, e.g., `Color.with_alpha Color.blue 128` to get a semi-transparent blue for drawing.

**Example:**

```ocaml
let c1 = Color.rgb 255 200 100          (* a peach color *)
let c2 = Color.rgba 0 128 255 128      (* semi-transparent light blue *)
let mixed = Color.blend c1 c2 ~pct:0.5 (* mix peach and blue equally *)
Graphics.clear mixed;                  (* clear background to the blended color *)

let outline = Color.black in
let fill = Color.with_alpha (Color.green) 150 in
Graphics.rect ~pos:(50,50) ~w:100 ~h:100 ~color:fill;            (* draw semi-transparent green square *)
Graphics.rect ~pos:(50,50) ~w:100 ~h:100 ~color:outline ~filled:false;
(* draws an outline (unfilled) black square on top *)
```

In this example, we demonstrate creation of colors and using them in drawing calls. `fill` is a translucent green (alpha 150/255), which we use to draw a filled rectangle. We then draw an outline rectangle in black. The color module made it straightforward to manage alpha and reuse base colors.

Internally, when passing colors to SDL, we will extract the `.r .g .b .a` fields. SDL’s renderer expects color as four bytes; Tsdl provides functions like `Sdl.set_render_draw_color renderer r g b a` which we will call. Thus, the Color module serves as a thin layer of type safety and utility on top of those four values.

By isolating color logic here, if we later support different color models (HSV, HSL) or need to do gamma correction, we could extend the Color module without affecting the rest of the code. For now, it operates in the standard sRGB 0-255 per channel space. Users doing advanced color calculations (like blending in linear color space) would have to convert themselves or wait for a future extension.
