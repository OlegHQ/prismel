type resource = { token : int; device : int; length : int; destroyed : bool }
type binding = { resource : resource; offset : int; stride : int option }
type command = { device : int; max_slots : int; bindings : binding option array; pipeline : resource option }

let empty ~device ~max_slots = { device; max_slots; bindings = Array.make max_slots None; pipeline = None }

let validate_resource ~device resource =
  if resource.destroyed then Error "destroyed indirect-command resource"
  else if resource.device <> device then Error "indirect-command resource belongs to another device"
  else if resource.length < 0 then Error "invalid resource length"
  else Ok ()

let set_binding command ~slot binding =
  if slot < 0 || slot >= command.max_slots then Error "indirect-command slot out of bounds"
  else if binding.offset < 0 || binding.offset > binding.resource.length then Error "buffer offset out of bounds"
  else if Option.fold ~none:false ~some:(fun stride -> stride <= 0) binding.stride then Error "attribute stride must be positive"
  else match validate_resource ~device:command.device binding.resource with
  | Error error -> Error error
  | Ok () ->
      let bindings = Array.copy command.bindings in
      bindings.(slot) <- Some binding;
      Ok { command with bindings }

let set_pipeline command pipeline =
  Result.map (fun () -> { command with pipeline = Some pipeline })
    (validate_resource ~device:command.device pipeline)

let validate_draw _command ~vertex_count ~instance_count =
  if vertex_count <= 0 || instance_count <= 0 then Error "draw cardinality must be positive" else Ok ()

let validate_indexed_draw command ~index_buffer ~index_offset ~index_count ~index_size =
  match validate_resource ~device:command.device index_buffer with
  | Error error -> Error error
  | Ok () ->
      if index_offset < 0 || index_count <= 0 || (index_size <> 2 && index_size <> 4)
         || index_offset mod index_size <> 0
         || index_count > (index_buffer.length - index_offset) / index_size
      then Error "invalid indexed-draw range" else Ok ()

let validate_patch_draw command ~patch_start ~patch_count ~control_points ~patch_indices
    ~tessellation ~tessellation_offset ~tessellation_stride ~instance_count =
  let validate_optional = function None -> Ok () | Some resource -> validate_resource ~device:command.device resource in
  match validate_optional patch_indices, validate_resource ~device:command.device tessellation with
  | Error error, _ | _, Error error -> Error error
  | Ok (), Ok () ->
      if patch_start < 0 || patch_count <= 0 || control_points <= 0 || instance_count <= 0
         || tessellation_offset < 0 || tessellation_stride <= 0
         || tessellation_offset > tessellation.length
         || instance_count > (tessellation.length - tessellation_offset) / tessellation_stride
      then Error "invalid patch draw range/cardinality"
      else match patch_indices with
      | Some indices when patch_start + patch_count > indices.length -> Error "patch index range out of bounds"
      | _ -> Ok ()

let retained_tokens command =
  let tokens = command.bindings |> Array.to_list
    |> List.filter_map (function None -> None | Some binding -> Some binding.resource.token)
  in
  match command.pipeline with None -> tokens | Some pipeline -> pipeline.token :: tokens

let reset command = { command with bindings = Array.make command.max_slots None; pipeline = None }

let validate_handoff () =
  if List.length Binding_indirect_command_tail_handoff.callable_ids <> 12 then
    invalid_arg "IndirectCommand callable12 drift"
