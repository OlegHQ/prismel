open Registry

let fail format = Printf.ksprintf failwith format

let c_name name = "caml_prismel_metal_gen_" ^ name

let validate_feature_map mappings =
  let seen = Hashtbl.create 32 in
  List.iter
    (fun (feature, symbols) ->
      (match feature with
       | Ogpu_core.Caps.Unknown _ ->
           fail "unknown OGPU feature map entry: %s" (feature_name feature)
       | _ -> ());
      if Hashtbl.mem seen feature then
        fail "duplicate OGPU feature map entry: %s" (feature_name feature);
      Hashtbl.add seen feature ();
      if symbols = [] && feature <> Ogpu_core.Caps.Timeline_fence then
        fail "empty Metal symbol map entry: %s" (feature_name feature);
      List.iter
        (function
          | Protocol name | Class name when name <> "" -> ()
          | _ -> fail "empty Metal SDK type in feature map")
        symbols)
    mappings;
  if List.length mappings <> 23 then fail "OGPU feature map is incomplete";
  if List.assoc_opt Ogpu_core.Caps.Timeline_fence mappings <> Some [] then
    fail "unsupported timeline fence has a Metal symbol"

let validate entries =
  validate_feature_map feature_map;
  let ocaml = Hashtbl.create 32
  and native = Hashtbl.create 32
  and selectors = Hashtbl.create 32
  and sdk_symbols = Hashtbl.create 256 in
  let check_feature name = function
    | Ogpu_core.Caps.Unknown _ -> fail "unknown OGPU feature for %s" name
    | feature when not (List.mem_assoc feature feature_map) ->
        fail "unmapped OGPU feature for %s" name
    | _ -> ()
  in
  List.iter
    (function
      | Enum { sdk; ocaml = name; cases; feature } ->
          check_feature name feature;
          if Hashtbl.mem ocaml name then fail "duplicate OCaml binding %s" name;
          Hashtbl.add ocaml name ();
          if cases = [] then fail "empty enum %s" sdk;
          List.iter
            (fun (case_name, symbol, _, _) ->
              if Hashtbl.mem ocaml case_name then
                fail "duplicate OCaml binding %s" case_name;
              Hashtbl.add ocaml case_name ();
              if Hashtbl.mem sdk_symbols symbol then
                fail "duplicate SDK enum case %s" symbol;
              Hashtbl.add sdk_symbols symbol ())
            cases
      | Record { sdk; ocaml = name; fields; feature } ->
          check_feature name feature;
          if sdk = "" || fields = [] then fail "empty Metal record %s" name;
          if Hashtbl.mem ocaml name then fail "duplicate OCaml binding %s" name;
          Hashtbl.add ocaml name ();
          let seen_fields = Hashtbl.create 8 in
          List.iter
            (fun (field, scalar) ->
              if field = "" || Hashtbl.mem seen_fields field then
                fail "duplicate or empty record field %s.%s" name field;
              Hashtbl.add seen_fields field ();
              match scalar with
              | Bool | Int | Nsuint | Nsint | Float | Double -> ())
            fields
      | Selector { ocaml = name; recv; sel; args; ret; feature; since = _ } ->
          if Hashtbl.mem ocaml name then fail "duplicate OCaml binding %s" name;
          Hashtbl.add ocaml name ();
          let symbol = c_name name in
          if Hashtbl.mem native symbol then fail "duplicate C binding %s" symbol;
          Hashtbl.add native symbol ();
          if Hashtbl.mem selectors (recv, sel) then
            fail "duplicate Metal selector %s.%s" recv sel;
          Hashtbl.add selectors (recv, sel) ();
          check_feature name feature;
          let getter =
            List.mem recv [ "MTLDevice"; "MTLComputePipelineState"; "MTLRenderPipelineState" ]
            && args = [] && List.mem ret [ Some Nsuint; Some Bool ]
          in
          if not getter then
            fail "selector %s needs a generator implementation" name;
          if sel = "" then fail "empty Metal selector for %s" name
      )
    entries

