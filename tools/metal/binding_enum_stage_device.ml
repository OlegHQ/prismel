let family_names =
  [ "MTLAttributeFormat"
  ; "MTLStepFunction"
  ; "MTLArgumentBuffersTier"
  ; "MTLDeviceError"
  ; "MTLDeviceLocation"
  ; "MTLFeatureSet"
  ; "MTLIOCompressionMethod"
  ; "MTLReadWriteTextureTier"
  ; "MTLSparseTextureRegionAlignmentMode"
  ]

let expected_family_count = 9
let expected_case_count = 114
let expected_declaration_count = 132

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
    invalid_arg "Metal stage/device enum family count drift";
  if
    expected_declaration_count
    <> expected_case_count + (2 * expected_family_count)
  then
    invalid_arg "Metal stage/device enum declaration count drift"
