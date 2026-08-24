let fail format = Printf.ksprintf failwith format

let expect_rejection operation =
  match operation () with
  | exception Invalid_argument _ -> ()
  | _ -> fail "value-record evidence unexpectedly accepted missing proof"

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let inventory = Yojson.Safe.from_file Sys.argv.(1) in
  let selection = Binding_value_record_plan.select inventory in
  let generated = Binding_value_record_codegen.generate selection in
  let tests = generated.test_ml in
  let ids =
    Binding_value_record_evidence.bound_ids ~inventory
      ~public_interface:generated.ocaml_mli ~test_source:tests
  in
  if ids <> selection.ids || List.length ids <> 180 then
    fail "value-record bound-evidence identifier closure drift";
  expect_rejection (fun () ->
      Binding_value_record_evidence.bound_ids ~inventory ~public_interface:""
        ~test_source:tests);
  expect_rejection (fun () ->
      Binding_value_record_evidence.bound_ids ~inventory
        ~public_interface:generated.ocaml_mli ~test_source:"");
  Printf.printf "Metal value-record evidence: exact digest + 29 records guard 180 bound value/type/function IDs\n%!"
