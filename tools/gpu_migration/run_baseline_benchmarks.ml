open Support

module String_set = Set.Make (String)

let baseline_relative =
  "specification/evidence/gpu_migration/phase0_baseline.json"

let environment_relative =
  "specification/evidence/gpu_migration/phase0_environment.json"

let output_relative =
  "specification/evidence/gpu_migration/phase0_performance.json"

let renderer_scenarios = [ "basic"; "pxui"; "canvas"; "scene3" ]
let render_targets = [ "native"; "headless"; "web" ]
let default_samples = 5
let default_warmup_seconds = 3.0
let default_measure_seconds = 30.0

let numeric_metrics =
  [ "frames"; "wall_seconds"; "frames_per_second"; "median_frame_seconds"
  ; "p95_frame_seconds"; "p99_frame_seconds"; "user_seconds"
  ; "system_seconds"; "cpu_percent"; "allocated_bytes"; "minor_bytes"
  ; "promoted_bytes"; "major_bytes"; "major_collections"; "ending_heap_bytes"
  ; "peak_heap_bytes"; "starting_rss_kib"; "ending_rss_kib"
  ; "peak_sampled_rss_kib"; "external_peak_rss_bytes"
  ; "legacy_gpu_duration_seconds"; "legacy_gpu_utilization_percent"
  ; "legacy_draw_count"; "legacy_upload_bytes"; "cook_seconds"
  ; "pack_seconds"; "geometry_payload_bytes"; "packed_payload_bytes"
  ]

type case =
  { benchmark : string
  ; scenario : string
  ; target : string option
  }

let case_key case =
  Printf.sprintf "%s:%s:%s" case.benchmark
    (Option.value case.target ~default:"cpu") case.scenario

let cases () =
  let ordinary =
    List.concat_map
      (fun target ->
        List.map
          (fun scenario -> { benchmark = "renderer"; scenario; target = Some target })
          renderer_scenarios)
      render_targets
  in
  ordinary
  @ [ { benchmark = "shattered_renderer"
      ; scenario = "shattered-visible"
      ; target = Some "native"
      }
    ; { benchmark = "shattered_renderer"
      ; scenario = "shattered-hidden"
      ; target = Some "native"
      }
    ; { benchmark = "shattered_cube"; scenario = "cook"; target = None }
    ]

let split_lines value =
  if value = "" then [] else String.split_on_char '\n' value

let iso8601_now () =
  let now = Unix.time () in
  let local = Unix.localtime now in
  let utc = Unix.gmtime now in
  let local_epoch, _ = Unix.mktime local in
  let utc_as_local, _ = Unix.mktime utc in
  let offset = int_of_float (local_epoch -. utc_as_local) in
  let sign = if offset < 0 then '-' else '+' in
  let offset = abs offset in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d%c%02d:%02d"
    (local.tm_year + 1900) (local.tm_mon + 1) local.tm_mday local.tm_hour
    local.tm_min local.tm_sec sign (offset / 3600) ((offset mod 3600) / 60)

let condition_lines root program arguments =
  let result = command ~cwd:root program arguments in
  let value = if result.stdout <> "" then result.stdout else result.stderr in
  if value = "" then
    let code =
      match result.status with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal
    in
    [ Printf.sprintf "unavailable (exit %d)" code ]
  else split_lines value

let string_list values = `List (List.map (fun value -> `String value) values)

let runtime_conditions root =
  `Assoc
    [ "captured_at", `String (iso8601_now ())
    ; "power", string_list (condition_lines root "pmset" [ "-g"; "batt" ])
    ; "thermal", string_list (condition_lines root "pmset" [ "-g"; "therm" ])
    ]

let explicit_environment case ~warmup ~seconds ~sample_index =
  let values =
    ref
      [ "PRISMEL_BENCH_PROFILE", "release"
      ; "PRISMEL_RENDERER_BENCH_WARMUP", Printf.sprintf "%g" warmup
      ; "PRISMEL_RENDERER_BENCH_SECONDS", Printf.sprintf "%g" seconds
      ]
  in
  Option.iter
    (fun target -> values := !values @ [ "PRISMEL_RENDER_TARGET", target ])
    case.target;
  if case.benchmark = "renderer" then begin
    values := !values @ [ "PRISMEL_BENCH_DOMAINS", "1" ];
    if case.target = Some "web" then
      values := !values @ [ "PRISMEL_WEB_PORT", "0" ]
  end
  else if case.benchmark = "shattered_renderer" then
    values :=
      !values
      @ [ "PRISMEL_SHATTER_DOMAINS", "1"; "PRISMEL_SHATTER_GRAIN", "2" ]
  else
    values :=
      !values
      @ [ "PRISMEL_SHATTER_DOMAINS", "7"
        ; "PRISMEL_SHATTER_GRAIN", "2"
        ; "PRISMEL_SHATTER_VERIFY_DOMAINS",
          (if sample_index = 0 then "1" else "0")
        ];
  !values