let contains_token source token =
  let length = String.length token in
  let rec search offset =
    match String.index_from_opt source offset token.[0] with
    | None -> false
    | Some index ->
        if
          index + length <= String.length source
          && String.sub source index length = token
          && (index + length = String.length source
             || not
                  (match source.[index + length] with
                   | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
                   | _ -> false))
        then true
        else search (index + 1)
  in
  search 0

let read path =
  let input = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let used_bindings source =
  let lexbuf = Lexing.from_string source in
  let tree = Parse.implementation lexbuf in
  let used = Hashtbl.create 32 in
  let expr iterator expression =
    (match expression.Parsetree.pexp_desc with
     | Pexp_apply
         ( { pexp_desc =
               Pexp_ident
                 { txt =
                     Longident.Ldot
                       (Longident.Ldot (Longident.Lident "Metal_raw", "Registry"), name)
                 ; _ }
           ; _ },
           _ ) ->
         Hashtbl.replace used name ()
     | _ -> ());
    Ast_iterator.default_iterator.expr iterator expression
  in
  let iterator = { Ast_iterator.default_iterator with expr } in
  iterator.structure iterator tree;
  used

let used_enum_modules source =
  let tree = Parse.implementation (Lexing.from_string source) in
  let used = Hashtbl.create 16 in
  let rec visit_path = function
    | Longident.Lident _ -> ()
    | Longident.Ldot (prefix, name) ->
        if String.starts_with ~prefix:"Mtl_" name then
          Hashtbl.replace used name ();
        visit_path prefix
    | Longident.Lapply (left, right) ->
        visit_path left;
        visit_path right
  in
  let expr iterator expression =
    (match expression.Parsetree.pexp_desc with
     | Pexp_ident identifier -> visit_path identifier.txt
     | _ -> ());
    Ast_iterator.default_iterator.expr iterator expression
  in
  let module_expr iterator expression =
    (match expression.Parsetree.pmod_desc with
     | Pmod_ident identifier -> visit_path identifier.txt
     | _ -> ());
    Ast_iterator.default_iterator.module_expr iterator expression
  in
  let typ iterator core_type =
    (match core_type.Parsetree.ptyp_desc with
     | Ptyp_constr (identifier, _) -> visit_path identifier.txt
     | _ -> ());
    Ast_iterator.default_iterator.typ iterator core_type
  in
  let iterator = { Ast_iterator.default_iterator with expr; module_expr; typ } in
  iterator.structure iterator tree;
  used

let write path body =
  let output = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr output)
    (fun () -> output_string output body)

let emit_enums_ml buffer entries =
  Buffer.add_string buffer "module Enum = struct\n";
  List.iter
    (function
      | Enum { ocaml; cases; _ } ->
          Printf.bprintf buffer "  module %s = struct\n    type t = int64\n" ocaml;
          List.iter
            (fun (name, _, bits, _) ->
              Printf.bprintf buffer "    let %s : t = 0x%016LxL\n" name bits)
            cases;
          Buffer.add_string buffer
            "    let to_int64 (value : t) = value\n    let of_int64 bits = match bits with\n";
          let unique =
            List.sort_uniq Int64.compare
              (List.map (fun (_, _, bits, _) -> bits) cases)
          in
          List.iter
            (fun bits -> Printf.bprintf buffer "    | 0x%016LxL -> Some bits\n" bits)
            unique;
          Buffer.add_string buffer "    | _ -> None\n  end\n"
      | Selector _ | Record _ -> ())
    entries;
  Buffer.add_string buffer "end\n"

