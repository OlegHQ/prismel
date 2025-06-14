Working with positions, directions, and transformations is much easier with dedicated types for vectors and matrices. In our framework, we provide a **Vec2** module for 2D vectors (points in the plane) and a **Mat3** module for 3x3 matrices that represent 2D linear transformations (affine transforms) including translation. These modules make operations like movement, rotation, and coordinate transformations more straightforward and less error-prone.

### Vec2 Module (2D Vectors)

**Type Definition:**

```ocaml
type Vec2.t = { x: float; y: float }

```

A `Vec2.t` represents a vector or point in 2D space, with `x` and `y` components. We use `float` for coordinates to allow sub-pixel precision and smooth movement (especially important if velocities are fractional or for interpolation). This can represent a position in world coordinates, a velocity vector, etc.

**Basic Operations:**

- `Vec2.create x y : Vec2.t` – construct a vector with given components. (`let v = Vec2.create 3.0 4.0`)
- `Vec2.zero : Vec2.t` – the zero vector (0,0).
- `Vec2.unit_x : Vec2.t` = (1,0), `Vec2.unit_y : Vec2.t` = (0,1).
- `Vec2.add v1 v2 : Vec2.t` – component-wise addition (returns v1 + v2).
- `Vec2.sub v1 v2 : Vec2.t` – subtraction (returns v1 - v2).
- `Vec2.neg v : Vec2.t` – negation (returns -v).
- `Vec2.scale v s : Vec2.t` – multiply vector v by scalar s (scales both components).
- `Vec2.dot v1 v2 : float` – dot product = v1.x \* v2.x + v1.y \* v2.y. Useful for projections, angle between vectors, etc.
- `Vec2.length v : float` – magnitude of v = sqrt(x^2 + y^2).
- `Vec2.length_sq v : float` – squared magnitude (avoids sqrt if comparing lengths).
- `Vec2.normalize v : Vec2.t` – returns a unit vector in same direction as v (i.e., scales v to length 1). If v is zero, returns zero vector (or we could return an option to indicate cannot normalize zero, but returning zero is fine practically).
- `Vec2.distance v1 v2 : float` – distance between points v1 and v2 (just length of (v2 - v1)).
- `Vec2.angle v : float` – angle (in radians) of vector v relative to the positive X axis. Implemented with `atan2(v.y, v.x)` which gives an angle from -π to π.
- `Vec2.rotate v theta : Vec2.t` – rotate vector v by angle theta (radians) around origin (0,0). Uses rotation matrix \[cosθ -sinθ; sinθ cosθ] \* (v.x, v.y).
- `Vec2.lerp v1 v2 t : Vec2.t` – linear interpolate between vectors v1 and v2 by t (as discussed in Math.lerp, but for vectors). Returns v1 + (v2 - v1) \* t.

All these functions treat vectors immutably (return new vectors, do not modify inputs). This fits OCaml’s preference for immutability and the typical usage in functional code (just like floats, one doesn’t mutate them, one produces new values).

We might also implement an equality check `Vec2.equal v1 v2` with a tolerance for floating error, but often direct equality isn’t useful due to floating precision. Usually, one compares squared distance < epsilon^2 if needed. We can provide `Vec2.nearly_equal v1 v2 ~eps:float`.

**Use Cases:**

- Movement: if an object has position `p` and velocity `v`, you can update position by `p <- Vec2.add p (Vec2.scale v dt)`.
- Collision: check distance between objects A and B: `Vec2.distance a.pos b.pos < (a.radius + b.radius)` for collision detection.
- Direction: to make an object face another, compute `let d = Vec2.sub target.pos self.pos in let angle = Vec2.angle d` to get the direction angle.
- Rotating a point around origin or around another point: use `Vec2.rotate` (and if around another point, translate, rotate, translate back).

**Integration with other modules:**

- The Graphics module currently expects int coords for drawing. One can easily convert a Vec2 to int pair when drawing: e.g., `Graphics.circle ~center:(int_of_float v.x, int_of_float v.y) ...`. We might provide `Vec2.to_pair vec : (int*int)` rounding or truncating appropriately. Possibly we should allow Graphics functions to accept `Vec2.t` directly for convenience, but to keep the core simple, we didn’t do function overloading; we could add separate functions or simply rely on conversion in user code.
- Physics or game logic will benefit from using Vec2 for positions and velocities instead of managing separate x and y floats and constantly writing things like `x += vx*dt; y += vy*dt`. With Vec2: `pos <- Vec2.add pos (Vec2.scale vel dt)`.

