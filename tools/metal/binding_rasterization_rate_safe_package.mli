type size = { width : int; height : int }
type capability = Unsupported | Supported of { max_layers : int }
type layer = { horizontal : float array; vertical : float array }
type descriptor = { screen : size; layers : layer option array; label : string option }
type buffer = { token : int; device : int; length : int; destroyed : bool }
type rate_map = { token : int; device : int; layer_count : int; parameter_size : int; parameter_align : int; destroyed : bool }
val create_layer : max_samples:int -> horizontal:float array -> vertical:float array -> (layer, string) result
val create_descriptor : capability:capability -> screen:size -> layers:layer option array -> label:string option -> (descriptor, string) result
val replace_layer : descriptor -> index:int -> layer option -> (descriptor, string) result
val validate_map : rate_map -> layer:int -> (unit, string) result
val validate_copy : rate_map -> buffer -> offset:int -> (unit, string) result
val validate_handoff : unit -> unit
