let ids = Binding_device_remaining6_safe_package.final4_ids

type public_site =
  { id : string
  ; module_name : string
  ; value_name : string }

let public_sites =
  [ { id = "method:-[MTLDevice functionHandleWithBinaryFunction:]"
    ; module_name = "Device_function_handle"
    ; value_name = "of_binary_function" }
  ; { id = "method:-[MTLDevice functionHandleWithFunction:]"
    ; module_name = "Device_function_handle"
    ; value_name = "of_function" }
  ; { id = "method:-[MTLDevice newArgumentEncoderWithArguments:]"
    ; module_name = "Shader_argument_encoder"
    ; value_name = "create" }
  ; { id = "method:-[MTLDevice newRenderPipelineStateWithDescriptor:error:]"
    ; module_name = "Pipeline_descriptor.Render"
    ; value_name = "compile_simple" } ]

let validate () =
  let site_ids = List.map (fun site -> site.id) public_sites in
  if List.length ids <> 4 || List.length (List.sort_uniq String.compare ids) <> 4 then
    invalid_arg "Device final4 exact ID drift";
  if List.sort String.compare site_ids <> List.sort String.compare ids then
    invalid_arg "Device final4 public-site mapping drift"
