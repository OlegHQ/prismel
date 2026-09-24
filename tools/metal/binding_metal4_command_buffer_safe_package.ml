type owned = { token : int; device : int; destroyed : bool }
type options = { mutable log_state : owned option; mutable destroyed : bool }
type state = Initial | Recording | Ended | Completed
type t =
  { device : int; mutable state : state; mutable active_children : int; mutable retained : int list
  ; mutable callbacks : (unit -> unit) list; mutable callback_errors : int }
type child = { buffer : t; token : int; mutable ended : bool }

let callable_ids =
  [ "class:MTL4CommandBufferOptions"
  ; "method:-[MTL4CommandBuffer beginCommandBufferWithAllocator:options:]"
  ; "method:-[MTL4CommandBuffer machineLearningCommandEncoder]"
  ; "method:-[MTL4CommandBuffer renderCommandEncoderWithDescriptor:options:]"
  ; "method:-[MTL4CommandBufferOptions logState]"
  ; "method:-[MTL4CommandBufferOptions setLogState:]"
  ; "property:MTL4CommandBufferOptions:logState" ]

let create_options ~available =
  if not available then Error "MTL4 command-buffer options require macOS 26"
  else Ok { log_state = None; destroyed = false }

let set_log_state ~device options (log_state : owned option) =
  if options.destroyed then Error "destroyed MTL4 command-buffer options"
  else match log_state with
  | Some state when state.destroyed -> Error "destroyed MTL4 command-buffer log state"
  | Some state when state.device <> device -> Error "MTL4 command-buffer log state belongs to another device"
  | value -> options.log_state <- value; Ok ()

let log_state options = options.log_state
let destroy_options options =
  if not options.destroyed then begin options.destroyed <- true; options.log_state <- None end

let create ~available ~device =
  let state = if available then Initial else Completed in
  { device; state; active_children = 0; retained = []; callbacks = []; callback_errors = 0 }

let begin_buffer buffer ~(allocator : owned) ~options =
  if buffer.state = Completed then Error "MTL4 command buffers require macOS 26 or are completed"
  else if buffer.state <> Initial then Error "MTL4 command buffer already began"
  else if allocator.destroyed then Error "destroyed MTL4 command allocator"
  else if allocator.device <> buffer.device then Error "MTL4 command allocator belongs to another device"
  else if options.destroyed then Error "destroyed MTL4 command-buffer options"
  else match options.log_state with
  | Some log when log.destroyed -> Error "destroyed MTL4 command-buffer log state"
  | Some log when log.device <> buffer.device -> Error "MTL4 command-buffer log state belongs to another device"
  | log ->
      buffer.retained <- allocator.token :: (match log with None -> [] | Some value -> [ value.token ]);
      buffer.state <- Recording;
      Ok ()

let create_child buffer native_token =
  if buffer.state <> Recording then Error "MTL4 command buffer is not recording"
  else if native_token <= 0 then Error "native MTL4 child encoder creation failed"
  else begin buffer.active_children <- buffer.active_children + 1;
    Ok { buffer; token = native_token; ended = false } end

let render_encoder buffer ~(descriptor : owned) ~encoder_options ~native_token =
  if descriptor.destroyed then Error "destroyed MTL4 render-pass descriptor"
  else if descriptor.device <> buffer.device then Error "MTL4 render-pass descriptor belongs to another device"
  else if encoder_options < 0 || encoder_options land lnot 0x7 <> 0 then Error "invalid MTL4 render encoder options"
  else match create_child buffer native_token with
  | Error error -> Error error
  | Ok child -> buffer.retained <- descriptor.token :: buffer.retained; Ok child

let machine_learning_encoder ~supported buffer ~native_token =
  if not supported then Error "MTL4 machine-learning encoder unsupported"
  else create_child buffer native_token

let end_child child =
  if child.ended then Error "MTL4 child encoder already ended"
  else if child.buffer.state <> Recording then Error "MTL4 command buffer ended before child"
  else begin child.ended <- true; child.buffer.active_children <- child.buffer.active_children - 1; Ok () end

let child_token child = child.token

let add_completion_handler buffer callback =
  match buffer.state with
  | Initial | Recording | Ended -> buffer.callbacks <- callback :: buffer.callbacks; Ok ()
  | Completed ->
      (try callback () with _ -> buffer.callback_errors <- buffer.callback_errors + 1);
      Ok ()

let end_buffer buffer =
  if buffer.state <> Recording then Error "MTL4 command buffer is not recording"
  else if buffer.active_children <> 0 then Error "MTL4 child encoders must end first"
  else begin buffer.state <- Ended; Ok () end

let complete buffer =
  if buffer.state = Ended then begin
    buffer.state <- Completed; buffer.retained <- [];
    let callbacks = List.rev buffer.callbacks in buffer.callbacks <- [];
    List.iter (fun callback -> try callback () with _ ->
      buffer.callback_errors <- buffer.callback_errors + 1) callbacks
  end

let retained_tokens buffer = List.rev buffer.retained
let callback_error_count buffer = buffer.callback_errors

let validate_handoff () =
  if List.length callable_ids <> 7 || List.length (List.sort_uniq String.compare callable_ids) <> 7 then
    invalid_arg "MTL4CommandBuffer callable7 drift"
