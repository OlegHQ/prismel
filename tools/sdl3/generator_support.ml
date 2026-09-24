exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

let read_file path =
  let input = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let write_file path contents =
  let output = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr output)
    (fun () -> output_string output contents)

let rec remove_directory path =
  Sys.readdir path
  |> Array.iter (fun name ->
    let entry = Filename.concat path name in
    if Sys.is_directory entry then remove_directory entry else Sys.remove entry);
  Unix.rmdir path

let with_temp_directory prefix f =
  let path = Filename.temp_dir prefix "" in
  Fun.protect ~finally:(fun () -> remove_directory path) (fun () -> f path)

let command_text program arguments =
  with_temp_directory "prismel-command-" (fun directory ->
    let stdout_path = Filename.concat directory "stdout" in
    let stderr_path = Filename.concat directory "stderr" in
    let output_flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] in
    let stdout_fd = Unix.openfile stdout_path output_flags 0o600 in
    let stderr_fd = Unix.openfile stderr_path output_flags 0o600 in
    let pid =
      Fun.protect
        ~finally:(fun () ->
          Unix.close stdout_fd;
          Unix.close stderr_fd)
        (fun () ->
          Unix.create_process_env program
            (Array.of_list (program :: arguments))
            (Unix.environment ()) Unix.stdin stdout_fd stderr_fd)
    in
    let _, status = Unix.waitpid [] pid in
    let stdout = read_file stdout_path in
    let stderr = String.trim (read_file stderr_path) in
    match status with
    | Unix.WEXITED 0 -> stdout
    | Unix.WEXITED code ->
        fail "%s exited %d: %s" (String.concat " " (program :: arguments))
          code
          (if stderr = "" then String.trim stdout else stderr)
    | Unix.WSIGNALED signal ->
        fail "%s was killed by signal %d" program signal
    | Unix.WSTOPPED signal ->
        fail "%s was stopped by signal %d" program signal)

let sha256 contents =
  Digestif.SHA256.(to_hex (digest_string contents))

let json_quote value =
  let output = Buffer.create (String.length value + 2) in
  Buffer.add_char output '"';
  String.iter
    (function
      | '"' -> Buffer.add_string output "\\\""
      | '\\' -> Buffer.add_string output "\\\\"
      | '\b' -> Buffer.add_string output "\\b"
      | '\012' -> Buffer.add_string output "\\f"
      | '\n' -> Buffer.add_string output "\\n"
      | '\r' -> Buffer.add_string output "\\r"
      | '\t' -> Buffer.add_string output "\\t"
      | character when Char.code character < 0x20 ->
          Printf.bprintf output "\\u%04x" (Char.code character)
      | character -> Buffer.add_char output character)
    value;
  Buffer.add_char output '"';
  Buffer.contents output

let add_indent output level = Buffer.add_string output (String.make (level * 2) ' ')

let rec add_json output level = function
  | `Null -> Buffer.add_string output "null"
  | `Bool value -> Buffer.add_string output (if value then "true" else "false")
  | `Int value -> Buffer.add_string output (string_of_int value)
  | `Intlit value -> Buffer.add_string output value
  | `Float value -> Buffer.add_string output (Yojson.Safe.to_string (`Float value))
  | `String value -> Buffer.add_string output (json_quote value)
  | `Assoc [] -> Buffer.add_string output "{}"
  | `Assoc fields ->
      Buffer.add_string output "{\n";
      fields
      |> List.sort (fun (left, _) (right, _) -> String.compare left right)
      |> List.iteri (fun index (name, value) ->
        if index > 0 then Buffer.add_string output ",\n";
        add_indent output (level + 1);
        Buffer.add_string output (json_quote name);
        Buffer.add_string output ": ";
        add_json output (level + 1) value);
      Buffer.add_char output '\n';
      add_indent output level;
      Buffer.add_char output '}'
  | `List [] -> Buffer.add_string output "[]"
  | `List values ->
      Buffer.add_string output "[\n";
      List.iteri
        (fun index value ->
          if index > 0 then Buffer.add_string output ",\n";
          add_indent output (level + 1);
          add_json output (level + 1) value)
        values;
      Buffer.add_char output '\n';
      add_indent output level;
      Buffer.add_char output ']'
  | `Tuple values -> add_json output level (`List values)
  | `Variant (name, None) -> add_json output level (`String name)
  | `Variant (name, Some value) -> add_json output level (`List [ `String name; value ])

let pretty_json json =
  let output = Buffer.create 4096 in
  add_json output 0 json;
  Buffer.add_char output '\n';
  Buffer.contents output

let assoc name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let string = function
  | `String value -> Some value
  | _ -> None

let list = function
  | `List values -> values
  | _ -> []

let member name json = assoc name json

let member_string name json = Option.bind (member name json) string

let member_list name json =
  match member name json with
  | Some value -> list value
  | None -> []

let integer_text = function
  | `Int value -> string_of_int value
  | `Intlit value -> value
  | value -> fail "expected a JSON integer, got %s" (Yojson.Safe.to_string value)

let first_line value =
  match String.split_on_char '\n' value with
  | line :: _ -> line
  | [] -> ""

let trim = String.trim
