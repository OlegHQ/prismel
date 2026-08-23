open Support

module String_map = Map.Make (String)
module String_set = Set.Make (String)

let expected_sdk_version = "26.5"
let deployment_target = "14.0"
let target_triple = "arm64-apple-macos14.0"
let output_relative = "lib/metal/generated_api_inventory.json"
let provenance_relative = "lib/metal/generated_provenance.ml"

let generator_source_paths =
  [ "tools/metal/generate_inventory.ml"
  ; "tools/metal/binding_availability.ml"
  ; "tools/metal/binding_availability.mli"
  ; "tools/metal/binding_availability_ast.ml"
  ; "tools/metal/binding_availability_ast.mli"
  ]

let generator_source_sha256 root =
  generator_source_paths
  |> List.map (fun relative ->
    relative, read_file (Filename.concat root relative))
  |> Binding_spec.aggregate_source_sha256

type availability_source =
  { header : string
  ; line : int
  ; macos_introduced : Binding_availability.version option
  ; macos_unavailable : bool
  }

type declaration =
  { identifier : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; line : int option
  ; signature : string
  ; attributes : string list
  ; constant_value : string option
  ; child_count : int
  ; macos_introduced : Binding_availability.version option
  ; availability_sources : availability_source list
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

type cached_header =
  { lines : string array
  }

type header_cache = cached_header String_map.t

let cache_headers files : header_cache =
  List.fold_left
    (fun cache (relative, path) ->
      if String_map.mem relative cache then
        fail "duplicate cached Metal header path: %s" relative;
      let lines = read_file path |> split_lines |> Array.of_list in
      String_map.add relative { lines } cache)
    String_map.empty files

let normalize_evidence_header headers path =
  let normalized =
    match normalize_header path with
    | Some path -> path
    | None when String_map.mem path headers -> path
    | None -> fail "availability source is not a public Metal header: %s" path
  in
  if not (String_map.mem normalized headers) then
    fail "availability source is not in the cached public header set: %s"
      normalized;
  normalized

let cached_header_line headers header line =
  let cached =
    match String_map.find_opt header headers with
    | Some cached -> cached
    | None -> fail "availability source header was not cached: %s" header
  in
  if line <= 0 || line > Array.length cached.lines then
    fail "availability source line is outside %s: %d (line count %d)" header
      line (Array.length cached.lines);
  cached.lines.(line - 1)

let compare_availability_source (left : availability_source)
    (right : availability_source) =
  let by_header = String.compare left.header right.header in
  if by_header <> 0 then by_header else Int.compare left.line right.line

let same_introduction left right =
  match left, right with
  | None, None -> true
  | Some left, Some right -> Binding_availability.equal left right
  | (None, Some _) | (Some _, None) -> false

let same_availability_source_value (left : availability_source)
    (right : availability_source) =
  same_introduction left.macos_introduced right.macos_introduced
  && Bool.equal left.macos_unavailable right.macos_unavailable

let describe_source_value (source : availability_source) =
  match source.macos_unavailable, source.macos_introduced with
  | true, None -> "unavailable"
  | false, None -> "no macOS introduction"
  | false, Some version -> Binding_availability.canonical version
  | true, Some version ->
      "invalid unavailable+" ^ Binding_availability.canonical version

let merge_availability_sources left right =
  let sorted = List.sort compare_availability_source (left @ right) in
  let rec loop output = function
    | first :: second :: rest
      when compare_availability_source first second = 0 ->
        if not (same_availability_source_value first second) then
          fail
            "availability source %s:%d resolves inconsistently (%s versus %s)"
            first.header first.line (describe_source_value first)
            (describe_source_value second);
        loop output (first :: rest)
    | source :: rest -> loop (source :: output) rest
    | [] -> List.rev output
  in
  loop [] sorted

let effective_introduction sources =
  if
    List.exists
      (fun (source : availability_source) -> source.macos_unavailable)
      sources
  then None
  else
    sources
    |> List.map (fun (source : availability_source) -> source.macos_introduced)
    |> Binding_availability.maximum

let macos_unavailable sources =
  List.exists
    (fun (source : availability_source) -> source.macos_unavailable)
    sources

let macos_unavailable_message =
  "API_UNAVAILABLE(macos) has no introduction version"

let availability_source headers (site : Binding_availability_ast.site) =
  let header = normalize_evidence_header headers site.file in
  let source = cached_header_line headers header site.line in
  match Binding_availability.parse_site source with
  | Ok macos_introduced ->
      { header
      ; line = site.line
      ; macos_introduced
      ; macos_unavailable = false
      }
  | Error error when String.equal error.message macos_unavailable_message ->
      { header
      ; line = site.line
      ; macos_introduced = None
      ; macos_unavailable = true
      }
  | Error error ->
      fail "cannot parse macOS availability at %s:%d:%d: %s" header site.line
        (error.offset + 1) error.message

let direct_availability_sources headers identifier value =
  let sites =
    match Binding_availability_ast.sites value with
    | sites -> sites
    | exception Binding_availability_ast.Error message ->
        fail "cannot resolve availability sources for %s: %s" identifier
          message
  in
  sites
  |> List.map (availability_source headers)
  |> merge_availability_sources []

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

let rec constant_expression_value value =
  match object_string "kind" value, object_string "value" value with
  | Some "ConstantExpr", Some value -> Some value
  | _ -> object_list "inner" value |> List.find_map constant_expression_value

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

let classify_declaration declaration =
  let unavailable =
    macos_unavailable declaration.availability_sources
    || List.mem "UnavailableAttr" declaration.attributes
  in
  let classification, reason =
    Classification.classify ~unavailable ~identifier:declaration.identifier
      ~header:declaration.header ~kind:declaration.kind
      ~signature:declaration.signature
  in
  { declaration with classification; reason }

let merge_declarations left right =
  let selected = better_declaration left right in
  let availability_sources =
    merge_availability_sources left.availability_sources
      right.availability_sources
  in
  { selected with
    attributes =
      List.sort_uniq String.compare (left.attributes @ right.attributes)
  ; macos_introduced = effective_introduction availability_sources
  ; availability_sources
  }
  |> classify_declaration

let add_declaration declarations declaration =
  declarations :=
    String_map.update declaration.identifier
      (function
        | None -> Some declaration
        | Some existing -> Some (merge_declarations existing declaration))
      !declarations

let owned_tag_ids value =
  (* Clang puts the tag actually owned by a typedef on an immediate type child.
     Searching recursively would incorrectly claim tags reached through an
     ordinary typedef alias, such as MTLCoordinate2D -> MTLSamplePosition. *)
  object_list "inner" value
  |> List.filter_map (fun child ->
    Option.bind (object_member "ownedTagDecl" child) (object_string "id"))
  |> List.sort_uniq String.compare

type alias_family =
  { name : string option
  ; direct_availability : availability_source list
  }

type alias_families =
  { parents : (string, string) Hashtbl.t
  ; values : (string, alias_family) Hashtbl.t
  }

let empty_alias_family = { name = None; direct_availability = [] }

let create_alias_families capacity =
  { parents = Hashtbl.create capacity; values = Hashtbl.create capacity }

let rec alias_root families tag_id =
  match Hashtbl.find_opt families.parents tag_id with
  | None ->
      Hashtbl.add families.parents tag_id tag_id;
      tag_id
  | Some parent when String.equal parent tag_id -> tag_id
  | Some parent ->
      let root = alias_root families parent in
      Hashtbl.replace families.parents tag_id root;
      root

let merge_alias_family_value tag_id left right =
  let name =
    match left.name, right.name with
    | None, name | name, None -> name
    | Some left, Some right when String.equal left right -> Some left
    | Some left, Some right ->
        fail "Clang tag family %s has conflicting owning typedefs %s and %s"
          tag_id left right
  in
  { name
  ; direct_availability =
      merge_availability_sources left.direct_availability
        right.direct_availability
  }

let union_alias_ids families left right =
  (* An NS_ENUM typedef owns the forward tag while the definition containing
     the cases has a distinct id and points back through [previousDecl]. *)
  let left = alias_root families left in
  let right = alias_root families right in
  if not (String.equal left right) then begin
    let root, child =
      if String.compare left right <= 0 then left, right else right, left
    in
    let root_value =
      Option.value (Hashtbl.find_opt families.values root)
        ~default:empty_alias_family
    in
    let child_value =
      Option.value (Hashtbl.find_opt families.values child)
        ~default:empty_alias_family
    in
    Hashtbl.replace families.parents child root;
    Hashtbl.remove families.values child;
    Hashtbl.replace families.values root
      (merge_alias_family_value root root_value child_value)
  end

let update_alias_family families tag_id update =
  let tag_id = alias_root families tag_id in
  let current =
    Option.value (Hashtbl.find_opt families.values tag_id)
      ~default:empty_alias_family
  in
  Hashtbl.replace families.values tag_id (update current)

let register_alias_name families tag_id name =
  update_alias_family families tag_id (fun family ->
    let name =
      match family.name with
      | None -> Some name
      | Some existing when String.equal existing name -> family.name
      | Some existing ->
          fail "Clang tag %s has conflicting owning typedefs %s and %s" tag_id
            existing name
    in
    { family with name })

let register_alias_availability families tag_id sources =
  update_alias_family families tag_id (fun family ->
    { family with
      direct_availability =
        merge_availability_sources family.direct_availability sources
    })

let alias_name families tag_id =
  let tag_id = alias_root families tag_id in
  Option.bind (Hashtbl.find_opt families.values tag_id) (fun family ->
    family.name)

let public_header = function
  | Some header ->
      String.starts_with ~prefix:"Metal/" header
      || String.equal header "QuartzCore/CAMetalLayer.h"
  | None -> false

let direct_sources_for_alias_scope headers label own_header value =
  if public_header own_header then
    direct_availability_sources headers label value
  else []

let rec collect_alias_families headers families ?header value =
  let ast_kind = object_string "kind" value in
  let own_header =
    match Option.bind (location_file value) normalize_header with
    | Some header -> Some header
    | None -> header
  in
  (match ast_kind, object_string "name" value with
   | Some "TypedefDecl", Some name when not (String.equal name "") ->
       let tag_ids = owned_tag_ids value in
       let direct_availability =
         if tag_ids = [] then []
         else
           direct_sources_for_alias_scope headers ("typedef:" ^ name) own_header
             value
       in
       tag_ids
       |> List.iter (fun tag_id ->
         register_alias_name families tag_id name;
         register_alias_availability families tag_id direct_availability)
   | Some (("EnumDecl" | "CXXRecordDecl") as kind), _ ->
       (match object_string "id" value with
        | Some tag_id ->
            Option.iter
              (fun previous -> union_alias_ids families tag_id previous)
              (object_string "previousDecl" value);
            let direct_availability =
              direct_sources_for_alias_scope headers kind own_header value
            in
            register_alias_availability families tag_id direct_availability
        | None -> fail "Clang %s is missing its exact tag id" kind)
   | _ -> ());
  object_list "inner" value
  |> List.iter (collect_alias_families headers families ?header:own_header)

let alias_scope_availability families ast_kind value =
  let family_sources tag_id =
    let tag_id = alias_root families tag_id in
    match Hashtbl.find_opt families.values tag_id with
    | Some family -> family.direct_availability
    | None -> []
  in
  match ast_kind with
  | Some "TypedefDecl" ->
      owned_tag_ids value
      |> List.concat_map family_sources
      |> merge_availability_sources []
  | Some ("EnumDecl" | "CXXRecordDecl") ->
      (match object_string "id" value with
       | Some tag_id -> family_sources tag_id
       | None -> [])
  | Some _ | None -> []

let availability_scope_kind = function
  | Some
      ("ObjCProtocolDecl" | "ObjCInterfaceDecl" | "ObjCCategoryDecl"
      | "EnumDecl" | "CXXRecordDecl" | "TypedefDecl") -> true
  | Some _ | None -> false

let rec collect headers declarations alias_families ?owner ?header
    ?(inherited_availability = []) value =
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
                    (alias_name alias_families))
         | Some "CXXRecordDecl", Some id ->
             alias_name alias_families id
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
  let declaration_identifier =
    match ast_kind, name with
    | Some ast_kind, Some name when Option.is_some (declaration_kind ast_kind) ->
        Some
          (identifier ~kind:ast_kind ~owner:declaration_owner ~name value)
    | _ -> None
  in
  let direct_availability =
    if
      public_header own_header
      && (Option.is_some declaration_identifier
          || availability_scope_kind ast_kind)
    then
      let label =
        match declaration_identifier, ast_kind with
        | Some identifier, _ -> identifier
        | None, Some kind -> kind
        | None, None -> "<unknown AST node>"
      in
      direct_availability_sources headers label value
    else []
  in
  let alias_availability =
    alias_scope_availability alias_families ast_kind value
  in
  let combined_availability =
    merge_availability_sources inherited_availability alias_availability
    |> merge_availability_sources direct_availability
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
           macos_unavailable combined_availability
           || List.mem "UnavailableAttr" attributes
         in
         let identifier = Option.get declaration_identifier in
         let classification, reason =
           Classification.classify ~unavailable ~identifier ~header
             ~kind:(Option.get (declaration_kind ast_kind)) ~signature
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
           ; constant_value =
               if ast_kind = "EnumConstantDecl" then
                 constant_expression_value value
               else None
           ; child_count = List.length (direct_declaration_children value)
           ; macos_introduced =
               effective_introduction combined_availability
           ; availability_sources = combined_availability
           ; classification
           ; reason
           }
       end
   | _ -> ());
  let inherited_availability =
    if availability_scope_kind ast_kind then combined_availability
    else inherited_availability
  in
  object_list "inner" value
  |> List.iter
       (collect headers declarations alias_families ?owner:next_owner
          ?header:own_header ~inherited_availability)

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

