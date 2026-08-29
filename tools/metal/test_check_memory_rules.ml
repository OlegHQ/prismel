open Check_memory_rules

let require condition message = if not condition then failwith message

let includes values expected = List.for_all (fun value -> List.mem value values) expected

let () =
  require (of_string "address-undefined" = Ok Address_undefined)
    "combined sanitizer mode is not parsed";
  require (Result.is_error (of_string "address,undefined"))
    "noncanonical combined sanitizer spelling was accepted";
  require
    (required_runtime_markers Address_undefined =
       [ "libclang_rt.asan" ])
    "combined sanitizer mode does not require the Darwin ASan runtime";
  require
    (missing_runtime_markers Address_undefined "/tmp/libclang_rt.asan_osx.dylib" =
       [])
    "Darwin combined sanitizer runtime was not recognized";
  require
    (required_instrumentation_markers Address_undefined = [ "ubsan_handle_" ])
    "combined sanitizer mode does not require UBSan instrumentation";
  require
    (missing_instrumentation_markers Address_undefined
       "U ___ubsan_handle_type_mismatch_v1_abort" = [])
    "combined UBSan instrumentation was not recognized";
  require
    (missing_instrumentation_markers Address_undefined "U _malloc" =
       [ "ubsan_handle_" ])
    "uninstrumented executable passed the combined preflight";
  require
    (includes (diagnostic_markers Address_undefined)
       [ "error: addresssanitizer"; "runtime error:";
         "addresssanitizer: deadlysignal"; "undefinedbehaviorsanitizer";
         "undefinedbehaviorsanitizer: deadlysignal"; "failed to munmap" ])
    "combined sanitizer mode does not reject both report families";
  require
    (includes (diagnostic_markers Guard_malloc)
       [ "malloc: *** error for object";
         "pointer being freed was not allocated"; "heap corruption detected" ])
    "Guard Malloc fatal diagnostics are incomplete";
  require (required_runtime_markers Leaks = [])
    "Leaks unexpectedly requires sanitizer linkage";
  print_endline
    "Metal memory-check rules: linked-runtime preflight and diagnostic families passed"
