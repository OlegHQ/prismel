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

type expected_argument_kind =
  | Enum_int of (string * int) list
  | Unsigned_int of
      { minimum : int
      ; multiple_of : int option
      }

type expected_argument =
  { name : string
  ; abi : string
  ; objc_type : string
  ; kind : expected_argument_kind
  ; error : string
  }

type expected_safe_api =
  { operation : string
  ; module_path : string list
  ; value_name : string
  ; test_value : string
  ; test_call : string list
  }

type expected_binding =
  { sdk_id : string
  ; selector : string
  ; ocaml_name : string
  ; c_symbol : string
  ; receiver_handle_kind : string
  ; arguments : expected_argument list
  ; safe_api : expected_safe_api option
  }

let expected_bindings =
  [ { sdk_id =
        "method:-[MTL4ComputeCommandEncoder setImageblockWidth:height:]"
    ; selector = "setImageblockWidth:height:"
    ; ocaml_name = "command4_compute_encoder_set_imageblock_size"
    ; c_symbol =
        "caml_prismel_metal_command4_compute_encoder_set_imageblock_size"
    ; receiver_handle_kind = "Compute_encoder4"
    ; arguments =
        [ { name = "width"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error = "Metal 4 compute imageblock width must be nonnegative"
          }
        ; { name = "height"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error = "Metal 4 compute imageblock height must be nonnegative"
          }
        ]
    ; safe_api = None
    }
  ; { sdk_id =
        "method:-[MTL4ComputeCommandEncoder setThreadgroupMemoryLength:atIndex:]"
    ; selector = "setThreadgroupMemoryLength:atIndex:"
    ; ocaml_name =
        "command4_compute_encoder_set_threadgroup_memory_length"
    ; c_symbol =
        "caml_prismel_metal_command4_compute_encoder_set_threadgroup_memory_length"
    ; receiver_handle_kind = "Compute_encoder4"
    ; arguments =
        [ { name = "length"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = Some 16 }
          ; error =
              "Metal 4 compute threadgroup-memory length must be nonnegative and a multiple of 16"
          }
        ; { name = "index"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error =
              "Metal 4 compute threadgroup-memory index must be nonnegative"
          }
        ]
    ; safe_api = None
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setCullMode:]"
    ; selector = "setCullMode:"
    ; ocaml_name = "command4_render_encoder_set_cull_mode"
    ; c_symbol = "caml_prismel_metal_command4_render_encoder_set_cull_mode"
    ; receiver_handle_kind = "Render_encoder4"
    ; arguments =
        [ { name = "mode"
          ; abi = "ocaml_int_to_objc_enum"
          ; objc_type = "MTLCullMode"
          ; kind =
              Enum_int
                [ "enum-case:MTLCullMode:MTLCullModeNone", 0
                ; "enum-case:MTLCullMode:MTLCullModeFront", 1
                ; "enum-case:MTLCullMode:MTLCullModeBack", 2
                ]
          ; error = "Metal 4 cull mode is invalid"
          }
        ]
    ; safe_api =
        Some
          { operation = "Metal.Command4.Render_encoder.set_cull_mode"
          ; module_path = [ "Command4"; "Render_encoder" ]
          ; value_name = "set_cull_mode"
          ; test_value = "test_metal4_raster_state_commands"
          ; test_call = [ "Command4"; "Render_encoder"; "set_cull_mode" ]
          }
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setDepthClipMode:]"
    ; selector = "setDepthClipMode:"
    ; ocaml_name = "command4_render_encoder_set_depth_clip_mode"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_depth_clip_mode"
    ; receiver_handle_kind = "Render_encoder4"
    ; arguments =
        [ { name = "mode"
          ; abi = "ocaml_int_to_objc_enum"
          ; objc_type = "MTLDepthClipMode"
          ; kind =
              Enum_int
                [ "enum-case:MTLDepthClipMode:MTLDepthClipModeClip", 0
                ; "enum-case:MTLDepthClipMode:MTLDepthClipModeClamp", 1
                ]
          ; error = "Metal 4 depth-clip mode is invalid"
          }
        ]
    ; safe_api =
        Some
          { operation = "Metal.Command4.Render_encoder.set_depth_clip_mode"
          ; module_path = [ "Command4"; "Render_encoder" ]
          ; value_name = "set_depth_clip_mode"
          ; test_value = "test_metal4_raster_state_commands"
          ; test_call =
              [ "Command4"; "Render_encoder"; "set_depth_clip_mode" ]
          }
    }
  ; { sdk_id =
        "method:-[MTL4RenderCommandEncoder setFrontFacingWinding:]"
    ; selector = "setFrontFacingWinding:"
    ; ocaml_name = "command4_render_encoder_set_front_facing_winding"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_front_facing_winding"
    ; receiver_handle_kind = "Render_encoder4"
    ; arguments =
        [ { name = "winding"
          ; abi = "ocaml_int_to_objc_enum"
          ; objc_type = "MTLWinding"
          ; kind =
              Enum_int
                [ "enum-case:MTLWinding:MTLWindingClockwise", 0
                ; "enum-case:MTLWinding:MTLWindingCounterClockwise", 1
                ]
          ; error = "Metal 4 front-facing winding is invalid"
          }
        ]
    ; safe_api =
        Some
          { operation =
              "Metal.Command4.Render_encoder.set_front_facing_winding"
          ; module_path = [ "Command4"; "Render_encoder" ]
          ; value_name = "set_front_facing_winding"
          ; test_value = "test_metal4_raster_state_commands"
          ; test_call =
              [ "Command4"; "Render_encoder"; "set_front_facing_winding" ]
          }
    }
  ; { sdk_id =
        "method:-[MTL4RenderCommandEncoder setObjectThreadgroupMemoryLength:atIndex:]"
    ; selector = "setObjectThreadgroupMemoryLength:atIndex:"
    ; ocaml_name =
        "command4_render_encoder_set_object_threadgroup_memory_length"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_object_threadgroup_memory_length"
    ; receiver_handle_kind = "Render_encoder4"
    ; arguments =
        [ { name = "length"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error =
              "Metal 4 object threadgroup-memory length must be nonnegative"
          }
        ; { name = "index"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error =
              "Metal 4 object threadgroup-memory index must be nonnegative"
          }
        ]
    ; safe_api = None
    }
  ; { sdk_id =
        "method:-[MTL4RenderCommandEncoder setThreadgroupMemoryLength:offset:atIndex:]"
    ; selector = "setThreadgroupMemoryLength:offset:atIndex:"
    ; ocaml_name = "command4_render_encoder_set_threadgroup_memory_length"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_threadgroup_memory_length"
    ; receiver_handle_kind = "Render_encoder4"
    ; arguments =
        [ { name = "length"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error =
              "Metal 4 render threadgroup-memory length must be nonnegative"
          }
        ; { name = "offset"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error =
              "Metal 4 render threadgroup-memory offset must be nonnegative"
          }
        ; { name = "index"
          ; abi = "ocaml_int_to_nsuint"
          ; objc_type = "NSUInteger"
          ; kind = Unsigned_int { minimum = 0; multiple_of = None }
          ; error =
              "Metal 4 render threadgroup-memory index must be nonnegative"
          }
        ]
    ; safe_api = None
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setTriangleFillMode:]"
    ; selector = "setTriangleFillMode:"
    ; ocaml_name = "command4_render_encoder_set_triangle_fill_mode"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_triangle_fill_mode"
    ; receiver_handle_kind = "Render_encoder4"
    ; arguments =
        [ { name = "mode"
          ; abi = "ocaml_int_to_objc_enum"
          ; objc_type = "MTLTriangleFillMode"
          ; kind =
              Enum_int
                [ "enum-case:MTLTriangleFillMode:MTLTriangleFillModeFill", 0
                ; "enum-case:MTLTriangleFillMode:MTLTriangleFillModeLines", 1
                ]
          ; error = "Metal 4 triangle-fill mode is invalid"
          }
        ]
    ; safe_api =
        Some
          { operation = "Metal.Command4.Render_encoder.set_triangle_fill_mode"
          ; module_path = [ "Command4"; "Render_encoder" ]
          ; value_name = "set_triangle_fill_mode"
          ; test_value = "test_metal4_raster_state_commands"
          ; test_call =
              [ "Command4"; "Render_encoder"; "set_triangle_fill_mode" ]
          }
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

