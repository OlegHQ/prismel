(* Mathematics Utilities Module *)

(* Constants *)
let pi = 3.141592653589793
let two_pi = 2.0 *. pi
let half_pi = pi /. 2.0
let e = 2.718281828459045

(* Angular Conversions *)
let deg_to_rad deg = deg *. pi /. 180.0
let rad_to_deg rad = rad *. 180.0 /. pi

(* Rounding and Clamping *)
let clamp_float x ~min ~max =
  if x < min then min
  else if x > max then max
  else x

let clamp_int x ~min ~max =
  if x < min then min
  else if x > max then max
  else x

let clamp x ~min ~max =
  if x < min then min
  else if x > max then max
  else x

let to_int x = int_of_float (Float.floor (x +. 0.5))

(* Interpolation and Mapping *)
let lerp a b t = a +. (b -. a) *. t

let inv_lerp x a b = 
  if abs_float (b -. a) < Float.epsilon then 0.0
  else (x -. a) /. (b -. a)

let map x ~in_min ~in_max ~out_min ~out_max =
  let t = inv_lerp x in_min in_max in
  lerp out_min out_max t

let map_clamped x ~in_min ~in_max ~out_min ~out_max =
  let x_clamped = clamp_float x ~min:in_min ~max:in_max in
  map x_clamped ~in_min ~in_max ~out_min ~out_max

(* Random Utilities *)
let random_float max = Random.float max

let random_range lo hi = lo +. Random.float (hi -. lo)

let random_int n = Random.int n

let random_bool () = Random.bool ()

let choose = function
  | [] -> failwith "Math.choose: empty list"
  | lst -> 
    let len = List.length lst in
    List.nth lst (Random.int len)

(* Trigonometry *)
let sin_deg theta = Float.sin (deg_to_rad theta)
let cos_deg theta = Float.cos (deg_to_rad theta)

(* Other Math Functions *)
let hypot x y = Float.sqrt (x *. x +. y *. y)

let sign x =
  if x > 0.0 then 1.0
  else if x < 0.0 then -1.0
  else 0.0

let smoothstep t =
  let t_clamped = clamp_float t ~min:0.0 ~max:1.0 in
  t_clamped *. t_clamped *. (3.0 -. 2.0 *. t_clamped)

(* Angle utilities *)
let normalize_angle theta =
  let rec normalize t =
    if t > pi then normalize (t -. two_pi)
    else if t <= -.pi then normalize (t +. two_pi)
    else t
  in
  normalize theta

let angle_of_vec (vx, vy) = Float.atan2 vy vx

let distance (x1, y1) (x2, y2) =
  let dx = x2 -. x1 in
  let dy = y2 -. y1 in
  hypot dx dy

(* Collision/Geometry Helpers *)
let point_in_rect (px, py) (rx, ry, rw, rh) =
  px >= rx && px <= rx +. rw && py >= ry && py <= ry +. rh

let rect_overlap (x1, y1, w1, h1) (x2, y2, w2, h2) =
  not (x1 +. w1 < x2 || x2 +. w2 < x1 || y1 +. h1 < y2 || y2 +. h2 < y1)

let point_in_circle (px, py) (cx, cy, radius) =
  let dx = px -. cx in
  let dy = py -. cy in
  dx *. dx +. dy *. dy <= radius *. radius

(* Initialize random seed *)
let () = Random.self_init ()
