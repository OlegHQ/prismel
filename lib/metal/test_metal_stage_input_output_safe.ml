open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok _ -> failwith "expected StageInputOutputDescriptor rejection"

let () =
  let descriptor = get (Shader_stage_descriptor.create ()) in
  let attributes = get (Shader_stage_descriptor.attributes descriptor) in
  let layouts = get (Shader_stage_descriptor.layouts descriptor) in
  expect Invalid_argument (Shader_attribute_descriptors.at attributes ~index:(-1));
  expect Invalid_argument
    (Shader_attribute_descriptors.at attributes
       ~index:Shader_attribute_descriptors.capacity);
  let attribute = get (Shader_attribute_descriptors.at attributes ~index:0) in
  get
    (Shader_attribute_descriptor.set_format attribute
       Enum.Mtl_attribute_format.mtl_attribute_format_float3);
  get (Shader_attribute_descriptor.set_offset attribute 4L);
  get (Shader_attribute_descriptor.set_buffer_index attribute 0L);
  if
    get (Shader_attribute_descriptor.format attribute)
    <> Enum.Mtl_attribute_format.mtl_attribute_format_float3
     || get (Shader_attribute_descriptor.offset attribute) <> 4L
     || get (Shader_attribute_descriptor.buffer_index attribute) <> 0L
  then failwith "stage attribute round-trip drift";
  expect Invalid_argument (Shader_attribute_descriptor.set_offset attribute (-1L));
  expect Invalid_argument (Shader_attribute_descriptor.set_buffer_index attribute 31L);
  let other = get (Shader_stage_descriptor.create ()) in
  let other_attributes = get (Shader_stage_descriptor.attributes other) in
  let other_attribute = get (Shader_attribute_descriptors.at other_attributes ~index:0) in
  expect Invalid_argument
    (Shader_attribute_descriptors.set attributes ~index:1 other_attribute);
  get (Shader_attribute_descriptors.set attributes ~index:1 attribute);
  get (Shader_stage_descriptor.reset descriptor);
  expect Parent_has_dependents (Shader_stage_descriptor.destroy descriptor);
  get (Shader_attribute_descriptor.destroy attribute);
  get (Shader_attribute_descriptors.destroy attributes);
  get (Shader_buffer_layout_descriptors.destroy layouts);
  get (Shader_stage_descriptor.destroy descriptor);
  get (Shader_attribute_descriptor.destroy other_attribute);
  get (Shader_attribute_descriptors.destroy other_attributes);
  get (Shader_stage_descriptor.destroy other);
  print_endline "stage input/output safe: exact7 ok"
