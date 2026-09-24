module Spec = Generator_spec
module Support = Generator_support
module C = Configurator.V1

open Support

let core_generator_version = "prismel-sdl3-clang-inventory-v2"
let extension_generator_version =
  "prismel-sdl3-extension-clang-inventory-v2"

type version = int * int * int

type item =
  { name : string
  ; classification : string
  ; json : Yojson.Safe.t
  }

type inventory_groups =
  { functions : item list
  ; records : item list
  ; enums : item list
  ; typedefs : item list
  }

type discovery =
  { include_root : string
  ; library_root : string option
  ; cflags : string list
  }

type generated =
  { outputs : (string * string) list
  ; counts : (string * int) list
  }

let classifications =
  [ "safe"; "raw-only"; "platform-excluded"; "not-applicable"; "unreviewed" ]

let has_prefix ~prefix value = String.starts_with ~prefix value

let contains ~needle value =
  let needle_length = String.length needle in
  let value_length = String.length value in
  let rec search index =
    index + needle_length <= value_length
    && (String.sub value index needle_length = needle || search (index + 1))
  in
  needle_length = 0 || search 0

let environment name =
  match Sys.getenv_opt name with
  | Some value when String.trim value <> "" -> Some value
  | Some _ | None -> None

let compiler () =
  Option.value (environment "PRISMEL_SDL3_CLANG") ~default:"clang"

let absolute path = Unix.realpath path

let require_file path description =
  if not (Sys.file_exists path) || Sys.is_directory path then
    fail "%s not found: %s" description path

let pkg_config_variable package variable =
  command_text "pkg-config" [ "--variable=" ^ variable; package ]
  |> String.trim

let pkg_config_flags package =
  let config = C.create "sdl3-generator" in
  match C.Pkg_config.get config with
  | None -> fail "pkg-config is unavailable"
  | Some pkg_config ->
      (match C.Pkg_config.query pkg_config ~package with
       | Some flags -> flags.cflags
       | None -> fail "pkg-config package %S is unavailable" package)

let core_discovery () =
  let include_root, cflags =
    match environment "PRISMEL_SDL3_INCLUDE_DIR" with
    | Some directory -> absolute directory, [ "-I" ^ absolute directory ]
    | None ->
        let directory = pkg_config_variable "sdl3" "includedir" |> absolute in
        directory, pkg_config_flags "sdl3"
  in
  let library_root =
    match environment "PRISMEL_SDL3_LIB_DIR" with
    | Some directory -> absolute directory
    | None -> pkg_config_variable "sdl3" "libdir" |> absolute
  in
  require_file (Filename.concat include_root "SDL3/SDL.h") "SDL3 header";
  { include_root; library_root = Some library_root; cflags }

let extension_discovery spec =
  let include_root, cflags =
    match environment spec.Spec.include_environment with
    | Some directory -> absolute directory, [ "-I" ^ absolute directory ]
    | None ->
        let directory =
          pkg_config_variable spec.package "includedir" |> absolute
        in
        directory, pkg_config_flags spec.package
  in
  require_file (Filename.concat include_root spec.include_file)
    "SDL3 extension header";
  { include_root; library_root = None; cflags }

let parse_macro_line prefixes line =
  let marker = "#define " in
  if not (has_prefix ~prefix:marker line) then None
  else
    let rest = String.sub line (String.length marker)
        (String.length line - String.length marker) in
    let rec name_end index =
      if index = String.length rest then index
      else
        match rest.[index] with
        | ' ' | '\t' -> index
        | _ -> name_end (index + 1)
    in
    let index = name_end 0 in
    let name = String.sub rest 0 index in
    if not (List.exists (fun prefix -> has_prefix ~prefix name) prefixes) then
      None
    else
      let value =
        String.sub rest index (String.length rest - index) |> String.trim
      in
      Some (name, value)

let macro_map clang cflags include_file prefixes =
  let output =
    command_text clang
      (cflags
       @ [ "-x"; "c"; "-dM"; "-E"; "-include"; include_file; "/dev/null" ])
  in
  let macros = Hashtbl.create 512 in
  String.split_on_char '\n' output
  |> List.iter (fun line ->
    match parse_macro_line prefixes line with
    | Some (name, value) -> Hashtbl.replace macros name value
    | None -> ());
  macros

