type t = int array

let create seed =
  let permutation, _ =
    Rand.shuffle (List.init 256 Fun.id) (Rand.seed seed)
  in
  let base = Array.of_list permutation in
  Array.init 512 (fun index -> base.(index land 255))

let[@inline always] fade value =
  value *. value *. value *. (value *. ((value *. 6.) -. 15.) +. 10.)

let[@inline always] lerp a b amount = a +. (amount *. (b -. a))

let[@inline always] grad hash x y z =
  let hash = hash land 15 in
  let u = if hash < 8 then x else y in
  let v =
    if hash < 4 then y
    else if hash = 12 || hash = 14 then x
    else z
  in
  (if hash land 1 = 0 then u else -.u)
  +. (if hash land 2 = 0 then v else -.v)

let[@inline always] raw3 permutation ~x ~y ~z =
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
  let h000 = permutation.(permutation.(permutation.(xi) + yi) + zi)
  and h100 = permutation.(permutation.(permutation.(xi + 1) + yi) + zi)
  and h010 = permutation.(permutation.(permutation.(xi) + yi + 1) + zi)
  and h110 = permutation.(permutation.(permutation.(xi + 1) + yi + 1) + zi)
  and h001 = permutation.(permutation.(permutation.(xi) + yi) + zi + 1)
  and h101 = permutation.(permutation.(permutation.(xi + 1) + yi) + zi + 1)
  and h011 = permutation.(permutation.(permutation.(xi) + yi + 1) + zi + 1)
  and h111 = permutation.(permutation.(permutation.(xi + 1) + yi + 1) + zi + 1) in
  let x00 = lerp (grad h000 x y z)
      (grad h100 (x -. 1.) y z) u in
  let x10 = lerp (grad h010 x (y -. 1.) z)
      (grad h110 (x -. 1.) (y -. 1.) z) u in
  let x01 = lerp (grad h001 x y (z -. 1.))
      (grad h101 (x -. 1.) y (z -. 1.)) u in
  let x11 = lerp (grad h011 x (y -. 1.) (z -. 1.))
      (grad h111 (x -. 1.) (y -. 1.) (z -. 1.)) u in
  lerp (lerp x00 x10 v) (lerp x01 x11 v) w

let[@inline always] clamp01 value =
  if value <= 0. then 0. else if value >= 1. then 1. else value
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

type fbm3_scratch = float array

let create_fbm3_scratch () = Array.make 4 0.

let[@inline] fbm3_with_scratch scratch noise ~octaves ~lacunarity ~gain
    ~x ~y ~z =
  scratch.(0) <- 1.;
  scratch.(1) <- 1.;
  scratch.(2) <- 0.;
  scratch.(3) <- 0.;
  for _octave = 0 to octaves - 1 do
    let sx = x *. scratch.(0) and sy = y *. scratch.(0)
    and sz = z *. scratch.(0) in
    if Float.is_finite sx && Float.is_finite sy && Float.is_finite sz
        && Float.is_finite scratch.(2) && Float.is_finite scratch.(3) then begin
      let sample = clamp01 ((raw3 noise ~x:sx ~y:sy ~z:sz +. 1.) *. 0.5) in
      scratch.(2) <- scratch.(2) +. (sample *. scratch.(1));
      scratch.(3) <- scratch.(3) +. scratch.(1);
      scratch.(0) <- scratch.(0) *. lacunarity;
      scratch.(1) <- scratch.(1) *. gain
    end else scratch.(2) <- Float.nan
  done;
  if Float.is_finite scratch.(2) && Float.is_finite scratch.(3) then
    if scratch.(3) = 0. then 0. else scratch.(2) /. scratch.(3)
  else Float.nan

module Private = struct
  type nonrec fbm3_scratch = fbm3_scratch
  let create_fbm3_scratch = create_fbm3_scratch
  let fbm3_with_scratch = fbm3_with_scratch

  let sample2_into noise ~first ~last ~frequency ~x ~y ~output =
    if first < 0 || last < first || last > Array.length x
       || last > Array.length y || last > Array.length output
    then invalid_arg "Noise.Private.sample2_into: invalid packed range";
    for index = first to last - 1 do
      output.(index) <- clamp01
          ((raw3 noise ~x:(x.(index) *. frequency)
              ~y:(y.(index) *. frequency) ~z:0. +. 1.) *. 0.5)
    done
end
