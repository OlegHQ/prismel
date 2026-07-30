type t = int array

let create seed =
  let permutation, _ =
    Rand.shuffle (List.init 256 Fun.id) (Rand.seed seed)
  in
  let base = Array.of_list permutation in
  Array.init 512 (fun index -> base.(index land 255))

let fade value =
  value *. value *. value *. (value *. ((value *. 6.) -. 15.) +. 10.)

let lerp a b amount = a +. (amount *. (b -. a))

let grad hash x y z =
  let hash = hash land 15 in
  let u = if hash < 8 then x else y in
  let v =
    if hash < 4 then y
    else if hash = 12 || hash = 14 then x
    else z
  in
  (if hash land 1 = 0 then u else -.u)
  +. (if hash land 2 = 0 then v else -.v)

let raw3 permutation ~x ~y ~z =
  let floor_x = Float.floor x in
  let floor_y = Float.floor y in
  let floor_z = Float.floor z in
  let xi = int_of_float floor_x land 255 in
  let yi = int_of_float floor_y land 255 in
  let zi = int_of_float floor_z land 255 in
  let x = x -. floor_x in
  let y = y -. floor_y in
  let z = z -. floor_z in
  let u = fade x and v = fade y and w = fade z in
  let hash dx dy dz =
    permutation.(permutation.(permutation.(xi + dx) + yi + dy) + zi + dz)
  in
  let x00 = lerp (grad (hash 0 0 0) x y z)
      (grad (hash 1 0 0) (x -. 1.) y z) u in
  let x10 = lerp (grad (hash 0 1 0) x (y -. 1.) z)
      (grad (hash 1 1 0) (x -. 1.) (y -. 1.) z) u in
  let x01 = lerp (grad (hash 0 0 1) x y (z -. 1.))
      (grad (hash 1 0 1) (x -. 1.) y (z -. 1.)) u in
  let x11 = lerp (grad (hash 0 1 1) x (y -. 1.) (z -. 1.))
      (grad (hash 1 1 1) (x -. 1.) (y -. 1.) (z -. 1.)) u in
  lerp (lerp x00 x10 v) (lerp x01 x11 v) w

let clamp01 value = max 0. (min 1. value)
let sample3 noise ~x ~y ~z = clamp01 ((raw3 noise ~x ~y ~z +. 1.) /. 2.)
let sample2 noise ~x ~y = sample3 noise ~x ~y ~z:0.
let sample1 noise x = sample3 noise ~x ~y:0. ~z:0.

let fractal ?(octaves = 4) ?(lacunarity = 2.) ?(gain = 0.5) sample =
  if octaves <= 0 then invalid_arg "Noise.fbm: octaves must be positive";
  if lacunarity <= 0. then invalid_arg "Noise.fbm: lacunarity must be positive";
  if gain < 0. then invalid_arg "Noise.fbm: gain must be non-negative";
  let rec loop octave frequency amplitude sum weights =
    if octave = octaves then
      if weights = 0. then 0. else sum /. weights
    else
      loop (octave + 1) (frequency *. lacunarity) (amplitude *. gain)
        (sum +. (sample frequency *. amplitude)) (weights +. amplitude)
  in
  loop 0 1. 1. 0. 0.

let fbm1 ?octaves ?lacunarity ?gain noise x =
  fractal ?octaves ?lacunarity ?gain
    (fun frequency -> sample1 noise (x *. frequency))

let fbm2 ?octaves ?lacunarity ?gain noise ~x ~y =
  fractal ?octaves ?lacunarity ?gain
    (fun frequency ->
      sample2 noise ~x:(x *. frequency) ~y:(y *. frequency))

let fbm3 ?octaves ?lacunarity ?gain noise ~x ~y ~z =
  fractal ?octaves ?lacunarity ?gain
    (fun frequency ->
      sample3 noise ~x:(x *. frequency) ~y:(y *. frequency)
        ~z:(z *. frequency))