let macro_value macros name =
  match Hashtbl.find_opt macros name with
  | Some value -> value
  | None -> fail "version macro %s is missing" name

let parse_version_part name value =
  match int_of_string_opt value with
  | Some value -> value
  | None -> fail "version macro %s is malformed: %S" name value

let version_of_macros macros (major_name, minor_name, patch_name) : version =
  ( parse_version_part major_name (macro_value macros major_name)
  , parse_version_part minor_name (macro_value macros minor_name)
  , parse_version_part patch_name (macro_value macros patch_name) )

let stable (_, minor, patch) = minor mod 2 = 0 && patch mod 2 = 0

let headers include_root header_directory =
  let root = Filename.concat include_root header_directory in
  let names =
    Sys.readdir root |> Array.to_list
    |> List.filter (fun name -> Filename.check_suffix name ".h")
    |> List.sort String.compare
  in
  let aggregate = Buffer.create 65536 in
  let entries =
    List.map
      (fun name ->
        let relative = header_directory ^ "/" ^ name in
        let contents = read_file (Filename.concat root name) in
        Buffer.add_string aggregate relative;
        Buffer.add_char aggregate '\000';
        Buffer.add_string aggregate contents;
        Buffer.add_char aggregate '\000';
        `Assoc
          [ "path", `String relative
          ; "sha256", `String (sha256 contents)
          ])
      names
  in
  entries, sha256 (Buffer.contents aggregate)

let field_names node =
  member_list "inner" node
  |> List.filter_map (fun child ->
    match member_string "kind" child, member_string "name" child with
    | Some "FieldDecl", Some name -> Some (`String name)
    | _ -> None)

