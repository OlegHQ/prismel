type counter_buffer = { token : int; device : int; sample_count : int; destroyed : bool }
type attachment = { buffer : counter_buffer option; start_index : int; end_index : int }
type t = { device : int; attachments : attachment option array }

let callable_ids =
  [ "method:+[MTLBlitPassDescriptor blitPassDescriptor]"
  ; "method:-[MTLBlitPassDescriptor sampleBufferAttachments]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor sampleBuffer]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor setSampleBuffer:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "property:MTLBlitPassDescriptor:sampleBufferAttachments"
  ; "property:MTLBlitPassSampleBufferAttachmentDescriptor:sampleBuffer" ]

let dont_sample = -1

let validate_attachment ~device attachment =
  match attachment.buffer with
  | None when attachment.start_index = dont_sample && attachment.end_index = dont_sample -> Ok ()
  | None -> Error "blit sample indices require a counter buffer"
  | Some buffer when buffer.destroyed -> Error "destroyed blit counter buffer"
  | Some buffer when buffer.device <> device -> Error "blit counter buffer belongs to another device"
  | Some buffer when buffer.sample_count <= 0 -> Error "blit counter buffer has no samples"
  | Some buffer when attachment.start_index < 0 || attachment.end_index < 0
                     || attachment.start_index > attachment.end_index
                     || attachment.end_index >= buffer.sample_count -> Error "invalid blit sample index range"
  | Some _ -> Ok ()

let create ~device ~max_attachments attachments =
  if max_attachments <= 0 || Array.length attachments > max_attachments then
    Error "blit attachment array exceeds capability"
  else
    let attachments = Array.copy attachments in
    let rec validate index =
      if index = Array.length attachments then Ok { device; attachments }
      else match attachments.(index) with
      | None -> validate (index + 1)
      | Some attachment ->
          (match validate_attachment ~device attachment with
           | Error error -> Error error | Ok () -> validate (index + 1))
    in validate 0

let attachment descriptor ~index =
  if index < 0 || index >= Array.length descriptor.attachments then Error "blit attachment index out of range"
  else Ok descriptor.attachments.(index)

let set_attachment descriptor ~index value =
  if index < 0 || index >= Array.length descriptor.attachments then Error "blit attachment index out of range"
  else match value with
  | None -> descriptor.attachments.(index) <- None; Ok ()
  | Some attachment ->
      (match validate_attachment ~device:descriptor.device attachment with
       | Error error -> Error error
       | Ok () -> descriptor.attachments.(index) <- Some attachment; Ok ())

let sample_buffer attachment = attachment.buffer

let retained_tokens descriptor =
  descriptor.attachments |> Array.to_list
  |> List.filter_map (function Some { buffer = Some buffer; _ } -> Some buffer.token | _ -> None)

let reset descriptor = Array.fill descriptor.attachments 0 (Array.length descriptor.attachments) None

let validate_handoff () =
  if List.length callable_ids <> 8 || List.length (List.sort_uniq String.compare callable_ids) <> 8 then
    invalid_arg "BlitPass callable8 drift"
