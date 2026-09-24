type store_action = Dont_care | Store | Multisample_resolve | Store_and_multisample_resolve
type store_options = No_options | Custom_sample_positions
type attachment = { token : int; device : int; destroyed : bool }
type write = { action : store_action; options : store_options }
type parent =
  { device : int; colors : attachment option array; depth : attachment option; stencil : attachment option
  ; color_writes : write option array; mutable depth_write : write option; mutable stencil_write : write option
  ; mutable active_children : int; mutable ended : bool }
type child = { parent : parent; token : int; mutable ended : bool }

let callable_ids =
  [ "method:-[MTLParallelRenderCommandEncoder renderCommandEncoder]"
  ; "method:-[MTLParallelRenderCommandEncoder setColorStoreAction:atIndex:]"
  ; "method:-[MTLParallelRenderCommandEncoder setColorStoreActionOptions:atIndex:]"
  ; "method:-[MTLParallelRenderCommandEncoder setDepthStoreAction:]"
  ; "method:-[MTLParallelRenderCommandEncoder setDepthStoreActionOptions:]"
  ; "method:-[MTLParallelRenderCommandEncoder setStencilStoreAction:]"
  ; "method:-[MTLParallelRenderCommandEncoder setStencilStoreActionOptions:]" ]

let validate_attachment ~device = function
  | Some attachment when attachment.destroyed -> Error "destroyed parallel-render attachment"
  | Some attachment when attachment.device <> device -> Error "parallel-render attachment belongs to another device"
  | _ -> Ok ()

let create_parent ~device ~colors ~depth ~stencil =
  let colors = Array.copy colors in
  let rec validate_colors index =
    if index = Array.length colors then Ok ()
    else match validate_attachment ~device colors.(index) with
    | Error error -> Error error
    | Ok () -> validate_colors (index + 1)
  in
  match validate_colors 0, validate_attachment ~device depth, validate_attachment ~device stencil with
  | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error
  | Ok (), Ok (), Ok () ->
      Ok { device; colors; depth; stencil; color_writes = Array.make (Array.length colors) None
         ; depth_write = None; stencil_write = None; active_children = 0; ended = false }

let create_child (parent : parent) ~token =
  if parent.ended then Error "parallel render encoder already ended"
  else if token <= 0 then Error "native child encoder creation failed"
  else begin parent.active_children <- parent.active_children + 1; Ok { parent; token; ended = false } end

let validate_write (parent : parent) action options =
  if parent.ended then Error "parallel render encoder already ended"
  else match action, options with
  | Dont_care, Custom_sample_positions -> Error "store options incompatible with dont-care action"
  | _ -> Ok { action; options }

let set_color_store (parent : parent) ~index action options =
  if index < 0 || index >= Array.length parent.colors then Error "color attachment index out of bounds"
  else if parent.colors.(index) = None then Error "color store write requires an attachment"
  else Result.map (fun write -> parent.color_writes.(index) <- Some write) (validate_write parent action options)

let set_depth_store (parent : parent) action options =
  if parent.depth = None then Error "depth store write requires an attachment"
  else Result.map (fun write -> parent.depth_write <- Some write) (validate_write parent action options)

let set_stencil_store (parent : parent) action options =
  if parent.stencil = None then Error "stencil store write requires an attachment"
  else Result.map (fun write -> parent.stencil_write <- Some write) (validate_write parent action options)

let end_child (child : child) =
  if child.ended then Error "child render encoder already ended"
  else if child.parent.ended then Error "parent render encoder ended before child"
  else begin child.ended <- true; child.parent.active_children <- child.parent.active_children - 1; Ok () end

let end_parent (parent : parent) =
  if parent.ended then Error "parallel render encoder already ended"
  else if parent.active_children <> 0 then Error "child render encoders must end first"
  else begin parent.ended <- true; Ok () end

let retained_attachment_tokens (parent : parent) =
  let tokens = parent.colors |> Array.to_list
    |> List.filter_map (Option.map (fun (item : attachment) -> item.token)) in
  let tokens = match parent.depth with None -> tokens | Some item -> item.token :: tokens in
  match parent.stencil with None -> tokens | Some item -> item.token :: tokens

let parent_device parent = parent.device
let child_token child = child.token

let configured_write_count parent =
  let inspect = function
    | None -> 0
    | Some { action; options } ->
        ignore (action, options);
        1
  in
  Array.fold_left (fun count write -> count + inspect write) 0 parent.color_writes
  + inspect parent.depth_write + inspect parent.stencil_write

let validate_handoff () =
  if List.length callable_ids <> 7 || List.length (List.sort_uniq String.compare callable_ids) <> 7 then
    invalid_arg "ParallelRender callable7 drift"
