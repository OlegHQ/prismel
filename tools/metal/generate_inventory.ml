open Support

module String_map = Map.Make (String)
module String_set = Set.Make (String)

let expected_sdk_version = "26.5"
let deployment_target = "14.0"
let target_triple = "arm64-apple-macos14.0"
let output_relative = "lib/metal/generated_api_inventory.json"
let provenance_relative = "lib/metal/generated_provenance.ml"

type declaration =
  { identifier : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; line : int option
  ; signature : string
  ; attributes : string list
  ; child_count : int
  ; classification : Classification.t
  ; reason : string
  }

let split_lines value =
  if value = "" then [] else String.split_on_char '\n' value

let first_line value =
  match split_lines value with
  | line :: _ -> line
  | [] -> ""

let object_member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let object_string name value = Option.bind (object_member name value) string
let object_bool name value = Option.bind (object_member name value) bool

let object_list name value =
  Option.value (Option.bind (object_member name value) list) ~default:[]

let nested_string path value =
  Option.bind
    (List.fold_left
       (fun value name -> Option.bind value (object_member name))
       (Some value) path)
    string

let nested_int path value =
  Option.bind
    (List.fold_left
       (fun value name -> Option.bind value (object_member name))
       (Some value) path)
    int

let rec remove_directory path =
  Sys.readdir path
  |> Array.iter (fun name ->
    let entry = Filename.concat path name in
    if Sys.is_directory entry then remove_directory entry else Sys.remove entry);
  Unix.rmdir path

let with_temp_directory prefix f =
  let path = Filename.temp_dir prefix "" in
  Fun.protect ~finally:(fun () -> remove_directory path) (fun () -> f path)

let framework_marker framework = "/" ^ framework ^ ".framework/Headers/"

let normalize_header path =
  let find marker prefix =
    match String.index_opt path marker.[0] with
    | None -> None
    | Some _ ->
        let marker_length = String.length marker in
        let path_length = String.length path in
        let rec search index =
          if index + marker_length > path_length then None
          else if String.sub path index marker_length = marker then
            Some
              (prefix
               ^ String.sub path (index + marker_length)
                   (path_length - index - marker_length))
          else search (index + 1)
        in
        search 0
  in
  match find (framework_marker "Metal") "Metal/" with
  | Some _ as path -> path
  | None -> find (framework_marker "QuartzCore") "QuartzCore/"

let location_file value =
  let candidates =
    [ [ "loc"; "file" ]
    ; [ "loc"; "expansionLoc"; "file" ]
    ; [ "loc"; "spellingLoc"; "file" ]
    ; [ "range"; "begin"; "file" ]
    ; [ "range"; "begin"; "expansionLoc"; "file" ]
    ; [ "range"; "begin"; "spellingLoc"; "file" ]
    ]
  in
  List.find_map (fun path -> nested_string path value) candidates

let location_line value =
  let candidates =
    [ [ "loc"; "line" ]
    ; [ "loc"; "expansionLoc"; "line" ]
    ; [ "loc"; "spellingLoc"; "line" ]
    ; [ "range"; "begin"; "line" ]
    ; [ "range"; "begin"; "expansionLoc"; "line" ]
    ; [ "range"; "begin"; "spellingLoc"; "line" ]
    ]
  in
  List.find_map (fun path -> nested_int path value) candidates

let declaration_attributes value =
  object_list "inner" value
  |> List.filter_map (fun child ->
    match object_string "kind" child with
    | Some kind when String.ends_with ~suffix:"Attr" kind -> Some kind
    | Some _ | None -> None)
  |> List.sort_uniq String.compare

let direct_declaration_children value =
  object_list "inner" value
  |> List.filter (fun child ->
    match object_string "kind" child with
    | Some
        ("ObjCMethodDecl" | "ObjCPropertyDecl" | "EnumConstantDecl"
        | "FieldDecl") -> true
    | Some _ | None -> false)

let type_string field value =
  match object_member field value with
  | Some type_value ->
      Option.value
        (object_string "qualType" type_value)
        ~default:"<unspecified>"
  | None -> "<unspecified>"

