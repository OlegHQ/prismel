let family_names =
  [ "MTLIntersectionFunctionSignature"
  ; "MTLArgumentType"
  ; "MTLIndirectCommandType"
  ; "MTL4CommandQueueError"
  ; "MTLIOCommandQueueType"
  ; "MTLIOError"
  ; "MTLIOPriority"
  ; "MTLMultisampleDepthResolveFilter"
  ; "MTLMultisampleStencilResolveFilter"
  ; "MTLStoreActionOptions"
  ; "MTLDynamicLibraryError"
  ; "MTLFunctionOptions"
  ; "MTLBarrierScope"
  ; "MTLResourceUsage"
  ; "MTLMutability"
  ; "MTLShaderValidation"
  ; "MTLBinaryArchiveError"
  ; "MTLIOStatus"
  ; "MTLBlitOption"
  ; "MTL4RenderEncoderOptions"
  ; "MTLStitchedLibraryOptions"
  ; "MTLIOCompressionStatus"
  ; "MTL4TimestampGranularity"
  ; "MTLLogStateError"
  ; "MTLFunctionLogType"
  ; "MTLDataType"
  ]

let expected_family_count = 26
let expected_case_count = 197
let expected_declaration_count = 249

let rec validate_family_names seen = function
  | [] -> ()
  | name :: rest ->
      if String.equal name "" then
        invalid_arg "Metal enum family name must not be empty";
      if List.exists (String.equal name) seen then
        invalid_arg ("Duplicate Metal enum family name: " ^ name);
      validate_family_names (name :: seen) rest

let () =
  validate_family_names [] family_names;
  if List.length family_names <> expected_family_count then
    invalid_arg "Metal misc enum family count drift";
  if
    expected_declaration_count
    <> expected_case_count + (2 * expected_family_count)
  then
    invalid_arg "Metal misc enum declaration count drift"