let emit_enums_mli buffer entries =
  Buffer.add_string buffer "module Enum : sig\n";
  List.iter
    (function
      | Enum { ocaml; cases; _ } ->
          Printf.bprintf buffer "  module %s : sig\n    type t = private int64\n" ocaml;
          List.iter
            (fun (name, _, _, _) ->
              Printf.bprintf buffer "    val %s : t\n" name)
            cases;
          Buffer.add_string buffer
            "    val to_int64 : t -> int64\n    val of_int64 : int64 -> t option\n  end\n"
      | Selector _ | Record _ -> ())
    entries;
  Buffer.add_string buffer "end\n"

let record_field_types = function
  | Bool -> "bool", "BOOL"
  | Int -> "int", "int"
  | Nsuint -> "int64", "NSUInteger"
  | Nsint -> "int64", "NSInteger"
  | Float -> "float", "float"
  | Double -> "float", "double"

let emit_records ~signature buffer entries =
  Buffer.add_string buffer (if signature then "module Record : sig\n" else "module Record = struct\n");
  List.iter
    (function
      | Record { ocaml; fields; _ } ->
          Printf.bprintf buffer "  module %s %s\n    type t = {\n"
            ocaml (if signature then ": sig" else "= struct");
          List.iter
            (fun (field, scalar) ->
              let ocaml_type, _ = record_field_types scalar in
              Printf.bprintf buffer "      %s : %s;\n" field ocaml_type)
            fields;
          Buffer.add_string buffer "    }\n  end\n"
      | Enum _ | Selector _ -> ())
    entries;
  Buffer.add_string buffer "end\n"

let emit_ml entries =
  let buffer = Buffer.create 512 in
  Buffer.add_string buffer
    "(* Generated from lib/metal/gen/registry.ml. Do not edit. *)\n";
  emit_enums_ml buffer entries;
  emit_records ~signature:false buffer entries;
  Buffer.add_string buffer "module Make (Types : sig type handle end) = struct\n";
  List.iter
    (function
      | Selector { ocaml; ret; args; _ } ->
          Printf.bprintf buffer
            "  external %s : Types.handle%s -> (%s, string) result = %S\n"
            ocaml (String.concat "" (List.map (fun _ -> " -> int") args))
            (if ret = None then "unit" else if ret = Some Bool then "bool" else "int64")
            (c_name ocaml)
      | Enum _ | Record _ -> ())
    entries;
  Buffer.add_string buffer "end\n";
  Buffer.contents buffer

let emit_mli entries =
  let buffer = Buffer.create 512 in
  Buffer.add_string buffer
    "(* Generated from lib/metal/gen/registry.ml. Do not edit. *)\n";
  emit_enums_mli buffer entries;
  emit_records ~signature:true buffer entries;
  Buffer.add_string buffer "module Make (Types : sig type handle end) : sig\n";
  List.iter
    (function
      | Selector { ocaml; ret; args; _ } ->
          Printf.bprintf buffer
            "  external %s : Types.handle%s -> (%s, string) result = %S\n"
            ocaml (String.concat "" (List.map (fun _ -> " -> int") args))
            (if ret = None then "unit" else if ret = Some Bool then "bool" else "int64")
            (c_name ocaml)
      | Enum _ | Record _ -> ())
    entries;
  Buffer.add_string buffer "end\n";
  Buffer.contents buffer