**Performance Considerations:**

- Creating a lot of small records (like Vec2 for every frame’s positions) is generally fine. The GC handles short-lived small allocations efficiently. If an application has thousands of vectors, one might worry, but typically these are in state and reused.
- We could optimize by not using a record but instead a tuple or even external library like Bigarray for vectors, but the overhead for our scales is not worth the complexity. Simplicity and clarity of record fields `x,y` is good.

**Example:**

```ocaml
let p = Vec2.create 100.0 50.0
let q = Vec2.create 130.0 70.0
let d = Vec2.distance p q             (* compute distance between p and q *)
let dir = Vec2.normalize (Vec2.sub q p)
(* 'dir' is a unit vector pointing from p to q *)
let new_p = Vec2.add p (Vec2.scale dir 10.0)
(* move p 10 units towards q *)

```

In this example, we got a direction vector and moved point p along that direction. This shows how expressive vector operations can be, making the code closer to mathematical notation.

### Mat3 Module (2D Transformation Matrices)

**Type Definition:**
We represent a 3x3 matrix. A 3x3 homogeneous transformation matrix for 2D has the form:

```
[ a  c  tx ]
[ b  d  ty ]
[ 0  0   1 ]

```

This can represent rotation, scale, shear (through a,b,c,d), and translation (tx, ty). The last row is always \[0 0 1] for affine transforms (no projective warp). We need 3x3 to include translation in the matrix multiplication.

We can define `type Mat3.t = { m11; m12; m13; m21; m22; m23; m31; m32; m33 : float }`. Or use an array \[9] or `float array array`. For simplicity, we could use a record with 6 floats for the meaningful ones (since m31,m32 are always 0 and m33=1 for affine). But maybe keep full 9 for generality and ease of certain operations like inversion.

**Construction:**

- `Mat3.identity : Mat3.t` – the identity matrix (no transform). Numerically: (1,0,0, 0,1,0, 0,0,1).
- `Mat3.translation tx ty : Mat3.t` – matrix that translates by (tx, ty). That matrix is (1,0,tx; 0,1,ty; 0,0,1).
- `Mat3.scale sx sy : Mat3.t` – scaling matrix (sx, 0, 0; 0, sy, 0; 0,0,1).
- `Mat3.rotation theta : Mat3.t` – rotation by angle theta (radians). Matrix: (cosθ, -sinθ, 0; sinθ, cosθ, 0; 0,0,1).
- `Mat3.shear sx sy : Mat3.t` – (optional) shear matrix (1, sx, 0; sy, 1, 0; 0,0,1) for skewing.

**Operations:**

- `Mat3.mul m1 m2 : Mat3.t` – matrix multiplication (compose transformations). Note: if we consider column vectors, then to apply m1 then m2 to a vector v, the resulting transform matrix is `m2 * m1`. We must be clear about order. Typically we consider the vector as a column on right: v' = M \* v. Then if we want do T then R to v, we do v' = R \* (T \* v) = (R \* T) \* v. So to compose "first do m1, then m2", we compute `Mat3.mul m2 m1`. We should document that our Mat3.mul returns a matrix that first applies the second argument, then the first argument (or define it opposite). Actually, it might be simpler to say `Mat3.mul a b` yields matrix = a \* b (in linear algebra terms). Then if you want to apply a then b, you do Mat3.mul b a. This could confuse; perhaps better:
  - We might not emphasize too much; just define clearly: we use conventional matrix multiplication rules. The user might not need to directly multiply matrices often; they can use our provided transforms and push/pop in Graphics for easier composition.
- `Mat3.transform m (x,y) : Vec2.t` – apply matrix `m` to point `(x,y)` (treating the point as homogeneous (x,y,1)). This yields a new Vec2: (a*x + c*y + tx, b*x + d*y + ty). This is crucial for transforming coordinates (like converting from world to screen).
- `Mat3.combine ~translate:(tx,ty) ~rotate:θ ~scale:(sx,sy)` – we might provide a helper to build a matrix from combined operations (applied in a certain order, e.g., scale then rotate then translate which is common). But since we have separate constructors and Mat3.mul, user can do:
  ```ocaml
  let m = Mat3.mul (Mat3.translation tx ty) (Mat3.rotation theta |> Mat3.mul (Mat3.scale sx sy))

  ```
  That example first scales, then rotates, then translates.
