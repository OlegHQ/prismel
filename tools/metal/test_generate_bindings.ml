open Support

type inputs =
  { generator : string
  ; inventory : string
  ; plan_source : string
  ; generator_source : string
  ; manual_native : string
  ; manual_raw_ml : string
  ; manual_raw_mli : string
  ; safe_source : string
  ; safe_tests : string
  }

type outputs =
  { raw_ml : string
  ; raw_mli : string
  ; native : string
  ; manifest : string
  }

let parse_options () =
  let generator = ref "" in
  let inventory = ref "" in
  let plan_source = ref "" in
  let generator_source = ref "" in
  let manual_native = ref "" in
  let manual_raw_ml = ref "" in
  let manual_raw_mli = ref "" in
  let safe_source = ref "" in
  let safe_tests = ref "" in
  let set target value = target := value in
  Arg.parse
    [ "--generator", Arg.String (set generator), "Generator executable"
    ; "--inventory", Arg.String (set inventory), "Pinned inventory"
    ; "--plan-source", Arg.String (set plan_source), "Binding plan source"
    ; ( "--generator-source"
      , Arg.String (set generator_source)
      , "Generator source" )
    ; "--manual-native", Arg.String (set manual_native), "Manual bridge"
    ; "--manual-raw-ml", Arg.String (set manual_raw_ml), "Manual raw ML"
    ; "--manual-raw-mli", Arg.String (set manual_raw_mli), "Manual raw MLI"
    ; "--safe-source", Arg.String (set safe_source), "Safe Metal API"
    ; "--safe-tests", Arg.String (set safe_tests), "Metal conformance tests"
    ]
    (fun value -> fail "unexpected generator-test argument: %s" value)
    "Test deterministic Metal binding generation";
  let require name value =
    if !value = "" then fail "missing generator-test option %s" name;
    !value
  in
  let generator = require "--generator" generator in
  let generator =
    if Filename.is_relative generator then Filename.concat (Sys.getcwd ()) generator
    else generator
  in
  { generator
  ; inventory = require "--inventory" inventory
  ; plan_source = require "--plan-source" plan_source
  ; generator_source = require "--generator-source" generator_source
  ; manual_native = require "--manual-native" manual_native
  ; manual_raw_ml = require "--manual-raw-ml" manual_raw_ml
  ; manual_raw_mli = require "--manual-raw-mli" manual_raw_mli
  ; safe_source = require "--safe-source" safe_source
  ; safe_tests = require "--safe-tests" safe_tests
  }

let outputs directory prefix =
  let path suffix = Filename.concat directory (prefix ^ suffix) in
  { raw_ml = path ".ml"
  ; raw_mli = path ".mli"
  ; native = path ".inc"
  ; manifest = path ".json"
  }

let run inputs ?(plan_source = inputs.plan_source)
    ?(manual_raw_ml = inputs.manual_raw_ml)
    ?(manual_raw_mli = inputs.manual_raw_mli)
    ?(safe_source = inputs.safe_source) ?(safe_tests = inputs.safe_tests)
    ~inventory ~manual_native outputs =
  command inputs.generator
    [ "--inventory"; inventory
    ; "--plan-source"; plan_source
    ; "--generator-source"; inputs.generator_source
    ; "--manual-native"; manual_native
    ; "--manual-raw-ml"; manual_raw_ml
    ; "--manual-raw-mli"; manual_raw_mli
    ; "--safe-source"; safe_source
    ; "--safe-tests"; safe_tests
    ; "--output-raw-ml"; outputs.raw_ml
    ; "--output-raw-mli"; outputs.raw_mli
    ; "--output-native"; outputs.native
    ; "--output-manifest"; outputs.manifest
    ]

let require_success description result =
  if not (successful result) then
    fail "%s failed:\nstdout: %s\nstderr: %s" description result.stdout
      result.stderr

let require_failure description needle result =
  if successful result then fail "%s unexpectedly succeeded" description;
  if not (contains ~needle result.stderr) then
    fail "%s reported the wrong error:\n%s" description result.stderr

