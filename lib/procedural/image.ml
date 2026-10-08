type t = {width : int; height : int; rgba : float array; data_id : int}
let width image = image.width
let height image = image.height
let data_id image = image.data_id
let rgba image = Array.copy image.rgba
let payload_bytes image = Array.length image.rgba * 8
module Private = struct
  let storage image = image.rgba
  let of_owned_rgba ~width ~height rgba =
    let error message = Error (Diagnostic.error ~code:"E_IMAGE" message) in
    if width <= 0 || height <= 0 then error "Image dimensions must be positive."
    else if width > Sys.max_floatarray_length / 4 / height then
      error "Image dimensions exceed native storage bounds."
    else if Array.length rgba <> width * height * 4 then
      error "Image RGBA storage must contain four samples per pixel."
    else if not (Array.for_all (fun sample -> Float.is_finite sample && sample >= 0. && sample <= 1.) rgba) then
      error "Image RGBA samples must be finite and within [0,1]."
    else Ok {width; height; rgba; data_id=Rdk.Data_id.fresh ()}
end
let create ~width ~height ~rgba =
  Result.map (fun image -> {image with rgba=Array.copy rgba})
    (Private.of_owned_rgba ~width ~height rgba)
