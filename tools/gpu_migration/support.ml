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

let sha256 contents = Digestif.SHA256.(to_hex (digest_string contents))

let has_prefix ~prefix value = String.starts_with ~prefix value

let contains ~needle value =
  let needle_length = String.length needle in
  let value_length = String.length value in
  let rec search index =
    index + needle_length <= value_length
    && (String.sub value index needle_length = needle || search (index + 1))
  in
  needle_length = 0 || search 0

let rec remove_directory path =
  Sys.readdir path
  |> Array.iter (fun name ->
    let entry = Filename.concat path name in
    if Sys.is_directory entry then remove_directory entry else Sys.remove entry);
  Unix.rmdir path

let with_temp_directory prefix f =
  let path = Filename.temp_dir prefix "" in
  Fun.protect ~finally:(fun () -> remove_directory path) (fun () -> f path)

type command_result =
  { status : Unix.process_status
  ; stdout : string
  ; stderr : string
  }

let command ?cwd ?(environment = Unix.environment ()) program arguments =
  with_temp_directory "prismel-command-" (fun directory ->
    let stdout_path = Filename.concat directory "stdout" in
    let stderr_path = Filename.concat directory "stderr" in
    let output_flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] in
    let stdout_fd = Unix.openfile stdout_path output_flags 0o600 in
    let stderr_fd = Unix.openfile stderr_path output_flags 0o600 in
    let original_directory = Sys.getcwd () in
    let pid =
      Fun.protect
        ~finally:(fun () ->
          (match cwd with
           | Some _ -> Sys.chdir original_directory
           | None -> ());
          Unix.close stdout_fd;
          Unix.close stderr_fd)
        (fun () ->
          (match cwd with
           | Some directory -> Sys.chdir directory
           | None -> ());
          Unix.create_process_env program
            (Array.of_list (program :: arguments))
            environment Unix.stdin stdout_fd stderr_fd)
    in
    let _, status = Unix.waitpid [] pid in
    { status
    ; stdout = read_file stdout_path |> String.trim
    ; stderr = read_file stderr_path |> String.trim
    })

let successful result = result.status = Unix.WEXITED 0

let command_output ?cwd program arguments =
  let result = command ?cwd program arguments in
  if successful result then result.stdout
  else
    let diagnostic = if result.stderr = "" then result.stdout else result.stderr in
    match result.status with
    | Unix.WEXITED code ->
        fail "%s failed (%d): %s"
          (String.concat " " (program :: arguments)) code diagnostic
    | Unix.WSIGNALED signal ->
        fail "%s was killed by signal %d" program signal
    | Unix.WSTOPPED signal ->
        fail "%s was stopped by signal %d" program signal

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

let add_indent output level = Buffer.add_string output (String.make (2 * level) ' ')

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

let pretty_json value =
  let output = Buffer.create 4096 in
  add_json output 0 value;
  Buffer.add_char output '\n';
  Buffer.contents output

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let member_exn name value =
  match member name value with
  | Some value -> value
  | None -> fail "missing JSON field %s" name

let string = function
  | `String value -> Some value
  | _ -> None

let bool = function
  | `Bool value -> Some value
  | _ -> None

let int = function
  | `Int value -> Some value
  | _ -> None

let list = function
  | `List values -> Some values
  | _ -> None

let assoc = function
  | `Assoc fields -> Some fields
  | _ -> None

let member_string name value = Option.bind (member name value) string
let member_bool name value = Option.bind (member name value) bool
let member_int name value = Option.bind (member name value) int
let member_list name value = Option.bind (member name value) list
let member_assoc name value = Option.bind (member name value) assoc

let rec ensure_directory path =
  if Sys.file_exists path then begin
    if not (Sys.is_directory path) then fail "%s is not a directory" path
  end
  else begin
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755
  end

type mode =
  | Write
  | Check

let root_and_mode () =
  let root = ref (Sys.getcwd ()) in
  let mode = ref None in
  let index = ref 1 in
  let usage () =
    fail "usage: %s [--root <repository>] <--write|--check>" Sys.argv.(0)
  in
  while !index < Array.length Sys.argv do
    match Sys.argv.(!index) with
    | "--root" when !index + 1 < Array.length Sys.argv ->
        root := Sys.argv.(!index + 1);
        index := !index + 2
    | "--write" ->
        if Option.is_some !mode then usage ();
        mode := Some Write;
        incr index
    | "--check" ->
        if Option.is_some !mode then usage ();
        mode := Some Check;
        incr index
    | _ -> usage ()
  done;
  match !mode with
  | Some mode -> Unix.realpath !root, mode
  | None -> usage ()

let protect_main f =
  try f () with
  | Error message | Sys_error message | Yojson.Json_error message ->
      prerr_endline message;
      exit 1
  | Unix.Unix_error (error, function_name, argument) ->
      Printf.eprintf "%s(%s): %s\n%!" function_name argument
        (Unix.error_message error);
      exit 1
