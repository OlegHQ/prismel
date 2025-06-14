# Mathematics Utilities (Math Module)

The Math module provides common mathematical functions and definitions that are useful in graphics and animation programming, complementing OCaml’s standard library and avoiding the need for users to reinvent basic calculations.

**Constants:**

- `Math.pi` – The value of π (3.141592653589793).
- `Math.two_pi` – 2π, and perhaps `Math.half_pi` (π/2) for convenience.
- `Math.e` – Euler’s number 2.71828, if needed (less common in graphics, but provided for completeness).
- These are provided as `float` constants. OCaml 4.08 introduced `Float.pi`, but we define our own for users on older versions or just for namespace consistency.

**Angular Conversions:**

- `Math.deg_to_rad deg : float` – convert degrees to radians (multiplying by π/180).
- `Math.rad_to_deg rad : float` – convert radians to degrees (multiplying by 180/π).
- These are helpful since input might come in degrees (e.g., a 45° rotation) but our internal trig functions expect radians (OCaml’s trigonometric functions use radians).
- Additionally, we might define common angles in radians: e.g., `Math.pi_over_4` for 45°, etc., but deg_to_rad covers that.

**Rounding and Clamping:**

- `Math.clamp x ~min ~max : 'a -> 'a` – clamps numeric value `x` to the interval \[min, max]. If x is less than min, returns min; if more than max, returns max; otherwise x. We can make it polymorphic and require a comparison (using an `'a -> 'a -> int` compare function) for generality, but typically we use it for floats or ints, so we might provide `clamp_int` and `clamp_float` specialized to avoid confusion.
- Example: `Math.clamp (player.x) ~min:0 ~max:(Window.width() - player.width)` ensures the player stays on screen.
- `Math.round f : int` – maybe provide because `Float.round` returns float. Or `Math.floor`, `Math.ceil` as shorthand to `Float.floor` etc. But since OCaml’s standard library has these (in Float module for float calculations), we might not duplicate too many. We can re-export some if desired under Math for convenience.

**Interpolation and Mapping:**

- `Math.lerp a b t : float` – linear interpolate between values `a` and `b` by fraction `t` (0 ≤ t ≤ 1). Returns `a + (b - a) * t`. Useful for smoothly transitioning values (for position, color, etc.). For example, to interpolate between 0 and 10 over time, one might compute t = elapsed/duration and then x = Math.lerp x0 x1 t.
- If we want `lerp` for vectors or colors, we might overload or provide separate functions (e.g., `Vec2.lerp` for vectors).
- `Math.inv_lerp x a b : float` – the inverse linear interpolation: given a value x in \[a,b], return the fraction t in \[0,1] such that lerp(a,b,t) = x. Essentially `(x - a) / (b - a)`. Can be useful for normalization (e.g., what fraction of the progress is the current value).
- `Math.map x ~in_min ~in_max ~out_min ~out_max : float` – map a value from one range to another. Equivalent to `out_min + (x - in_min) * (out_max - out_min) / (in_max - in_min)`. This is extremely handy in creative coding (e.g., map a sensor value 0–1023 to screen coordinates 0–800). We will clamp the result or not depending if we want to allow extrapolation; perhaps provide `map_clamped` variant that first clamps x to \[in_min, in_max] then maps.
- Ex: `Math.map (sin t) ~in_min:(-1.0) ~in_max:1.0 ~out_min:0.0 ~out_max:255.0` would convert a sine output to a 0-255 range.

**Random Utilities:**

- We can re-export OCaml’s Random in a more user-friendly way:
  - `Math.random_float max` and `Math.random_range lo hi` to get random floats in \[0, max) or \[lo, hi).
  - `Math.random_int n` for \[0, n).
  - `Math.random_bool ()`.
