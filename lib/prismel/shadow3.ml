type filter = Hard | Pcf_3x3 | Pcf_5x5

type t = {
  light : Light.t;
  view_projection : Mat4.t;
  width : int;
  height : int;
  depths : float array;
  bias : float;
  normal_bias : float;
  filter : filter;
  strength : float;
}

let create ?(bias = 0.001) ?(normal_bias = 0.005) ?(filter = Pcf_3x3)
    ?(strength = 1.) ~light ~camera ~width ~height ~depths () =
  if width <= 0 || height <= 0 then
    invalid_arg "Shadow3.create: dimensions must be positive";
  if Array.length depths <> width * height then
    invalid_arg "Shadow3.create: depth count must match dimensions";
  if not (Float.is_finite bias) || bias < 0.
     || not (Float.is_finite normal_bias) || normal_bias < 0.
  then invalid_arg "Shadow3.create: biases must be finite and non-negative";
  if not (Float.is_finite strength) || strength < 0. || strength > 1. then
    invalid_arg "Shadow3.create: strength must be finite and in 0..1";
  {
    light;
    view_projection =
      Camera.view_projection_matrix ~viewport:(0, 0, width, height) camera;
    width;
    height;
    depths = Array.copy depths;
    bias;
    normal_bias;
    filter;
    strength;
  }

let light shadow = shadow.light
let filter shadow = shadow.filter
let size shadow = shadow.width, shadow.height

let toward_light light world =
  match light.Light.kind with
  | Ambient -> Vec3.zero
  | Directional { direction } -> Vec3.neg direction
  | Point { position; _ }
  | Spot { position; _ }
  | Area { position; _ } ->
      Vec3.sub position world |> Vec3.normalize

module Private = struct
  let affects shadow light =
    shadow.light == light || shadow.light = light

  let visibility shadow ~world ~normal =
    let x, y, z, w =
      Mat4.transform shadow.view_projection
        (world.Vec3.x, world.y, world.z, 1.)
    in
    if w <= 1e-12 then 1.
    else
      let ndc_x = x /. w and ndc_y = y /. w and ndc_z = z /. w in
      if ndc_x < (-1.) || ndc_x > 1.
         || ndc_y < (-1.) || ndc_y > 1.
         || ndc_z < (-1.) || ndc_z > 1.
      then 1.
      else
        let u = (ndc_x +. 1.) *. 0.5
        and v = (1. -. ndc_y) *. 0.5
        and fragment_depth = (ndc_z +. 1.) *. 0.5 in
        let facing =
          Vec3.dot (Vec3.normalize normal)
            (toward_light shadow.light world)
          |> Float.max 0.
        in
        let bias =
          shadow.bias +. (shadow.normal_bias *. (1. -. facing))
        in
        let center_x =
          int_of_float
            (Float.round (u *. float_of_int (shadow.width - 1)))
        and center_y =
          int_of_float
            (Float.round (v *. float_of_int (shadow.height - 1)))
        in
        let radius =
          match shadow.filter with Hard -> 0 | Pcf_3x3 -> 1 | Pcf_5x5 -> 2
        in
        let visible = ref 0 and count = ref 0 in
        for offset_y = -radius to radius do
          for offset_x = -radius to radius do
            incr count;
            let sample_x = center_x + offset_x
            and sample_y = center_y + offset_y in
            if sample_x < 0 || sample_y < 0
               || sample_x >= shadow.width || sample_y >= shadow.height
            then incr visible
            else
              let stored =
                shadow.depths.((sample_y * shadow.width) + sample_x)
              in
              if fragment_depth -. bias <= stored then incr visible
          done
        done;
        let fraction = float_of_int !visible /. float_of_int !count in
        (1. -. shadow.strength) +. (shadow.strength *. fraction)
end
