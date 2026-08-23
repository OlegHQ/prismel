let fail format = Printf.ksprintf failwith format

let rec mkdir_p path =
  if path = "" || path = "." || Sys.file_exists path then ()
  else begin
    mkdir_p (Filename.dirname path);
    Unix.mkdir path 0o755
  end

let copy_file source destination =
  let input_channel = open_in_bin source in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input_channel)
    (fun () ->
      let output_channel = open_out_bin destination in
      Fun.protect
        ~finally:(fun () -> close_out_noerr output_channel)
        (fun () ->
          let buffer = Bytes.create 65_536 in
          let rec loop () =
            match input input_channel buffer 0 (Bytes.length buffer) with
            | 0 -> ()
            | count ->
                output output_channel buffer 0 count;
                loop ()
          in
          loop ()))

let write_file destination contents =
  let output = open_out_bin destination in
  Fun.protect
    ~finally:(fun () -> close_out_noerr output)
    (fun () -> output_string output contents)

let xml_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | '\'' -> Buffer.add_string buffer "&apos;"
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let plist entries =
  let pairs =
    entries
    |> List.map (fun (key, value) ->
      Printf.sprintf "<key>%s</key><string>%s</string>"
        (xml_escape key) (xml_escape value))
    |> String.concat "\n"
  in
  String.concat "\n"
    [ {|<?xml version="1.0" encoding="UTF-8"?>|}
    ; {|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">|}
    ; {|<plist version="1.0"><dict>|}
    ; pairs
    ; {|</dict></plist>|}
    ; ""
    ]

let service_plist ~executable ~identifier =
  String.concat "\n"
    [ {|<?xml version="1.0" encoding="UTF-8"?>|}
    ; {|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">|}
    ; {|<plist version="1.0"><dict>|}
    ; Printf.sprintf "<key>CFBundleExecutable</key><string>%s</string>"
        (xml_escape executable)
    ; Printf.sprintf "<key>CFBundleIdentifier</key><string>%s</string>"
        (xml_escape identifier)
    ; {|<key>CFBundlePackageType</key><string>XPC!</string>|}
    ; {|<key>CFBundleVersion</key><string>1</string>|}
    ; {|<key>XPCService</key><dict><key>ServiceType</key><string>Application</string></dict>|}
    ; {|</dict></plist>|}
    ; ""
    ]

let () =
  let client = ref None
  and service = ref None
  and output_directory = ref None
  and service_name = ref None in
  let set target value = target := Some value in
  Arg.parse
    [ "--client", Arg.String (set client), "PATH client executable"
    ; "--service", Arg.String (set service), "PATH XPC service executable"
    ; "--output", Arg.String (set output_directory), "PATH output .app"
    ; "--service-name", Arg.String (set service_name), "NAME XPC service name"
    ]
    (fun argument -> fail "unexpected argument %S" argument)
    "build_xpc_bundle";
  let required name = function
    | Some value when value <> "" -> value
    | Some _ | None -> fail "missing %s" name
  in
  let client = required "--client" !client
  and service = required "--service" !service
  and output_directory = required "--output" !output_directory
  and service_name = required "--service-name" !service_name in
  let client_name = "test_metal_xpc_client"
  and service_executable = "test_metal_xpc_service" in
  let contents = Filename.concat output_directory "Contents" in
  let host_bin = Filename.concat contents "MacOS" in
  let service_contents =
    Filename.concat contents
      (Filename.concat "XPCServices"
         (Filename.concat (service_name ^ ".xpc") "Contents"))
  in
  let service_bin = Filename.concat service_contents "MacOS" in
  mkdir_p host_bin;
  mkdir_p service_bin;
  let client_target = Filename.concat host_bin client_name in
  let service_target = Filename.concat service_bin service_executable in
  copy_file client client_target;
  copy_file service service_target;
  Unix.chmod client_target 0o755;
  Unix.chmod service_target 0o755;
  write_file (Filename.concat contents "Info.plist")
    (plist
       [ "CFBundleExecutable", client_name
       ; "CFBundleIdentifier", "org.prismel.metal.xpc-conformance-host"
       ; "CFBundlePackageType", "APPL"
       ; "CFBundleVersion", "1"
       ]);
  write_file (Filename.concat service_contents "Info.plist")
    (service_plist ~executable:service_executable ~identifier:service_name)
