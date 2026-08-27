open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let ()=
  match Device.system_default()with Error _->print_endline"device value25: skipped"|Ok device->
  let architecture=get(Device.architecture device)in
  if Architecture.name architecture="" then failwith"empty architecture name";
  let descriptor=get(Shader_argument_encoder.descriptor
    ~data_type:Data_type.mtl_data_type_u_int ~index:3L ~array_length:7L
    ~access:Shader_argument_encoder.Read_write
    ~texture_kind:Texture.Texture_2d ~constant_block_alignment:16L())in
  let snapshot=Shader_argument_encoder.descriptor_snapshot descriptor in
  if snapshot.index<>3L||snapshot.array_length<>7L||snapshot.constant_block_alignment<>16L
  then failwith"argument descriptor snapshot drift";
  let encoder=get(Shader_argument_encoder.create device[descriptor])in
  get(Shader_argument_encoder.destroy encoder);
  get(Device.destroy device);
  print_endline"device value25: argument descriptor + architecture ok"
