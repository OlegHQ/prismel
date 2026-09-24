type size = { width : int; height : int }
type capability = Unsupported | Supported of { max_layers : int }
type layer = { horizontal : float array; vertical : float array }
type descriptor = { screen : size; layers : layer option array; label : string option }
type buffer = { token : int; device : int; length : int; destroyed : bool }
type rate_map = { token : int; device : int; layer_count : int; parameter_size : int; parameter_align : int; destroyed : bool }

let finite_positive value = Float.is_finite value && value > 0.0
let valid_size size = size.width > 0 && size.height > 0

let create_layer ~max_samples ~horizontal ~vertical =
  if max_samples <= 0 || Array.length horizontal = 0 || Array.length vertical = 0
     || Array.length horizontal > max_samples || Array.length vertical > max_samples
  then Error "invalid rasterization-rate sample count"
  else if not (Array.for_all finite_positive horizontal && Array.for_all finite_positive vertical)
  then Error "rasterization-rate samples must be finite and positive"
  else Ok { horizontal = Array.copy horizontal; vertical = Array.copy vertical }

let create_descriptor ~capability ~screen ~layers ~label =
  if not (valid_size screen) then Error "invalid rasterization-rate screen size"
  else match capability with
    | Unsupported -> Error "rasterization-rate maps are unsupported"
    | Supported { max_layers } when Array.length layers = 0 || Array.length layers > max_layers ->
        Error "invalid rasterization-rate layer count"
    | Supported _ -> Ok { screen; layers = Array.copy layers; label }

let replace_layer descriptor ~index layer =
  if index < 0 || index >= Array.length descriptor.layers then Error "rasterization-rate layer index"
  else let layers = Array.copy descriptor.layers in layers.(index) <- layer; Ok { descriptor with layers }

let validate_map map ~layer =
  if map.destroyed then Error "destroyed rasterization-rate map"
  else if layer < 0 || layer >= map.layer_count then Error "rasterization-rate map layer index"
  else Ok ()

let validate_copy (map : rate_map) (buffer : buffer) ~offset =
  if map.destroyed || buffer.destroyed then Error "destroyed rasterization-rate copy object"
  else if map.device <> buffer.device then Error "rasterization-rate copy uses another device"
  else if offset < 0 || map.parameter_align <= 0 || offset mod map.parameter_align <> 0
  then Error "rasterization-rate parameter offset alignment"
  else if map.parameter_size < 0 || offset > buffer.length
          || map.parameter_size > buffer.length - offset
  then Error "rasterization-rate parameter buffer range"
  else Ok ()

let validate_handoff () =
  Binding_rasterization_rate_safe_handoff.validate ();
  if List.length Binding_rasterization_rate_safe_handoff.callable_ids <> 50
  then invalid_arg "RasterizationRate callable50 drift"
