type format = Bgra8 | Bgra8_srgb | Rgba16_float | Bgra10_xr | Bgra10_xr_srgb

type layer = { mutable width : int; mutable height : int; mutable format : format }

type drawable =
  { width : int
  ; height : int
  ; format : format
  ; mutable texture_live : bool
  ; mutable scheduled : bool
  }

let acquire (layer : layer) =
  { width = layer.width
  ; height = layer.height
  ; format = layer.format
  ; texture_live = false
  ; scheduled = false
  }

let resize (layer : layer) ~width ~height ~format =
  layer.width <- width;
  layer.height <- height;
  layer.format <- format

let texture drawable =
  drawable.texture_live <- true;
  drawable.width, drawable.height, drawable.format

let destroy_drawable drawable =
  if drawable.texture_live then Error `Parent_has_dependents else Ok ()

let destroy_texture drawable = drawable.texture_live <- false

let present drawable =
  if drawable.scheduled then Error `Already_scheduled
  else begin drawable.scheduled <- true; Ok () end
