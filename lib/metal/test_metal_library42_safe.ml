open Metal
let expect_ok = function Ok value -> value | Error error -> failwith error.message
let expect_error = function Error _ -> () | Ok _ -> failwith "expected rejection"
let () =
  let options = expect_ok (Compile_options.create [| "COUNT", "4"; "MODE", "safe" |]) in
  let macros = Compile_options.macros options in
  macros.(0) <- "CHANGED", "1";
  if Compile_options.macros options <> [| "COUNT", "4"; "MODE", "safe" |]
  then failwith "compile-options macro snapshot escaped";
  expect_error (Compile_options.create [| "", "1" |]);
  expect_error (Compile_options.create [| "A", "1"; "A", "2" |]);
  let required = Compile_options.{ width=1L; height=1L; depth=1L } in
  (match Compile_options.create ~required_threads:required [||] with
   | Ok value ->
       if Compile_options.required_threads value <> Some required then
         failwith "required threadgroup snapshot mismatch";
       ignore (expect_ok (Compile_options.destroy value))
   | Error { kind=Unsupported; _ } -> ()
   | Error error -> failwith error.message);
  ignore (expect_ok (Compile_options.destroy options));
  let device = expect_ok (Device.system_default ()) in
  let library = expect_ok (Library.compile_source ~device
    "#include <metal_stdlib>\nusing namespace metal; kernel void library42(device uint *out [[buffer(0)]]) { out[0]=42; }\n") in
  let reflected = Library.reflection library "library42" in
  (match reflected with Ok _ | Error { kind=Unsupported; _ } -> ()
   | Error error -> failwith error.message);
  let task = expect_ok (Library_function_task.start ~library
    Library_function_task.Descriptor "library42") in
  let rec await remaining =
    if remaining = 0 then failwith "library callback timed out"
    else match expect_ok (Library_function_task.poll task) with
      | Library_function_task.Pending -> Unix.sleepf 0.001; await (remaining-1)
      | Library_function_task.Cancelled -> failwith "library callback cancelled"
      | Library_function_task.Complete result -> expect_ok result
  in
  let function_ = await 10_000 in
  ignore (expect_ok (Function.destroy function_));
  if not (Library_function_task.destroyed task) then
    failwith "completed callback token remains live";
  for _ = 1 to 1 do
    let cancelled = expect_ok (Library_function_task.start ~library
      Library_function_task.Descriptor "library42") in
    ignore (expect_ok (Library_function_task.cancel cancelled));
    ignore (expect_ok (Library_function_task.cancel cancelled))
  done;
  ignore (expect_ok (Library.destroy library));
  ignore (expect_ok (Device.destroy device));
  print_endline "MTLLibrary42 compile-options safe conformance: ok"