let replace_symbol_field ~target ~field replacement value =
  match value with
  | `Assoc fields ->
      let found = ref false in
      let fields =
        List.map
          (fun (name, value) ->
            if name <> "symbols" then name, value
            else
              let symbols =
                match value with
                | `List symbols ->
                    List.map
                      (function
                        | `Assoc declaration as original ->
                            if List.assoc_opt "id" declaration
                               = Some (`String target)
                            then begin
                              found := true;
                              `Assoc
                                ((field, replacement)
                                 :: List.remove_assoc field declaration)
                            end
                            else original
                        | other -> other)
                      symbols
                | _ -> fail "inventory symbols field is not a list"
              in
              name, `List symbols)
          fields
      in
      if not !found then fail "could not find drift-test symbol %s" target;
      `Assoc fields
  | _ -> fail "inventory root is not an object"

type expected_binding =
  { sdk_id : string
  ; selector : string
  ; ocaml_name : string
  ; c_symbol : string
  ; argument_name : string
  ; objc_type : string
  ; cases : (string * int) list
  ; error : string
  ; operation : string
  ; value_name : string
  ; test_value : string
  ; test_call : string list
  }

let expected_bindings =
  [ { sdk_id = "method:-[MTL4RenderCommandEncoder setCullMode:]"
    ; selector = "setCullMode:"
    ; ocaml_name = "command4_render_encoder_set_cull_mode"
    ; c_symbol = "caml_prismel_metal_command4_render_encoder_set_cull_mode"
    ; argument_name = "mode"
    ; objc_type = "MTLCullMode"
    ; cases =
        [ "enum-case:MTLCullMode:MTLCullModeNone", 0
        ; "enum-case:MTLCullMode:MTLCullModeFront", 1
        ; "enum-case:MTLCullMode:MTLCullModeBack", 2
        ]
    ; error = "Metal 4 cull mode is invalid"
    ; operation = "Metal.Command4.Render_encoder.set_cull_mode"
    ; value_name = "set_cull_mode"
    ; test_value = "test_metal4_raster_state_commands"
    ; test_call = [ "Command4"; "Render_encoder"; "set_cull_mode" ]
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setDepthClipMode:]"
    ; selector = "setDepthClipMode:"
    ; ocaml_name = "command4_render_encoder_set_depth_clip_mode"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_depth_clip_mode"
    ; argument_name = "mode"
    ; objc_type = "MTLDepthClipMode"
    ; cases =
        [ "enum-case:MTLDepthClipMode:MTLDepthClipModeClip", 0
        ; "enum-case:MTLDepthClipMode:MTLDepthClipModeClamp", 1
        ]
    ; error = "Metal 4 depth-clip mode is invalid"
    ; operation = "Metal.Command4.Render_encoder.set_depth_clip_mode"
    ; value_name = "set_depth_clip_mode"
    ; test_value = "test_metal4_raster_state_commands"
    ; test_call = [ "Command4"; "Render_encoder"; "set_depth_clip_mode" ]
    }
  ; { sdk_id =
        "method:-[MTL4RenderCommandEncoder setFrontFacingWinding:]"
    ; selector = "setFrontFacingWinding:"
    ; ocaml_name = "command4_render_encoder_set_front_facing_winding"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_front_facing_winding"
    ; argument_name = "winding"
    ; objc_type = "MTLWinding"
    ; cases =
        [ "enum-case:MTLWinding:MTLWindingClockwise", 0
        ; "enum-case:MTLWinding:MTLWindingCounterClockwise", 1
        ]
    ; error = "Metal 4 front-facing winding is invalid"
    ; operation = "Metal.Command4.Render_encoder.set_front_facing_winding"
    ; value_name = "set_front_facing_winding"
    ; test_value = "test_metal4_raster_state_commands"
    ; test_call =
        [ "Command4"; "Render_encoder"; "set_front_facing_winding" ]
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setTriangleFillMode:]"
    ; selector = "setTriangleFillMode:"
    ; ocaml_name = "command4_render_encoder_set_triangle_fill_mode"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_triangle_fill_mode"
    ; argument_name = "mode"
    ; objc_type = "MTLTriangleFillMode"
    ; cases =
        [ "enum-case:MTLTriangleFillMode:MTLTriangleFillModeFill", 0
        ; "enum-case:MTLTriangleFillMode:MTLTriangleFillModeLines", 1
        ]
    ; error = "Metal 4 triangle-fill mode is invalid"
    ; operation = "Metal.Command4.Render_encoder.set_triangle_fill_mode"
    ; value_name = "set_triangle_fill_mode"
    ; test_value = "test_metal4_raster_state_commands"
    ; test_call = [ "Command4"; "Render_encoder"; "set_triangle_fill_mode" ]
    }
  ]

let json_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "generated manifest field %s is not a string" name

let json_int name value =
  match member_int name value with
  | Some value -> value
  | None -> fail "generated manifest field %s is not an integer" name

let json_list name value =
  match member_list name value with
  | Some value -> value
  | None -> fail "generated manifest field %s is not a list" name

let json_string_list name value =
  json_list name value
  |> List.map (function
    | `String value -> value
    | _ -> fail "generated manifest field %s contains a non-string" name)

