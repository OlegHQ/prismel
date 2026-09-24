open Prismel

type t = {
  a : float;
  b : float;
  c : float;
  d : float;
  e : float;
  f : float;
}

let make ~a ~b ~c ~d ~e ~f =
  if
    not
      (List.for_all Float.is_finite [a; b; c; d; e; f])
  then invalid_arg "Affine2.make: coefficients must be finite";
  { a; b; c; d; e; f }

let identity = make ~a:1. ~b:0. ~c:0. ~d:1. ~e:0. ~f:0.

let translation offset =
  make ~a:1. ~b:0. ~c:0. ~d:1. ~e:offset.Vec2.x ~f:offset.y

let rotation angle =
  if not (Float.is_finite angle) then
    invalid_arg "Affine2.rotation: angle must be finite";
  let cosine = cos angle and sine = sin angle in
  make ~a:cosine ~b:sine ~c:(-.sine) ~d:cosine ~e:0. ~f:0.

let scaling scale =
  make ~a:scale.Vec2.x ~b:0. ~c:0. ~d:scale.y ~e:0. ~f:0.

let uniform_scaling amount = scaling (Vec2.create amount amount)

let shear amount =
  make ~a:1. ~b:(tan amount.Vec2.y)
    ~c:(tan amount.x) ~d:1. ~e:0. ~f:0.

let compose outer inner =
  {
    a = (outer.a *. inner.a) +. (outer.c *. inner.b);
    b = (outer.b *. inner.a) +. (outer.d *. inner.b);
    c = (outer.a *. inner.c) +. (outer.c *. inner.d);
    d = (outer.b *. inner.c) +. (outer.d *. inner.d);
    e = (outer.a *. inner.e) +. (outer.c *. inner.f) +. outer.e;
    f = (outer.b *. inner.e) +. (outer.d *. inner.f) +. outer.f;
  }

let apply transform point =
  Vec2.create
    ((transform.a *. point.Vec2.x) +. (transform.c *. point.y) +. transform.e)
    ((transform.b *. point.x) +. (transform.d *. point.y) +. transform.f)

let apply_direction transform direction =
  Vec2.create
    ((transform.a *. direction.Vec2.x) +. (transform.c *. direction.y))
    ((transform.b *. direction.x) +. (transform.d *. direction.y))

let determinant transform =
  (transform.a *. transform.d) -. (transform.b *. transform.c)

let inverse transform =
  let determinant = determinant transform in
  if abs_float determinant <= 1e-15 then None
  else
    let inverse = 1. /. determinant in
    Some {
      a = transform.d *. inverse;
      b = -.transform.b *. inverse;
      c = -.transform.c *. inverse;
      d = transform.a *. inverse;
      e =
        ((transform.c *. transform.f) -. (transform.d *. transform.e))
        *. inverse;
      f =
        ((transform.b *. transform.e) -. (transform.a *. transform.f))
        *. inverse;
    }

let coefficients value =
  value.a, value.b, value.c, value.d, value.e, value.f