let check_argument sdk_id expected value =
  if json_string "name" value <> expected.name
     || json_string "abi" value <> expected.abi
     || json_string "objc_type" value <> expected.objc_type
     || json_string "error" value <> expected.error
  then fail "generated manifest argument drift for %s" sdk_id;
  match expected.kind with
  | Enum_int expected_cases ->
      let cases =
        json_list "cases" value
        |> List.map (fun case -> json_string "sdk_id" case, json_int "value" case)
      in
      if cases <> expected_cases then
        fail "generated manifest enum-case drift for %s argument %s" sdk_id
          expected.name;
      if member "minimum" value <> None || member "multiple_of" value <> None
      then
        fail "generated manifest enum argument has scalar constraints for %s"
          sdk_id
  | Unsigned_int { minimum; multiple_of } ->
      if member_int "minimum" value <> Some minimum then
        fail "generated manifest minimum drift for %s argument %s" sdk_id
          expected.name;
      let actual_multiple =
        match member_exn "multiple_of" value with
        | `Null -> None
        | `Int value -> Some value
        | _ ->
            fail "generated manifest multiple_of is invalid for %s argument %s"
              sdk_id expected.name
      in
      if actual_multiple <> multiple_of then
        fail "generated manifest multiple_of drift for %s argument %s" sdk_id
          expected.name;
      if member "cases" value <> None then
        fail "generated manifest scalar argument has enum cases for %s" sdk_id

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
  require "receiver_handle_kind" expected.receiver_handle_kind;
  require "template" "direct_void_scalar";
  let arguments = json_list "arguments" value in
  if List.length arguments <> List.length expected.arguments then
    fail "generated manifest argument-list drift for %s" expected.sdk_id;
  List.iter2 (check_argument expected.sdk_id) expected.arguments arguments;
  match expected.safe_api, member_exn "safe_api" value with
  | None, `Null -> ()
  | None, _ ->
      fail "generated manifest raw-only binding has safe-API evidence for %s"
        expected.sdk_id
  | Some _, `Null ->
      fail "generated manifest safe binding has null evidence for %s"
        expected.sdk_id
  | Some expected_safe_api, safe_api ->
      if json_string "operation" safe_api <> expected_safe_api.operation
         || json_string_list "module_path" safe_api
            <> expected_safe_api.module_path
         || json_string "value_name" safe_api <> expected_safe_api.value_name
         || json_string "test_value" safe_api <> expected_safe_api.test_value
         || json_string_list "test_call" safe_api
            <> expected_safe_api.test_call
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

