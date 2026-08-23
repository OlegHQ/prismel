open Binding_descriptor_property_spec

let sdk_version = "26.5"
let os_version = "26.4.1"
let os_build = "25E253"
let machine = "Macmini9,1 / Apple M1"
let measured_property_count = 51

let measured_nonzero =
  [ "property:MTLCompileOptions:languageVersion", 262144L
  ; "property:MTLCompileOptions:mathMode", 2L
  ; "property:MTLComputePipelineDescriptor:maxCallStackDepth", 1L
  ; "property:MTLHeapDescriptor:resourceOptions", 32L
  ; "property:MTLTextureDescriptor:resourceOptions", 16L
  ; "property:MTLIndirectCommandBufferDescriptor:inheritCullMode", 1L
  ; "property:MTLIndirectCommandBufferDescriptor:inheritDepthBias", 1L
  ; "property:MTLIndirectCommandBufferDescriptor:inheritDepthClipMode", 1L
  ; "property:MTLIndirectCommandBufferDescriptor:inheritDepthStencilState", 1L
  ; "property:MTLIndirectCommandBufferDescriptor:inheritFrontFacingWinding", 1L
  ; "property:MTLIndirectCommandBufferDescriptor:inheritTriangleFillMode", 1L
  ; ( "property:MTLIndirectCommandBufferDescriptor:maxKernelThreadgroupMemoryBindCount"
    , 31L )
  ]

let bits = function Default_bool false -> 0L | Default_bool true -> 1L | Default_int64 value -> value

let validate () =
  let entries = Binding_descriptor_property_plan.entries in
  if List.length entries <> measured_property_count then
    invalid_arg "Metal descriptor default evidence count drift";
  List.iter
    (fun entry ->
      let expected = Option.value ~default:0L (List.assoc_opt (property_sdk_id entry) measured_nonzero) in
      let actual = bits entry.default in
      if actual <> expected then
        invalid_arg
          (Printf.sprintf "Metal descriptor default drift for %s: expected %Ld, got %Ld"
             (property_sdk_id entry) expected actual))
    entries

let () = validate ()
