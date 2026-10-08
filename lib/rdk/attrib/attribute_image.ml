open Rays_math

type channel = Red | Green | Blue | Alpha | Luminance

let from_image ?cancel ?(grain = 16_384) ?(uv = "uv") ~attribute
    ~channel ~width ~height ~rgba geometry =
  let invalid message = invalid_arg ("attr_from_image: " ^ message) in
  try Error.guard ~operation:"attr_from_image" ~code:"invalid_image_attribute" (fun () ->
    Cancel.check_opt cancel;
    if grain <= 0 then invalid "grain must be positive";
    if String.trim attribute = "" || attribute = "P" then invalid "attribute must be nonblank and cannot be P";
    if width <= 0 || height <= 0 || width > Sys.max_floatarray_length / 4 / height
      || Array.length rgba <> width * height * 4 then invalid "invalid RGBA dimensions";
    Array.iteri (fun i value ->
      if i land 16383 = 0 then Cancel.check_opt cancel;
      if not (Float.is_finite value) || value < 0. || value > 1. then invalid "RGBA must be finite and in [0,1]") rgba;
    let us, vs = match Geometry.find_attribute ~owner:Attribute.Point uv geometry with
      | Some attribute -> (match Attribute.Private.storage attribute with
          | Float2 values -> let p = Packed.Float2.Private.view values in p.x, p.y
          | Float3 values -> let p = Packed.Float3.Private.view values in p.x, p.y
          | _ -> invalid "UV needs a Point Float2 or Float3 attribute")
      | None -> invalid ("missing Point UV attribute " ^ uv) in
    let count = Geometry.point_count geometry in
    if Array.length us <> count || Array.length vs <> count then invalid "UV count differs from points";
    let pixel x y =
      let i = 4 * (y * width + x) in
      match channel with
      | Red -> rgba.(i) | Green -> rgba.(i + 1) | Blue -> rgba.(i + 2) | Alpha -> rgba.(i + 3)
      | Luminance -> 0.2126 *. rgba.(i) +. 0.7152 *. rgba.(i + 1) +. 0.0722 *. rgba.(i + 2) in
    let lerp a b t = a +. (b -. a) *. t in
    let output = Array.make count 0. in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1) (fun i ->
      if i land 4095 = 0 then Cancel.check_opt cancel;
      let u = us.(i) and v = vs.(i) in
      if not (Float.is_finite u && Float.is_finite v) then invalid "UV must be finite";
      let x = max 0. (min 1. u) *. float (width - 1)
      and y = max 0. (min 1. v) *. float (height - 1) in
      let x0 = int_of_float x and y0 = int_of_float y in
      let x1 = min (width - 1) (x0 + 1) and y1 = min (height - 1) (y0 + 1) in
      let tx = x -. float x0 and ty = y -. float y0 in
      output.(i) <- lerp (lerp (pixel x0 y0) (pixel x1 y0) tx)
        (lerp (pixel x0 y1) (pixel x1 y1) tx) ty);
    Cancel.check_opt cancel;
    Result.bind (Attribute.create_owned ~name:attribute ~owner:Attribute.Point (Float output))
      (fun attribute -> Geometry.with_attribute attribute geometry))
  with Invalid_argument message -> Error (Error.make ~operation:"attr_from_image"
    ~code:"invalid_image_attribute" message)