let emit_c entries =
  let buffer = Buffer.create 1024 in
  Buffer.add_string buffer "/* Generated from lib/metal/gen/registry.ml. Do not edit. */\n";
  List.iter
    (function
      | Enum { cases; _ } ->
          List.iter
            (fun (_, symbol, bits, (major, minor, _)) ->
              Printf.bprintf buffer
                "#if __MAC_OS_X_VERSION_MAX_ALLOWED >= %d\n#pragma clang diagnostic push\n#pragma clang diagnostic ignored \"-Wunguarded-availability-new\"\n#pragma clang diagnostic ignored \"-Wdeprecated-declarations\"\nstatic_assert(static_cast<unsigned long long>(%s) == 0x%016LxULL);\n#pragma clang diagnostic pop\n#endif\n"
                ((major * 10000) + (minor * 100)) symbol bits)
            cases
      | Record { sdk; fields; _ } ->
          Printf.bprintf buffer "static_assert(std::is_standard_layout_v<%s>);\n" sdk;
          List.iter
            (fun (field, scalar) ->
              let _, native_type = record_field_types scalar in
              Printf.bprintf buffer
                "static_assert(std::is_same_v<decltype(%s{}.%s), %s>);\n"
                sdk field native_type)
            fields
      | Selector { ocaml; recv; sel; since; ret; _ } ->
          let kind =
            match recv with
            | "MTLDevice" -> "Device"
            | "MTLComputePipelineState" -> "Compute_pipeline"
            | "MTLRenderPipelineState" -> "Render_pipeline"
            | _ -> assert false
          in
          let guard =
            match since with
            | None -> ""
            | Some (major, minor) ->
                Printf.sprintf "    if (@available(macOS %d.%d, *)) {\n" major minor
          in
          let close_guard = if since = None then "" else "    }\n" in
          let unavailable =
            match since with
            | None -> ""
            | Some (major, minor) ->
                Printf.sprintf
                  "    CAMLreturn(result_error_text(\"Metal selector %s requires macOS %d.%d\"));\n"
                  sel major minor
          in
          let native_type, copy =
            if ret = Some Bool then
              "BOOL", "copied_result = Val_bool(native_result);\n"
            else
              "NSUInteger",
              "if (native_result > static_cast<NSUInteger>(INT64_MAX))\n"
              ^ "          CAMLreturn(result_error_text(\"Metal returned a value outside signed 64-bit range\"));\n"
              ^ "        copied_result = caml_copy_int64(static_cast<std::int64_t>(native_result));\n"
          in
          Printf.bprintf buffer
            "extern \"C\" CAMLprim value %s(value raw_handle) {\n  CAMLparam1(raw_handle);\n  CAMLlocal2(result, copied_result);\n  @autoreleasepool {\n%s      @try {\n        id<%s> object = object_of_handle(raw_handle, Handle_kind::%s);\n        const %s native_result = [object %s];\n        %s        result = result_ok(copied_result);\n        CAMLreturn(result);\n      } @catch (NSException *exception) {\n        CAMLreturn(result_error(exception.reason));\n      }\n%s%s  }\n}\n"
            (c_name ocaml) guard recv kind native_type sel copy close_guard unavailable)
    entries;
  Buffer.contents buffer

let emit_feature_checks () =
  let buffer = Buffer.create 1024 in
  Buffer.add_string buffer
    "/* Checked OGPU feature map from lib/metal/gen/registry.ml. */\n#pragma clang diagnostic push\n#pragma clang diagnostic ignored \"-Wunguarded-availability-new\"\n";
  List.iter
    (fun (_, symbols) ->
      List.iter
        (function
          | Protocol name ->
              Printf.bprintf buffer
                "static_assert(sizeof(id<%s>) == sizeof(void *));\n" name
          | Class name ->
              Printf.bprintf buffer
                "static_assert(sizeof(%s *) == sizeof(void *));\n" name)
        symbols)
    feature_map;
  Buffer.add_string buffer "#pragma clang diagnostic pop\n";
  Buffer.contents buffer