let enum_constants node =
  member_list "inner" node
  |> List.filter_map (fun child ->
    match member_string "kind" child, member_string "name" child with
    | Some "EnumConstantDecl", Some name -> Some (`String name)
    | _ -> None)

let source_file node =
  Option.bind (member "loc" node) (member_string "file")

let type_qualification node =
  match Option.bind (member "type" node) (member_string "qualType") with
  | Some value -> value
  | None -> "unknown"

let inventory_groups ~clang ~arguments ~symbol_prefix ~header_directory
    ~safe_functions ~core_source_filter =
  let ast = command_text clang arguments |> Yojson.Safe.from_string in
  let safe name = List.assoc_opt name safe_functions in
  let functions = Hashtbl.create 2048 in
  let records = Hashtbl.create 512 in
  let enums = Hashtbl.create 512 in
  let typedefs = Hashtbl.create 2048 in
  let rec visit node =
    member_list "inner" node |> List.rev |> List.iter visit;
    match member_string "kind" node, member_string "name" node with
    | Some kind, Some name when has_prefix ~prefix:symbol_prefix name ->
        let source = source_file node in
        let allowed_source =
          match core_source_filter, source with
          | true, Some source -> contains ~needle:"/SDL3/" source
          | true, None | false, _ -> true
        in
        if allowed_source then begin
          let classification =
            if Option.is_some (safe name) then "safe" else "raw-only"
          in
          let header =
            match source with
            | Some source -> header_directory ^ "/" ^ Filename.basename source
            | None -> header_directory ^ "/<clang-elided-source>"
          in
          let base =
            [ "name", `String name
            ; "header", `String header
            ; "classification", `String classification
            ]
          in
          let replace table fields =
            Hashtbl.replace table name
              { name; classification; json = `Assoc (base @ fields) }
          in
          match kind with
          | "FunctionDecl" ->
              replace functions
                [ "signature", `String (type_qualification node)
                ; ( "thread"
                  , `String
                      (Option.value (safe name)
                         ~default:"raw-only-not-reviewed") )
                ]
          | "RecordDecl" | "UnionDecl" ->
              let record_kind =
                match member_string "tagUsed" node with
                | Some "union" -> "union"
                | Some _ | None -> "struct"
              in
              replace records
                [ "kind", `String record_kind
                ; "fields", `List (field_names node)
                ]
          | "EnumDecl" ->
              replace enums [ "constants", `List (enum_constants node) ]
          | "TypedefDecl" ->
              replace typedefs
                [ "underlying", `String (type_qualification node) ]
          | _ -> ()
        end
    | Some _, Some _ | Some _, None | None, _ -> ()
  in
  visit ast;
  let sorted table =
    Hashtbl.to_seq_values table |> List.of_seq
    |> List.sort (fun left right -> String.compare left.name right.name)
  in
  { functions = sorted functions
  ; records = sorted records
  ; enums = sorted enums
  ; typedefs = sorted typedefs
  }

let group_items groups =
  [ groups.functions; groups.records; groups.enums; groups.typedefs ]

let group_json items = `List (List.map (fun item -> item.json) items)

let classification_counts groups macro_count =
  List.map
    (fun classification ->
      let item_count =
        group_items groups |> List.concat
        |> List.fold_left
             (fun count item ->
               if item.classification = classification then count + 1 else count)
             0
      in
      ( classification
      , item_count + if classification = "raw-only" then macro_count else 0 ))
    classifications

let counts_json counts =
  `Assoc (List.map (fun (name, count) -> name, `Int count) counts)

let macros_json macros =
  Hashtbl.to_seq_keys macros |> List.of_seq |> List.sort String.compare
  |> List.map (fun name ->
    `Assoc
      [ "name", `String name
      ; "value", `String (Hashtbl.find macros name)
      ; "classification", `String "raw-only"
      ])
  |> fun values -> `List values

let header_version_json (major, minor, patch) =
  `Assoc [ "major", `Int major; "minor", `Int minor; "patch", `Int patch ]

let check_safe_functions safe_functions groups subject =
  let inventoried = Hashtbl.create (List.length groups.functions) in
  List.iter (fun item -> Hashtbl.replace inventoried item.name ()) groups.functions;
  let missing =
    List.filter_map
      (fun (name, _) ->
        if Hashtbl.mem inventoried name then None else Some name)
      safe_functions
    |> List.sort_uniq String.compare
  in
  if missing <> [] then
    fail "safe %s functions missing from Clang inventory: %s" subject
      (String.concat ", " missing)

let compiler_facts clang =
  ( command_text clang [ "--version" ] |> first_line
  , command_text clang [ "-dumpmachine" ] |> String.trim )

let layout_probe_source () =
  let output = Buffer.create 16384 in
  Buffer.add_string output
    "#include <SDL3/SDL.h>\n#include <stddef.h>\n#include <stdint.h>\n\
     #include <stdio.h>\nint main(void) {\n  printf(\"{\\\"types\\\":{\");\n";
  List.iteri
    (fun type_index (type_name, fields) ->
      let prefix = if type_index = 0 then "" else "," in
      Printf.bprintf output
        "  printf(\"%s\\\"%s\\\":{\\\"size\\\":%%zu,\\\"alignment\\\":%%zu,\
         \\\"offsets\\\":{\", sizeof(%s), _Alignof(%s));\n"
        prefix type_name type_name type_name;
      List.iteri
        (fun field_index field ->
          let field_prefix = if field_index = 0 then "" else "," in
          Printf.bprintf output
            "  printf(\"%s\\\"%s\\\":%%zu\", offsetof(%s, %s));\n"
            field_prefix field type_name field)
        fields;
      Buffer.add_string output "  printf(\"}}\");\n")
    Spec.layout_fields;
  Buffer.add_string output "  printf(\"},\\\"constants\\\":{\");\n";
  List.iteri
    (fun index name ->
      let prefix = if index = 0 then "" else "," in
      Printf.bprintf output
        "  printf(\"%s\\\"%s\\\":%%llu\", (unsigned long long)(%s));\n"
        prefix name name)
    Spec.abi_constants;
  Buffer.add_string output
    "  printf(\"},\\\"callback_calling_convention\\\":\\\"default-c\\\"}\\n\");\n\
     return 0;\n}\n";
  Buffer.contents output

let compile_layout_probe clang discovery =
  let library_root =
    match discovery.library_root with
    | Some value -> value
    | None -> fail "SDL3 core library directory is unavailable"
  in
  with_temp_directory "prismel-sdl3-layout-" (fun directory ->
    let source_path = Filename.concat directory "probe.c" in
    let executable = Filename.concat directory "probe" in
    write_file source_path (layout_probe_source ());
    ignore
      (command_text clang
         (discovery.cflags
          @ [ source_path; "-L" ^ library_root; "-lSDL3"; "-o"; executable ]));
    command_text executable [] |> Yojson.Safe.from_string)

let core_provenance version aggregate_hash clang_version target groups
    layout_hash =
  let major, minor, patch = version in
  let safe_count =
    List.fold_left
      (fun count item ->
        if item.classification = "safe" then count + 1 else count)
      0 groups.functions
  in
  Printf.sprintf
    "(* Generated by %s; do not edit. *)\n\
     type version = { major : int; minor : int; patch : int }\n\n\
     let generator_version = %s\n\
     let header_version = { major = %d; minor = %d; patch = %d }\n\
     let header_version_number = %d\n\
     let stable_headers = %b\n\
     let header_aggregate_sha256 = %s\n\
     let clang_version = %s\n\
     let target_triple = %s\n\
     let function_count = %d\n\
     let safe_function_count = %d\n\
     let layout_sha256 = %s\n"
    core_generator_version (json_quote core_generator_version) major minor patch
    ((major * 1_000_000) + (minor * 1_000) + patch)
    (stable version) (json_quote aggregate_hash) (json_quote clang_version)
    (json_quote target) (List.length groups.functions) safe_count
    (json_quote layout_hash)

let assoc_fields name json =
  match member name json with
  | Some (`Assoc fields) -> fields
  | Some value ->
      fail "expected %s to be an object, got %s" name
        (Yojson.Safe.to_string value)
  | None -> fail "missing JSON object %s" name

