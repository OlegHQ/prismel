open Metal
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"pp_error error)
let expect kind=function Error error when error.kind=kind->()|Error error->failwith error.message|Ok _->failwith"expected rejection"
let run () =match Device.system_default()with Error _->print_endline"binary-archive5: skipped"|Ok device->
  let source="#include <metal_stdlib>\nusing namespace metal; vertex float4 archive_vertex(){return float4(0); } fragment float4 archive_fragment(){return float4(1); } kernel void archive_kernel(){}"in
  let library=get(Library.compile_source ~device source)in
  let kernel=get(Function.find ~library "archive_kernel")and vertex=get(Function.find ~library "archive_vertex")and fragment=get(Function.find ~library "archive_fragment")in
  let archive=get(Binary_archive.create device)in
  expect Invalid_argument
    (Binary_archive.add_mesh_render_pipeline archive~mesh:kernel
       ~color_format:Texture.Rgba8_unorm());
  expect Invalid_argument
    (Binary_archive.add_tile_render_pipeline archive~tile:vertex
       ~color_format:Texture.Rgba8_unorm);
  get(Binary_archive.destroy archive);get(Function.destroy kernel);get(Function.destroy vertex);get(Function.destroy fragment);get(Library.destroy library);get(Device.destroy device);
  print_endline"binary-archive5 safe: pipeline kind rejections ok"
