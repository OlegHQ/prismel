let commit = "57e1078952b62a39452665cea68d3629530b45b6"
let source_path = "tools/bench_renderer.ml"
let source_sha256 =
  "dac6871f68b57264c5cd641f2d7887865db712d9113af0de23a94e7173c2fe7c"
let source_bytes = 15_678

let expected = function
  | R10_scene2_legacy_equivalent.Basic ->
      (9, "r10-public-basic-v2:34789495c96ce3fbbbf536f5632b896c")
  | Pxui ->
      (21, "r10-public-pxui-v2:ac0f4966af0f54b08008a10d21b6e4f6")
  | Canvas ->
      (7, "r10-public-canvas-v2:cd1d28d9089af1e686c4bf5bc703412a")
  | Scene3 ->
      (110_592, "r10-public-scene3-v2:27d16e56efacacc1c93fbc3e9b7adc88")

let scenario_name = function
  | R10_scene2_legacy_equivalent.Basic -> "basic"
  | Pxui -> "pxui"
  | Canvas -> "canvas"
  | Scene3 -> "scene3"

let validate_descriptor scenario descriptor =
  let work_units, signature = expected scenario in
  if descriptor.R10_scene2_legacy_equivalent.scenario <> scenario
     || descriptor.work_units <> work_units
     || descriptor.semantic_signature <> signature
  then
    invalid_arg
      (Printf.sprintf "Phase0 %s workload descriptor drift"
         (scenario_name scenario))

let read_process program argv =
  let input = Unix.open_process_args_in program argv in
  let buffer = Buffer.create source_bytes in
  (try while true do Buffer.add_char buffer (input_char input) done
   with End_of_file -> ());
  match Unix.close_process_in input with
  | Unix.WEXITED 0 -> Buffer.contents buffer
  | Unix.WEXITED code ->
      failwith (Printf.sprintf "%s exited %d" program code)
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
      failwith (Printf.sprintf "%s received signal %d" program signal)

let verify_frozen_source () =
  let object_name = commit ^ ":" ^ source_path in
  let contents =
    read_process "/usr/bin/git"
      [| "/usr/bin/git"; "cat-file"; "blob"; object_name |]
  in
  let digest = Digestif.SHA256.(to_hex (digest_string contents)) in
  if String.length contents <> source_bytes || digest <> source_sha256 then
    failwith "Phase0 renderer workload source authority drift"

let validate_all ~width ~height =
  if width <> 640 || height <> 480 then
    invalid_arg "Phase0 R10 authority is frozen at 640x480";
  verify_frozen_source ();
  List.iter
    (fun scenario ->
      validate_descriptor scenario
        (R10_scene2_legacy_equivalent.describe scenario ~width ~height))
    [ R10_scene2_legacy_equivalent.Basic; Pxui; Canvas; Scene3 ]