let method_signature value =
  let return_type = type_string "returnType" value in
  let parameters =
    object_list "inner" value
    |> List.filter_map (fun child ->
      if object_string "kind" child = Some "ParmVarDecl" then
        Some (type_string "type" child)
      else None)
  in
  let receiver =
    match object_bool "instance" value with
    | Some true -> "instance"
    | Some false -> "class"
    | None -> "unknown"
  in
  Printf.sprintf "%s (%s) -> %s" receiver
    (String.concat ", " parameters) return_type

let signature kind value =
  match kind with
  | "ObjCMethodDecl" -> method_signature value
  | "ObjCPropertyDecl" | "FieldDecl" | "TypedefDecl" | "VarDecl" ->
      type_string "type" value
  | "FunctionDecl" -> type_string "type" value
  | "EnumConstantDecl" -> type_string "type" value
  | "ObjCProtocolDecl" | "ObjCInterfaceDecl" | "EnumDecl"
  | "CXXRecordDecl" -> object_string "tagUsed" value |> Option.value ~default:""
  | _ -> ""

let method_owner value =
  match object_string "mangledName" value with
  | Some mangled
    when String.length mangled > 3
         && (String.starts_with ~prefix:"-[" mangled
             || String.starts_with ~prefix:"+[" mangled) ->
      (match String.index_from_opt mangled 2 ' ' with
       | None -> None
       | Some separator ->
           let candidate = String.sub mangled 2 (separator - 2) in
           let candidate =
             match String.index_opt candidate '(' with
             | Some category -> String.sub candidate 0 category
             | None -> candidate
           in
           if candidate = "" then None else Some candidate)
  | Some _ | None -> None

let identifier ~kind ~owner ~name value =
  match kind with
  | "ObjCMethodDecl" ->
      (match owner, object_bool "instance" value with
       | Some owner, Some instance ->
           Printf.sprintf "method:%c[%s %s]" (if instance then '-' else '+')
             owner name
       | _ ->
           Printf.sprintf "method:%s:%s"
             (Option.value owner ~default:"<unknown>") name)
  | "ObjCPropertyDecl" ->
      Printf.sprintf "property:%s:%s"
        (Option.value owner ~default:"<unknown>") name
  | "EnumConstantDecl" ->
      Printf.sprintf "enum-case:%s:%s"
        (Option.value owner ~default:"<unknown>") name
  | "FieldDecl" ->
      Printf.sprintf "field:%s:%s"
        (Option.value owner ~default:"<unknown>") name
  | "ObjCProtocolDecl" -> "protocol:" ^ name
  | "ObjCInterfaceDecl" -> "class:" ^ name
  | "EnumDecl" -> "enum:" ^ name
  | "CXXRecordDecl" -> "record:" ^ name
  | "FunctionDecl" -> "function:" ^ name
  | "TypedefDecl" -> "typedef:" ^ name
  | "VarDecl" -> "variable:" ^ name
  | _ -> kind ^ ":" ^ name

let declaration_kind = function
  | "ObjCProtocolDecl" -> Some "protocol"
  | "ObjCInterfaceDecl" -> Some "class"
  | "ObjCMethodDecl" -> Some "method"
  | "ObjCPropertyDecl" -> Some "property"
  | "EnumDecl" -> Some "enum"
  | "EnumConstantDecl" -> Some "enum-case"
  | "CXXRecordDecl" -> Some "record"
  | "FieldDecl" -> Some "field"
  | "FunctionDecl" -> Some "function"
  | "TypedefDecl" -> Some "typedef"
  | "VarDecl" -> Some "variable"
  | _ -> None

let better_declaration left right =
  if right.child_count > left.child_count then right
  else if right.child_count < left.child_count then left
  else if String.length right.signature > String.length left.signature then right
  else left

let add_declaration declarations declaration =
  declarations :=
    String_map.update declaration.identifier
      (function
        | None -> Some declaration
        | Some existing -> Some (better_declaration existing declaration))
      !declarations

let rec owned_tag_ids value =
  let own =
    match object_member "ownedTagDecl" value with
    | Some tag ->
        (match object_string "id" tag with Some id -> [ id ] | None -> [])
    | None -> []
  in
  own @ (object_list "inner" value |> List.concat_map owned_tag_ids)

