open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok x -> x | Error e -> fail "%s" (Format.asprintf "%a" pp_error e)
let expect kind = function Error e when e.kind=kind->()|Error e->fail "%s" (Format.asprintf "%a" pp_error e)|Ok _->fail "expected rejection"

let () =
  let device=get(Device.system_default()) in
  let library=get(Library.compile_source ~device
    "#include <metal_stdlib>\nusing namespace metal; struct Args { device uint *data [[id(0)]]; uint value [[id(1)]]; }; kernel void shader157(constant Args& args [[buffer(0)]], device uint *out [[buffer(1)]]) { out[0]=args.value; }\n")in
  let function_=get(Function.find ~library "shader157")in
  ignore(get(Function.options function_));
  ignore(get(Function.patch_control_point_count function_));
  ignore(get(Function.patch_type function_));
  let attributes=get(Function.attributes function_ ~vertex:false)in
  List.iter(fun attribute->ignore(get(Shader_attribute.name attribute));ignore(get(Shader_attribute.index attribute));ignore(get(Shader_attribute.data_type attribute));ignore(get(Shader_attribute.active attribute));ignore(get(Shader_attribute.patch_control_point_data attribute));ignore(get(Shader_attribute.patch_data attribute)))attributes;
  expect Invalid_argument(Function.argument_encoder function_ ~buffer_index:(-1L));
  let encoder=get(Function.argument_encoder function_ ~buffer_index:0L)in
  if Shader_argument_encoder.buffer_index encoder<>0L then fail "argument encoder index drift";
  let _,encoded_length,alignment,encoder_device=Shader_argument_encoder.snapshot encoder in
  if encoded_length<=0L||alignment<=0L||encoder_device!=device then fail "argument encoder snapshot drift";
  get(Shader_argument_encoder.set_label encoder(Some "args"));
  if Shader_argument_encoder.label encoder<>Some "args" then fail "argument encoder label drift";
  let argument_buffer=get(Buffer.create~device~length:encoded_length~storage:Buffer.Shared())in
  let data=get(Buffer.create~device~length:64L~storage:Buffer.Shared())in
  get(Shader_argument_encoder.set_argument_buffer encoder argument_buffer~offset:0L());
  get(Shader_argument_encoder.set encoder~index:0L(Shader_argument_encoder.Buffer data));
  get(Shader_argument_encoder.set_array encoder~location:0L~offsets:[|0L|]
    [|Shader_argument_encoder.Buffer data|]);
  let wrong_kind=get(Texture.create~device(Texture.descriptor_2d~format:Texture.Rgba8_unorm~width:1~height:1()))in
  expect Invalid_argument(Shader_argument_encoder.set_array encoder~location:0L
    [|Shader_argument_encoder.Buffer data;Shader_argument_encoder.Texture
      wrong_kind|]);
  ignore(get(Shader_argument_encoder.constant_available encoder~index:1L));
  expect Parent_has_dependents(Buffer.destroy data);
  expect Parent_has_dependents(Function.destroy function_);
  get(Shader_argument_encoder.destroy encoder);
  get(Texture.destroy wrong_kind);
  get(Buffer.destroy data);get(Buffer.destroy argument_buffer);
  List.iter(fun x->get(Shader_attribute.destroy x))attributes;
  get(Function.destroy function_);
  expect Destroyed(Function.options function_);
  let stage=get(Shader_stage_descriptor.create())in
  get(Shader_stage_descriptor.set_index_buffer_index stage 3L);
  get(Shader_stage_descriptor.set_index_type stage Shader_stage_descriptor.Uint32);
  if get(Shader_stage_descriptor.index_buffer_index stage)<>3L then fail "stage index drift";
  let attributes=get(Shader_stage_descriptor.attributes stage)in
  let layouts=get(Shader_stage_descriptor.layouts stage)in
  expect Invalid_argument(Shader_attribute_descriptors.at attributes ~index:31);
  let descriptor=get(Shader_attribute_descriptors.at attributes ~index:0)in
  get(Shader_attribute_descriptor.set_buffer_index descriptor 2L);
  get(Shader_attribute_descriptor.set_offset descriptor 16L);
  get(Shader_attribute_descriptor.set_format descriptor Enum.Mtl_attribute_format.mtl_attribute_format_float3);
  get(Shader_attribute_descriptors.set attributes ~index:0 descriptor);
  if get(Shader_attribute_descriptor.buffer_index descriptor)<>2L then fail "attribute buffer index drift";
  if get(Shader_attribute_descriptor.offset descriptor)<>16L then fail "attribute offset drift";
  if get(Shader_attribute_descriptor.format descriptor)<>Enum.Mtl_attribute_format.mtl_attribute_format_float3 then fail "attribute format drift";
  expect Parent_has_dependents(Shader_stage_descriptor.destroy stage);
  get(Shader_attribute_descriptor.destroy descriptor);
  get(Shader_attribute_descriptors.destroy attributes);
  get(Shader_buffer_layout_descriptors.destroy layouts);
  get(Shader_stage_descriptor.reset stage);
  get(Shader_stage_descriptor.destroy stage);
  let input=get(Shader_stitching_input.create ~argument_index:2L)in
  get(Shader_stitching_input.set_argument_index input 4L);
  if get(Shader_stitching_input.argument_index input)<>4L then fail "stitching index drift";
  get(Shader_stitching_input.destroy input);
  get(Library.destroy library);get(Device.destroy device)
