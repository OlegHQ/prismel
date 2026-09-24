type mode =
  | Address
  | Undefined
  | Address_undefined
  | Thread
  | Leaks
  | Guard_malloc

let of_string = function
  | "address" -> Ok Address
  | "undefined" -> Ok Undefined
  | "address-undefined" -> Ok Address_undefined
  | "thread" -> Ok Thread
  | "leaks" -> Ok Leaks
  | "guard-malloc" -> Ok Guard_malloc
  | value -> Error value

let name = function
  | Address -> "address"
  | Undefined -> "undefined"
  | Address_undefined -> "address-undefined"
  | Thread -> "thread"
  | Leaks -> "leaks"
  | Guard_malloc -> "guard-malloc"

let address_markers =
  [ "error: addresssanitizer"; "addresssanitizer: check failed";
    "addresssanitizer: deadlysignal"; "addresssanitizer: aborting";
    "leaksanitizer"; "failed to munmap" ]

let undefined_markers =
  [ "runtime error:"; "undefinedbehaviorsanitizer";
    "undefinedbehaviorsanitizer: deadlysignal" ]

let diagnostic_markers = function
  | Address -> address_markers
  | Undefined -> undefined_markers
  | Address_undefined -> address_markers @ undefined_markers
  | Thread ->
      [ "warning: threadsanitizer"; "threadsanitizer: reported";
        "error: threadsanitizer"; "fatal: threadsanitizer" ]
  | Leaks -> [ "root leak"; "leak of" ]
  | Guard_malloc ->
      [ "guardmalloc: invalid"; "guardmalloc: error"; "guard malloc:";
        "malloc: *** error for object";
        "pointer being freed was not allocated"; "heap corruption detected";
        "double free"; "use-after-free" ]

let required_runtime_markers = function
  | Address -> [ "libclang_rt.asan" ]
  | Undefined -> [ "libclang_rt.ubsan" ]
  | Address_undefined -> [ "libclang_rt.asan" ]
  | Thread -> [ "libclang_rt.tsan" ]
  | Leaks | Guard_malloc -> []

let required_instrumentation_markers = function
  | Undefined | Address_undefined -> [ "ubsan_handle_" ]
  | Address | Thread | Leaks | Guard_malloc -> []

let missing_markers required inspected =
  let inspected = String.lowercase_ascii inspected in
  let contains needle =
    let needle_length = String.length needle
    and value_length = String.length inspected in
    let rec search index =
      index + needle_length <= value_length
      && (String.sub inspected index needle_length = needle
          || search (index + 1))
    in
    search 0
  in
  List.filter (fun marker -> not (contains marker)) required

let missing_runtime_markers mode linked_libraries =
  missing_markers (required_runtime_markers mode) linked_libraries

let missing_instrumentation_markers mode undefined_symbols =
  missing_markers (required_instrumentation_markers mode) undefined_symbols