let executable_arguments case =
  if case.benchmark = "renderer" then
    [ "dune"; "exec"; "--profile"; "release"; "tools/bench_renderer.exe"; "--"
    ; case.scenario
    ]
  else if case.benchmark = "shattered_renderer" then
    let prefix = "shattered-" in
    let mode =
      String.sub case.scenario (String.length prefix)
        (String.length case.scenario - String.length prefix)
    in
    [ "dune"; "exec"; "--profile"; "release"
    ; "tools/bench_shattered_renderer.exe"; "--"; mode
    ]
  else
    [ "dune"; "exec"; "--profile"; "release"
    ; "tools/bench_shattered_cube.exe"
    ]

let shell_safe = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '@' | '%' | '+' | '=' | ':'
  | ',' | '.' | '/' | '-' -> true
  | _ -> false

let shell_quote value =
  if value <> "" && String.for_all shell_safe value then value
  else "'" ^ String.concat "'\"'\"'" (String.split_on_char '\'' value) ^ "'"

let recorded_command environment arguments =
  let assignments =
    List.map (fun (name, value) -> name ^ "=" ^ shell_quote value) environment
  in
  String.concat " "
    (assignments @ [ "/usr/bin/time"; "-l" ] @ List.map shell_quote arguments)

let environment_array additions =
  let values = Hashtbl.create 128 in
  Unix.environment ()
  |> Array.iter (fun entry ->
    match String.index_opt entry '=' with
    | None -> ()
    | Some separator ->
        Hashtbl.replace values (String.sub entry 0 separator) entry);
  List.iter
    (fun (name, value) -> Hashtbl.replace values name (name ^ "=" ^ value))
    additions;
  Hashtbl.to_seq_values values |> Array.of_seq

type running_process =
  { pid : int
  ; stdout_path : string
  ; stderr_path : string
  ; mutable result : int option
  }

let start_process ~root ~environment ~directory program arguments =
  let stdout_path = Filename.concat directory "stdout" in
  let stderr_path = Filename.concat directory "stderr" in
  let flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] in
  let stdout_fd = Unix.openfile stdout_path flags 0o600 in
  let stderr_fd = Unix.openfile stderr_path flags 0o600 in
  let original_directory = Sys.getcwd () in
  let pid =
    Fun.protect
      ~finally:(fun () ->
        Sys.chdir original_directory;
        Unix.close stdout_fd;
        Unix.close stderr_fd)
      (fun () ->
        Sys.chdir root;
        Unix.create_process_env program
          (Array.of_list (program :: arguments))
          (environment_array environment) Unix.stdin stdout_fd stderr_fd)
  in
  { pid; stdout_path; stderr_path; result = None }

let process_output process = read_file process.stdout_path, read_file process.stderr_path

let exit_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal

let poll_process process =
  match process.result with
  | Some code -> Some code
  | None ->
      (match Unix.waitpid [ Unix.WNOHANG ] process.pid with
       | 0, _ -> None
       | _, status ->
           let code = exit_code status in
           process.result <- Some code;
           Some code)

let wait_process process ~timeout =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec wait () =
    match poll_process process with
    | None when Unix.gettimeofday () < deadline ->
        Thread.delay 0.05;
        wait ()
    | None ->
        Unix.kill process.pid Sys.sigkill;
        let _, status = Unix.waitpid [] process.pid in
        process.result <- Some (exit_code status);
        fail "benchmark exceeded its %.1f second timeout" timeout
    | Some code -> code
  in
  wait ()