let rec collect_aliases aliases value =
  (match object_string "kind" value, object_string "name" value with
   | Some "TypedefDecl", Some name ->
       owned_tag_ids value
       |> List.iter (fun id -> Hashtbl.replace aliases id name)
   | _ -> ());
  object_list "inner" value |> List.iter (collect_aliases aliases)

let rec collect declarations aliases ?owner ?header value =
  let ast_kind = object_string "kind" value in
  let own_header =
    match Option.bind (location_file value) normalize_header with
    | Some header -> Some header
    | None -> header
  in
  let name =
    match object_string "name" value with
    | Some name when name <> "" -> Some name
    | Some _ | None ->
        (match ast_kind, object_string "id" value with
         | Some "EnumDecl", _ ->
             (match nested_string [ "fixedUnderlyingType"; "qualType" ] value with
              | Some name when String.starts_with ~prefix:"MTL" name -> Some name
              | Some _ | None ->
                  Option.bind (object_string "id" value)
                    (Hashtbl.find_opt aliases))
         | Some "CXXRecordDecl", Some id ->
             Hashtbl.find_opt aliases id
         | _ -> None)
  in
  let next_owner =
    match ast_kind, name with
    | (Some ("ObjCProtocolDecl" | "ObjCInterfaceDecl" | "EnumDecl"
      | "CXXRecordDecl" | "TypedefDecl")), Some name -> Some name
    | _ -> owner
  in
  let declaration_owner =
    match owner, ast_kind with
    | None, Some "ObjCMethodDecl" -> method_owner value
    | _ -> owner
  in
  (match ast_kind, name, own_header with
   | Some ast_kind, Some name, Some header
     when Option.is_some (declaration_kind ast_kind)
          && (String.starts_with ~prefix:"Metal/" header
              || header = "QuartzCore/CAMetalLayer.h") ->
       let attributes = declaration_attributes value in
       if not (List.mem "DeprecatedAttr" attributes) then begin
         let signature = signature ast_kind value in
         let unavailable =
           List.mem "UnavailableAttr" attributes
           || contains ~needle:"API_UNAVAILABLE" signature
         in
         let identifier =
           identifier ~kind:ast_kind ~owner:declaration_owner ~name value
         in
         let classification, reason =
           Classification.classify ~unavailable ~identifier
         in
         add_declaration declarations
           { identifier
           ; kind = Option.get (declaration_kind ast_kind)
           ; name
           ; owner = declaration_owner
           ; header
           ; line = location_line value
           ; signature
           ; attributes
           ; child_count = List.length (direct_declaration_children value)
           ; classification
           ; reason
           }
       end
   | _ -> ());
  object_list "inner" value
  |> List.iter
       (collect declarations aliases ?owner:next_owner ?header:own_header)

let run_to_file program arguments output_path error_path =
  let flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] in
  let output = Unix.openfile output_path flags 0o600 in
  let error = Unix.openfile error_path flags 0o600 in
  let pid =
    Fun.protect
      ~finally:(fun () ->
        Unix.close output;
        Unix.close error)
      (fun () ->
        Unix.create_process program (Array.of_list (program :: arguments))
          Unix.stdin output error)
  in
  let _, status = Unix.waitpid [] pid in
  match status with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED code ->
      fail "%s exited %d: %s" program code (read_file error_path)
  | Unix.WSIGNALED signal -> fail "%s was killed by signal %d" program signal
  | Unix.WSTOPPED signal -> fail "%s was stopped by signal %d" program signal

let clang_ast ~sdk ~source ~filter output error =
  let arguments =
    [ "-x"; "objective-c++"; "-std=c++17"; "-fobjc-arc"; "-fblocks"
    ; "-fsyntax-only"; "-Werror"; "-isysroot"; sdk; "-target"; target_triple
    ; "-mmacosx-version-min=" ^ deployment_target
    ; "-Xclang"; "-ast-dump=json"; "-Xclang"; "-ast-dump-filter"
    ; "-Xclang"; filter; source
    ]
  in
  run_to_file "clang++" arguments output error

