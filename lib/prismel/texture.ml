open Tsdl

type level = {
  width : int;
  height : int;
  pixels : Color.t array;
}

type t = {
  width : int;
  height : int;
  pixels : Color.t array;
  mipmaps : level array;
}

type filter = Nearest | Bilinear | Trilinear
type wrap = Clamp | Repeat | Mirror

let create_owned ~width ~height pixels =
  if width <= 0 || height <= 0 then
    Error "Texture.create: dimensions must be positive"
  else
    let expected = width * height in
    if Array.length pixels <> expected then
      Error
        (Printf.sprintf
           "Texture.create: expected %d pixels for %dx%d, received %d"
           expected width height (Array.length pixels))
    else Ok { width; height; pixels; mipmaps = [||] }

let create ~width ~height pixels =
  create_owned ~width ~height (Array.of_list pixels)

let create_exn ~width ~height pixels =
  match create ~width ~height pixels with
  | Ok texture -> texture
  | Error message -> invalid_arg message

let init ~width ~height make =
  if width <= 0 || height <= 0 then
    invalid_arg "Texture.init: dimensions must be positive";
  {
    width;
    height;
    pixels =
      Array.init (width * height) (fun index ->
        make ~x:(index mod width) ~y:(index / width));
    mipmaps = [||];
  }

let require_main_domain () =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Texture.load must run on the main domain"

let load filename =
  require_main_domain ();
  match Tsdl_image.Image.load filename with
  | Error (`Msg message) -> Error ("Texture load failed: " ^ message)
  | Ok source ->
      Fun.protect ~finally:(fun () -> Sdl.free_surface source) (fun () ->
        match
          Sdl.convert_surface_format source Sdl_compat.format_rgba32
        with
        | Error (`Msg message) ->
            Error ("Texture format conversion failed: " ^ message)
        | Ok surface ->
            Fun.protect ~finally:(fun () -> Sdl.free_surface surface) (fun () ->
              let width, height = Sdl.get_surface_size surface in
              match Sdl.lock_surface surface with
              | Error (`Msg message) ->
                  Error ("Texture pixel lock failed: " ^ message)
              | Ok () ->
                  Fun.protect
                    ~finally:(fun () -> Sdl.unlock_surface surface)
                    (fun () ->
                      match
                        Sdl.alloc_format Sdl_compat.format_rgba32
                      with
                      | Error (`Msg message) ->
                          Error ("Texture pixel format failed: " ^ message)
                      | Ok format ->
                          Fun.protect
                            ~finally:(fun () -> Sdl.free_format format)
                            (fun () ->
                              let values =
                                Sdl.get_surface_pixels surface Bigarray.int32
                              and stride = Sdl.get_surface_pitch surface / 4 in
                              let pixels =
                                Array.init (width * height) (fun index ->
                                  let x = index mod width
                                  and y = index / width in
                                  let r, g, b, a =
                                    Sdl.get_rgba format values.{(y * stride) + x}
                                  in
                                  Color.rgba r g b a)
                              in
                              Ok { width; height; pixels; mipmaps = [||] }))))

let load_exn filename =
  match load filename with
  | Ok texture -> texture
  | Error message -> failwith message

let width texture = texture.width
let height texture = texture.height
let size texture = texture.width, texture.height
let pixels texture = Array.to_list texture.pixels

let pixel texture ~x ~y =
  if x < 0 || y < 0 || x >= texture.width || y >= texture.height then None
  else Some texture.pixels.((y * texture.width) + x)

let next_level (source : level) : level =
  let width = max 1 ((source.width + 1) / 2)
  and height = max 1 ((source.height + 1) / 2) in
  {
    width;
    height;
    pixels =
      Array.init (width * height) (fun index ->
        let x = index mod width and y = index / width in
        let red = ref 0 and green = ref 0 and blue = ref 0
        and alpha = ref 0 and count = ref 0 in
        for offset_y = 0 to 1 do
          for offset_x = 0 to 1 do
            let source_x = (x * 2) + offset_x
            and source_y = (y * 2) + offset_y in
            if source_x < source.width && source_y < source.height then begin
              let color =
                source.pixels.((source_y * source.width) + source_x)
              in
              red := !red + color.Color.r;
              green := !green + color.g;
              blue := !blue + color.b;
              alpha := !alpha + color.a;
              incr count
            end
          done
        done;
        let rounded value = (value + (!count / 2)) / !count in
        Color.rgba (rounded !red) (rounded !green)
          (rounded !blue) (rounded !alpha));
  }

let generate_mipmaps texture =
  let rec build (level : level) (acc : level list) =
    if level.width = 1 && level.height = 1 then List.rev acc
    else
      let level = next_level level in
      build level (level :: acc)
  in
  let base : level = {
    width = texture.width;
    height = texture.height;
    pixels = texture.pixels;
  } in
  { texture with mipmaps = Array.of_list (build base []) }

let has_mipmaps texture = Array.length texture.mipmaps > 0
let mipmap_count texture = 1 + Array.length texture.mipmaps

let subsection ~x ~y ~width ~height texture =
  if width <= 0 || height <= 0 then
    Error "Texture.subsection: dimensions must be positive"
  else if x < 0 || y < 0
          || x + width > texture.width || y + height > texture.height
  then Error "Texture.subsection: rectangle is outside the source texture"
  else
    Ok {
      width;
      height;
      pixels =
        Array.init (width * height) (fun index ->
          let target_x = index mod width and target_y = index / width in
          texture.pixels.
            (((y + target_y) * texture.width) + x + target_x));
      mipmaps = [||];
    }