let parse_json_line stdout =
  let rec find = function
    | [] -> fail "benchmark emitted no JSON object; stdout=%S" stdout
    | line :: rest ->
        let line = String.trim line in
        if line <> "" && line.[0] = '{' then
          (match Yojson.Safe.from_string line with
           | `Assoc _ as value -> value
           | _ -> find rest
           | exception Yojson.Json_error _ -> find rest)
        else find rest
  in
  split_lines stdout |> List.rev |> find

let external_peak_rss stderr =
  let suffix = "maximum resident set size" in
  split_lines stderr
  |> List.find_map (fun line ->
    let line = String.trim line in
    if String.ends_with ~suffix line then
      let prefix =
        String.sub line 0 (String.length line - String.length suffix)
        |> String.trim
      in
      int_of_string_opt prefix
    else None)

let assoc_set name value = function
  | `Assoc fields -> `Assoc ((name, value) :: List.remove_assoc name fields)
  | value -> fail "expected benchmark object, got %s" (Yojson.Safe.to_string value)

let uint8 value = Char.chr (value land 0xff)

let bytes_of_i32_le value =
  Bytes.init 4 (fun index -> uint8 (value lsr (index * 8)))

let int_of_bytes_be bytes =
  let value = ref 0L in
  Bytes.iter
    (fun character ->
      value := Int64.(logor (shift_left !value 8) (of_int (Char.code character))))
    bytes;
  !value

let read_exact socket length =
  let output = Bytes.create length in
  let rec read offset =
    if offset = length then output
    else
      let count = Unix.read socket output offset (length - offset) in
      if count = 0 then raise End_of_file else read (offset + count)
  in
  read 0

let read_until ?(limit = 2_000_000) socket marker =
  let output = Buffer.create 4096 in
  let marker_length = String.length marker in
  let rec loop matched =
    if Buffer.length output > limit then fail "HTTP response exceeded safety limit";
    let byte = Bytes.get_uint8 (read_exact socket 1) 0 |> Char.chr in
    Buffer.add_char output byte;
    let matched =
      if byte = marker.[matched] then matched + 1
      else if byte = marker.[0] then 1
      else 0
    in
    if matched = marker_length then Buffer.contents output else loop matched
  in
  if marker_length = 0 then "" else loop 0

let socket_connect port =
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let connected = ref false in
  Fun.protect
    ~finally:(fun () -> if not !connected then Unix.close socket)
    (fun () ->
      Unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
      connected := true;
      socket)

let send_all socket bytes =
  let rec send offset =
    if offset < Bytes.length bytes then
      let count = Unix.write socket bytes offset (Bytes.length bytes - offset) in
      if count = 0 then raise End_of_file else send (offset + count)
  in
  send 0

let substring_between value opening closing =
  let find_from start needle =
    let rec find index =
      if index + String.length needle > String.length value then None
      else if String.sub value index (String.length needle) = needle then Some index
      else find (index + 1)
    in
    find start
  in
  match find_from 0 opening with
  | None -> None
  | Some start ->
      let value_start = start + String.length opening in
      Option.map
        (fun stop -> String.sub value value_start (stop - value_start))
        (find_from value_start closing)

let connect_websocket port =
  let http = socket_connect port in
  let page =
    Fun.protect ~finally:(fun () -> Unix.close http) (fun () ->
      Printf.sprintf
        "GET / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n"
        port
      |> Bytes.of_string |> send_all http;
      read_until http "</html>")
  in
  let token =
    match substring_between page "data-token=\"" "\"" with
    | Some token -> token
    | None -> fail "web benchmark page omitted its authentication token"
  in
  let socket = socket_connect port in
  let request =
    Printf.sprintf
      "GET /ws?token=%s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: \
       websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n\
       Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
      token port
  in
  send_all socket (Bytes.of_string request);
  let handshake = read_until socket "\r\n\r\n" in
  if not (has_prefix ~prefix:"HTTP/1.1 101" handshake) then begin
    Unix.close socket;
    fail "web benchmark WebSocket upgrade was rejected"
  end;
  Unix.setsockopt_float socket Unix.SO_RCVTIMEO 2.0;
  socket

let websocket_frame socket =
  let header = read_exact socket 2 in
  let first = Bytes.get_uint8 header 0 in
  let second = Bytes.get_uint8 header 1 in
  let opcode = first land 0x0f in
  let final = first land 0x80 <> 0 in
  let masked = second land 0x80 <> 0 in
  let short_length = second land 0x7f in
  let length =
    if short_length = 126 then
      read_exact socket 2 |> int_of_bytes_be |> Int64.to_int
    else if short_length = 127 then begin
      let value = read_exact socket 8 |> int_of_bytes_be in
      if value > Int64.of_int max_int then fail "WebSocket payload is too large";
      Int64.to_int value
    end
    else short_length
  in
  let mask = if masked then read_exact socket 4 else Bytes.empty in
  let payload = read_exact socket length in
  if masked then
    Bytes.iteri
      (fun index value ->
        Bytes.set_uint8 payload index
          (Char.code value lxor Bytes.get_uint8 mask (index land 3)))
      payload;
  opcode, final, payload

let send_frame_ack socket frame_id =
  let payload = Bytes.create 6 in
  Bytes.set_uint8 payload 0 0x01;
  Bytes.set_uint8 payload 1 0x0d;
  Bytes.blit (bytes_of_i32_le frame_id) 0 payload 2 4;
  let mask =
    Bytes.init 4 (fun index -> uint8 ((frame_id + (index * 37) + 19) land 0xff))
  in
  let masked = Bytes.copy payload in
  Bytes.iteri
    (fun index value ->
      Bytes.set_uint8 masked index
        (Char.code value lxor Bytes.get_uint8 mask (index land 3)))
    masked;
  let frame = Bytes.create 12 in
  Bytes.set_uint8 frame 0 0x82;
  Bytes.set_uint8 frame 1 (0x80 lor Bytes.length payload);
  Bytes.blit mask 0 frame 2 4;
  Bytes.blit masked 0 frame 6 6;
  send_all socket frame

type loopback =
  { mutable frames_received : int
  ; mutable acknowledgements_sent : int
  ; mutable messages_received : int
  ; mutable payload_bytes_received : int
  ; mutable reader_error : string option
  }

let drain_websocket socket stop result =
  let pending_frame_id = ref None in
  let rec loop () =
    if not (Atomic.get stop) then begin
      try
        let opcode, final, payload = websocket_frame socket in
          result.messages_received <- result.messages_received + 1;
          result.payload_bytes_received <-
            result.payload_bytes_received + Bytes.length payload;
          if opcode = 2 && Bytes.length payload >= 4
             && Bytes.sub_string payload 0 4 = "PRSM"
          then begin
            result.frames_received <- result.frames_received + 1;
            if final || Bytes.length payload < 12 then
              fail "web frame metadata is malformed";
            pending_frame_id := Some (Bytes.get_int32_le payload 8 |> Int32.to_int)
          end
          else if opcode = 0 && final then
            Option.iter
              (fun frame_id ->
                send_frame_ack socket frame_id;
                result.acknowledgements_sent <- result.acknowledgements_sent + 1;
                pending_frame_id := None)
              !pending_frame_id;
          if opcode <> 8 then loop ()
      with
      | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) ->
          loop ()
    end
  in
  (try loop () with
   | End_of_file -> ()
   | Error message ->
       if not (Atomic.get stop) then result.reader_error <- Some message
   | Unix.Unix_error (error, function_name, argument) ->
       if not (Atomic.get stop) then
         result.reader_error <-
           Some
             (Printf.sprintf "%s(%s): %s" function_name argument
                (Unix.error_message error)));
  (try Unix.close socket with Unix.Unix_error _ -> ())

let port_from_output value =
  let marker = "http://0.0.0.0:" in
  match substring_between value marker "/" with
  | Some value -> int_of_string_opt value
  | None -> None

let wait_for_web_port process timeout =
  let deadline = Unix.gettimeofday () +. min timeout 45.0 in
  let rec wait () =
    let stderr = read_file process.stderr_path in
    match port_from_output stderr with
    | Some port -> port
    | None when Option.is_some (poll_process process) ->
        let stdout, stderr = process_output process in
        fail "web benchmark did not report its listening port; stdout=%s; stderr=%s"
          stdout stderr
    | None when Unix.gettimeofday () >= deadline ->
        Unix.kill process.pid Sys.sigkill;
        ignore (Unix.waitpid [] process.pid);
        process.result <- Some 137;
        fail "web benchmark did not report its listening port; stderr=%s" stderr
    | None ->
        Thread.delay 0.1;
        wait ()
  in
  wait ()

let loopback_json result =
  `Assoc
    [ "port", `String "ephemeral"
    ; "frames_received", `Int result.frames_received
    ; "frame_acknowledgements_sent", `Int result.acknowledgements_sent
    ; "messages_received", `Int result.messages_received
    ; "payload_bytes_received", `Int result.payload_bytes_received
    ; "reader_error", Option.fold ~none:`Null ~some:(fun value -> `String value) result.reader_error
    ]

let run_web process ~timeout =
  let port = wait_for_web_port process timeout in
  let socket = connect_websocket port in
  let stop = Atomic.make false in
  let loopback =
    { frames_received = 0
    ; acknowledgements_sent = 0
    ; messages_received = 0
    ; payload_bytes_received = 0
    ; reader_error = None
    }
  in
  let reader = Thread.create (fun () -> drain_websocket socket stop loopback) () in
  let code =
    Fun.protect
      ~finally:(fun () ->
        Atomic.set stop true;
        (try Unix.shutdown socket Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ()))
      (fun () -> wait_process process ~timeout)
  in
  Thread.join reader;
  code, loopback

let explicit_environment_json environment =
  `Assoc (List.map (fun (name, value) -> name, `String value) environment)

let run_one case ~root ~commit ~sample_index ~warmup ~seconds =
  let environment = explicit_environment case ~warmup ~seconds ~sample_index in
  let arguments = executable_arguments case in
  let recorded = recorded_command environment arguments in
  Printf.eprintf "[%d/%d] %s: %s\n%!" (sample_index + 1) default_samples
    (case_key case) recorded;
  let before = runtime_conditions root in
  let timeout = max 300.0 (warmup +. seconds +. 240.0) in
  with_temp_directory "prismel-benchmark-" (fun directory ->
    let process =
      start_process ~root ~environment ~directory "/usr/bin/time"
        ("-l" :: arguments)
    in
    let code, loopback =
      if case.target = Some "web" then
        let code, loopback = run_web process ~timeout in
        code, Some loopback
      else wait_process process ~timeout, None
    in
    let stdout, stderr = process_output process in
    if code <> 0 then
      fail "%s failed (%d)\nstdout:\n%s\nstderr:\n%s" (case_key case) code stdout
        stderr;
    let value = parse_json_line stdout in
    let value = assoc_set "profile" (`String "release") value in
    let value =
      assoc_set "external_peak_rss_bytes"
        (Option.fold ~none:`Null ~some:(fun value -> `Int value)
           (external_peak_rss stderr))
        value
    in
    let value =
      match loopback with
      | None -> value
      | Some loopback ->
          Option.iter
            (fun error -> fail "web loopback reader failed: %s" error)
            loopback.reader_error;
          if loopback.frames_received < 1 then
            fail "web loopback received no framebuffer metadata";
          if loopback.acknowledgements_sent <> loopback.frames_received then
            fail "web loopback did not acknowledge every framebuffer";
          assoc_set "web_loopback" (loopback_json loopback) value
    in
    assoc_set "evidence"
      (`Assoc
        [ "commit", `String commit
        ; "dirty", `Bool false
        ; "sample_index", `Int (sample_index + 1)
        ; "command", `String recorded
        ; "explicit_environment", explicit_environment_json environment
        ; "conditions_before", before
        ; "conditions_after", runtime_conditions root
        ])
      value)

let finite_number = function
  | `Int value -> Some (float_of_int value)
  | `Intlit value ->
      (match float_of_string_opt value with
       | Some value when Float.is_finite value -> Some value
       | Some _ | None -> None)
  | `Float value when Float.is_finite value -> Some value
  | `Null | `Bool _ | `Float _ | `String _ | `Assoc _ | `List _ | `Tuple _
  | `Variant _ -> None

let median values =
  let ordered = List.sort Float.compare values |> Array.of_list in
  let length = Array.length ordered in
  if length = 0 then fail "cannot summarize an empty metric";
  if length mod 2 = 1 then ordered.(length / 2)
  else (ordered.((length / 2) - 1) +. ordered.(length / 2)) /. 2.0

let percentile values fraction =
  let ordered = List.sort Float.compare values |> Array.of_list in
  let raw = int_of_float (ceil (fraction *. float_of_int (Array.length ordered))) - 1 in
  let index = max 0 (min (Array.length ordered - 1) raw) in
  ordered.(index)

let summarize runs =
  let metrics =
    List.map
      (fun metric ->
        let values =
          List.filter_map
            (fun run -> Option.bind (member metric run) finite_number)
            runs
        in
        if values = [] then metric, `Assoc [ "available", `Bool false ]
        else
          let median_value = median values in
          let deviations = List.map (fun value -> abs_float (value -. median_value)) values in
          ( metric
          , `Assoc
              [ "available", `Bool true
              ; "samples", `Int (List.length values)
              ; "median", `Float median_value
              ; "p95", `Float (percentile values 0.95)
              ; "minimum", `Float (List.fold_left min infinity values)
              ; "maximum", `Float (List.fold_left max neg_infinity values)
              ; "median_absolute_deviation", `Float (median deviations)
              ] ))
      numeric_metrics
  in
  `Assoc metrics

let progress_json commit signature recorded =
  let runs =
    Hashtbl.to_seq recorded |> List.of_seq
    |> List.map (fun (key, values) -> key, `List values)
  in
  `Assoc
    [ "schema", `Int 1
    ; "commit", `String commit
    ; "signature", `String signature
    ; "runs", `Assoc runs
    ]

let write_progress path value =
  let temporary = Filename.remove_extension path ^ ".tmp" in
  write_file temporary (pretty_json value);
  Unix.rename temporary path

let load_progress path commit signature =
  let recorded = Hashtbl.create 32 in
  if Sys.file_exists path then begin
    let value = read_file path |> Yojson.Safe.from_string in
    if member_string "commit" value <> Some commit then
      fail "progress file %s belongs to another commit" path;
    if member_string "signature" value <> Some signature then
      fail "progress file %s belongs to another run policy" path;
    match member_assoc "runs" value with
    | None -> fail "progress file %s is malformed" path
    | Some runs ->
        List.iter
          (fun (key, value) ->
            match value with
            | `List values -> Hashtbl.replace recorded key values
            | _ -> fail "progress file %s is malformed" path)
          runs
  end;
  recorded

