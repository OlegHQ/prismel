let require condition message = if not condition then failwith message

let () =
  let artifact = R10_scene3_legacy_equivalent.create ~width:640 ~height:480 in
  let proof =
    match R10_scene3_equivalence_bridge.prove ~width:640 ~height:480 artifact with
    | Ok proof -> proof
    | Error message -> failwith message
  in
  require (proof.triangles = 110_592) "exact triangle cardinality";
  require (proof.transforms = 12) "exact transform cardinality";
  require
    (List.length proof.representative_pixels_milli = 12 * 5)
    "representative pixel cardinality";
  let again = R10_scene3_legacy_equivalent.create ~width:640 ~height:480 in
  let again =
    match R10_scene3_equivalence_bridge.prove ~width:640 ~height:480 again with
    | Ok proof -> proof
    | Error message -> failwith message
  in
  require
    (again.representative_pixels_milli = proof.representative_pixels_milli)
    "frozen representative pixels";
  require (again.semantic_signature = proof.semantic_signature)
    "frozen staged signature";
  print_endline
    "R10 Scene3 public/staged equivalence: topology/transforms/material/light/camera/MSAA/pixels exact"