- Possibly `Math.perlin2d x y` or some noise function if we want to include a simple noise generator (could be a bit involved; maybe leave it out initially).
- If using Random, we might seed it by default (OCaml Random is seeded with time by default if not, but it’s often good to call `Random.self_init` or allow user to set seed for reproducibility).
- `Math.choose list` – pick a random element from a list or array, if that’s something often needed (like picking a random color from a palette). Not essential but easy to add.
- These are convenience; the user could just use Random directly, but having them under Math means not having to open Random or add another open.

**Vector and Matrix Operations:** (Though these are in Vec2/Mat3 modules, we mention as part of “math subsystem”)

- See next section for detailed Vec2 and Mat3, but in context:
  - `Math.distance (x1,y1) (x2,y2)` – distance between two points (maybe in Vec2 module).
  - `Math.angle_of_vec (vx,vy)` – angle of a vector (returns radian angle from x-axis).
  - `Math.normalize_angle theta` – wrap angle into \[-π, π] or \[0,2π] range.
  - These might reside in Vec2 or here.

**Trigonometry and other functions:**

- We won’t re-implement sin, cos, etc., because OCaml’s `Float.sin` etc. do that. But we might include alias functions for convenience:
  - `Math.sin_deg theta` – sin of an angle given in degrees (just does sin(deg_to_rad theta)).
  - `Math.cos_deg theta` similarly.
  - This can save the user from converting degrees to rad in their code if they prefer degrees.
- `Math.hypot x y` – return √(x^2 + y^2), (the length of vector (x,y)), akin to Pervasives.hypot if we want.
- `Math.sign x` – sign of number as -1, 0, 1 (for quick directional decisions).
- `Math.smoothstep t` – as mentioned, returns t^2 \* (3 - 2t) for t in \[0,1], an ease curve useful for animations.

**Collisions/Geometry:**

- Possibly, add geometry helpers:
  - `Math.point_in_rect (px,py) (rx,ry,rw,rh) -> bool`.
  - `Math.rect_overlap rect1 rect2 -> bool` (AABB collision).
  - `Math.point_in_circle (px,py) (cx,cy,radius) -> bool`.
  - These can help in games (like checking if a click is inside a button, or if two objects collided).
  - If included, likely part of Math or a separate Collision module. Given their simplicity, including a couple in Math is fine.

**Precision:** Most math here will be in `float`. We should mention that for coordinates we typically use int pixels; but for internal calculations, floats are used for smoother movement. E.g., an object’s position can be a float (it might move 0.5 px per frame and accumulate until it actually moves an int pixel on screen). When drawing, we round or truncate float positions to int. This is typical: physical simulation might be float, but rasterizing is int.
We could provide `Math.to_int x = int_of_float (floor (x + 0.5))` for rounding to nearest int, or just rely on OCaml’s int_of_float which truncs (which is fine, or use Float.round to nearest int but careful with .5 cases).

**Example usage:**

```ocaml
let vx = 100.0 in
let angle = 30.0 in
let vx_x = vx *. Math.cos_deg angle
let vx_y = vx *. Math.sin_deg angle
(* vx_x, vx_y is a vector of length 100 in direction 30 degrees *)

(* Map player health (0-100) to color from red to green *)
let health_color =
  let pct = Math.clamp (player.health /. 100.0) ~min:0.0 ~max:1.0 in
  Color.rgb
    (int_of_float (Math.lerp 255. 0. pct))    (* red goes from 255 to 0 *)
    (int_of_float (Math.lerp 0. 255. pct))    (* green goes 0 to 255 *)
    0
(* At full health pct=1 -> Color.rgb 0 255 0 (green), at 0 health pct=0 -> red *)

```

In this snippet, we see `cos_deg` and `sin_deg` let us use a 30° angle directly. We see clamping and lerping to create a color gradient based on health percentage. The Math utilities help avoid manual formulas or magic numbers in user code, making it more readable and less error-prone.

Overall, the Math module collects those one-liner utility functions that are very common in creative coding. By providing them, we help users (especially those coming from languages like Processing or openFrameworks, which have ofMap, ofClamp, etc.) get up to speed quickly. It also ensures consistency (everyone using the same `map` function, rather than each implementing slightly differently).
