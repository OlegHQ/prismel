open Prismel_math

let noise_displace_raw ?cancel ?grain ~amplitude ~frequency ~seed geometry =
  if not (Float.is_finite amplitude && Float.is_finite frequency) then
    Error "Pdk.Ops.noise_displace: amplitude and frequency must be finite"
  else
    let noise = Noise.create seed in
    let samples = Array.make (Geometry.point_count geometry) 0. in
    let displaced = Kernel.edit_point_ranges ?grain
        (fun ~first ~last ~x ~y ~z ->
          Cancel.check_opt cancel;
          Noise.Private.sample2_into noise ~first ~last ~frequency
            ~x ~y:z ~output:samples;
          for index = first to last - 1 do
            y.(index) <- y.(index) +. amplitude *. ((samples.(index) *. 2.) -. 1.)
          done) geometry in
    Ok (displaced
        |> Geometry.without_attribute ~owner:Attribute.Point "N"
        |> Geometry.without_attribute ~owner:Attribute.Vertex "N")

let noise_displace_checked ?cancel ?grain ~amplitude ~frequency ~seed geometry =
  Error.guard ~operation:"noise_displace" ~code:"invalid_parameter" (fun () ->
    noise_displace_raw ?cancel ?grain ~amplitude ~frequency ~seed geometry)

let peak_checked ?cancel ?(grain = 16_384) ?selection ?direction_attribute
    ?(normalize_direction = true) ?mask_attribute ~distance
    ?(recompute_normals = false) geometry =
  Error.guard ~operation:"peak" ~code:"invalid_deformation" (fun () ->
    Deform.peak ?cancel ~grain ?selection ?direction_attribute
      ~normalize_direction ?mask_attribute ~distance ~recompute_normals geometry)

let bend_checked ?cancel ?(grain = 16_384) ?selection ?mask_attribute
    ?(origin = Vec3.zero) ?(direction = Vec3.unit_z) ?(up = Vec3.unit_y)
    ~length ?(bend_angle = 0.) ?(twist_angle = 0.) ?(limit = true)
    ?(both_directions = false) ?(continuous_twist = true) ?capture_attribute
    ?(recompute_normals = false) geometry =
  Error.guard ~operation:"bend" ~code:"invalid_deformation" (fun () ->
    Deform.bend ?cancel ~grain ?selection ?mask_attribute ~origin ~direction ~up
      ~length ~bend_angle ~twist_angle ~limit ~both_directions ~continuous_twist
      ?capture_attribute ~recompute_normals geometry)

let mountain_checked ?cancel ?(grain = 16_384) ?selection ?direction_attribute
    ?(normalize_direction = true) ?mask_attribute ?(seed = 0) ~height
    ?(frequency = Vec3.create 1. 1. 1.) ?(offset = Vec3.zero) ?(octaves = 4)
    ?(lacunarity = 2.) ?(roughness = 0.5) ?height_attribute
    ?(recompute_normals = false) geometry =
  Error.guard ~operation:"mountain" ~code:"invalid_deformation" (fun () ->
    Deform.mountain ?cancel ~grain ?selection ?direction_attribute
      ~normalize_direction ?mask_attribute ~seed ~height ~frequency ~offset
      ~octaves ~lacunarity ~roughness ?height_attribute ~recompute_normals geometry)

let point_jitter_checked ?cancel ?(grain = 16_384) ?points ?mask_attribute
    ?id_attribute ?(use_point_scale = false) ~seed ~scale
    ?(axis_scales = Vec3.create 1. 1. 1.) geometry =
  let selection_error = match points with
    | Some group when Group.owner group <> Group.Point ->
        Some "selection must own points"
    | Some group when Group.length group <> Geometry.point_count geometry ->
        Some "selection length does not match point count"
    | None | Some _ -> None in
  match selection_error with
  | Some message -> Error (Error.of_string ~operation:"point_jitter"
      ~code:"invalid_selection" message)
  | None -> Error.guard ~operation:"point_jitter" ~code:"invalid_attribute"
      (fun () -> Point_jitter.run ?cancel ~grain ?points ?mask_attribute
        ?id_attribute ~use_point_scale ~seed ~scale ~axis_scales geometry)
