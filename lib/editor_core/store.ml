type kind = Preset | Settings

let kind_name = function Preset -> "preset" | Settings -> "settings"

let rec ensure_directory path =
  if path <> "" && path <> "." && not (Sys.file_exists path) then (
    let parent = Filename.dirname path in
    if parent <> path then ensure_directory parent;
    try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())

let save ~filename ~kind ~sketch ~sections =
  try
    let directory = Filename.dirname filename in
    ensure_directory directory;
    let temporary, channel = Filename.open_temp_file ~temp_dir:directory
      ".prismel-" ".tmp" in
    Fun.protect ~finally:(fun () ->
      close_out_noerr channel;
      if Sys.file_exists temporary then Sys.remove temporary) (fun () ->
      Yojson.Safe.to_channel channel (`Assoc [
        "prismel", `Int 1; "kind", `String (kind_name kind);
        "sketch", `String sketch; "sections", `Assoc sections ]);
      close_out channel;
      Sys.rename temporary filename);
    Ok ()
  with Sys_error message -> Error message
     | Unix.Unix_error (error, _, _) -> Error (Unix.error_message error)

let load ~filename ~kind =
  try match Yojson.Safe.from_file filename with
    | `Assoc fields ->
        let field name = List.assoc_opt name fields in
        (match field "prismel", field "kind", field "sketch", field "sections" with
         | Some (`Int 1), Some (`String saved_kind), Some (`String sketch),
           Some (`Assoc sections) when saved_kind = kind_name kind ->
             Ok (sketch, sections)
         | _ -> Error "unsupported Prismel store envelope")
    | _ -> Error "Prismel store envelope is not an object"
  with Sys_error message -> Error message
     | Yojson.Json_error message -> Error message

module Viewport = struct
  open Prismel

  let number = function
    | `Float v when Float.is_finite v -> Some v
    | `Int v -> Some (float_of_int v)
    | _ -> None

  let encode3 easy ~look_through =
    let camera = Easy_camera.camera easy in
    let vector (v : Vec3.t) = `List [`Float v.x; `Float v.y; `Float v.z] in
    `Assoc ["eye", vector (Camera.position camera);
            "target", vector (Camera.target camera);
            "fov", `Float (Easy_camera.fov_y easy);
            "look_through", `Bool look_through]

  let decode3 easy = function
    | `Assoc fields ->
        let field name = List.assoc_opt name fields in
        let vector = function
          | Some (`List [x; y; z]) ->
              (match number x, number y, number z with
               | Some x, Some y, Some z -> Some (Vec3.create x y z)
               | _ -> None)
          | _ -> None in
        let easy = match vector (field "eye"), vector (field "target") with
          | Some eye, Some target -> Easy_camera.of_view ~eye ~target easy
          | _ -> easy in
        let easy = match Option.bind (field "fov") number with
          | Some fov when fov > 0. && fov < Float.pi -> Easy_camera.with_fov_y fov easy
          | _ -> easy in
        easy, field "look_through" = Some (`Bool true)
    | _ -> easy, false

  let encode2 camera =
    let center = Easy_camera2.center camera in
    `Assoc ["center", `List [`Float center.Vec2.x; `Float center.y];
            "zoom", `Float (Easy_camera2.zoom camera);
            "rotation", `Float (Easy_camera2.rotation camera)]

  let decode2 camera = function
    | `Assoc fields ->
        let field name = List.assoc_opt name fields in
        let camera = match field "center" with
          | Some (`List [x; y]) ->
              (match number x, number y with
               | Some x, Some y -> Easy_camera2.with_center (Vec2.create x y) camera
               | _ -> camera)
          | _ -> camera in
        let camera = match Option.bind (field "zoom") number with
          | Some zoom when zoom > 0. -> Easy_camera2.with_zoom zoom camera
          | _ -> camera in
        (match Option.bind (field "rotation") number with
         | Some rotation -> Easy_camera2.with_rotation rotation camera
         | None -> camera)
    | _ -> camera
end