let subsection_exn ~x ~y ~width ~height texture =
  match subsection ~x ~y ~width ~height texture with
  | Ok texture -> texture
  | Error message -> invalid_arg message

let[@inline always] wrap_coordinate mode value =
  match mode with
  | Clamp -> Float.max 0. (Float.min 1. value)
  | Repeat ->
      let value = value -. Float.floor value in
      if value < 0. then value +. 1. else value
  | Mirror ->
      let value = value -. (2. *. Float.floor (value /. 2.)) in
      let value = if value < 0. then value +. 2. else value in
      if value <= 1. then value else 2. -. value

let pack color =
  (color.Color.r lsl 24) lor (color.g lsl 16)
  lor (color.b lsl 8) lor color.a

let unpack value =
  Color.rgba ((value lsr 24) land 0xff) ((value lsr 16) land 0xff)
    ((value lsr 8) land 0xff) (value land 0xff)

let packed_channel value shift = (value lsr shift) land 0xff

let[@inline always] blend_packed left right amount =
  let inverse = 1. -. amount in
  let red = int_of_float
      ((float_of_int (packed_channel left 24) *. inverse)
       +. (float_of_int (packed_channel right 24) *. amount) +. 0.5)
  and green = int_of_float
      ((float_of_int (packed_channel left 16) *. inverse)
       +. (float_of_int (packed_channel right 16) *. amount) +. 0.5)
  and blue = int_of_float
      ((float_of_int (packed_channel left 8) *. inverse)
       +. (float_of_int (packed_channel right 8) *. amount) +. 0.5)
  and alpha = int_of_float
      ((float_of_int (packed_channel left 0) *. inverse)
       +. (float_of_int (packed_channel right 0) *. amount) +. 0.5) in
  (red lsl 24) lor (green lsl 16) lor (blue lsl 8) lor alpha

let packed_texel pixels width x y = pack pixels.((y * width) + x)

let[@inline always] sample_pixels_packed
    ~filter ~wrap_u ~wrap_v ~width ~height pixels ~u ~v =
  let u = wrap_coordinate wrap_u u and v = wrap_coordinate wrap_v v in
  let x = u *. float_of_int (width - 1)
  and y = v *. float_of_int (height - 1) in
  match filter with
  | Nearest ->
      packed_texel pixels width (int_of_float (Float.round x))
        (int_of_float (Float.round y))
  | Bilinear | Trilinear ->
      let x0 = int_of_float (Float.floor x)
      and y0 = int_of_float (Float.floor y) in
      let x1 = min (width - 1) (x0 + 1)
      and y1 = min (height - 1) (y0 + 1) in
      let horizontal = x -. float_of_int x0
      and vertical = y -. float_of_int y0 in
      let top = blend_packed
          (packed_texel pixels width x0 y0)
          (packed_texel pixels width x1 y0) horizontal
      and bottom = blend_packed
          (packed_texel pixels width x0 y1)
          (packed_texel pixels width x1 y1) horizontal in
      blend_packed top bottom vertical

let[@inline always] sample_index_packed
    ~filter ~wrap_u ~wrap_v texture index ~u ~v =
  if index = 0 then
    sample_pixels_packed ~filter ~wrap_u ~wrap_v
      ~width:texture.width ~height:texture.height texture.pixels ~u ~v
  else
    let level = texture.mipmaps.(index - 1) in
    sample_pixels_packed ~filter ~wrap_u ~wrap_v
      ~width:level.width ~height:level.height level.pixels ~u ~v

let sample_lod_packed ?(filter = Bilinear) ?(wrap_u = Clamp) ?(wrap_v = Clamp)
    texture ~lod ~u ~v =
  if not (Float.is_finite lod) then
    invalid_arg "Texture.sample_lod: lod must be finite";
  let maximum = mipmap_count texture - 1 in
  let lod = Float.max 0. (Float.min (float_of_int maximum) lod) in
  match filter with
  | Nearest | Bilinear ->
      let index = int_of_float (Float.round lod) in
      sample_index_packed ~filter ~wrap_u ~wrap_v texture index ~u ~v
  | Trilinear ->
      let lower = int_of_float (Float.floor lod) in
      let upper = min maximum (lower + 1) in
      let amount = lod -. float_of_int lower in
      blend_packed
        (sample_index_packed ~filter:Bilinear ~wrap_u ~wrap_v
           texture lower ~u ~v)
        (sample_index_packed ~filter:Bilinear ~wrap_u ~wrap_v
           texture upper ~u ~v)
        amount

let sample_lod ?filter ?wrap_u ?wrap_v texture ~lod ~u ~v =
  sample_lod_packed ?filter ?wrap_u ?wrap_v texture ~lod ~u ~v |> unpack

let sample ?(filter = Bilinear) ?(wrap_u = Clamp) ?(wrap_v = Clamp)
    texture ~u ~v =
  sample_lod ~filter ~wrap_u ~wrap_v texture ~lod:0. ~u ~v

module Private = struct
  let create_owned = create_owned
  let sample_lod_packed = sample_lod_packed
end