let core_abi_header layout version =
  let major, minor, patch = version in
  let output = Buffer.create 32768 in
  Buffer.add_string output
    "/* Generated ABI assertions; do not edit. */\n\
     #ifndef PRISMEL_SDL3_GENERATED_ABI_H\n\
     #define PRISMEL_SDL3_GENERATED_ABI_H\n\
     #include <SDL3/SDL.h>\n#include <stddef.h>\n";
  Printf.bprintf output
    "_Static_assert(SDL_MAJOR_VERSION == %d, \"SDL major header changed\");\n\
     _Static_assert(SDL_MINOR_VERSION == %d, \"SDL minor header changed\");\n\
     _Static_assert(SDL_MICRO_VERSION == %d, \"SDL patch header changed\");\n"
    major minor patch;
  assoc_fields "types" layout
  |> List.iter (fun (type_name, facts) ->
    let size =
      match member "size" facts with
      | Some value -> integer_text value
      | None -> fail "missing %s size" type_name
    in
    let alignment =
      match member "alignment" facts with
      | Some value -> integer_text value
      | None -> fail "missing %s alignment" type_name
    in
    Printf.bprintf output
      "_Static_assert(sizeof(%s) == %s, \"%s size changed\");\n" type_name
      size type_name;
    Printf.bprintf output
      "_Static_assert(_Alignof(%s) == %s, \"%s alignment changed\");\n"
      type_name alignment type_name;
    assoc_fields "offsets" facts
    |> List.iter (fun (field, offset) ->
      Printf.bprintf output
        "_Static_assert(offsetof(%s, %s) == %s, \"%s.%s offset changed\");\n"
        type_name field (integer_text offset) type_name field));
  assoc_fields "constants" layout
  |> List.iter (fun (name, value) ->
    Printf.bprintf output
      "_Static_assert((unsigned long long)(%s) == %sULL, \"%s changed\");\n"
      name (integer_text value) name);
  Buffer.add_string output "#endif\n";
  Buffer.contents output

