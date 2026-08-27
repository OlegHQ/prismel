type sexp = Atom of string | List of sexp list

exception Parse_error of string

let read path =
  let input = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
    really_input_string input (in_channel_length input))

let tokenize source =
  let length = String.length source in
  let rec skip index =
    if index >= length then index
    else match source.[index] with
      | ' ' | '\t' | '\r' | '\n' -> skip (index + 1)
      | ';' ->
          let rec line cursor =
            if cursor >= length || source.[cursor] = '\n' then cursor
            else line (cursor + 1)
          in
          skip (line (index + 1))
      | _ -> index
  in
  let quoted start =
    let buffer = Buffer.create 32 in
    let rec loop index escaped =
      if index >= length then raise (Parse_error "unterminated string")
      else
        let character = source.[index] in
        if escaped then begin
          Buffer.add_char buffer character;
          loop (index + 1) false
        end else if character = '\\' then
          loop (index + 1) true
        else if character = '"' then
          Buffer.contents buffer, index + 1
        else begin
          Buffer.add_char buffer character;
          loop (index + 1) false
        end
    in
    loop start false
  in
  let atom start =
    let rec finish index =
      if index >= length then index
      else match source.[index] with
        | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ';' -> index
        | _ -> finish (index + 1)
    in
    let stop = finish start in
    String.sub source start (stop - start), stop
  in
  let rec loop index reversed =
    let index = skip index in
    if index >= length then List.rev reversed
    else match source.[index] with
      | '(' -> loop (index + 1) ("(" :: reversed)
      | ')' -> loop (index + 1) (")" :: reversed)
      | '"' ->
          let value, next = quoted (index + 1) in
          loop next (value :: reversed)
      | _ ->
          let value, next = atom index in
          loop next (value :: reversed)
  in
  loop 0 []

let parse tokens =
  let rec one = function
    | [] -> raise (Parse_error "unexpected end of file")
    | ")" :: _ -> raise (Parse_error "unexpected closing parenthesis")
    | "(" :: rest ->
        let values, rest = many [] rest in
        List values, rest
    | atom :: rest -> Atom atom, rest
  and many reversed = function
    | [] -> raise (Parse_error "unterminated list")
    | ")" :: rest -> List.rev reversed, rest
    | tokens ->
        let value, rest = one tokens in
        many (value :: reversed) rest
  in
  let rec all reversed = function
    | [] -> List.rev reversed
    | tokens ->
        let value, rest = one tokens in
        all (value :: reversed) rest
  in
  all [] tokens

let field name = function
  | List (_ :: fields) ->
      List.find_map (function
        | List (Atom candidate :: values) when candidate = name -> Some values
        | _ -> None) fields
  | List [] -> None
  | Atom _ -> None

let rec atoms = function
  | Atom value -> [value]
  | List values -> List.concat_map atoms values

let libraries_of_file path =
  let forms = read path |> tokenize |> parse in
  forms
  |> List.filter_map (fun stanza ->
    match stanza with
    | List (Atom "library" :: _) ->
      let name = match field "name" stanza with
        | Some [Atom value] -> value
        | _ -> raise (Parse_error (path ^ ": library has no scalar name"))
      in
      let dependencies = match field "libraries" stanza with
        | None -> []
        | Some values -> List.concat_map atoms values
      in
      Some (name, dependencies)
    | _ -> None)

let forbidden = function
  | "sdl3" | "sdl3_image" | "sdl3_ttf" | "sdl3_mixer" ->
      ["metal"; "metal_fx"; "ogpu"; "ogpu_metal"; "runtime"; "prismel";
       "pxui"; "wap"]
  | "metal" | "metal_fx" ->
      ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "ogpu";
       "ogpu_metal"; "runtime"; "prismel"; "pxui"; "wap"]
  | "ogpu" ->
      ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal";
       "metal_fx"; "ogpu_metal"; "runtime"; "prismel"; "pxui"; "wap"]
  | "ogpu_metal" ->
      ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "runtime";
       "prismel"; "pxui"; "wap"; "raster2"]
  | "raster2" ->
      ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal";
       "metal_fx"; "ogpu"; "ogpu_metal"; "runtime"; "prismel"; "pxui"]
  | "wap" ->
      ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal";
       "metal_fx"; "ogpu"; "ogpu_metal"; "raster2"; "runtime";
       "prismel"; "pxui"]
  | "runtime" -> ["metal"; "metal_fx"; "ogpu"; "raster2"; "prismel"; "pxui"]
  | _ -> []

let violations graph =
  List.concat_map (fun (owner, dependencies) ->
    List.filter_map (fun dependency ->
      if List.mem dependency (forbidden owner) then
        Some (Printf.sprintf "%s imports forbidden foundational library %s"
          owner dependency)
      else None) dependencies) graph

let verify_negative_test graph =
  let check owner dependency =
    let injected = (owner, [dependency]) :: graph in
    let expected =
      Printf.sprintf "%s imports forbidden foundational library %s" owner
        dependency
    in
    match violations injected with
    | [] ->
        failwith
          (Printf.sprintf "injected %s -> %s reverse edge was not rejected"
             owner dependency)
    | messages ->
        if not (List.exists (( = ) expected) messages) then
          failwith "dependency checker rejected the wrong injected edge"
  in
  check "sdl3" "prismel";
  check "metal" "sdl3";
  check "ogpu" "metal";
  check "ogpu_metal" "runtime"

let require_current_foundations graph =
  [ "sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal"; "ogpu"; "runtime"
  ; "wap"
  ]
  |> List.iter (fun required ->
    if not (List.exists (fun (name, _) -> name = required) graph) then
      failwith ("dependency graph omitted required library " ^ required))

let dune_files path =
  if Sys.is_directory path then
    Sys.readdir path |> Array.to_list |> List.sort String.compare
    |> List.filter_map (fun entry ->
      let candidate = Filename.concat (Filename.concat path entry) "dune" in
      if Sys.file_exists candidate then Some candidate else None)
  else [path]

let () =
  let paths = Array.to_list Sys.argv |> List.tl |> List.concat_map dune_files in
  if paths = [] then invalid_arg "gpu_dependency_direction: expected Dune files";
  let graph = List.concat_map libraries_of_file paths in
  require_current_foundations graph;
  verify_negative_test graph;
  match violations graph with
  | [] ->
      Printf.printf
        "GPU dependency direction passed (%d libraries; injected reverse edge rejected)\n"
        (List.length graph)
  | messages -> failwith (String.concat "\n" messages)
