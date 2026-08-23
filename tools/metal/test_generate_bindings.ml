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

type expected_result =
  { abi : string
  ; objc_type : string
  ; ocaml_type : string
  ; overflow_error : string
  }

type expected_companion =
  { sdk_id : string
  ; kind : string
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  }

type expected_binding =
  { sdk_id : string
  ; selector : string
  ; ocaml_name : string
  ; c_symbol : string
  ; receiver_handle_kind : string
  ; macos_major : int
  ; macos_minor : int
  ; arguments : expected_argument list
  ; result : expected_result option
  ; companions : expected_companion list
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
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
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
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
    ; safe_api = None
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setCullMode:]"
    ; selector = "setCullMode:"
    ; ocaml_name = "command4_render_encoder_set_cull_mode"
    ; c_symbol = "caml_prismel_metal_command4_render_encoder_set_cull_mode"
    ; receiver_handle_kind = "Render_encoder4"
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
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
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
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
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
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
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
    ; safe_api = None
    }
  ; { sdk_id =
        "method:-[MTL4RenderCommandEncoder setThreadgroupMemoryLength:offset:atIndex:]"
    ; selector = "setThreadgroupMemoryLength:offset:atIndex:"
    ; ocaml_name = "command4_render_encoder_set_threadgroup_memory_length"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_threadgroup_memory_length"
    ; receiver_handle_kind = "Render_encoder4"
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
    ; safe_api = None
    }
  ; { sdk_id = "method:-[MTL4RenderCommandEncoder setTriangleFillMode:]"
    ; selector = "setTriangleFillMode:"
    ; ocaml_name = "command4_render_encoder_set_triangle_fill_mode"
    ; c_symbol =
        "caml_prismel_metal_command4_render_encoder_set_triangle_fill_mode"
    ; receiver_handle_kind = "Render_encoder4"
    ; macos_major = 26
    ; macos_minor = 0
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
    ; result = None
    ; companions = []
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
  ; { sdk_id = "method:-[MTLDevice maxThreadgroupMemoryLength]"
    ; selector = "maxThreadgroupMemoryLength"
    ; ocaml_name = "device_max_threadgroup_memory_length"
    ; c_symbol = "caml_prismel_metal_device_max_threadgroup_memory_length"
    ; receiver_handle_kind = "Device"
    ; macos_major = 10
    ; macos_minor = 13
    ; arguments = []
    ; result =
        Some
          { abi = "objc_nsuint_to_checked_ocaml_int64"
          ; objc_type = "NSUInteger"
          ; ocaml_type = "int64"
          ; overflow_error =
              "Metal returned a threadgroup-memory limit outside signed 64-bit range"
          }
    ; companions =
        [ { sdk_id = "property:MTLDevice:maxThreadgroupMemoryLength"
          ; kind = "property"
          ; owner = "MTLDevice"
          ; name = "maxThreadgroupMemoryLength"
          ; header = "Metal/MTLDevice.h"
          ; signature = "NSUInteger"
          ; attributes = [ "AvailabilityAttr" ]
          }
        ]
    ; safe_api =
        Some
          { operation = "Metal.Device.info"
          ; module_path = [ "Device" ]
          ; value_name = "info"
          ; test_value = "test_device_info"
          ; test_call = [ "Device"; "info" ]
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

let check_argument sdk_id (expected : expected_argument) value =
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

let check_result sdk_id (expected : expected_result) value =
  if json_string "abi" value <> expected.abi
     || json_string "objc_type" value <> expected.objc_type
     || json_string "ocaml_type" value <> expected.ocaml_type
     || json_string "overflow_error" value <> expected.overflow_error
  then fail "generated manifest result drift for %s" sdk_id

let check_companion parent_sdk_id (expected : expected_companion) value =
  let require field expected_value =
    let actual = json_string field value in
    if actual <> expected_value then
      fail "generated manifest companion %s drift for %s: expected %s, found %s"
        field parent_sdk_id expected_value actual
  in
  require "sdk_id" expected.sdk_id;
  require "kind" expected.kind;
  require "owner" expected.owner;
  require "name" expected.name;
  require "header" expected.header;
  require "signature" expected.signature;
  if json_string_list "attributes" value <> expected.attributes then
    fail "generated manifest companion attributes drift for %s" parent_sdk_id

let check_entry (expected : expected_binding) value =
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
  require "macos_introduced"
    (Printf.sprintf "%d.%d" expected.macos_major expected.macos_minor);
  require "template"
    (match expected.result with
     | None -> "direct_void_scalar"
     | Some _ -> "direct_getter");
  let arguments = json_list "arguments" value in
  if List.length arguments <> List.length expected.arguments then
    fail "generated manifest argument-list drift for %s" expected.sdk_id;
  List.iter2 (check_argument expected.sdk_id) expected.arguments arguments;
  (match expected.result, member "result" value with
   | None, None -> ()
   | None, Some _ ->
       fail "generated manifest void binding unexpectedly records a result for %s"
         expected.sdk_id
   | Some _, None ->
       fail "generated manifest getter result is absent for %s" expected.sdk_id
   | Some expected_result, Some result ->
       check_result expected.sdk_id expected_result result);
  let companions = json_list "companions" value in
  if List.length companions <> List.length expected.companions then
    fail "generated manifest companion-list drift for %s" expected.sdk_id;
  List.iter2 (check_companion expected.sdk_id) expected.companions companions;
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

let replace_once ~needle ~replacement value =
  if count_occurrences ~needle value <> 1 then
    fail "replacement fixture must contain exactly one occurrence of %S" needle;
  match find_from ~needle value 0 with
  | None -> assert false
  | Some start ->
      String.sub value 0 start ^ replacement
      ^ String.sub value (start + String.length needle)
          (String.length value - start - String.length needle)

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

let selector_pieces (expected : expected_binding) =
  if expected.arguments = [] then [ expected.selector ]
  else
    let pieces = String.split_on_char ':' expected.selector in
    let pieces =
      match List.rev pieces with
      | "" :: reversed -> List.rev reversed
      | _ -> fail "golden selector must end in a colon: %s" expected.selector
    in
    if List.length pieces <> List.length expected.arguments then
      fail "golden selector/argument cardinality mismatch for %s" expected.sdk_id;
    pieces

let receiver_names (expected : expected_binding) =
  match expected.receiver_handle_kind with
  | "Device" -> "raw_device", "device"
  | "Compute_encoder4" | "Render_encoder4" -> "raw_encoder", "encoder"
  | other -> fail "unknown golden receiver kind for %s: %s" expected.sdk_id other

let receiver_objc_type (expected : expected_binding) =
  match expected.receiver_handle_kind with
  | "Device" -> "id<MTLDevice>"
  | "Compute_encoder4" -> "id<MTL4ComputeCommandEncoder>"
  | "Render_encoder4" -> "id<MTL4RenderCommandEncoder>"
  | other -> fail "unknown golden receiver kind for %s: %s" expected.sdk_id other

let raw_external (expected : expected_binding) =
  let result_type =
    match expected.result with
    | None -> "(unit, string) result"
    | Some result -> Printf.sprintf "(%s, string) result" result.ocaml_type
  in
  let types =
    "Types.handle"
    :: (List.map (fun _ -> "int") expected.arguments @ [ result_type ])
  in
  Printf.sprintf "external %s :\n    %s =\n    %S" expected.ocaml_name
    (String.concat " -> " types) expected.c_symbol

let native_signature (expected : expected_binding) =
  let raw_receiver, _ = receiver_names expected in
  let arguments =
    ("value " ^ raw_receiver)
    :: List.map
         (fun (argument : expected_argument) -> "value raw_" ^ argument.name)
         expected.arguments
  in
  match expected.result with
  | None ->
      Printf.sprintf "%s(\n    %s) {" expected.c_symbol
        (String.concat ", " arguments)
  | Some _ ->
      Printf.sprintf "%s(%s) {" expected.c_symbol
        (String.concat ", " arguments)

let native_camlparam (expected : expected_binding) =
  let raw_receiver, _ = receiver_names expected in
  let arguments =
    raw_receiver
    :: List.map
         (fun (argument : expected_argument) -> "raw_" ^ argument.name)
         expected.arguments
  in
  Printf.sprintf "CAMLparam%d(%s);" (List.length arguments)
    (String.concat ", " arguments)

let native_call (expected : expected_binding) =
  let _, receiver = receiver_names expected in
  match expected.arguments with
  | [] -> Printf.sprintf "[%s %s]" receiver expected.selector
  | arguments ->
      let components =
        List.map2
          (fun piece (argument : expected_argument) ->
            Printf.sprintf "%s:static_cast<%s>(%s)" piece argument.objc_type
              argument.name)
          (selector_pieces expected) arguments
      in
      Printf.sprintf "[%s %s]" receiver (String.concat " " components)

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

let argument_validation (argument : expected_argument) =
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

let native_argument_conversion (argument : expected_argument) =
  Printf.sprintf
    "const intnat %s = Long_val(raw_%s);\n        if (%s) {\n          CAMLreturn(result_error_text(%S));\n        }"
    argument.name argument.name (argument_validation argument) argument.error

let native_getter_core expected result =
  let raw_receiver, receiver = receiver_names expected in
  Printf.sprintf
    "  CAMLlocal2(result, copied_result);\n  @autoreleasepool {\n    if (@available(macOS %d.%d, *)) {\n      @try {\n        %s %s =\n            object_of_handle(%s, Handle_kind::%s);\n        const NSUInteger native_result = %s;\n        if (native_result > static_cast<NSUInteger>(INT64_MAX)) {\n          CAMLreturn(result_error_text(%S));\n        }\n        copied_result = caml_copy_int64(\n            static_cast<std::int64_t>(native_result));\n        result = result_ok(copied_result);\n        CAMLreturn(result);"
    expected.macos_major expected.macos_minor (receiver_objc_type expected)
    receiver raw_receiver expected.receiver_handle_kind (native_call expected)
    result.overflow_error

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
      let raw_receiver, _ = receiver_names expected in
      [ ( "raw ML OCaml name"
        , raw_external expected
        , raw_ml )
      ; ( "raw MLI OCaml name"
        , raw_external expected
        , raw_mli )
      ; "native signature", native_signature expected, native_body
      ; "native CAMLparam", native_camlparam expected, native_body
      ; ( "native receiver kind"
        , "object_of_handle(" ^ raw_receiver ^ ", Handle_kind::"
          ^ expected.receiver_handle_kind ^ ");"
        , native_body )
      ; "native direct selector", native_call expected, native_body
      ]
      |> List.iter (fun (description, needle, contents) ->
        if count_occurrences ~needle contents <> 1 then
          fail "%s must occur exactly once for %s" description expected.sdk_id);
      match expected.result with
      | None ->
          List.iter
            (fun argument ->
              let conversion = native_argument_conversion argument in
              if count_occurrences ~needle:conversion native_body <> 1 then
                fail
                  "native argument conversion/validation drift for %s argument %s"
                  expected.sdk_id argument.name;
              if count_occurrences ~needle:argument.error native_body <> 1 then
                fail "native validation error must occur once for %s argument %s"
                  expected.sdk_id argument.name;
              match argument.kind with
              | Enum_int _ -> ()
              | Unsigned_int { multiple_of = None; _ } ->
                  if contains ~needle:(argument.name ^ " % ") native_body then
                    fail
                      "native scalar validation gained an unexpected multiple for %s"
                      expected.sdk_id
              | Unsigned_int { multiple_of = Some _; _ } -> ())
            expected.arguments
      | Some result ->
          let core = native_getter_core expected result in
          if count_occurrences ~needle:core native_body <> 1 then
            fail "native getter ordered/rooted core must occur once for %s"
              expected.sdk_id)
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
    let getter_drift_inventory =
      Filename.concat directory "getter-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:"method:-[MTLDevice maxThreadgroupMemoryLength]"
         ~field:"signature" (`String "instance () -> NSInteger")
    |> pretty_json |> write_file getter_drift_inventory;
    require_failure "SDK getter-signature drift test" "Metal inventory drift"
      (run inputs ~inventory:getter_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "getter-drift"));
    let property_drift_inventory =
      Filename.concat directory "property-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:"property:MTLDevice:maxThreadgroupMemoryLength"
         ~field:"signature" (`String "NSInteger")
    |> pretty_json |> write_file property_drift_inventory;
    require_failure "SDK companion-property drift test" "Metal inventory drift"
      (run inputs ~inventory:property_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "property-drift"));
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
    let transitive_tests = Filename.concat directory "transitive-tests.ml" in
    write_file transitive_tests
      "let test_metal4_raster_state_commands encoder =\n\
       \  ignore\n\
       \    (Command4.Render_encoder.set_cull_mode encoder (Obj.magic 0));\n\
       \  ignore\n\
       \    (Command4.Render_encoder.set_depth_clip_mode encoder (Obj.magic 0));\n\
       \  ignore\n\
       \    (Command4.Render_encoder.set_front_facing_winding encoder\n\
       \       (Obj.magic 0));\n\
       \  ignore\n\
       \    (Command4.Render_encoder.set_triangle_fill_mode encoder\n\
       \       (Obj.magic 0))\n\
       let test_device_info device = ignore (Device.info device)\n\
       let run_generated_conformance encoder device =\n\
       \  test_metal4_raster_state_commands encoder;\n\
       \  test_device_info device\n\
       let main () =\n\
       \  run_generated_conformance (Obj.magic ()) (Obj.magic ())\n\
       let () = main ()\n";
    require_success "transitive conformance reachability test"
      (run inputs ~safe_tests:transitive_tests ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native
         (outputs directory "transitive-tests"));
    let unreachable_tests = Filename.concat directory "unreachable-tests.ml" in
    read_file inputs.safe_tests
    |> replace_once ~needle:"let info = test_device_info device in"
         ~replacement:"let info = get (Device.info device) in"
    |> write_file unreachable_tests;
    require_failure "unreachable conformance helper test"
      "conformance function is not reachable from an executable top-level runner"
      (run inputs ~safe_tests:unreachable_tests ~inventory:inputs.inventory
         ~manual_native:inputs.manual_native
         (outputs directory "unreachable-tests"));
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
