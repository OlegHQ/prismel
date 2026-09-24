type dispatch = Serial | Concurrent
type capability = { concurrent_dispatch : bool; max_attachments : int }
type sample_buffer = { token : int; device : int; sample_count : int; destroyed : bool }
type attachment = { buffer : sample_buffer option; start_index : int; end_index : int }
type descriptor = { device : int; dispatch : dispatch; attachments : attachment option array }

let dont_sample = -1

let validate_dispatch capability = function
  | Concurrent when not capability.concurrent_dispatch -> Error "concurrent compute dispatch unsupported"
  | value -> Ok value

let validate_attachment ~device attachment =
  match attachment.buffer with
  | None when attachment.start_index = dont_sample && attachment.end_index = dont_sample -> Ok attachment
  | None -> Error "sample indices require a sample buffer"
  | Some buffer when buffer.destroyed -> Error "destroyed counter sample buffer"
  | Some buffer when buffer.device <> device -> Error "counter sample buffer belongs to another device"
  | Some buffer
    when buffer.sample_count <= 0 || attachment.start_index < 0 || attachment.end_index < 0
         || attachment.start_index > attachment.end_index || attachment.end_index >= buffer.sample_count ->
      Error "invalid compute pass sample index range"
  | Some _ -> Ok attachment

let create_descriptor ~capability ~device ~dispatch ~attachments =
  match validate_dispatch capability dispatch with
  | Error error -> Error error
  | Ok dispatch ->
      if capability.max_attachments < 0 || Array.length attachments > capability.max_attachments then
        Error "too many compute pass attachments"
      else
        let attachments = Array.copy attachments in
        let rec loop index =
          if index = Array.length attachments then Ok { device; dispatch; attachments }
          else
            match attachments.(index) with
            | None -> loop (index + 1)
            | Some attachment ->
                (match validate_attachment ~device attachment with
                 | Error error -> Error error
                 | Ok attachment -> attachments.(index) <- Some attachment; loop (index + 1))
        in
        loop 0

let replace_attachment descriptor ~index attachment =
  if index < 0 || index >= Array.length descriptor.attachments then Error "compute pass attachment index"
  else
    match attachment with
    | Some attachment ->
        (match validate_attachment ~device:descriptor.device attachment with
         | Error error -> Error error
         | Ok attachment ->
             let attachments = Array.copy descriptor.attachments in
             attachments.(index) <- Some attachment;
             Ok { descriptor with attachments })
    | None ->
        let attachments = Array.copy descriptor.attachments in
        attachments.(index) <- None;
        Ok { descriptor with attachments }

let retained_buffers descriptor =
  descriptor.attachments |> Array.to_list
  |> List.filter_map (function Some { buffer = Some buffer; _ } -> Some buffer | _ -> None)

let validate_handoff () =
  if List.length Binding_compute_pass_tail_handoff.callable_ids <> 17 then
    invalid_arg "ComputePass callable17 drift"