let check_entry expected value =
  let require field expected_value =
    let actual = json_string field value in
    if actual <> expected_value then
      fail "generated manifest %s drift for %s: expected %s, found %s" field
        expected.sdk_id expected_value actual
  in
  require "sdk_id" expected.sdk_id;
  require "selector" expected.selector;
  require "ocaml_name" expected.ocaml_name;
  require "c_symbol" expected.c_symbol;
  require "receiver_handle_kind" "Render_encoder4";
  let argument =
    match json_list "arguments" value with
    | [ argument ] -> argument
    | _ -> fail "generated manifest must record one argument for %s" expected.sdk_id
  in
  if json_string "name" argument <> expected.argument_name
     || json_string "objc_type" argument <> expected.objc_type
     || json_string "abi" argument <> "ocaml_int_to_objc_enum"
     || json_string "error" argument <> expected.error
  then fail "generated manifest argument drift for %s" expected.sdk_id;
  let cases =
    json_list "cases" argument
    |> List.map (fun case -> json_string "sdk_id" case, json_int "value" case)
  in
  if cases <> expected.cases then
    fail "generated manifest enum-case drift for %s" expected.sdk_id;
  let safe_api = member_exn "safe_api" value in
  if json_string "operation" safe_api <> expected.operation
     || json_string_list "module_path" safe_api
        <> [ "Command4"; "Render_encoder" ]
     || json_string "value_name" safe_api <> expected.value_name
     || json_string "test_value" safe_api <> expected.test_value
     || json_string_list "test_call" safe_api <> expected.test_call
  then fail "generated manifest safe-API evidence drift for %s" expected.sdk_id

let count_occurrences ~needle value =
  let needle_length = String.length needle in
  let value_length = String.length value in
  let rec count index total =
    if index + needle_length > value_length then total
    else if String.sub value index needle_length = needle then
      count (index + needle_length) (total + 1)
    else count (index + 1) total
  in
  if needle_length = 0 then 0 else count 0 0

let find_from ~needle value start =
  let needle_length = String.length needle in
  let value_length = String.length value in
  let rec search index =
    if index + needle_length > value_length then None
    else if String.sub value index needle_length = needle then Some index
    else search (index + 1)
  in
  search start

let native_binding_body symbol native =
  match find_from ~needle:symbol native 0 with
  | None -> fail "generated native binding is absent: %s" symbol
  | Some start ->
      let ending =
        match find_from ~needle:"\nextern \"C\" CAMLprim value" native
                (start + String.length symbol) with
        | Some ending -> ending
        | None -> String.length native
      in
      String.sub native start (ending - start)