let parse_ast headers path declarations =
  let alias_families = create_alias_families 256 in
  let iter parse =
    let input = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr input)
      (fun () -> Yojson.Safe.seq_from_channel input |> Seq.iter parse)
  in
  iter (collect_alias_families headers alias_families);
  iter (collect headers declarations alias_families)

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
  let availability_source_json (source : availability_source) =
    `Assoc [ "header", `String source.header; "line", `Int source.line ]
  in
  let fields =
    [ "id", `String declaration.identifier
    ; "kind", `String declaration.kind
    ; "name", `String declaration.name
    ; "owner", option_json (fun value -> `String value) declaration.owner
    ; "header", `String declaration.header
    ; "line", option_json (fun value -> `Int value) declaration.line
    ; "signature", `String declaration.signature
    ; "attributes", `List (List.map (fun value -> `String value) declaration.attributes)
    ; ( "macos_introduced"
      , option_json
          (fun version ->
            `String (Binding_availability.canonical version))
          declaration.macos_introduced )
    ; ( "availability_sources"
      , `List
          (List.map availability_source_json declaration.availability_sources)
      )
    ; "classification", `String (Classification.name declaration.classification)
    ; "reason", `String declaration.reason
    ]
  in
  let fields =
    match declaration.constant_value with
    | Some value -> fields @ [ "constant_value", `String value ]
    | None -> fields
  in
  `Assoc fields

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
          |> classify_declaration
      | _ -> declaration
    in
    add_declaration resolved declaration);
  String_map.bindings !resolved |> List.map snd