- `Mat3.inv m : Mat3.t` – compute the inverse transform (if not singular). For an affine matrix, we can derive the inverse easily if determinant non-zero. We'll implement it so the user can get a matrix that undoes m. Useful e.g., converting screen coordinates back to world by using inverse of camera transform.
- We might also define `Mat3.of_mat2 a b c d` for matrix from just rotation/scale part (with no translation).
- If needed, `Mat3.equal` to compare (with tolerance).

**Using Mat3 in Graphics:**

- As described in Graphics section, we maintain a current transformation matrix that starts as identity each frame. When user calls Graphics.translate/rotate, we actually multiply the current matrix by the respective transform matrix. We push it on stack via push_matrix. That stack is essentially storing Mat3’s. In implementation, we likely store an array of Mat3, or simply push a copy of current matrix on OCaml list, etc.
- When drawing shapes, we could multiply their coordinates by the current matrix to get actual screen coordinates. But actually, SDL2 doesn’t support applying a custom matrix directly to primitives (it has RenderGeometry for textured polygons, but not for all shapes). So if a transform is active, we have to either:
  - Compute transformed coordinates ourselves for each shape (like transform all vertices of a polygon or endpoints of a line) then call SDL to draw.
  - Or use SDL_RenderSetLogicalSize / SetViewport incorrectly to simulate (not general).

Given moderate complexity, likely we do manual transform:

- E.g., if current matrix is M and user calls Graphics.circle at center (x,y), we transform (x,y) by M to get (x',y'). For rotation/scale, a circle might become an ellipse if non-uniform scale or rotate off-axis (but then it's not a circle strictly). If we allow non-uniform scale, drawing a perfect circle after scale in x vs y yields an ellipse – our immediate mode can’t draw ellipses easily except by polygon approximations. So that’s a limitation: using transform to scale shapes that are drawn by fixed algorithms might distort them not easily supported by SDL’s primitive draws.
- For moderate usage (rotating the whole scene, or uniform scaling, or translating), it works fine (circle stays circle if uniform scale, just bigger or moved).
- We will mention: if non-uniform scaling or shearing is used, primitive shapes might not render as the mathematically exact result, since we do not fully support that (we might approximate or ignore shear for shape drawing, focusing on rotation and uniform scale which we can handle by adjusting coordinates or radius).

Alternatively, one could implement a quick fudge: e.g. for scale (sx, sy), if drawing a circle, we could draw it as an ellipse by scaling radius in x or y direction. That means drawing many points, not ideal. But since transform is advanced usage, a user wanting a rotated rectangle or rotated line – those we can handle by transforming endpoints easily (lines become lines between transformed endpoints, rotated rect can be drawn via 4 lines connecting transformed corners).

In any case, the Mat3 concept is beneficial for the architecture and advanced use. Contributors implementing transforms in Graphics must use Mat3 for the math.

**Example (Combining transforms manually):**

```ocaml
let m1 = Mat3.translation 100. 0.
let m2 = Mat3.rotation (Float.pi /. 2.0)
let m = Mat3.mul m2 m1    (* first translate, then rotate 90deg *)
let v = Vec2.create 10.0 0.0
let v' = Mat3.transform m v
(* v = (10,0), after m: first translated by (100,0) -> (110,0), then rotated 90° about origin -> (0,110)
   so v' should be (0,110). *)

```

We would verify that sequence. Since rotation is about origin, the translation’s effect got rotated. If we wanted rotate then translate, we’d do `m = Mat3.mul m1 m2`.

**Precision & Efficiency:**

- Matrix multiplication is 9x9 operations (or effectively 6 significant values if last row fixed). That’s trivial computationally, even if done many times per frame (like push/pop often).
- Inversion of 2D affine is straightforward and quick.
- Using float is fine; no significant precision issues for typical coordinate ranges (floats can exactly represent up to 2^53 \~ 9e15, we are only dealing with screen coordinates maybe up to 1e4, well within safe integer range).
- If chain multiplications become large (like applying 100 transforms), it’s fine – maybe some slight floating error, but minor.

**Conclusion:** The Vec2 and Mat3 modules empower users and internal code with clear and concise operations for geometry. They reduce errors (less manual math spread in code) and improve readability (Vec2.add vs writing `{ x = a.x +. b.x; y = a.y +. b.y }` every time). They also conceptually connect with how artists and game devs think (points, vectors, transforms) rather than raw numbers.

These modules remain fully functional (no mutation; one can make a copy of a vector or matrix if needed but generally one just uses them and discards old ones if changed). If performance of vector heavy code is a concern, one could consider using a mutable record for vector to update in place, but that sacrifices clarity and thread safety (which might not be a big issue here). For now, we prioritize clarity and the overhead is negligible for typical use.