let expected_keys () =
  cases () |> List.map case_key |> String_set.of_list

let json_is_object = function
  | `Assoc _ -> true
  | _ -> false

let numeric_at_least name minimum value =
  match Option.bind (member name value) finite_number with
  | Some value -> value >= minimum
  | None -> false

let cardinality value =
  member_int "pieces" value, member_int "triangles" value,
  member_int "render_vertices" value

let validate root value =
  let failures = ref [] in
  let reject condition message = if condition then failures := message :: !failures in
  let baseline =
    read_file (Filename.concat root baseline_relative) |> Yojson.Safe.from_string
  in
  reject (member_int "schema" value <> Some 1)
    "unsupported performance evidence schema";
  reject
    (member "baseline_commit" value <> member "baseline_commit" baseline)
    "performance evidence names the wrong baseline commit";
  reject (member_bool "capture_dirty" value = Some true)
    "performance evidence was captured from a dirty worktree";
  reject
    (member "new_gpu_stuff_sha256" value
     <> member "new_gpu_stuff_sha256" baseline)
    "performance evidence used a different migration plan";
  let groups = Option.value (member_list "groups" value) ~default:[] in
  let by_key = Hashtbl.create 32 in
  List.iter
    (fun group ->
      match member_string "key" group with
      | Some key when json_is_object group -> Hashtbl.replace by_key key group
      | Some _ | None -> ())
    groups;
  let actual_keys = Hashtbl.to_seq_keys by_key |> String_set.of_seq in
  let expected = expected_keys () in
  reject
    (not (String_set.equal actual_keys expected))
    (Printf.sprintf "performance scenario set differs: expected %s, got %s"
       (String.concat ", " (String_set.elements expected))
       (String.concat ", " (String_set.elements actual_keys)));
  String_set.inter expected actual_keys |> String_set.elements
  |> List.iter (fun key ->
    let group = Hashtbl.find by_key key in
    let runs = Option.value (member_list "runs" group) ~default:[] in
    if List.length runs < default_samples then
      failures :=
        Printf.sprintf "%s has %d runs, expected at least %d" key
          (List.length runs) default_samples
        :: !failures
    else begin
      reject (member_string "profile" group <> Some "release")
        (key ^ " was not captured in release profile");
      List.iteri
        (fun index run ->
          let prefix = Printf.sprintf "%s run %d" key (index + 1) in
          let evidence =
            Option.value (member "evidence" run) ~default:(`Assoc [])
          in
          reject (member_bool "dirty" evidence = Some true)
            (prefix ^ " was dirty");
          reject
            (member "commit" evidence <> member "capture_commit" value)
            (prefix ^ " names a different capture commit");
          reject
            (match member_string "command" evidence with
             | Some value -> value = ""
             | None -> true)
            (prefix ^ " has no reproduction command");
          if member_string "benchmark" group <> Some "shattered_cube" then begin
            reject
              (not
                 (numeric_at_least "requested_measure_seconds"
                    default_measure_seconds run))
              (prefix ^ " measured for less than 30 seconds");
            reject
              (not (numeric_at_least "warmup_seconds" default_warmup_seconds run))
              (prefix ^ " warmed for less than 3 seconds");
            [ "wall_seconds"; "user_seconds"; "system_seconds"
            ; "median_frame_seconds"; "p95_frame_seconds"; "p99_frame_seconds"
            ; "allocated_bytes"; "promoted_bytes"; "peak_sampled_rss_kib"
            ]
            |> List.iter (fun metric ->
              reject
                (Option.bind (member metric run) finite_number = None)
                (prefix ^ " is missing " ^ metric));
            if member_string "target" group = Some "web" then begin
              let loopback =
                Option.value (member "web_loopback" run) ~default:(`Assoc [])
              in
              reject
                (Option.value (member_int "frames_received" loopback) ~default:0 < 1)
                (prefix ^ " did not exercise web frame delivery");
              reject
                (member_int "frame_acknowledgements_sent" loopback
                 <> member_int "frames_received" loopback)
                (prefix ^ " did not acknowledge every delivered frame")
            end
          end;
          if member_string "benchmark" group = Some "shattered_renderer" then
            reject
              (cardinality run <> (Some 18_278, Some 278_368, Some 835_104))
              (prefix ^ " cardinality changed"))
        runs;
      reject
        (match member "summary" group with
         | Some (`Assoc _) -> false
         | Some _ | None -> true)
        (key ^ " has no aggregate summary")
    end);
  (match Hashtbl.find_opt by_key "shattered_cube:cpu:cook" with
   | None -> ()
   | Some group ->
       let runs = Option.value (member_list "runs" group) ~default:[] in
       (match runs with
        | first :: _ ->
            reject
              (cardinality first <> (Some 18_278, Some 278_368, Some 835_104))
              "shattered cook cardinality changed"
        | [] -> ());
       reject
         (not
            (List.exists
               (fun run -> member_bool "one_multi_domain_exact" run = Some true)
               runs))
         "shattered cook never verified one/multi-domain exactness");
  let gaps = Option.value (member "instrumentation_gaps" value) ~default:(`Assoc []) in
  [ "gpu_duration"; "gpu_utilization"; "draw_count"; "upload_bytes" ]
  |> List.iter (fun name ->
    reject
      (match member_string name gaps with
       | Some value -> value = ""
       | None -> true)
      ("legacy instrumentation gap " ^ name ^ " is undocumented"));
  List.rev !failures

let git_facts root =
  let commit = command_output ~cwd:root "git" [ "rev-parse"; "HEAD" ] in
  let status = command_output ~cwd:root "git" [ "status"; "--porcelain=v1" ] in
  commit, status <> "", split_lines status

let rotate amount values =
  let rec take count prefix rest =
    if count = 0 then List.rev prefix, rest
    else
      match rest with
      | value :: rest -> take (count - 1) (value :: prefix) rest
      | [] -> List.rev prefix, []
  in
  let prefix, suffix = take amount [] values in
  suffix @ prefix

let group_json case runs =
  `Assoc
    [ "key", `String (case_key case)
    ; "benchmark", `String case.benchmark
    ; "scenario", `String case.scenario
    ; "target", Option.fold ~none:`Null ~some:(fun value -> `String value) case.target
    ; "profile", `String "release"
    ; "sample_count", `Int (List.length runs)
    ; "runs", `List runs
    ; "summary", summarize runs
    ]

let capture root ~selected ~samples ~warmup ~seconds ~resume =
  let baseline_path = Filename.concat root baseline_relative in
  let environment_path = Filename.concat root environment_relative in
  let baseline = read_file baseline_path |> Yojson.Safe.from_string in
  let commit, dirty, modifications = git_facts root in
  if dirty then
    fail "performance evidence must start from a clean worktree: %s"
      (String.concat ", " modifications);
  let plan_hash = sha256 (read_file (Filename.concat root "NEW_GPU_STUFF.md")) in
  if Some (`String plan_hash) <> member "new_gpu_stuff_sha256" baseline then
    fail "NEW_GPU_STUFF.md changed after its Phase 0 freeze";
  let build =
    [ "dune"; "build"; "--profile"; "release"; "tools/bench_renderer.exe"
    ; "tools/bench_shattered_renderer.exe"; "tools/bench_shattered_cube.exe"
    ]
  in
  Printf.eprintf "%s\n%!" (String.concat " " (List.map shell_quote build));
  (match build with
   | program :: arguments -> ignore (command_output ~cwd:root program arguments)
   | [] -> assert false);
  let signature_payload =
    `Assoc
      [ "cases", string_list (List.map case_key selected)
      ; "samples", `Int samples
      ; "warmup", `Float warmup
      ; "seconds", `Float seconds
      ]
    |> pretty_json
  in
  let signature = String.sub (sha256 signature_payload) 0 16 in
  let progress_path =
    Printf.sprintf "/tmp/prismel-phase0-performance-%s-%s.json" commit signature
  in
  let recorded =
    if resume then load_progress progress_path commit signature
    else Hashtbl.create 32
  in
  for sample_index = 0 to samples - 1 do
    let rotated = rotate (sample_index mod List.length selected) selected in
    List.iter
      (fun case ->
        let key = case_key case in
        let runs = Option.value (Hashtbl.find_opt recorded key) ~default:[] in
        if List.length runs <= sample_index then begin
          let run =
            run_one case ~root ~commit ~sample_index ~warmup ~seconds
          in
          Hashtbl.replace recorded key (runs @ [ run ]);
          write_progress progress_path (progress_json commit signature recorded)
        end)
      rotated
  done;
  let groups =
    List.map
      (fun case ->
        let runs = Hashtbl.find recorded (case_key case) in
        let rec first count values =
          match count, values with
          | 0, _ | _, [] -> []
          | count, value :: rest -> value :: first (count - 1) rest
        in
        group_json case (first samples runs))
      selected
  in
  let instrumentation_gaps =
    `Assoc
      [ ( "gpu_duration"
        , `String
            "Legacy SDL2/OpenGL and SDL software paths expose no timestamp query; \
             full Xcode Instruments is absent on the capture host." )
      ; ( "gpu_utilization"
        , `String
            "powermetrics requires superuser access and full Xcode Metal System \
             Trace is absent; no privileged measurement was fabricated." )
      ; ( "draw_count"
        , `String
            "The frozen legacy renderer has no public draw-counter telemetry." )
      ; ( "upload_bytes"
        , `String
            "The frozen legacy renderer has no public upload-byte telemetry." )
      ]
  in
  `Assoc
    [ "schema", `Int 1
    ; "kind", `String "phase0_performance"
    ; "baseline_commit", member_exn "baseline_commit" baseline
    ; "capture_commit", `String commit
    ; "capture_dirty", `Bool false
    ; "local_modifications", `List []
    ; "captured_at", `String (iso8601_now ())
    ; "new_gpu_stuff_sha256", `String plan_hash
    ; ( "environment_evidence"
      , `Assoc
          [ "path", `String environment_relative
          ; "sha256", `String (sha256 (read_file environment_path))
          ] )
    ; ( "policy"
      , `Assoc
          [ "profile", `String "release"
          ; "samples_per_scenario", `Int samples
          ; "warmup_seconds", `Float warmup
          ; "interactive_measure_seconds", `Float seconds
          ; "interleaved_order", `Bool true
          ; "build_command", `String (String.concat " " (List.map shell_quote build))
          ] )
    ; "instrumentation_gaps", instrumentation_gaps
    ; "groups", `List groups
    ]

type mode =
  | Write
  | Check
  | List_cases

type arguments =
  { root : string
  ; output : string option
  ; samples : int
  ; warmup : float
  ; seconds : float
  ; resume : bool
  ; only : string list
  ; mode : mode
  }

let absolute_output value =
  if Filename.is_relative value then Filename.concat (Sys.getcwd ()) value else value

let parse_arguments () =
  let root = ref (Sys.getcwd ()) in
  let output = ref None in
  let samples = ref default_samples in
  let warmup = ref default_warmup_seconds in
  let seconds = ref default_measure_seconds in
  let resume = ref false in
  let only = ref [] in
  let mode = ref None in
  let index = ref 1 in
  let usage () =
    fail
      "usage: %s [--root <repository>] [--output <path>] [--samples <n>] \
       [--warmup <seconds>] [--seconds <seconds>] [--resume] [--only <text>] \
       <--write|--check|--list>"
      Sys.argv.(0)
  in
  let value () =
    if !index + 1 >= Array.length Sys.argv then usage ();
    let value = Sys.argv.(!index + 1) in
    index := !index + 2;
    value
  in
  let set_mode value =
    if Option.is_some !mode then usage ();
    mode := Some value;
    incr index
  in
  while !index < Array.length Sys.argv do
    match Sys.argv.(!index) with
    | "--root" -> root := value ()
    | "--output" -> output := Some (value () |> absolute_output)
    | "--samples" ->
        let raw = value () in
        samples :=
          (match int_of_string_opt raw with
           | Some value -> value
           | None -> fail "invalid sample count %S" raw)
    | "--warmup" ->
        let raw = value () in
        warmup :=
          (match float_of_string_opt raw with
           | Some value -> value
           | None -> fail "invalid warmup %S" raw)
    | "--seconds" ->
        let raw = value () in
        seconds :=
          (match float_of_string_opt raw with
           | Some value -> value
           | None -> fail "invalid measurement time %S" raw)
    | "--resume" ->
        resume := true;
        incr index
    | "--only" -> only := !only @ [ value () ]
    | "--write" -> set_mode Write
    | "--check" -> set_mode Check
    | "--list" -> set_mode List_cases
    | _ -> usage ()
  done;
  if !samples <= 0 then fail "sample count must be positive";
  if not (Float.is_finite !warmup) || !warmup < 0.0 then
    fail "warmup must be finite and non-negative";
  if not (Float.is_finite !seconds) || !seconds <= 0.0 then
    fail "measurement time must be finite and positive";
  match !mode with
  | None -> usage ()
  | Some mode ->
      { root = Unix.realpath !root
      ; output = !output
      ; samples = !samples
      ; warmup = !warmup
      ; seconds = !seconds
      ; resume = !resume
      ; only = !only
      ; mode
      }

let selected_cases fragments =
  if fragments = [] then cases ()
  else
    cases ()
    |> List.filter (fun case ->
      List.exists (fun fragment -> contains ~needle:fragment (case_key case)) fragments)

let main () =
  let arguments = parse_arguments () in
  let selected = selected_cases arguments.only in
  let output_path =
    Option.value arguments.output
      ~default:(Filename.concat arguments.root output_relative)
  in
  match arguments.mode with
  | List_cases -> List.iter (fun case -> print_endline (case_key case)) selected
  | Check ->
      if Option.is_some arguments.output || arguments.only <> [] then
        fail "--check validates only the committed complete evidence";
      if not (Sys.file_exists output_path) then
        fail "missing performance evidence: %s" output_path;
      let value = read_file output_path |> Yojson.Safe.from_string in
      let failures = validate arguments.root value in
      if failures <> [] then fail "%s" (String.concat "; " failures);
      print_endline "Phase 0 performance evidence is complete"
  | Write ->
      if selected = [] then fail "--only selected no benchmark cases";
      let complete_capture =
        Option.is_none arguments.output && arguments.only = []
        && arguments.samples = default_samples
        && arguments.warmup >= default_warmup_seconds
        && arguments.seconds >= default_measure_seconds
      in
      if not complete_capture && Option.is_none arguments.output then
        fail "development captures require --output outside the repository";
      let value =
        capture arguments.root ~selected ~samples:arguments.samples
          ~warmup:arguments.warmup ~seconds:arguments.seconds
          ~resume:arguments.resume
      in
      if complete_capture then begin
        let failures = validate arguments.root value in
        if failures <> [] then fail "%s" (String.concat "; " failures)
      end;
      ensure_directory (Filename.dirname output_path);
      write_file output_path (pretty_json value);
      Printf.printf "wrote performance evidence to %s\n%!" output_path

let () = protect_main main
