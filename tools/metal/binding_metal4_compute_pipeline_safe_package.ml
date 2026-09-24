type configured =
  { function_token : int; linked_functions_token : int option
  ; max_threads : int; threadgroup_multiple : bool }
type descriptor = { mutable configured : configured option; mutable destroyed : bool }

let callable_ids = [ "method:-[MTL4ComputePipelineDescriptor reset]" ]

let create ~available =
  if not available then Error "MTL4 compute pipelines require macOS 26"
  else Ok { configured = None; destroyed = false }

let configure descriptor ~function_token ~linked_functions_token ~max_threads ~threadgroup_multiple =
  if descriptor.destroyed then Error "destroyed MTL4 compute pipeline descriptor"
  else if function_token <= 0 then Error "compute pipeline requires a function"
  else if Option.fold ~none:false ~some:(fun token -> token <= 0) linked_functions_token then
    Error "invalid linked-functions handle"
  else if max_threads <= 0 then Error "maximum thread count must be positive"
  else begin
    descriptor.configured <- Some { function_token; linked_functions_token; max_threads; threadgroup_multiple };
    Ok ()
  end

let snapshot descriptor =
  if descriptor.destroyed then Error "destroyed MTL4 compute pipeline descriptor"
  else Ok (Option.map (fun value ->
    value.function_token, value.linked_functions_token, value.max_threads, value.threadgroup_multiple)
    descriptor.configured)

let retained_tokens descriptor = match descriptor.configured with
  | None -> []
  | Some value -> value.function_token :: Option.to_list value.linked_functions_token

let reset descriptor =
  if descriptor.destroyed then Error "destroyed MTL4 compute pipeline descriptor"
  else begin descriptor.configured <- None; Ok () end

let destroy descriptor =
  if not descriptor.destroyed then begin descriptor.destroyed <- true; descriptor.configured <- None end

let validate_handoff () =
  if callable_ids <> [ "method:-[MTL4ComputePipelineDescriptor reset]" ] then
    invalid_arg "MTL4ComputePipeline callable1 drift"