let validate_alias_availability_propagation () =
  let relative_header = "Metal/Fixture.h" in
  let absolute_header =
    "/SDK/System/Library/Frameworks/Metal.framework/Headers/Fixture.h"
  in
  let headers =
    String_map.singleton relative_header
      { lines =
          [| "API_AVAILABLE(macos(12.0));"
           ; "API_AVAILABLE(macos(13.0));"
           ; "API_AVAILABLE(macos(14.0));"
           ; "API_UNAVAILABLE(macos);"
           ; "API_AVAILABLE(macos(12));"
           ; ""
           ; ""
           ; ""
          |]
      }
  in
  let location line =
    `Assoc [ "file", `String absolute_header; "line", `Int line ]
  in
  let availability_attribute line =
    `Assoc
      [ "kind", `String "AvailabilityAttr"
      ; ( "loc"
        , `Assoc
            [ ( "spellingLoc"
              , `Assoc
                  [ "file", `String "/SDK/usr/include/AvailabilityInternal.h"
                  ; "line", `Int 244
                  ] )
            ; "expansionLoc", location line
            ] )
      ]
  in
  let owned_type tag_id =
    `Assoc
      [ "kind", `String "ElaboratedType"
      ; "ownedTagDecl", `Assoc [ "id", `String tag_id ]
      ]
  in
  let typedef ?availability ~name ~tag_id line =
    let inner =
      owned_type tag_id
      :: (match availability with
          | Some line -> [ availability_attribute line ]
          | None -> [])
    in
    `Assoc
      [ "kind", `String "TypedefDecl"
      ; "id", `String ("typedef-" ^ name)
      ; "name", `String name
      ; "loc", location line
      ; "type", `Assoc [ "qualType", `String name ]
      ; "inner", `List inner
      ]
  in
  let enum_case ?availability name line =
    let inner =
      match availability with
      | Some line -> [ availability_attribute line ]
      | None -> []
    in
    `Assoc
      [ "kind", `String "EnumConstantDecl"
      ; "id", `String ("case-" ^ name)
      ; "name", `String name
      ; "loc", location line
      ; "type", `Assoc [ "qualType", `String "NSUInteger" ]
      ; "inner", `List inner
      ]
  in
  let field name line =
    `Assoc
      [ "kind", `String "FieldDecl"
      ; "id", `String ("field-" ^ name)
      ; "name", `String name
      ; "loc", location line
      ; "type", `Assoc [ "qualType", `String "NSUInteger" ]
      ]
  in
  let enum ?availability ?previous ~tag_id cases line =
    let inner =
      cases
      @
      match availability with
      | Some line -> [ availability_attribute line ]
      | None -> []
    in
    let fields =
      [ "kind", `String "EnumDecl"
      ; "id", `String tag_id
      ; "name", `String ""
      ; "loc", location line
      ; "inner", `List inner
      ]
    in
    let fields =
      match previous with
      | Some previous -> ("previousDecl", `String previous) :: fields
      | None -> fields
    in
    `Assoc fields
  in
  let record ?availability ~tag_id fields line =
    let inner =
      fields
      @
      match availability with
      | Some line -> [ availability_attribute line ]
      | None -> []
    in
    `Assoc
      [ "kind", `String "CXXRecordDecl"
      ; "id", `String tag_id
      ; "name", `String ""
      ; "loc", location line
      ; "inner", `List inner
      ]
  in
  let enum_forward_tag = "tag-enum-typedef-direct-forward" in
  let enum_tag = "tag-enum-typedef-direct-definition" in
  let record_tag = "tag-record-tag-direct" in
  let unavailable_tag = "tag-enum-unavailable" in
  let roots =
    [ enum ~previous:enum_forward_tag ~tag_id:enum_tag
        [ enum_case ~availability:3 "MTLFixtureCaseDirect" 7
        ; enum_case "MTLFixtureCaseSibling" 8
        ]
        6
    ; typedef ~availability:1 ~name:"MTLFixtureEnum"
        ~tag_id:enum_forward_tag 6
    ; record ~availability:2 ~tag_id:record_tag
        [ field "first" 7; field "second" 8 ]
        6
    ; typedef ~name:"MTLFixtureRecord" ~tag_id:record_tag 6
    ; enum ~tag_id:unavailable_tag [ enum_case "MTLFixtureUnavailable" 7 ] 6
    ; typedef ~availability:4 ~name:"MTLFixtureUnavailableEnum"
        ~tag_id:unavailable_tag 6
    ]
  in
  let collect_roots roots =
    let alias_families = create_alias_families 8 in
    List.iter (collect_alias_families headers alias_families) roots;
    let declarations = ref String_map.empty in
    List.iter (collect headers declarations alias_families) roots;
    String_map.bindings !declarations |> List.map snd
  in
  let declarations = collect_roots roots in
  let duplicate_and_reordered = collect_roots (List.rev roots @ roots) in
  if declarations <> duplicate_and_reordered then
    fail
      "typedef/tag availability propagation depends on AST root order or duplicate roots";
  let find identifier =
    match
      List.find_opt
        (fun declaration -> String.equal declaration.identifier identifier)
        declarations
    with
    | Some declaration -> declaration
    | None -> fail "alias availability fixture is missing %s" identifier
  in
  let require_version identifier expected =
    let declaration = find identifier in
    match declaration.macos_introduced with
    | Some actual when Binding_availability.equal actual expected -> declaration
    | Some actual ->
        fail "alias availability fixture %s expected %s, found %s" identifier
          (Binding_availability.canonical expected)
          (Binding_availability.canonical actual)
    | None ->
        fail "alias availability fixture %s expected %s, found baseline"
          identifier (Binding_availability.canonical expected)
  in
  let v12 = { Binding_availability.major = 12; minor = 0; patch = 0 } in
  let v13 = { Binding_availability.major = 13; minor = 0; patch = 0 } in
  let v14 = { Binding_availability.major = 14; minor = 0; patch = 0 } in
  [ "enum:MTLFixtureEnum"
  ; "typedef:MTLFixtureEnum"
  ; "enum-case:MTLFixtureEnum:MTLFixtureCaseSibling"
  ]
  |> List.iter (fun identifier -> ignore (require_version identifier v12));
  let direct_case =
    require_version
      "enum-case:MTLFixtureEnum:MTLFixtureCaseDirect" v14
  in
  if List.length direct_case.availability_sources <> 2 then
    fail "member-only availability evidence was not kept on its exact enum case";
  [ "record:MTLFixtureRecord"
  ; "typedef:MTLFixtureRecord"
  ; "field:MTLFixtureRecord:first"
  ; "field:MTLFixtureRecord:second"
  ]
  |> List.iter (fun identifier -> ignore (require_version identifier v13));
  let sibling = find "enum-case:MTLFixtureEnum:MTLFixtureCaseSibling" in
  if List.length sibling.availability_sources <> 1 then
    fail "member-only availability evidence contaminated its enum sibling";
  [ "enum:MTLFixtureUnavailableEnum"
  ; "typedef:MTLFixtureUnavailableEnum"
  ; "enum-case:MTLFixtureUnavailableEnum:MTLFixtureUnavailable"
  ]
  |> List.iter (fun identifier ->
    let declaration = find identifier in
    if Option.is_some declaration.macos_introduced then
      fail "macOS-unavailable alias fixture %s acquired an introduction" identifier;
    if declaration.classification <> Classification.Scope_excluded then
      fail "macOS-unavailable alias fixture %s is not scope-excluded" identifier);
  let malformed =
    [ typedef ~availability:5 ~name:"MTLMalformedAlias"
        ~tag_id:"tag-malformed" 6
    ; enum ~tag_id:"tag-malformed" [] 6
    ]
  in
  (match collect_roots malformed with
   | exception Support.Error _ -> ()
   | _ -> fail "malformed typedef-owned availability was accepted");
  let conflicting_aliases =
    [ typedef ~name:"MTLFirstAlias" ~tag_id:"tag-conflict" 6
    ; typedef ~name:"MTLSecondAlias" ~tag_id:"tag-conflict" 7
    ; enum ~tag_id:"tag-conflict" [] 8
    ]
  in
  match collect_roots conflicting_aliases with
  | exception Support.Error _ -> ()
  | _ -> fail "one Clang tag was accepted with two owning typedef aliases"

let validate_availability_source_merge () =
  let source version =
    { header = "Metal/Fixture.h"
    ; line = 7
    ; macos_introduced = Some version
    ; macos_unavailable = false
    }
  in
  let first = source { major = 10; minor = 13; patch = 0 } in
  let duplicate = source { major = 10; minor = 13; patch = 0 } in
  if List.length (merge_availability_sources [ first ] [ duplicate ]) <> 1 then
    fail "identical availability-source evidence was not deduplicated";
  let conflicting = source { major = 10; minor = 15; patch = 0 } in
  match merge_availability_sources [ first ] [ conflicting ] with
  | exception Support.Error message
    when contains ~needle:"resolves inconsistently" message -> ()
  | exception Support.Error message ->
      fail "availability-source conflict produced the wrong error: %s" message
  | _ -> fail "conflicting availability-source evidence was accepted"

let validate_availability_fixtures declarations =
  validate_availability_source_merge ();
  let by_identifier =
    List.fold_left
      (fun declarations declaration ->
        String_map.add declaration.identifier declaration declarations)
      String_map.empty declarations
  in
  let find identifier =
    match String_map.find_opt identifier by_identifier with
    | Some declaration -> declaration
    | None -> fail "availability fixture is missing from inventory: %s" identifier
  in
  let require_version identifier expected =
    let declaration = find identifier in
    match declaration.macos_introduced with
    | Some actual when Binding_availability.equal actual expected -> ()
    | Some actual ->
        fail "availability fixture %s expected macOS %s, found %s" identifier
          (Binding_availability.canonical expected)
          (Binding_availability.canonical actual)
    | None ->
        fail "availability fixture %s expected macOS %s, found no introduction"
          identifier (Binding_availability.canonical expected)
  in
  let require_baseline identifier =
    let declaration = find identifier in
    match declaration.macos_introduced with
    | None -> ()
    | Some actual ->
        fail "availability fixture %s expected baseline, found macOS %s"
          identifier (Binding_availability.canonical actual)
  in
  require_version "method:-[MTLRenderCommandEncoder setViewports:count:]"
    { major = 10; minor = 13; patch = 0 };
  require_version
    "method:-[MTLRenderCommandEncoder setVertexAmplificationCount:viewMappings:]"
    { major = 10; minor = 15; patch = 4 };
  require_version "property:CAMetalLayer:residencySet"
    { major = 26; minor = 0; patch = 0 };
  require_baseline "field:MTLOrigin:x";
  let v10_11 = { Binding_availability.major = 10; minor = 11; patch = 0 } in
  let v10_15_4 =
    { Binding_availability.major = 10; minor = 15; patch = 4 }
  in
  let v11 = { Binding_availability.major = 11; minor = 0; patch = 0 } in
  let v26 = { Binding_availability.major = 26; minor = 0; patch = 0 } in
  [ "enum:MTL4CompilerTaskStatus"
  ; "typedef:MTL4CompilerTaskStatus"
  ; "enum-case:MTL4CompilerTaskStatus:MTL4CompilerTaskStatusNone"
  ; "enum-case:MTL4CompilerTaskStatus:MTL4CompilerTaskStatusScheduled"
  ; "enum-case:MTL4CompilerTaskStatus:MTL4CompilerTaskStatusCompiling"
  ; "enum-case:MTL4CompilerTaskStatus:MTL4CompilerTaskStatusFinished"
  ]
  |> List.iter (fun identifier -> require_version identifier v26);
  [ "record:MTLVertexAmplificationViewMapping"
  ; "typedef:MTLVertexAmplificationViewMapping"
  ; "field:MTLVertexAmplificationViewMapping:viewportArrayIndexOffset"
  ; "field:MTLVertexAmplificationViewMapping:renderTargetArrayIndexOffset"
  ]
  |> List.iter (fun identifier -> require_version identifier v10_15_4);
  require_version "typedef:MTLBlendFactor" v10_11;
  require_version "enum:MTLAccelerationStructureUsage" v11;
  require_version
    "enum-case:MTLAccelerationStructureUsage:MTLAccelerationStructureUsagePreferFastBuild"
    v11;
  require_version
    "enum-case:MTLAccelerationStructureUsage:MTLAccelerationStructureUsagePreferFastIntersection"
    v26;
  let unavailable =
    find "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v1"
  in
  if Option.is_some unavailable.macos_introduced then
    fail "macOS-unavailable fixture acquired an introduction version";
  if unavailable.classification <> Classification.Scope_excluded then
    fail "macOS-unavailable fixture lost its scope-excluded classification";
  let available = find "property:CAMetalLayer:preferredDevice" in
  if available.classification = Classification.Scope_excluded then
    fail "watchOS-unavailable fixture corrupted macOS classification"

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
  validate_alias_availability_propagation ();
  let sdk = command_output "xcrun" [ "--sdk"; "macosx"; "--show-sdk-path" ] in
  let sdk_version =
    command_output "xcrun" [ "--sdk"; "macosx"; "--show-sdk-version" ]
  in
  if sdk_version <> expected_sdk_version then
    fail "Metal inventory requires macOS SDK %s, found %s" expected_sdk_version
      sdk_version;
  let headers = header_files sdk in
  let cached_headers = cache_headers headers in
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
      parse_ast cached_headers output declarations));
  let declarations =
    String_map.bindings !declarations |> List.map snd
    |> resolve_unknown_owners
    |> List.sort (fun left right -> String.compare left.identifier right.identifier)
  in
  validate_availability_fixtures declarations;
  validate_bound_identifiers declarations;
  let header_hash = aggregate_headers headers in
  let classification_path = Filename.concat root "tools/metal/classification.ml" in
  let binding_plan_hash = Binding_plan.source_sha256 ~root in
  let generator_source_hash = generator_source_sha256 root in
  let value =
    `Assoc
      [ "schema", `Int 2
      ; "kind", `String "metal_api_inventory"
      ; "generator", `String "tools/metal/generate_inventory.exe"
      ; "sdk_version", `String sdk_version
      ; "deployment_target", `String deployment_target
      ; "target_triple", `String target_triple
      ; "clang", `String (command_output "clang++" [ "--version" ] |> first_line)
      ; "generator_source_sha256", `String generator_source_hash
      ; "header_count", `Int (List.length headers)
      ; "header_aggregate_sha256", `String header_hash
      ; "classification_source_sha256",
        `String (sha256 (read_file classification_path))
      ; "binding_plan_source_sha256", `String binding_plan_hash
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
       let generator_source_sha256 = %S\n\
       let header_aggregate_sha256 = %S\n\
       let binding_plan_source_sha256 = %S\n"
      sdk_version deployment_target target_triple (List.length headers)
      generator_source_hash header_hash binding_plan_hash
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
