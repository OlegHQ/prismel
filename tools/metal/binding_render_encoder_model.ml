type error = Wrong_state | Device_mismatch | Out_of_range | Missing_pipeline
type buffer = { id : int64; device : int64; length : int64 }
type pipeline = { id : int64; device : int64 }
type command =
  | Pipeline of int64
  | Vertex_buffer of int * int64 * int64 option
  | Fragment_buffer of int * int64 * int64 option
  | Draw of int * int * int
type state = Encoding | Ended
type t =
  { device : int64
  ; state : state
  ; pipeline : pipeline option
  ; retained : int64 list
  ; reversed_commands : command list
  }

let create ~device =
  { device; state = Encoding; pipeline = None; retained = []
  ; reversed_commands = [] }

let retain id retained =
  if List.mem id retained then retained else id :: retained

let encoding value = match value.state with Encoding -> true | Ended -> false

let set_pipeline (value : t) (pipeline : pipeline) =
  if not (encoding value) then Error Wrong_state
  else if pipeline.device <> value.device then Error Device_mismatch
  else
    Ok { value with pipeline = Some pipeline
       ; retained = retain pipeline.id value.retained
       ; reversed_commands = Pipeline pipeline.id :: value.reversed_commands }

let set_buffer stage (value : t) ~index ~offset (buffer : buffer option) =
  if not (encoding value) then Error Wrong_state
  else if index < 0 || index >= 31 || Int64.compare offset 0L < 0 then
    Error Out_of_range
  else
    match buffer with
    | Some buffer when buffer.device <> value.device -> Error Device_mismatch
    | Some buffer when Int64.compare offset buffer.length > 0 -> Error Out_of_range
    | _ ->
        let id = Option.map (fun (value : buffer) -> value.id) buffer in
        let retained =
          match id with None -> value.retained | Some id -> retain id value.retained
        in
        Ok { value with retained
           ; reversed_commands = stage index offset id :: value.reversed_commands }

let set_vertex_buffer = set_buffer (fun i o id -> Vertex_buffer (i, o, id))
let set_fragment_buffer = set_buffer (fun i o id -> Fragment_buffer (i, o, id))

let draw value ~first ~count ~instances =
  if not (encoding value) then Error Wrong_state
  else if first < 0 || count <= 0 || instances <= 0 then Error Out_of_range
  else if Option.is_none value.pipeline then Error Missing_pipeline
  else
    Ok { value with
         reversed_commands = Draw (first, count, instances) :: value.reversed_commands }

let finish value =
  if not (encoding value) then Error Wrong_state
  else Ok { value with state = Ended }

let retained_resource_count value = List.length value.retained
let commands value = List.rev value.reversed_commands
