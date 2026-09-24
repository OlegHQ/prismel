let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected FunctionLog rejection"

let () =
  let open Binding_function_log_safe_package in
  validate_handoff ();
  let source_url = Bytes.of_string "file:///tmp/lambda.metal" in
  let location =
    { url = Some (Bytes.unsafe_to_string source_url); function_name = Some "kernel_main"; line = 7; column = 3 }
  in
  let log =
    { log_type = Validation; encoder_label = Some "compute"; function_token = Some 41; location = Some location }
  in
  let retained = ok (retain_until_completion [ log ]) in
  Bytes.fill source_url 0 (Bytes.length source_url) 'x';
  let retained_url = match retained.logs with
    | [ { location = Some { url = Some url; _ }; _ } ] -> url
    | _ -> failwith "FunctionLog nullable graph was not retained"
  in
  if retained_url <> "file:///tmp/lambda.metal" then failwith "FunctionLog URL was not snapshotted";
  error (validate_location { location with line = 0 });
  error (validate_location { location with url = Some (String.make 1 (Char.chr 0xc0)) });
  ignore (ok (snapshot_log { log with function_token = None; location = None; encoder_label = None }));
  let completed = complete retained in
  if not completed.completed || completed.logs <> [] then failwith "FunctionLog completion retention was not released";
  Printf.printf
    "FunctionLog safe package: callable16 enum2/source4/log-graph6/source-identity4 nullable/UTF-8/snapshot/completion passed\n%!"