let generate_core () =
  let clang = compiler () in
  let discovery = core_discovery () in
  let macros = macro_map clang discovery.cflags "SDL3/SDL.h" [ "SDL_" ] in
  let version =
    version_of_macros macros
      ("SDL_MAJOR_VERSION", "SDL_MINOR_VERSION", "SDL_MICRO_VERSION")
  in
  let header_entries, aggregate_hash = headers discovery.include_root "SDL3" in
  let groups =
    inventory_groups ~clang
      ~arguments:
        [ "-isystem"; discovery.include_root; "-x"; "c"; "-fsyntax-only"
        ; "-Xclang"; "-ast-dump=json"; "-include"; "SDL3/SDL.h"; "/dev/null"
        ]
      ~symbol_prefix:"SDL_" ~header_directory:"SDL3"
      ~safe_functions:Spec.core_safe_functions ~core_source_filter:true
  in
  check_safe_functions Spec.core_safe_functions groups "SDL3";
  let clang_version, target = compiler_facts clang in
  let counts = classification_counts groups (Hashtbl.length macros) in
  let inventory =
    `Assoc
      [ "schema", `Int 1
      ; "generator", `String core_generator_version
      ; "header_version", header_version_json version
      ; "stable_headers", `Bool (stable version)
      ; "header_aggregate_sha256", `String aggregate_hash
      ; "compiler", `String clang_version
      ; "target_triple", `String target
      ; "headers", `List header_entries
      ; "functions", group_json groups.functions
      ; "records", group_json groups.records
      ; "enums", group_json groups.enums
      ; "typedefs", group_json groups.typedefs
      ; "macros", macros_json macros
      ; "classification_counts", counts_json counts
      ]
  in
  let layout =
    match compile_layout_probe clang discovery with
    | `Assoc fields ->
        `Assoc
          (fields
           @ [ "schema", `Int 1
             ; "generator", `String core_generator_version
             ; "header_version", header_version_json version
             ; "header_aggregate_sha256", `String aggregate_hash
             ; "compiler", `String clang_version
             ; "target_triple", `String target
             ])
    | value ->
        fail "SDL3 layout probe returned %s instead of an object"
          (Yojson.Safe.to_string value)
  in
  let inventory_text = pretty_json inventory in
  let layout_text = pretty_json layout in
  let layout_hash = sha256 layout_text in
  { counts
  ; outputs =
      [ ( "generated_provenance.ml"
        , core_provenance version aggregate_hash clang_version target groups
            layout_hash )
      ; "generated_inventory.json", inventory_text
      ; "generated_layout.json", layout_text
      ; "generated_abi.h", core_abi_header layout version
      ]
  }

let extension_provenance version aggregate_hash clang_version target groups =
  let major, minor, patch = version in
  let safe_count =
    List.fold_left
      (fun count item ->
        if item.classification = "safe" then count + 1 else count)
      0 groups.functions
  in
  Printf.sprintf
    "(* Generated by %s; do not edit. *)\n\
     type version = { major : int; minor : int; patch : int }\n\n\
     let generator_version = %s\n\
     let header_version = { major = %d; minor = %d; patch = %d }\n\
     let stable_headers = %b\n\
     let header_sha256 = %s\n\
     let clang_version = %s\n\
     let target_triple = %s\n\
     let function_count = %d\n\
     let safe_function_count = %d\n"
    extension_generator_version (json_quote extension_generator_version) major
    minor patch (stable version) (json_quote aggregate_hash)
    (json_quote clang_version) (json_quote target)
    (List.length groups.functions) safe_count

let image_abi_header spec (major, minor, patch) =
  Printf.sprintf
    {|/* Generated by %s; do not edit. */
#ifndef PRISMEL_SDL3_IMAGE_GENERATED_ABI_H
#define PRISMEL_SDL3_IMAGE_GENERATED_ABI_H
#include <%s>
#include <SDL3/SDL.h>
_Static_assert(SDL_IMAGE_MAJOR_VERSION == %d, "SDL3_image major changed");
_Static_assert(SDL_IMAGE_MINOR_VERSION == %d, "SDL3_image minor changed");
_Static_assert(SDL_IMAGE_MICRO_VERSION == %d, "SDL3_image patch changed");
typedef int (SDLCALL *prismel_img_version_fn)(void);
typedef SDL_Surface * (SDLCALL *prismel_img_load_fn)(const char *);
typedef SDL_Surface * (SDLCALL *prismel_img_load_io_fn)(SDL_IOStream *, bool);
typedef SDL_Surface * (SDLCALL *prismel_img_load_typed_io_fn)(SDL_IOStream *, bool, const char *);
_Static_assert(_Generic(&IMG_Version, prismel_img_version_fn: 1, default: 0),
  "IMG_Version signature/calling convention changed");
_Static_assert(_Generic(&IMG_Load, prismel_img_load_fn: 1, default: 0),
  "IMG_Load signature/calling convention changed");
_Static_assert(_Generic(&IMG_Load_IO, prismel_img_load_io_fn: 1, default: 0),
  "IMG_Load_IO signature/calling convention changed");
_Static_assert(_Generic(&IMG_LoadTyped_IO, prismel_img_load_typed_io_fn: 1, default: 0),
  "IMG_LoadTyped_IO signature/calling convention changed");
#endif
|}
    extension_generator_version spec.Spec.include_file major minor patch

let ttf_abi_header spec (major, minor, patch) =
  Printf.sprintf
    {|/* Generated by %s; do not edit. */
#ifndef PRISMEL_SDL3_TTF_GENERATED_ABI_H
#define PRISMEL_SDL3_TTF_GENERATED_ABI_H
#include <%s>
#include <SDL3/SDL.h>
_Static_assert(SDL_TTF_MAJOR_VERSION == %d, "SDL3_ttf major changed");
_Static_assert(SDL_TTF_MINOR_VERSION == %d, "SDL3_ttf minor changed");
_Static_assert(SDL_TTF_MICRO_VERSION == %d, "SDL3_ttf patch changed");
typedef int (SDLCALL *prismel_ttf_version_fn)(void);
typedef bool (SDLCALL *prismel_ttf_init_fn)(void);
typedef void (SDLCALL *prismel_ttf_quit_fn)(void);
typedef TTF_Font * (SDLCALL *prismel_ttf_open_font_fn)(const char *, float);
typedef void (SDLCALL *prismel_ttf_close_font_fn)(TTF_Font *);
typedef bool (SDLCALL *prismel_ttf_size_fn)(TTF_Font *, const char *, size_t, int *, int *);
typedef SDL_Surface * (SDLCALL *prismel_ttf_render_fn)(TTF_Font *, const char *, size_t, SDL_Color);
_Static_assert(_Generic(&TTF_Version, prismel_ttf_version_fn: 1, default: 0),
  "TTF_Version signature/calling convention changed");
_Static_assert(_Generic(&TTF_Init, prismel_ttf_init_fn: 1, default: 0),
  "TTF_Init signature/calling convention changed");
_Static_assert(_Generic(&TTF_Quit, prismel_ttf_quit_fn: 1, default: 0),
  "TTF_Quit signature/calling convention changed");
_Static_assert(_Generic(&TTF_OpenFont, prismel_ttf_open_font_fn: 1, default: 0),
  "TTF_OpenFont signature/calling convention changed");
_Static_assert(_Generic(&TTF_CloseFont, prismel_ttf_close_font_fn: 1, default: 0),
  "TTF_CloseFont signature/calling convention changed");
_Static_assert(_Generic(&TTF_GetStringSize, prismel_ttf_size_fn: 1, default: 0),
  "TTF_GetStringSize signature/calling convention changed");
_Static_assert(_Generic(&TTF_RenderText_Blended, prismel_ttf_render_fn: 1, default: 0),
  "TTF_RenderText_Blended signature/calling convention changed");
#endif
|}
    extension_generator_version spec.Spec.include_file major minor patch

let mixer_abi_header spec (major, minor, patch) =
  Printf.sprintf
    {|/* Generated by %s; do not edit. */
#ifndef PRISMEL_SDL3_MIXER_GENERATED_ABI_H
#define PRISMEL_SDL3_MIXER_GENERATED_ABI_H
#include <%s>
#include <SDL3/SDL.h>
_Static_assert(SDL_MIXER_MAJOR_VERSION == %d, "SDL3_mixer major changed");
_Static_assert(SDL_MIXER_MINOR_VERSION == %d, "SDL3_mixer minor changed");
_Static_assert(SDL_MIXER_MICRO_VERSION == %d, "SDL3_mixer patch changed");
typedef int (SDLCALL *prismel_mix_version_fn)(void);
typedef bool (SDLCALL *prismel_mix_init_fn)(void);
typedef void (SDLCALL *prismel_mix_quit_fn)(void);
typedef MIX_Mixer * (SDLCALL *prismel_mix_create_device_fn)(SDL_AudioDeviceID, const SDL_AudioSpec *);
typedef MIX_Mixer * (SDLCALL *prismel_mix_create_fn)(const SDL_AudioSpec *);
typedef MIX_Audio * (SDLCALL *prismel_mix_load_fn)(MIX_Mixer *, const char *, bool);
typedef MIX_Track * (SDLCALL *prismel_mix_create_track_fn)(MIX_Mixer *);
typedef bool (SDLCALL *prismel_mix_play_track_fn)(MIX_Track *, SDL_PropertiesID);
typedef int (SDLCALL *prismel_mix_generate_fn)(MIX_Mixer *, void *, int);
_Static_assert(_Generic(&MIX_Version, prismel_mix_version_fn: 1, default: 0),
  "MIX_Version signature/calling convention changed");
_Static_assert(_Generic(&MIX_Init, prismel_mix_init_fn: 1, default: 0),
  "MIX_Init signature/calling convention changed");
_Static_assert(_Generic(&MIX_Quit, prismel_mix_quit_fn: 1, default: 0),
  "MIX_Quit signature/calling convention changed");
_Static_assert(_Generic(&MIX_CreateMixerDevice, prismel_mix_create_device_fn: 1, default: 0),
  "MIX_CreateMixerDevice signature/calling convention changed");
_Static_assert(_Generic(&MIX_CreateMixer, prismel_mix_create_fn: 1, default: 0),
  "MIX_CreateMixer signature/calling convention changed");
_Static_assert(_Generic(&MIX_LoadAudio, prismel_mix_load_fn: 1, default: 0),
  "MIX_LoadAudio signature/calling convention changed");
_Static_assert(_Generic(&MIX_CreateTrack, prismel_mix_create_track_fn: 1, default: 0),
  "MIX_CreateTrack signature/calling convention changed");
_Static_assert(_Generic(&MIX_PlayTrack, prismel_mix_play_track_fn: 1, default: 0),
  "MIX_PlayTrack signature/calling convention changed");
_Static_assert(_Generic(&MIX_Generate, prismel_mix_generate_fn: 1, default: 0),
  "MIX_Generate signature/calling convention changed");
#endif
|}
    extension_generator_version spec.Spec.include_file major minor patch

let extension_abi_header spec version =
  match spec.Spec.extension with
  | Spec.Image -> image_abi_header spec version
  | Spec.Ttf -> ttf_abi_header spec version
  | Spec.Mixer -> mixer_abi_header spec version
  | Spec.Core -> fail "core SDL3 does not use an extension ABI header"

let generate_extension spec =
  let clang = compiler () in
  let discovery = extension_discovery spec in
  let macros =
    macro_map clang discovery.cflags spec.Spec.include_file spec.macro_prefixes
  in
  let version = version_of_macros macros spec.version_macros in
  let header_entries, aggregate_hash =
    headers discovery.include_root spec.header_directory
  in
  let groups =
    inventory_groups ~clang
      ~arguments:
        (discovery.cflags
         @ [ "-x"; "c"; "-fsyntax-only"; "-Xclang"; "-ast-dump=json"
           ; "-include"; spec.include_file; "/dev/null"
           ])
      ~symbol_prefix:spec.symbol_prefix
      ~header_directory:spec.header_directory
      ~safe_functions:spec.safe_functions ~core_source_filter:false
  in
  check_safe_functions spec.safe_functions groups ("SDL3 " ^ spec.name);
  let clang_version, target = compiler_facts clang in
  let counts = classification_counts groups (Hashtbl.length macros) in
  let inventory =
    `Assoc
      [ "schema", `Int 1
      ; "generator", `String extension_generator_version
      ; "extension", `String spec.name
      ; "header_version", header_version_json version
      ; "stable_headers", `Bool (stable version)
      ; "header_sha256", `String aggregate_hash
      ; "compiler", `String clang_version
      ; "target_triple", `String target
      ; "headers", `List header_entries
      ; "functions", group_json groups.functions
      ; "records", group_json groups.records
      ; "enums", group_json groups.enums
      ; "typedefs", group_json groups.typedefs
      ; "macros", macros_json macros
      ; "classification_counts", counts_json counts
      ]
  in
  { counts
  ; outputs =
      [ ( "generated_provenance.ml"
        , extension_provenance version aggregate_hash clang_version target
            groups )
      ; "generated_inventory.json", pretty_json inventory
      ; "generated_abi.h", extension_abi_header spec version
      ]
  }

type selection =
  | Core
  | Extension of Spec.extension_spec

type mode =
  | Write
  | Check

type arguments =
  { root : string
  ; selection : selection
  ; mode : mode
  }

let usage () =
  fail
    "usage: %s --root <repository> --extension <core|image|ttf|mixer> \
     <--write|--check>"
    Sys.argv.(0)

let parse_arguments () =
  let root = ref (Sys.getcwd ()) in
  let selection = ref None in
  let mode = ref None in
  let index = ref 1 in
  while !index < Array.length Sys.argv do
    match Sys.argv.(!index) with
    | "--root" when !index + 1 < Array.length Sys.argv ->
        root := Sys.argv.(!index + 1);
        index := !index + 2
    | "--extension" when !index + 1 < Array.length Sys.argv ->
        let value = Sys.argv.(!index + 1) in
        selection :=
          Some
            (if value = "core" then Core
             else Extension (Spec.extension value));
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
  match !selection, !mode with
  | Some selection, Some mode ->
      { root = absolute !root; selection; mode }
  | Some _, None | None, Some _ | None, None -> usage ()

let rec ensure_directory path =
  if Sys.file_exists path then begin
    if not (Sys.is_directory path) then fail "%s is not a directory" path
  end
  else begin
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755
  end

let output_directory root = function
  | Core -> Filename.concat root "lib/sdl3"
  | Extension spec -> Filename.concat root ("lib/" ^ spec.Spec.directory)

let selection_name = function
  | Core -> "SDL3"
  | Extension spec -> "SDL3 " ^ spec.Spec.name

let format_counts counts =
  counts
  |> List.map (fun (name, count) -> Printf.sprintf "%s=%d" name count)
  |> String.concat ", "

let execute arguments =
  let generated =
    match arguments.selection with
    | Core -> generate_core ()
    | Extension spec -> generate_extension spec
  in
  let directory = output_directory arguments.root arguments.selection in
  match arguments.mode with
  | Write ->
      ensure_directory directory;
      List.iter
        (fun (name, contents) ->
          write_file (Filename.concat directory name) contents)
        generated.outputs;
      Printf.printf "generated %s inventory with %s\n%!"
        (selection_name arguments.selection)
        (format_counts generated.counts)
  | Check ->
      let failures =
        List.filter_map
          (fun (name, expected) ->
            let path = Filename.concat directory name in
            if not (Sys.file_exists path) then Some ("missing " ^ path)
            else if read_file path <> expected then Some ("stale " ^ path)
            else None)
          generated.outputs
      in
      if failures <> [] then fail "%s" (String.concat "; " failures);
      Printf.printf "%s generated inventory is current\n%!"
        (selection_name arguments.selection)

let () =
  try parse_arguments () |> execute with
  | Error message | Sys_error message | Yojson.Json_error message ->
      prerr_endline message;
      exit 1
  | Unix.Unix_error (error, function_name, argument) ->
      Printf.eprintf "%s(%s): %s\n%!" function_name argument
        (Unix.error_message error);
      exit 1
