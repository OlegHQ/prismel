let count inventory header exact_ids =
  let open Yojson.Safe.Util in
  inventory |> member "symbols" |> to_list
  |> List.filter (fun j ->
    let id = j |> member "id" |> to_string in
    j |> member "classification" |> to_string = "bound"
    && j |> member "header" |> to_string = header
    && List.mem id exact_ids)

let owners items =
  let open Yojson.Safe.Util in
  List.map (fun j -> j |> member "owner" |> to_string_option) items

let count_owner owner values =
  List.length (List.filter (fun value -> value = Some owner) values)

let stage_callable_ids =
  [ "method:-[MTLAttributeDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLAttributeDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLStageInputOutputDescriptor attributes]"
  ; "method:-[MTLStageInputOutputDescriptor layouts]"
  ; "method:-[MTLStageInputOutputDescriptor reset]"
  ; "property:MTLStageInputOutputDescriptor:attributes"
  ; "property:MTLStageInputOutputDescriptor:layouts" ]

let drawable_callable_ids =
  [ "method:-[MTLDrawable addPresentedHandler:]"; "method:-[MTLDrawable drawableID]"
  ; "method:-[MTLDrawable presentAfterMinimumDuration:]"; "method:-[MTLDrawable presentAtTime:]"
  ; "method:-[MTLDrawable present]"; "method:-[MTLDrawable presentedTime]"
  ; "property:MTLDrawable:drawableID"; "property:MTLDrawable:presentedTime" ]

let blit_callable_ids =
  [ "method:+[MTLBlitPassDescriptor blitPassDescriptor]"
  ; "method:-[MTLBlitPassDescriptor sampleBufferAttachments]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor sampleBuffer]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptor setSampleBuffer:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLBlitPassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]"
  ; "property:MTLBlitPassDescriptor:sampleBufferAttachments"
  ; "property:MTLBlitPassSampleBufferAttachmentDescriptor:sampleBuffer" ]

let stage_metadata_ids =
  [ "class:MTLAttributeDescriptor"; "class:MTLAttributeDescriptorArray"
  ; "class:MTLStageInputOutputDescriptor" ]

let drawable_metadata_ids = [ "protocol:MTLDrawable"; "typedef:MTLDrawablePresentedHandler" ]

let blit_metadata_ids =
  [ "class:MTLBlitPassDescriptor"; "class:MTLBlitPassSampleBufferAttachmentDescriptorArray" ]

let () =
  if Array.length Sys.argv <> 2 then invalid_arg "inventory";
  let inventory = Yojson.Safe.from_file Sys.argv.(1) in
  let stage = count inventory "Metal/MTLStageInputOutputDescriptor.h" (stage_callable_ids @ stage_metadata_ids)
  and drawable = count inventory "Metal/MTLDrawable.h" (drawable_callable_ids @ drawable_metadata_ids)
  and blit = count inventory "Metal/MTLBlitPass.h" (blit_callable_ids @ blit_metadata_ids) in
  if List.length stage <> 10
     || count_owner "MTLAttributeDescriptorArray" (owners stage) <> 2
     || count_owner "MTLStageInputOutputDescriptor" (owners stage) <> 5
  then failwith "StageInputOutput10 closure drift";
  if List.length drawable <> 10
     || count_owner "MTLDrawable" (owners drawable) <> 8
  then failwith "Drawable10 closure drift";
  if List.length blit <> 10
     || count_owner "MTLBlitPassDescriptor" (owners blit) <> 3
     || count_owner "MTLBlitPassSampleBufferAttachmentDescriptor" (owners blit) <> 3
     || count_owner "MTLBlitPassSampleBufferAttachmentDescriptorArray" (owners blit) <> 2
  then failwith "BlitPass10 closure drift";
  print_endline
    "10-ID tails: StageIO ownership/effect7 metadata3; Drawable mechanical4 effect4 metadata2; BlitPass ownership8 metadata2"