let selector_pieces expected =
  let pieces = String.split_on_char ':' expected.selector in
  let pieces =
    match List.rev pieces with
    | "" :: reversed -> List.rev reversed
    | _ -> fail "golden selector must end in a colon: %s" expected.selector
  in
  if List.length pieces <> List.length expected.arguments then
    fail "golden selector/argument cardinality mismatch for %s" expected.sdk_id;
  pieces

let raw_external expected =
  let types =
    "Types.handle"
    :: (List.map (fun _ -> "int") expected.arguments
        @ [ "(unit, string) result" ])
  in
  Printf.sprintf "external %s :\n    %s =\n    %S" expected.ocaml_name
    (String.concat " -> " types) expected.c_symbol

let native_signature expected =
  let arguments =
    "value raw_encoder"
    :: List.map
         (fun argument -> "value raw_" ^ argument.name)
         expected.arguments
  in
  Printf.sprintf "%s(\n    %s) {" expected.c_symbol
    (String.concat ", " arguments)

let native_camlparam expected =
  let arguments =
    "raw_encoder"
    :: List.map (fun argument -> "raw_" ^ argument.name) expected.arguments
  in
  Printf.sprintf "CAMLparam%d(%s);" (List.length arguments)
    (String.concat ", " arguments)

let native_call expected =
  let components =
    List.map2
      (fun piece argument ->
        Printf.sprintf "%s:static_cast<%s>(%s)" piece argument.objc_type
          argument.name)
      (selector_pieces expected) expected.arguments
  in
  Printf.sprintf "[encoder %s];" (String.concat " " components)

