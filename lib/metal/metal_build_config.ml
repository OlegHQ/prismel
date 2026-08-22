type sanitizer =
  | Address
  | Undefined
  | Thread

let sanitizer_name = function
  | Address -> "address"
  | Undefined -> "undefined"
  | Thread -> "thread"

let parse_sanitizers value =
  let value = String.trim value in
  let parsed =
    if value = "" || value = "none" then Ok []
    else
      value
      |> String.split_on_char ','
      |> List.map String.trim
      |> List.fold_left
           (fun result name ->
             match result, name with
             | Error _ as failure, _ -> failure
             | Ok sanitizers, "address" -> Ok (Address :: sanitizers)
             | Ok sanitizers, "undefined" -> Ok (Undefined :: sanitizers)
             | Ok sanitizers, "thread" -> Ok (Thread :: sanitizers)
             | Ok _, invalid -> Error (Printf.sprintf "unknown sanitizer %S" invalid))
           (Ok [])
  in
  match parsed with
  | Error _ as failure -> failure
  | Ok sanitizers ->
      let sanitizers = List.sort_uniq compare sanitizers in
      if List.mem Thread sanitizers && List.length sanitizers <> 1 then
        Error "thread sanitizer cannot be combined with address or undefined"
      else Ok sanitizers

let sanitizer_flag sanitizers =
  match sanitizers with
  | [] -> []
  | sanitizers ->
      [ "-fsanitize="
        ^ String.concat "," (List.map sanitizer_name sanitizers)
      ]

let undefined_flags sanitizers =
  if List.mem Undefined sanitizers then [ "-fno-sanitize-recover=undefined" ]
  else []

let compile_flags sanitizers =
  match sanitizer_flag sanitizers with
  | [] -> []
  | flags -> flags @ [ "-fno-omit-frame-pointer" ] @ undefined_flags sanitizers

let link_flags sanitizers =
  sanitizer_flag sanitizers @ undefined_flags sanitizers

let profile_compile_flags = function
  | "dev" -> [ "-O0"; "-g" ]
  | "release" -> [ "-O3"; "-DNDEBUG" ]
  | _ -> [ "-O2" ]

let framework_link_flags =
  [ "-framework"; "Foundation"; "-framework"; "Metal"; "-framework"
  ; "QuartzCore"; "-lc++"
  ]

let write_sexp path flags =
  let output = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr output)
    (fun () ->
      output_string output "(";
      flags
      |> List.iteri (fun index flag ->
        if index <> 0 then output_char output ' ';
        Printf.fprintf output "%S" flag);
      output_string output ")\n")
