type public_module =
  | Render_pass_descriptor
  | Layer
  | Drawable
  | Command_buffer

type item =
  { id : string
  ; public_module : public_module
  ; public_operation : string
  ; required_tests : string list
  }

let contains s needle =
  let needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= String.length s
    &&
    (String.sub s offset needle_length = needle || loop (offset + 1))
  in
  loop 0

let module_of_id id =
  if contains id "MTLRenderPassDescriptor" then Render_pass_descriptor
  else if contains id "CAMetalLayer" then Layer
  else if contains id "CAMetalDrawable" then Drawable
  else if contains id "MTLCommandBuffer" then Command_buffer
  else failwith ("Presentation81 ID has no public-module owner: " ^ id)

let operation_and_tests = function
  | Render_pass_descriptor ->
      ( "Metal.Render_pass_descriptor"
      , [ "exact native round trip"
        ; "attachment ownership and mutation-after-create"
        ; "wrong device/format/size/sample rejection with no handle delta"
        ; "native setter rollback on failure"
        ] )
  | Layer ->
      ( "Metal.Layer"
      , [ "availability and nullable-value round trip"
        ; "device identity and retained configuration"
        ; "destroy-order and no-handle-delta rejection"
        ] )
  | Drawable ->
      ( "Metal.Drawable"
      , [ "layer parent identity"
        ; "texture and drawable lifetime retention"
        ; "destroy-order and no-handle-delta rejection"
        ] )
  | Command_buffer ->
      ( "Metal.Command_buffer"
      , [ "real submission exact behavior"
        ; "scheduled/completed callback retention"
        ; "encoder/result ownership through completion"
        ; "wrong-device/state rejection with no handle delta"
        ] )

let make id =
  let public_module = module_of_id id in
  let public_operation, required_tests = operation_and_tests public_module in
  { id; public_module; public_operation; required_tests }

let pending_items =
  Binding_presentation_public_audit.missing_public
  |> List.filter (fun id -> id <> "record:_CAMetalLayerPrivate")
  |> List.map make

let items_for public_module =
  List.filter (fun item -> item.public_module = public_module) pending_items

let modules = [ Render_pass_descriptor; Layer; Drawable; Command_buffer ]

let private_metadata_ids =
  [ "record:_CAMetalLayerPrivate" ]

let final_graph_blocked id =
  contains id "rasterizationRateMap"
  || contains id "sampleBufferAttachments"
  || contains id "parallelRenderCommandEncoderWithDescriptor"

let promotable_ids =
  pending_items |> List.filter_map (fun item ->
    if final_graph_blocked item.id then None else Some item.id)

let validate () =
  let ids = List.map (fun item -> item.id) pending_items in
  let category_counts =
    List.map (fun public_module -> List.length (items_for public_module)) modules
  in
  if List.length pending_items <> 81
     || List.sort_uniq String.compare ids
        <> (Binding_presentation_public_audit.missing_public
            |> List.filter(fun id->id<>"record:_CAMetalLayerPrivate")
            |> List.sort String.compare)
     || List.exists
          (fun item -> item.public_operation = "" || item.required_tests = [])
          pending_items
     || category_counts <> [ 31; 17; 2; 31 ]
     || List.length promotable_ids <> 76
     || private_metadata_ids <> [ "record:_CAMetalLayerPrivate" ]
  then failwith "Presentation81 public-module safe handoff drift"

let () = validate ()
