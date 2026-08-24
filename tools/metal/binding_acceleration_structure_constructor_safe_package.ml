type buffer = { token : int; device : int; length : int; destroyed : bool }
type buffer_range = { buffer : buffer; offset : int; stride : int; count : int; element_size : int }
type vertex_format = Float3 | Float4
type index_format = UInt16 | UInt32
type geometry = Bounding_boxes of buffer_range | Triangles of buffer_range * index_format option | Curves of buffer_range | Motion of geometry list
type instance_record = { acceleration_structure_index : int; options : int; mask : int; intersection_function_table_offset : int }
type descriptor = Geometry of geometry | Instances of buffer_range | Indirect_instances of buffer_range | Primitive of geometry list | Motion_keyframe of buffer_range

let validate_buffer_range ~device range =
  if range.buffer.destroyed then Error "destroyed acceleration-structure buffer"
  else if range.buffer.device <> device then Error "acceleration-structure buffer belongs to another device"
  else if range.offset < 0 || range.stride <= 0 || range.count <= 0 || range.element_size <= 0
          || range.stride < range.element_size then Error "invalid acceleration-structure range shape"
  else if range.offset > range.buffer.length then Error "acceleration-structure offset out of bounds"
  else
    let available = range.buffer.length - range.offset in
    if available < range.element_size
       || range.count - 1 > (available - range.element_size) / range.stride then
      Error "acceleration-structure range exceeds buffer"
    else Ok ()

let rec validate_geometry ~device = function
  | Bounding_boxes range | Curves range -> validate_buffer_range ~device range
  | Triangles (range, index_format) ->
      (match validate_buffer_range ~device range with
       | Error error -> Error error
       | Ok () ->
           let alignment = match index_format with None -> 4 | Some UInt16 -> 2 | Some UInt32 -> 4 in
           if range.offset mod alignment <> 0 then Error "triangle index/vertex format alignment" else Ok ())
  | Motion keyframes ->
      if List.length keyframes < 2 then Error "motion geometry requires at least two keyframes"
      else validate_geometries ~device keyframes
and validate_geometries ~device = function
  | [] -> Ok ()
  | geometry :: rest ->
      (match validate_geometry ~device geometry with Error error -> Error error | Ok () -> validate_geometries ~device rest)

let create ~device descriptor =
  let validation = match descriptor with
    | Geometry geometry -> validate_geometry ~device geometry
    | Instances range | Indirect_instances range | Motion_keyframe range -> validate_buffer_range ~device range
    | Primitive geometries ->
        if geometries = [] then Error "primitive descriptor requires geometry"
        else validate_geometries ~device geometries
  in
  Result.map (fun () -> descriptor) validation

let validate_instance_record record =
  if record.acceleration_structure_index < 0 || record.intersection_function_table_offset < 0
     || record.mask < 0 || record.mask > 0xff || record.options land lnot 0xff <> 0
  then Error "invalid fixed instance record" else Ok record

let rec geometry_tokens = function
  | Bounding_boxes range | Curves range | Triangles (range, _) -> [ range.buffer.token ]
  | Motion geometries -> List.concat_map geometry_tokens geometries

let retained_tokens = function
  | Geometry geometry -> geometry_tokens geometry
  | Instances range | Indirect_instances range | Motion_keyframe range -> [ range.buffer.token ]
  | Primitive geometries -> List.concat_map geometry_tokens geometries

let validate_handoff () =
  if List.length Binding_acceleration_structure_header_handoff.callable_ids <> 10 then
    invalid_arg "AccelerationStructure constructor callable10 drift"
