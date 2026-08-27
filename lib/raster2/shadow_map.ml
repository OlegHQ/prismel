type vec3 = { x : float; y : float; z : float }
type kernel = Tap1 | Tap4 | Tap9 | Tap25
type bias = { constant : float; slope : float }
type light_kind = Directional | Spot
type error = Invalid_size | Invalid_matrix | Non_finite | Invalid_bias | Out_of_bounds
type t = { depth : Depth_stencil.t; width : int; height : int }
type prepared = { map : t; matrix : float array; bias : bias; kernel : kernel; strength : float }
type snapshot = {
  width : int;
  height : int;
  depths : float array;
  matrix : float array;
  bias : bias;
  kernel : kernel;
  strength : float;
}

let finite = Float.is_finite
let create ~width ~height =
  if width <= 0 || height <= 0 then Error Invalid_size else
  match Depth_stencil.create ~width ~height () with Error _ -> Error Invalid_size | Ok depth -> Ok { depth; width; height }
let clear (t : t) ~depth = if not (finite depth && depth >= 0. && depth <= 1.) then Error Non_finite else
  match Depth_stencil.clear t.depth ~depth ~stencil:0 with Ok () -> Ok () | Error _ -> Error Non_finite
let write (t : t) ~x ~y ~depth =
  if x < 0 || y < 0 || x >= t.width || y >= t.height then Error Out_of_bounds
  else if not (finite depth && depth >= 0. && depth <= 1.) then Error Non_finite
  else
    let state = Depth_stencil.{ depth_compare = Always; depth_write = true; stencil = None } in
    match Depth_stencil.test_and_update t.depth state ~x ~y ~depth with Ok _ -> Ok () | Error _ -> Error Out_of_bounds
let prepare ?(strength=1.) map ~light_kind ~matrix ~bias ~kernel =
  if Array.length matrix <> 16 then Error Invalid_matrix
  else if not (Array.for_all finite matrix) then Error Non_finite
  else if not (finite bias.constant && finite bias.slope && finite strength) || bias.constant < 0. || bias.slope < 0. || bias.constant > 1. || bias.slope > 1. || strength<0. || strength>1.
  then Error Invalid_bias
  else match light_kind with Directional | Spot -> Ok { map; matrix = Array.copy matrix; bias; kernel; strength }

let get_depth (map : t) x y =
  let offset = (y * Depth_stencil.pitch map.depth) + (x * 8) in
  let bytes = Depth_stencil.bytes map.depth in
  let byte n = Int32.of_int (Char.code (Bytes.get bytes (offset + n))) in
  Int32.float_of_bits Int32.(logor (byte 0) (logor (shift_left (byte 1) 8)
    (logor (shift_left (byte 2) 16) (shift_left (byte 3) 24))))
let compare (map : t) x y depth = if x < 0 || y < 0 || x >= map.width || y >= map.height then 1.
  else if depth <= get_depth map x y then 1. else 0.
let snapshot (prepared : prepared) =
  {
    width = prepared.map.width;
    height = prepared.map.height;
    depths =
      Array.init (prepared.map.width * prepared.map.height) (fun index ->
          get_depth prepared.map (index mod prepared.map.width)
            (index / prepared.map.width));
    matrix = Array.copy prepared.matrix;
    bias = prepared.bias;
    kernel = prepared.kernel;
    strength = prepared.strength;
  }
let visibility (prepared : prepared) ~position ~normal_dot_light =
  if not (finite position.x && finite position.y && finite position.z && finite normal_dot_light) then 0. else
  let m = prepared.matrix in
  let tx = position.x*.m.(0)+.position.y*.m.(1)+.position.z*.m.(2)+.m.(3)
  and ty = position.x*.m.(4)+.position.y*.m.(5)+.position.z*.m.(6)+.m.(7)
  and tz = position.x*.m.(8)+.position.y*.m.(9)+.position.z*.m.(10)+.m.(11)
  and tw = position.x*.m.(12)+.position.y*.m.(13)+.position.z*.m.(14)+.m.(15) in
  if tw <= 0. || not (finite tx && finite ty && finite tz && finite tw) then 1. else
  let x = (tx /. tw *. 0.5) +. 0.5 and y = 0.5 -. (ty /. tw *. 0.5) and z = tz /. tw in
  if x < 0. || x > 1. || y < 0. || y > 1. || z < 0. || z > 1. then 1. else
  let px = int_of_float (floor (x *. float prepared.map.width))
  and py = int_of_float (floor (y *. float prepared.map.height)) in
  let bias = prepared.bias.constant +. prepared.bias.slope *. (1. -. max 0. (min 1. normal_dot_light)) in
  let depth = z -. bias in
  let raw=match prepared.kernel with
  | Tap1 -> compare prepared.map px py depth
  | Tap4 ->
      (compare prepared.map px py depth +. compare prepared.map (px+1) py depth +.
       compare prepared.map px (py+1) depth +. compare prepared.map (px+1) (py+1) depth) *. 0.25
  | Tap9 ->
      (compare prepared.map (px-1) (py-1) depth +. compare prepared.map px (py-1) depth +.
       compare prepared.map (px+1) (py-1) depth +. compare prepared.map (px-1) py depth +.
       compare prepared.map px py depth +. compare prepared.map (px+1) py depth +.
       compare prepared.map (px-1) (py+1) depth +. compare prepared.map px (py+1) depth +.
       compare prepared.map (px+1) (py+1) depth) /. 9.
  | Tap25 ->
      let visible=ref 0. in for y=py-2 to py+2 do for x=px-2 to px+2 do
        visible:=!visible+.compare prepared.map x y depth
      done done;!visible/.25. in
  (1.-.prepared.strength)+.prepared.strength*.raw