module Settings = struct
  type value =
    | Bool of bool | Float of float | Int of int
    | Text of string | Choice of string | Pair of float * float
  type t = (string * value) list

  let string_of_hex encoded =
    let nibble = function
      | '0' .. '9' as c -> Ok (Char.code c - Char.code '0')
      | 'a' .. 'f' as c -> Ok (10 + Char.code c - Char.code 'a')
      | 'A' .. 'F' as c -> Ok (10 + Char.code c - Char.code 'A')
      | c -> Error (Printf.sprintf "invalid hexadecimal digit %C" c) in
    if String.length encoded mod 2 <> 0 then Error "odd hexadecimal value"
    else
      let decoded = Bytes.create (String.length encoded / 2) in
      let rec loop index =
        if index = Bytes.length decoded then Ok (Bytes.unsafe_to_string decoded)
        else match nibble encoded.[index * 2], nibble encoded.[(index * 2) + 1] with
          | Ok high, Ok low ->
              Bytes.set decoded index (Char.chr ((high lsl 4) lor low));
              loop (index + 1)
          | Error message, _ | _, Error message -> Error message in
      loop 0

  let decode_legacy encoded =
    match String.split_on_char '\n' encoded with
    | "PXUI1" :: entries ->
        let rec parse line_number values = function
          | [] -> Ok (List.rev values)
          | "" :: rest -> parse (line_number + 1) values rest
          | entry :: rest ->
              let error message =
                Error (Printf.sprintf "PXUI settings line %d: %s" line_number message) in
              (match String.split_on_char '\t' entry with
               | [kind; encoded_name; raw] ->
                   (match string_of_hex encoded_name with
                    | Error message -> error message
                    | Ok name ->
                        let value = match kind with
                          | ("A" | "B") when raw = "0" -> Ok (Bool false)
                          | ("A" | "B") when raw = "1" -> Ok (Bool true)
                          | "F" ->
                              (match float_of_string_opt raw with
                               | Some value when Float.is_finite value -> Ok (Float value)
                               | Some _ -> error "non-finite float"
                               | None -> error "invalid float")
                          | "I" ->
                              (match int_of_string_opt raw with
                               | Some value -> Ok (Int value)
                               | None -> error "invalid integer")
                          | "S" -> Result.map (fun s -> Text s) (string_of_hex raw)
                          | "C" -> Result.map (fun s -> Choice s) (string_of_hex raw)
                          | "R" | "P" ->
                              (match String.split_on_char ',' raw with
                               | [first; second] ->
                                   (match float_of_string_opt first,
                                      float_of_string_opt second with
                                    | Some x, Some y when Float.is_finite x && Float.is_finite y ->
                                        Ok (Pair (x, y))
                                    | _ -> error "invalid float pair")
                               | _ -> error "invalid float pair")
                          | _ -> error "unknown value kind" in
                        Result.bind value (fun value ->
                          parse (line_number + 1)
                            ((name, value) :: List.remove_assoc name values) rest))
               | _ -> error "expected three tab-separated fields") in
        parse 2 [] entries
    | _ -> Error "PXUI settings: unsupported or missing PXUI1 header"

  let value_json = function
    | Bool value -> `Assoc ["bool", `Bool value]
    | Float value -> `Assoc ["float", `Float value]
    | Int value -> `Assoc ["int", `Int value]
    | Text value -> `Assoc ["text", `String value]
    | Choice value -> `Assoc ["choice", `String value]
    | Pair (x, y) -> `Assoc ["pair", `List [`Float x; `Float y]]

  let number = function
    | `Int n -> Some (float_of_int n)
    | `Float n when Float.is_finite n -> Some n
    | _ -> None

  let value_of_json = function
    | `Assoc ["bool", `Bool value] -> Ok (Bool value)
    | `Assoc ["float", json] ->
        Option.to_result ~none:"invalid settings float" (Option.map (fun n -> Float n) (number json))
    | `Assoc ["int", `Int value] -> Ok (Int value)
    | `Assoc ["text", `String value] -> Ok (Text value)
    | `Assoc ["choice", `String value] -> Ok (Choice value)
    | `Assoc ["pair", `List [x; y]] ->
        (match number x, number y with
         | Some x, Some y -> Ok (Pair (x, y))
         | _ -> Error "invalid settings pair")
    | _ -> Error "invalid settings value"

  let save ~sketch filename values =
    if List.exists (function
      | _, Float x -> not (Float.is_finite x)
      | _, Pair (x, y) -> not (Float.is_finite x && Float.is_finite y)
      | _ -> false) values then Error "non-finite settings value"
    else save ~filename ~kind:Settings ~sketch
      ~sections:["values", `List (List.map (fun (name, value) ->
        `List [`String name; value_json value]) values)]

  let load ~sketch filename =
    let ( let* ) = Result.bind in
    let channel = try Ok (open_in_bin filename) with Sys_error message -> Error message in
    let* channel = channel in
    let encoded = Fun.protect ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel)) in
    if String.starts_with ~prefix:"PXUI1\n" encoded then decode_legacy encoded
    else
      let* saved_sketch, sections = load ~filename ~kind:Settings in
      if saved_sketch <> sketch then Error "settings belong to another sketch"
      else match List.assoc_opt "values" sections with
        | Some (`List values) ->
            List.fold_left (fun result entry ->
              let* values = result in
              match entry with
              | `List [`String name; json] ->
                  let* value = value_of_json json in
                  Ok ((name, value) :: List.remove_assoc name values)
              | _ -> Error "invalid settings entry") (Ok []) values
            |> Result.map List.rev
        | _ -> Error "settings section has no values"

  let find settings name extract = Option.bind (List.assoc_opt name settings) extract
  let bool settings name = find settings name (function Bool v -> Some v | _ -> None)
  let float settings name = find settings name (function Float v -> Some v | _ -> None)
  let int settings name = find settings name (function Int v -> Some v | _ -> None)
end