let enum_validation name cases =
  let values = List.map snd cases |> List.sort Int.compare in
  let rec consecutive = function
    | [] | [ _ ] -> true
    | left :: (right :: _ as rest) ->
        right = left + 1 && consecutive rest
  in
  match values with
  | minimum :: _ when consecutive values ->
      let maximum = List.hd (List.rev values) in
      Printf.sprintf "%s < %d || %s > %d" name minimum name maximum
  | _ ->
      values
      |> List.map (fun value -> Printf.sprintf "%s != %d" name value)
      |> String.concat " && "

let argument_validation argument =
  match argument.kind with
  | Enum_int cases -> enum_validation argument.name cases
  | Unsigned_int { minimum; multiple_of } ->
      let conditions =
        (if minimum = 0 then [ argument.name ^ " < 0" ]
         else [ Printf.sprintf "%s < %d" argument.name minimum ])
        @
        match multiple_of with
        | None -> []
        | Some divisor ->
            [ Printf.sprintf "%s %% %d != 0" argument.name divisor ]
      in
      String.concat " || " conditions

let native_argument_conversion argument =
  Printf.sprintf
    "const intnat %s = Long_val(raw_%s);\n        if (%s) {\n          CAMLreturn(result_error_text(%S));\n        }"
    argument.name argument.name (argument_validation argument) argument.error

let check_manifest inputs outputs =
  let value = read_file outputs.manifest |> Yojson.Safe.from_string in
  if member_int "entry_count" value <> Some (List.length expected_bindings) then
    fail "generated Metal manifest must record %d golden bindings"
      (List.length expected_bindings);
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
        , raw_external expected
        , raw_ml )
      ; ( "raw MLI OCaml name"
        , raw_external expected
        , raw_mli )
      ; "native signature", native_signature expected, native_body
      ; "native CAMLparam", native_camlparam expected, native_body
      ; ( "native receiver kind"
        , "object_of_handle(raw_encoder, Handle_kind::"
          ^ expected.receiver_handle_kind ^ ");"
        , native_body )
      ; "native direct selector", native_call expected, native_body
      ]
      |> List.iter (fun (description, needle, contents) ->
        if count_occurrences ~needle contents <> 1 then
          fail "%s must occur exactly once for %s" description expected.sdk_id);
      List.iter
        (fun argument ->
          let conversion = native_argument_conversion argument in
          if count_occurrences ~needle:conversion native_body <> 1 then
            fail "native argument conversion/validation drift for %s argument %s"
              expected.sdk_id argument.name;
          if count_occurrences ~needle:argument.error native_body <> 1 then
            fail "native validation error must occur once for %s argument %s"
              expected.sdk_id argument.name;
          match argument.kind with
          | Enum_int _ -> ()
          | Unsigned_int { multiple_of = None; _ } ->
              if contains ~needle:(argument.name ^ " % ") native_body then
                fail "native scalar validation gained an unexpected multiple for %s"
                  expected.sdk_id
          | Unsigned_int { multiple_of = Some _; _ } -> ())
        expected.arguments)
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
    let scalar_drift_inventory =
      Filename.concat directory "scalar-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:
           "method:-[MTL4ComputeCommandEncoder setImageblockWidth:height:]"
         ~field:"signature"
         (`String "instance (NSInteger, NSUInteger) -> void")
    |> pretty_json |> write_file scalar_drift_inventory;
    require_failure "SDK scalar-signature drift test" "Metal inventory drift"
      (run inputs ~inventory:scalar_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "scalar-drift"));
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