let self_test () =
  validate entries;
  (try
     validate_feature_map (List.hd feature_map :: feature_map);
     fail "duplicate feature map entry was accepted"
   with Failure message ->
     if not (String.starts_with ~prefix:"duplicate OGPU feature map entry" message) then
       fail "unexpected feature map error: %s" message);
  (try
     validate_feature_map
       ((Ogpu_core.Caps.Unknown "future", [ Protocol "MTLDevice" ]) :: List.tl feature_map);
     fail "unknown feature map entry was accepted"
   with Failure message ->
     if not (String.starts_with ~prefix:"unknown OGPU feature map entry" message) then
       fail "unexpected feature map error: %s" message);
  let checked_types = emit_feature_checks () in
  if not (contains_token checked_types "id<MTLFXSpatialScaler>")
     || not (contains_token checked_types "id<MTLResidencySet>")
  then fail "feature map lost SDK type checks";
  let record =
    Record
      { sdk = "MTLSize"
      ; ocaml = "Mtl_size"
      ; fields = [ "width", Nsuint; "height", Nsuint; "depth", Nsuint ]
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  in
  validate [ record ];
  if not (contains_token (emit_ml [ record ]) "module Mtl_size = struct")
     || not (contains_token (emit_c [ record ]) "decltype(MTLSize{}.width), NSUInteger")
  then fail "record generation lost its OCaml or SDK type check";
  (try
     validate (entries @ entries);
     fail "duplicate binding was accepted"
   with Failure message ->
     if not (String.starts_with ~prefix:"duplicate OCaml binding" message) then
       fail "unexpected duplicate error: %s" message);
  (match List.find_opt (function Selector _ -> true | _ -> false) entries with
   | Some (Selector selector) ->
       (try
          validate
            (Selector { selector with ocaml = "duplicate_selector" } :: entries);
          fail "duplicate Metal selector was accepted"
        with Failure message ->
          if not (String.starts_with ~prefix:"duplicate Metal selector" message)
          then fail "unexpected selector error: %s" message)
   | _ -> fail "registry self-test has no selector");
  let native = emit_c entries in
  if
    not (contains_token native "[object maxThreadgroupMemoryLength]")
    || not (contains_token native "@available(macOS 10.13, *)")
    || not (contains_token native "const BOOL native_result = [object supportIndirectCommandBuffers]")
    || not (contains_token native "Val_bool(native_result)")
  then fail "generated selector lost its typed call or availability guard";
  let name = "device_max_threadgroup_memory_length" in
  let source =
    "(* Metal_raw.Registry." ^ name ^ " *)\n"
    ^ "let call handle = Metal_raw.Registry." ^ name ^ " handle\n"
  in
  if not (Hashtbl.mem (used_bindings source) name) then
    fail "safe-layer call was not found";
  if
    Hashtbl.mem
      (used_bindings ("(* Metal_raw.Registry." ^ name ^ " *)\nlet unused = ()\n"))
      name
  then fail "comment was mistaken for a safe-layer call";
  let source = "(* Enum.Mtl_data_type *)\nmodule Data_type = Metal_gen.Enum.Mtl_data_type\n" in
  if not (Hashtbl.mem (used_enum_modules source) "Mtl_data_type") then
    fail "enum alias was not found";
  if Hashtbl.mem (used_enum_modules "(* Enum.Mtl_data_type *)\nlet x = ()\n") "Mtl_data_type"
  then fail "comment was mistaken for an enum reference"

let () =
  try
    match Array.to_list Sys.argv with
    | [ _; "--self-test" ] -> self_test ()
    | [ _; source; ml; mli; native; feature_checks ] ->
        validate entries;
        let source = read source in
        let used = used_bindings source in
        let used_enums = used_enum_modules source in
        List.iter
          (function
            | Selector { ocaml; _ } ->
                if not (Hashtbl.mem used ocaml) then
                  fail "registry binding %s is not used by metal.ml" ocaml
            | Enum { ocaml; _ } ->
                if not (Hashtbl.mem used_enums ocaml) then
                  fail "registry enum %s is not used by metal.ml" ocaml
            | Record { ocaml; _ } ->
                if not (Hashtbl.mem used_enums ocaml) then
                  fail "registry record %s is not used by metal.ml" ocaml)
          entries;
        write ml (emit_ml entries);
        write mli (emit_mli entries);
        write native (emit_c entries);
        write feature_checks (emit_feature_checks ())
    | _ -> fail "usage: generate [--self-test | METAL_ML ML MLI NATIVE FEATURE_CHECKS]"
  with Failure message ->
    prerr_endline message;
    exit 1
