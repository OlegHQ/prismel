type format = Invalid | Float | Float2 | Float3 | Float4 | UChar4_normalized
type attribute = { format : format; offset : int; buffer_index : int }
type layout = { stride : int }
type t = { attributes : attribute option array; layouts : layout option array }

let callable_ids =
  [ "method:-[MTLAttributeDescriptorArray objectAtIndexedSubscript:]"
  ; "method:-[MTLAttributeDescriptorArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLStageInputOutputDescriptor attributes]"
  ; "method:-[MTLStageInputOutputDescriptor layouts]"
  ; "method:-[MTLStageInputOutputDescriptor reset]"
  ; "property:MTLStageInputOutputDescriptor:attributes"
  ; "property:MTLStageInputOutputDescriptor:layouts" ]

let create ~max_attributes ~max_buffers =
  if max_attributes <= 0 || max_buffers <= 0 then Error "stage descriptor capacities must be positive"
  else Ok { attributes = Array.make max_attributes None; layouts = Array.make max_buffers None }

let set_layout descriptor ~index layout =
  if index < 0 || index >= Array.length descriptor.layouts then Error "layout index out of range"
  else match layout with
  | Some layout when layout.stride <= 0 -> Error "layout stride must be positive"
  | _ -> descriptor.layouts.(index) <- layout; Ok ()

let format_size = function
  | Invalid -> None | Float -> Some 4 | Float2 -> Some 8 | Float3 -> Some 12
  | Float4 -> Some 16 | UChar4_normalized -> Some 4

let validate_attribute descriptor attribute =
  if attribute.offset < 0 then Error "attribute offset must be nonnegative"
  else if attribute.buffer_index < 0 || attribute.buffer_index >= Array.length descriptor.layouts then
    Error "attribute buffer index out of range"
  else match format_size attribute.format, descriptor.layouts.(attribute.buffer_index) with
  | None, _ -> Error "invalid attribute format"
  | _, None -> Error "attribute buffer has no layout"
  | Some size, Some layout when attribute.offset > layout.stride || size > layout.stride - attribute.offset ->
      Error "attribute range exceeds buffer stride"
  | Some _, Some _ -> Ok ()

let set_attribute descriptor ~index attribute =
  if index < 0 || index >= Array.length descriptor.attributes then Error "attribute index out of range"
  else match attribute with
  | None -> descriptor.attributes.(index) <- None; Ok ()
  | Some attribute ->
      (match validate_attribute descriptor attribute with
       | Error error -> Error error
       | Ok () -> descriptor.attributes.(index) <- Some attribute; Ok ())

let attribute descriptor ~index =
  if index < 0 || index >= Array.length descriptor.attributes then Error "attribute index out of range"
  else Ok descriptor.attributes.(index)

let attributes_snapshot descriptor = Array.copy descriptor.attributes
let layouts_snapshot descriptor = Array.copy descriptor.layouts
let retained_attribute_count descriptor =
  Array.fold_left (fun count -> function None -> count | Some _ -> count + 1) 0 descriptor.attributes

let reset descriptor =
  Array.fill descriptor.attributes 0 (Array.length descriptor.attributes) None;
  Array.fill descriptor.layouts 0 (Array.length descriptor.layouts) None

let validate_handoff () =
  if List.length callable_ids <> 7 || List.length (List.sort_uniq String.compare callable_ids) <> 7 then
    invalid_arg "StageInputOutputDescriptor callable7 drift"