let parse_ast path declarations =
  let aliases = Hashtbl.create 256 in
  let iter parse =
    let input = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr input)
      (fun () -> Yojson.Safe.seq_from_channel input |> Seq.iter parse)
  in
  iter (collect_aliases aliases);
  iter (collect declarations aliases)

let sorted_directory_files directory =
  Sys.readdir directory |> Array.to_list |> List.sort String.compare
  |> List.filter_map (fun name ->
    let path = Filename.concat directory name in
    if Sys.is_directory path then None else Some (name, path))

let header_files sdk =
  let metal =
    Filename.concat sdk
      "System/Library/Frameworks/Metal.framework/Headers"
  in
  let quartz =
    Filename.concat sdk
      "System/Library/Frameworks/QuartzCore.framework/Headers/CAMetalLayer.h"
  in
  if not (Sys.is_directory metal) then fail "Metal headers are missing from %s" sdk;
  if not (Sys.file_exists quartz) then fail "CAMetalLayer.h is missing from %s" sdk;
  sorted_directory_files metal
  |> List.filter (fun (name, _) ->
    String.ends_with ~suffix:".h" name
    || String.ends_with ~suffix:".apinotes" name)
  |> List.map (fun (name, path) -> "Metal/" ^ name, path)
  |> fun files -> files @ [ "QuartzCore/CAMetalLayer.h", quartz ]

let header_json (relative, path) =
  let contents = read_file path in
  `Assoc
    [ "path", `String relative
    ; "bytes", `Int (String.length contents)
    ; "sha256", `String (sha256 contents)
    ]

let aggregate_headers files =
  files
  |> List.map (fun (relative, path) ->
    let contents = read_file path in
    relative ^ "\000" ^ string_of_int (String.length contents) ^ "\000" ^ contents)
  |> String.concat "\000"
  |> sha256

