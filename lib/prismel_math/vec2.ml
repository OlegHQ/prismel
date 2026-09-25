type t = { x : float; y : float }
let create x y = { x; y }
let zero = { x=0.; y=0. }
let unit_x = { x=1.; y=0. }
let unit_y = { x=0.; y=1. }
let add a b = { x=a.x+.b.x; y=a.y+.b.y }
let sub a b = { x=a.x-.b.x; y=a.y-.b.y }
let neg a = { x=(-.a.x); y=(-.a.y) }
let scale a value = { x=a.x*.value; y=a.y*.value }
let dot a b = a.x*.b.x +. a.y*.b.y
let length_sq a = dot a a
let length a = sqrt (length_sq a)
let normalize a = let value=length a in if value=0. then zero else scale a (1./.value)
let distance a b = length (sub a b)
let angle a = atan2 a.y a.x
let rotate a value = let c=cos value and s=sin value in
  { x=a.x*.c-.a.y*.s; y=a.x*.s+.a.y*.c }
let lerp a b value = add a (scale (sub b a) value)
let nearly_equal a b ~eps = abs_float(a.x-.b.x)<=eps && abs_float(a.y-.b.y)<=eps
let to_pair a = int_of_float a.x, int_of_float a.y
let to_pair_float a = a.x,a.y
let of_pair (x,y) = {x=float x;y=float y}
let of_pair_float (x,y) = {x;y}
let to_string a = Printf.sprintf "(%g, %g)" a.x a.y
