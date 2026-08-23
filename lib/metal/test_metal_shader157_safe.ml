open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok x -> x | Error e -> fail "%s" (Format.asprintf "%a" pp_error e)
let expect kind = function Error e when e.kind=kind->()|Error e->fail "%s" (Format.asprintf "%a" pp_error e)|Ok _->fail "expected rejection"

let () =
  let device=get(Device.system_default()) in
  let library=get(Library.compile_source ~device
    "#include <metal_stdlib>\nusing namespace metal; struct Args { uint value; }; kernel void shader157(constant Args& args [[buffer(0)]], device uint *out [[buffer(1)]]) { out[0]=args.value; }\n")in
  let function_=get(Function.find ~library "shader157")in
  ignore(get(Function.options function_));
  ignore(get(Function.patch_control_point_count function_));
  ignore(get(Function.patch_type function_));
  let attributes=get(Function.attributes function_ ~vertex:false)in
  List.iter(fun attribute->ignore(get(Shader_attribute.name attribute));ignore(get(Shader_attribute.index attribute));ignore(get(Shader_attribute.data_type attribute));ignore(get(Shader_attribute.active attribute));ignore(get(Shader_attribute.patch_control_point_data attribute));ignore(get(Shader_attribute.patch_data attribute)))attributes;
  expect Invalid_argument(Function.argument_encoder function_ ~buffer_index:(-1L));
  let encoder=get(Function.argument_encoder function_ ~buffer_index:0L)in
  if Shader_argument_encoder.buffer_index encoder<>0L then fail "argument encoder index drift";
  expect Parent_has_dependents(Function.destroy function_);
  get(Shader_argument_encoder.destroy encoder);
  List.iter(fun x->get(Shader_attribute.destroy x))attributes;
  get(Function.destroy function_);
  expect Destroyed(Function.options function_);
  get(Library.destroy library);get(Device.destroy device)
