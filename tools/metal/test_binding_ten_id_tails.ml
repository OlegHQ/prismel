let count inventory header =
  let open Yojson.Safe.Util in
  inventory |> member "symbols" |> to_list
  |> List.filter (fun j ->
    j |> member "classification" |> to_string = "bound"
    && j |> member "header" |> to_string = header)

let owners items =
  let open Yojson.Safe.Util in
  List.map (fun j -> j |> member "owner" |> to_string_option) items

let count_owner owner values =
  List.length (List.filter (fun value -> value = Some owner) values)

let () =
  if Array.length Sys.argv <> 2 then invalid_arg "inventory";
  let inventory = Yojson.Safe.from_file Sys.argv.(1) in
  let stage = count inventory "Metal/MTLStageInputOutputDescriptor.h"
  and drawable = count inventory "Metal/MTLDrawable.h"
  and blit = count inventory "Metal/MTLBlitPass.h" in
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
