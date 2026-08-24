type attachment =
  { mutable pixel_format : int option; mutable write_mask : int; mutable blending : bool
  ; mutable destroyed : bool }
type attachment_array = { entries : attachment option array; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTL4RenderPipelineColorAttachmentDescriptor reset]"
  ; "method:-[MTL4RenderPipelineColorAttachmentDescriptorArray reset]" ]

let create_attachment ~available =
  if not available then Error "MTL4 render pipelines require macOS 26"
  else Ok { pixel_format = None; write_mask = 0xf; blending = false; destroyed = false }

let configure (attachment : attachment) ~pixel_format ~write_mask ~blending =
  if attachment.destroyed then Error "destroyed MTL4 color attachment descriptor"
  else if pixel_format <= 0 then Error "invalid MTL4 color pixel format"
  else if write_mask < 0 || write_mask land lnot 0xf <> 0 then Error "invalid MTL4 color write mask"
  else begin attachment.pixel_format <- Some pixel_format; attachment.write_mask <- write_mask;
    attachment.blending <- blending; Ok () end

let snapshot (attachment : attachment) =
  if attachment.destroyed then Error "destroyed MTL4 color attachment descriptor"
  else Ok (attachment.pixel_format, attachment.write_mask, attachment.blending)

let reset_attachment (attachment : attachment) =
  if attachment.destroyed then Error "destroyed MTL4 color attachment descriptor"
  else begin attachment.pixel_format <- None; attachment.write_mask <- 0xf;
    attachment.blending <- false; Ok () end

let create_array ~available ~length =
  if not available then Error "MTL4 render pipelines require macOS 26"
  else if length <= 0 then Error "MTL4 color attachment array must be nonempty"
  else Ok { entries = Array.make length None; destroyed = false }

let set (array : attachment_array) ~index (value : attachment option) =
  if array.destroyed then Error "destroyed MTL4 color attachment array"
  else if index < 0 || index >= Array.length array.entries then Error "MTL4 color attachment index"
  else match value with
  | Some attachment when attachment.destroyed -> Error "destroyed MTL4 color attachment descriptor"
  | _ -> array.entries.(index) <- value; Ok ()

let retained_count (array : attachment_array) =
  Array.fold_left (fun count -> function None -> count | Some _ -> count + 1) 0 array.entries

let reset_array (array : attachment_array) =
  if array.destroyed then Error "destroyed MTL4 color attachment array"
  else begin Array.fill array.entries 0 (Array.length array.entries) None; Ok () end

let destroy_attachment (attachment : attachment) = attachment.destroyed <- true
let destroy_array (array : attachment_array) =
  if not array.destroyed then begin array.destroyed <- true; Array.fill array.entries 0 (Array.length array.entries) None end

let validate_handoff () =
  if List.length callable_ids <> 2 || List.length (List.sort_uniq String.compare callable_ids) <> 2 then
    invalid_arg "MTL4RenderPipeline callable2 drift"