let option_json f = function
  | Some value -> f value
  | None -> `Null

let declaration_json declaration =
  `Assoc
    [ "id", `String declaration.identifier
    ; "kind", `String declaration.kind
    ; "name", `String declaration.name
    ; "owner", option_json (fun value -> `String value) declaration.owner
    ; "header", `String declaration.header
    ; "line", option_json (fun value -> `Int value) declaration.line
    ; "signature", `String declaration.signature
    ; "attributes", `List (List.map (fun value -> `String value) declaration.attributes)
    ; "classification", `String (Classification.name declaration.classification)
    ; "reason", `String declaration.reason
    ]

let classification_counts declarations =
  let counts = Hashtbl.create 8 in
  [ Classification.Bound; Classification.Availability_gated
  ; Classification.Scope_excluded; Classification.Unreviewed
  ]
  |> List.iter (fun classification ->
    Hashtbl.add counts (Classification.name classification) 0);
  List.iter
    (fun declaration ->
      let name = Classification.name declaration.classification in
      Hashtbl.replace counts name (Hashtbl.find counts name + 1))
    declarations;
  `Assoc
    (Hashtbl.to_seq counts |> List.of_seq
     |> List.map (fun (name, count) -> name, `Int count)
     |> List.sort (fun (left, _) (right, _) -> String.compare left right))

let resolve_unknown_owners declarations =
  let candidates declaration =
    declarations
    |> List.filter (fun candidate ->
      candidate.kind = declaration.kind
      && candidate.name = declaration.name
      && candidate.header = declaration.header
      && candidate.signature = declaration.signature
      && Option.is_some candidate.owner)
  in
  let resolved = ref String_map.empty in
  declarations
  |> List.iter (fun declaration ->
    let declaration =
      match declaration.kind, declaration.owner, candidates declaration with
      | "property", None, [ candidate ] ->
          let owner = Option.get candidate.owner in
          { declaration with
            owner = Some owner
          ; identifier = "property:" ^ owner ^ ":" ^ declaration.name
          }
      | _ -> declaration
    in
    add_declaration resolved declaration);
  String_map.bindings !resolved |> List.map snd

let validate_bound_identifiers declarations =
  let inventory_identifiers =
    declarations
    |> List.fold_left
         (fun identifiers declaration ->
           String_set.add declaration.identifier identifiers)
         String_set.empty
  in
  let duplicate_bound_identifiers =
    Classification.bound_identifiers
    |> List.sort String.compare
    |> List.to_seq
    |> Seq.group ( = )
    |> Seq.filter_map (fun group ->
      match List.of_seq group with
      | identifier :: _ :: _ -> Some identifier
      | _ -> None)
    |> List.of_seq
  in
  if duplicate_bound_identifiers <> [] then
    fail "duplicate bound Metal identifiers: %s"
      (String.concat ", " duplicate_bound_identifiers);
  let missing =
    Classification.bound_identifiers
    |> List.filter (fun identifier ->
      not (String_set.mem identifier inventory_identifiers))
  in
  if missing <> [] then
    fail "bound Metal identifiers missing from the pinned SDK inventory: %s"
      (String.concat ", " missing)

let generate root =
  let sdk = command_output "xcrun" [ "--sdk"; "macosx"; "--show-sdk-path" ] in
  let sdk_version =
    command_output "xcrun" [ "--sdk"; "macosx"; "--show-sdk-version" ]
  in
  if sdk_version <> expected_sdk_version then
    fail "Metal inventory requires macOS SDK %s, found %s" expected_sdk_version
      sdk_version;
  let headers = header_files sdk in
  let declarations = ref String_map.empty in
  with_temp_directory "prismel-metal-inventory-" (fun directory ->
    let source = Filename.concat directory "inventory.mm" in
    write_file source
      "#import <Metal/Metal.h>\n#import <QuartzCore/CAMetalLayer.h>\n";
    [ "MTL"; "CAMetal" ]
    |> List.iter (fun filter ->
      let output = Filename.concat directory (filter ^ ".json") in
      let error = Filename.concat directory (filter ^ ".stderr") in
      clang_ast ~sdk ~source ~filter output error;
      parse_ast output declarations));
  let declarations =
    String_map.bindings !declarations |> List.map snd
    |> resolve_unknown_owners
    |> List.sort (fun left right -> String.compare left.identifier right.identifier)
  in
  validate_bound_identifiers declarations;
  let header_hash = aggregate_headers headers in
  let classification_path = Filename.concat root "tools/metal/classification.ml" in
  let value =
    `Assoc
      [ "schema", `Int 1
      ; "kind", `String "metal_api_inventory"
      ; "generator", `String "tools/metal/generate_inventory.exe"
      ; "sdk_version", `String sdk_version
      ; "deployment_target", `String deployment_target
      ; "target_triple", `String target_triple
      ; "clang", `String (command_output "clang++" [ "--version" ] |> first_line)
      ; "header_count", `Int (List.length headers)
      ; "header_aggregate_sha256", `String header_hash
      ; "classification_source_sha256",
        `String (sha256 (read_file classification_path))
      ; "symbol_count", `Int (List.length declarations)
      ; "classification_counts", classification_counts declarations
      ; "headers", `List (List.map header_json headers)
      ; "symbols", `List (List.map declaration_json declarations)
      ]
  in
  let provenance =
    Printf.sprintf
      "let sdk_version = %S\nlet deployment_target = %S\n\
       let target_triple = %S\nlet header_count = %d\n\
       let header_aggregate_sha256 = %S\n"
      sdk_version deployment_target target_triple (List.length headers) header_hash
  in
  pretty_json value, provenance, List.length declarations

let check path expected reproduction =
  if not (Sys.file_exists path) then fail "missing generated file: %s" path;
  if read_file path <> expected then
    fail "stale generated file: %s; run %s" path reproduction

let main () =
  let root, mode = root_and_mode () in
  let inventory, provenance, count = generate root in
  let inventory_path = Filename.concat root output_relative in
  let provenance_path = Filename.concat root provenance_relative in
  let reproduction =
    "dune exec tools/metal/generate_inventory.exe -- --write"
  in
  match mode with
  | Write ->
      ensure_directory (Filename.dirname inventory_path);
      write_file inventory_path inventory;
      write_file provenance_path provenance;
      Printf.printf "wrote %d Metal/CAMetalLayer API declarations\n%!" count
  | Check ->
      check inventory_path inventory reproduction;
      check provenance_path provenance reproduction;
      Printf.printf "Metal/CAMetalLayer inventory is current (%d declarations)\n%!"
        count

let () = protect_main main