let check_manifest inputs outputs =
  let value = read_file outputs.manifest |> Yojson.Safe.from_string in
  if member_int "entry_count" value <> Some (List.length expected_bindings) then
    fail "generated Metal manifest must record four golden bindings";
  if member_string "binding_plan_source_sha256" value
     <> Some (sha256 (read_file inputs.plan_source))
  then fail "generated Metal manifest has stale plan provenance";
  if member_string "generator_source_sha256" value
     <> Some (sha256 (read_file inputs.generator_source))
  then fail "generated Metal manifest has stale generator provenance";
  [ "inventory_sha256", inputs.inventory
  ; "raw_ml_sha256", outputs.raw_ml
  ; "raw_mli_sha256", outputs.raw_mli
  ; "native_include_sha256", outputs.native
  ]
  |> List.iter (fun (field, path) ->
    if member_string field value <> Some (sha256 (read_file path)) then
      fail "generated Metal manifest has stale %s" field);
  let entries = json_list "entries" value in
  if List.length entries <> List.length expected_bindings then
    fail "generated Metal manifest entry list has the wrong length";
  List.iter2 check_entry expected_bindings entries;
  let raw_ml = read_file outputs.raw_ml in
  let raw_mli = read_file outputs.raw_mli in
  let native = read_file outputs.native in
  List.iter
    (fun expected ->
      let native_body = native_binding_body expected.c_symbol native in
      [ ( "raw ML OCaml name"
        , "external " ^ expected.ocaml_name ^ " :"
        , raw_ml )
      ; ( "raw MLI OCaml name"
        , "external " ^ expected.ocaml_name ^ " :"
        , raw_mli )
      ; "raw ML primitive", Printf.sprintf "%S" expected.c_symbol, raw_ml
      ; "raw MLI primitive", Printf.sprintf "%S" expected.c_symbol, raw_mli
      ; "native primitive", expected.c_symbol, native_body
      ; "native selector", "[encoder " ^ expected.selector, native_body
      ; "native validation error", expected.error, native_body
      ]
      |> List.iter (fun (description, needle, contents) ->
        if count_occurrences ~needle contents <> 1 then
          fail "%s must occur exactly once for %s" description expected.sdk_id);
      let values = List.map snd expected.cases |> List.sort Int.compare in
      let minimum = List.hd values in
      let maximum = List.hd (List.rev values) in
      let validation =
        Printf.sprintf "%s < %d || %s > %d" expected.argument_name minimum
          expected.argument_name maximum
      in
      if count_occurrences ~needle:validation native_body <> 1 then
        fail "native enum validation is incomplete for %s" expected.sdk_id)
    expected_bindings

