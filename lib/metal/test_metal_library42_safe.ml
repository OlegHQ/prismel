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
  print_endline "MTLLibrary42 compile-options safe conformance: ok"
