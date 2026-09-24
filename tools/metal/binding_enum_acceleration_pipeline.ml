let family_names =
  [ "MTLAccelerationStructureInstanceDescriptorType"
  ; "MTLAccelerationStructureInstanceOptions"
  ; "MTLAccelerationStructureRefitOptions"
  ; "MTLAccelerationStructureUsage"
  ; "MTLCurveBasis"
  ; "MTLCurveEndCaps"
  ; "MTLCurveType"
  ; "MTLMatrixLayout"
  ; "MTLMotionBorderMode"
  ; "MTLTransformType"
  ; "MTLCompileSymbolVisibility"
  ; "MTLLanguageVersion"
  ; "MTLLibraryError"
  ; "MTLLibraryOptimizationLevel"
  ; "MTLMathFloatingPointFunctions"
  ; "MTLMathMode"
  ; "MTLPatchType"
  ; "MTLCommandBufferError"
  ; "MTLCommandBufferErrorOption"
  ; "MTLCommandEncoderErrorState"
  ; "MTLTensorDataType"
  ; "MTLTensorError"
  ; "MTLTensorUsage"
  ; "MTLTessellationControlPointIndexType"
  ; "MTLTessellationFactorFormat"
  ; "MTLTessellationFactorStepFunction"
  ; "MTLTessellationPartitionMode"
  ]

let expected_family_count = 27
let expected_case_count = 112
let expected_declaration_count = 166

let validate () =
  if List.length family_names <> expected_family_count then
    invalid_arg "Metal acceleration/pipeline enum-family count drift";
  if
    expected_declaration_count
    <> expected_case_count + (2 * expected_family_count)
  then
    invalid_arg "Metal acceleration/pipeline enum declaration count drift";
  if List.exists (fun name -> String.equal name "") family_names then
    invalid_arg
      "Metal acceleration/pipeline enum family name must not be empty";
  let sorted = List.sort String.compare family_names in
  let rec reject_duplicates = function
    | left :: right :: _ when String.equal left right ->
        invalid_arg ("Duplicate Metal enum family name: " ^ left)
    | _ :: rest -> reject_duplicates rest
    | [] -> ()
  in
  reject_duplicates sorted

let () = validate ()