let main () =
  let inputs = parse_options () in
  with_temp_directory "prismel-metal-bindings-test-" (fun directory ->
    let first = outputs directory "first" in
    let second = outputs directory "second" in
    require_success "first Metal generation"
      (run inputs ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native first);
    require_success "second Metal generation"
      (run inputs ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native second);
    [ first.raw_ml, second.raw_ml
    ; first.raw_mli, second.raw_mli
    ; first.native, second.native
    ; first.manifest, second.manifest
    ]
    |> List.iter (fun (left, right) ->
      if read_file left <> read_file right then
        fail "Metal generation is nondeterministic: %s differs from %s" left
          right);
    let native = read_file first.native in
    [ "objc_msgSend"; "performSelector"; "valueForKey" ]
    |> List.iter (fun forbidden ->
      if contains ~needle:forbidden native then
        fail "generated bridge contains forbidden dispatch: %s" forbidden);
    check_manifest inputs first;
    let collision_source = Filename.concat directory "collision.mm" in
    write_file collision_source
      (read_file inputs.manual_native
       ^ "\nextern \"C\" CAMLprim value \
          caml_prismel_metal_command4_render_encoder_set_cull_mode(value);\n");
    require_failure "manual/generated collision test"
      "generated C symbol still exists in the handwritten bridge"
      (run inputs ~inventory:inputs.inventory ~manual_native:collision_source
         (outputs directory "collision"));
    let non_collision_source = Filename.concat directory "prefix.mm" in
    write_file non_collision_source
      (read_file inputs.manual_native
       ^ "\n// caml_prismel_metal_command4_render_encoder_set_cull_mode\n\
          int caml_prismel_metal_command4_render_encoder_set_cull_modes = 0;\n");
    let non_collision_raw = Filename.concat directory "prefix.ml" in
    write_file non_collision_raw
      (read_file inputs.manual_raw_ml
       ^ "\n(* command4_render_encoder_set_cull_mode and its primitive *)\n\
          let command4_render_encoder_set_cull_modes = 0\n");
    require_success "prefix/comment non-collision test"
      (run inputs ~manual_raw_ml:non_collision_raw
         ~inventory:inputs.inventory ~manual_native:non_collision_source
         (outputs directory "prefix"));
    let alternate_raw = Filename.concat directory "alternate.ml" in
    write_file alternate_raw
      (read_file inputs.manual_raw_ml
       ^ "\nexternal alternate_cull_mode : handle -> int -> unit = \
          \"caml_prismel_metal_command4_render_encoder_set_cull_mode\"\n");
    require_failure "alternate-name primitive collision test"
      "generated C primitive still exists in handwritten Metal_raw"
      (run inputs ~manual_raw_ml:alternate_raw ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "alternate"));
    let stale_plan = Filename.concat directory "stale-plan.ml" in
    write_file stale_plan (read_file inputs.plan_source ^ "\n");
    require_failure "binding-plan provenance test"
      "Metal inventory binding-plan provenance drift"
      (run inputs ~plan_source:stale_plan ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "stale-plan"));
    let drift_inventory = Filename.concat directory "drift.json" in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:"method:-[MTL4RenderCommandEncoder setCullMode:]"
         ~field:"signature" (`String "instance (BOOL) -> void")
    |> pretty_json |> write_file drift_inventory;
    require_failure "SDK signature drift test" "Metal inventory drift"
      (run inputs ~inventory:drift_inventory
         ~manual_native:inputs.manual_native (outputs directory "drift"));
    let enum_drift_inventory = Filename.concat directory "enum-drift.json" in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:"enum-case:MTLCullMode:MTLCullModeBack"
         ~field:"constant_value" (`String "7")
    |> pretty_json |> write_file enum_drift_inventory;
    require_failure "SDK enum-value drift test" "Metal enum-case value drift"
      (run inputs ~inventory:enum_drift_inventory
         ~manual_native:inputs.manual_native (outputs directory "enum-drift"));
    let empty_safe_source = Filename.concat directory "empty-safe.ml" in
    write_file empty_safe_source "";
    require_failure "missing safe-API evidence test" "safe Metal module is absent"
      (run inputs ~safe_source:empty_safe_source ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "safe-evidence"));
    let string_safe_source = Filename.concat directory "string-safe.ml" in
    write_file string_safe_source
      "module Command4 = struct\n\
       module Render_encoder = struct\n\
       let set_cull_mode () =\n\
         ignore \"Metal_raw.command4_render_encoder_set_cull_mode\"\n\
       end\n\
       end\n";
    require_failure "string-only safe-API evidence test"
      "does not call generated raw binding"
      (run inputs ~safe_source:string_safe_source ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "string-safe"));
    let unrelated_safe_source = Filename.concat directory "unrelated-safe.ml" in
    write_file unrelated_safe_source
      "module Command4 = struct\n\
       module Render_encoder = struct\n\
       let unrelated value mode =\n\
         Metal_raw.command4_render_encoder_set_cull_mode value mode\n\
       let set_cull_mode () = ()\n\
       end\n\
       end\n";
    require_failure "unrelated-call safe-API evidence test"
      "does not call generated raw binding"
      (run inputs ~safe_source:unrelated_safe_source
         ~inventory:inputs.inventory ~manual_native:inputs.manual_native
         (outputs directory "unrelated-safe"));
    let prefix_safe_source = Filename.concat directory "prefix-safe.ml" in
    write_file prefix_safe_source
      "module Command4 = struct\n\
       module Render_encoder = struct\n\
       let set_cull_mode value mode =\n\
         Metal_raw.command4_render_encoder_set_cull_modes value mode\n\
       end\n\
       end\n";
    require_failure "prefix-call safe-API evidence test"
      "does not call generated raw binding"
      (run inputs ~safe_source:prefix_safe_source ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "prefix-safe"));
    let string_tests = Filename.concat directory "string-tests.ml" in
    write_file string_tests
      "let test_metal4_raster_state_commands () =\n\
       ignore \"Command4.Render_encoder.set_cull_mode\"\n";
    require_failure "string-only conformance evidence test"
      "conformance function does not call generated Metal operation"
      (run inputs ~safe_tests:string_tests ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "string-tests"));
    let unrelated_tests = Filename.concat directory "unrelated-tests.ml" in
    write_file unrelated_tests
      "let unrelated value mode =\n\
       Command4.Render_encoder.set_cull_mode value mode\n\
       let test_metal4_raster_state_commands () = ()\n";
    require_failure "unrelated-call conformance evidence test"
      "conformance function does not call generated Metal operation"
      (run inputs ~safe_tests:unrelated_tests ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native
         (outputs directory "unrelated-tests"));
    let prefix_tests = Filename.concat directory "prefix-tests.ml" in
    write_file prefix_tests
      "let test_metal4_raster_state_commands value mode =\n\
       Command4.Render_encoder.set_cull_modes value mode\n";
    require_failure "prefix-call conformance evidence test"
      "conformance function does not call generated Metal operation"
      (run inputs ~safe_tests:prefix_tests ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native (outputs directory "prefix-tests"));
    Printf.printf
      "Metal generator goldens, determinism, exact collisions, structural safe evidence, and SDK drift checks passed\n%!" )

let () = protect_main main
