type t = { x : float; y : float; z : float }
let create x y z = {x;y;z}
let zero = {x=0.;y=0.;z=0.}
let unit_x = {x=1.;y=0.;z=0.}
let unit_y = {x=0.;y=1.;z=0.}
let unit_z = {x=0.;y=0.;z=1.}
let add a b = {x=a.x+.b.x;y=a.y+.b.y;z=a.z+.b.z}
let sub a b = {x=a.x-.b.x;y=a.y-.b.y;z=a.z-.b.z}
let neg a = {x=(-.a.x);y=(-.a.y);z=(-.a.z)}
let scale a value = {x=a.x*.value;y=a.y*.value;z=a.z*.value}
let dot a b = a.x*.b.x+.a.y*.b.y+.a.z*.b.z
let cross a b = {x=a.y*.b.z-.a.z*.b.y;y=a.z*.b.x-.a.x*.b.z;
  z=a.x*.b.y-.a.y*.b.x}
let length_sq a = dot a a
let length a = sqrt(length_sq a)
let normalize a = let value=length a in if value=0. then zero else scale a (1./.value)
let distance a b = length(sub a b)
let lerp a b value = add a (scale(sub b a)value)
let nearly_equal a b ~eps = abs_float(a.x-.b.x)<=eps &&
  abs_float(a.y-.b.y)<=eps && abs_float(a.z-.b.z)<=eps
let to_vec2 (a:t) = Vec2.{x=a.x;y=a.y}
let of_vec2 a z = {x=a.Vec2.x;y=a.y;z}
let to_triple a = a.x,a.y,a.z
let of_triple (x,y,z) = {x;y;z}
let to_string a = Printf.sprintf "(%g, %g, %g)" a.x a.y a.z
