let property name =
  [ "method:-[MTLRenderPassDescriptor " ^ name ^ "]"
  ; "method:-[MTLRenderPassDescriptor set" ^ String.capitalize_ascii name ^ ":]"
  ; "property:MTLRenderPassDescriptor:" ^ name ]

let callable_ids = List.sort_uniq String.compare
  (List.concat_map property
     [ "imageblockSampleLength"; "threadgroupMemoryLength"; "tileWidth"
     ; "tileHeight"; "visibilityResultType"; "supportColorAttachmentMapping"
     ; "rasterizationRateMap" ]
   @ [ "method:-[MTLRenderPassDescriptor setSamplePositions:count:]"
     ; "method:-[MTLRenderPassDescriptor getSamplePositions:count:]" ])

let remaining_ids =
  Binding_presentation_public_audit.missing_public
  |> List.filter (fun id -> not (List.mem id callable_ids))

let validate () =
  if List.length callable_ids <> 23 || List.length remaining_ids <> 59 then
    failwith "presentation advanced 23/59 closure drift";
  if List.exists (fun id -> not (List.mem id Binding_presentation_public_audit.missing_public)) callable_ids
  then failwith "presentation advanced closure escaped residual82"

let () = validate ()
