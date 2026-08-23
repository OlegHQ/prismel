open Support

type inputs =
  { generator : string
  ; inventory : string
  ; plan_root : string
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
  ; public_enum_ml : string
  ; public_enum_mli : string
  ; public_enum_test : string
  ; public_value_ml : string
  ; public_value_mli : string
  ; public_value_test : string
  ; public_global_ml : string
  ; public_global_mli : string
  ; public_global_test : string
  ; public_descriptor_ml : string
  ; public_descriptor_mli : string
  ; public_descriptor_test : string
  ; native_descriptor_test : string
  }

let parse_options () =
  let generator = ref "" in
  let inventory = ref "" in
  let plan_root = ref "" in
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
    ; "--plan-root", Arg.String (set plan_root), "Binding plan workspace root"
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
  ; plan_root = require "--plan-root" plan_root
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
  ; public_enum_ml = path "_enum.ml"
  ; public_enum_mli = path "_enum.mli"
  ; public_enum_test = path "_enum_test.ml"
  ; public_value_ml = path "_value.ml"
  ; public_value_mli = path "_value.mli"
  ; public_value_test = path "_value_test.ml"
  ; public_global_ml = path "_global.ml"
  ; public_global_mli = path "_global.mli"
  ; public_global_test = path "_global_test.ml"
  ; public_descriptor_ml = path "_descriptor.ml"
  ; public_descriptor_mli = path "_descriptor.mli"
  ; public_descriptor_test = path "_descriptor_test.ml"
  ; native_descriptor_test = path "_descriptor_test.mm"
  }

let run inputs ?(plan_root = inputs.plan_root)
    ?(manual_raw_ml = inputs.manual_raw_ml)
    ?(manual_raw_mli = inputs.manual_raw_mli)
    ?(safe_source = inputs.safe_source) ?(safe_tests = inputs.safe_tests)
    ~inventory ~manual_native outputs =
  command inputs.generator
    [ "--inventory"; inventory
    ; "--plan-root"; plan_root
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
    ; "--output-public-enum-ml"; outputs.public_enum_ml
    ; "--output-public-enum-mli"; outputs.public_enum_mli
    ; "--output-public-enum-test"; outputs.public_enum_test
    ; "--output-public-value-ml"; outputs.public_value_ml
    ; "--output-public-value-mli"; outputs.public_value_mli
    ; "--output-public-value-test"; outputs.public_value_test
    ; "--output-public-global-ml"; outputs.public_global_ml
    ; "--output-public-global-mli"; outputs.public_global_mli
    ; "--output-public-global-test"; outputs.public_global_test
    ; "--output-public-descriptor-ml"; outputs.public_descriptor_ml
    ; "--output-public-descriptor-mli"; outputs.public_descriptor_mli
    ; "--output-public-descriptor-test"; outputs.public_descriptor_test
    ; "--output-native-descriptor-test"; outputs.native_descriptor_test
    ]

let require_success description result =
  if not (successful result) then
    fail "%s failed:\nstdout: %s\nstderr: %s" description result.stdout
      result.stderr

let require_failure description needle result =
  if successful result then fail "%s unexpectedly succeeded" description;
  if not (contains ~needle result.stderr) then
    fail "%s reported the wrong error:\n%s" description result.stderr

let rec ensure_directory path =
  if path = "" || path = "." || Sys.file_exists path then ()
  else begin
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755
  end

let copy_plan_sources ~source_root ~destination_root ~mutate =
  if not (List.mem mutate Binding_plan.source_paths) then
    fail "unknown binding-plan mutation source: %s" mutate;
  Binding_plan.source_paths
  |> List.iter (fun relative ->
    let source = Filename.concat source_root relative in
    let destination = Filename.concat destination_root relative in
    ensure_directory (Filename.dirname destination);
    let contents = read_file source in
    let contents = if relative = mutate then contents ^ "\n" else contents in
    write_file destination contents)

let check_plan_provenance root =
  let sources =
    Binding_plan.source_paths
    |> List.map (fun relative ->
      relative, read_file (Filename.concat root relative))
  in
  let expected = Binding_plan.source_sha256 ~root in
  if Binding_spec.aggregate_source_sha256 sources <> expected then
    fail "binding-plan aggregate digest disagrees with its source list";
  if Binding_spec.aggregate_source_sha256 (List.rev sources) <> expected then
    fail "binding-plan aggregate digest depends on source-list order";
  if
    Binding_spec.aggregate_source_sha256 [ "a", "bc" ]
    = Binding_spec.aggregate_source_sha256 [ "ab", "c" ]
  then fail "binding-plan aggregate digest framing is ambiguous"

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
    ; safe_api =
        Some
          { operation =
              "Metal.Command4.Compute_encoder.set_threadgroup_memory_length"
          ; module_path = [ "Command4"; "Compute_encoder" ]
          ; value_name = "set_threadgroup_memory_length"
          ; test_value = "test_metal4_compute_commands"
          ; test_call =
              [ "Command4"; "Compute_encoder"
              ; "set_threadgroup_memory_length"
              ]
          }
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
  ; { sdk_id =
        "method:-[MTLComputePipelineState staticThreadgroupMemoryLength]"
    ; selector = "staticThreadgroupMemoryLength"
    ; ocaml_name = "compute_pipeline_static_threadgroup_memory_length"
    ; c_symbol =
        "caml_prismel_metal_compute_pipeline_static_threadgroup_memory_length"
    ; receiver_handle_kind = "Compute_pipeline"
    ; macos_major = 10
    ; macos_minor = 13
    ; arguments = []
    ; result =
        Some
          { abi = "objc_nsuint_to_checked_ocaml_int64"
          ; objc_type = "NSUInteger"
          ; ocaml_type = "int64"
          ; overflow_error =
              "Metal returned a static threadgroup-memory length outside signed 64-bit range"
          }
    ; companions =
        [ { sdk_id =
              "property:MTLComputePipelineState:staticThreadgroupMemoryLength"
          ; kind = "property"
          ; owner = "MTLComputePipelineState"
          ; name = "staticThreadgroupMemoryLength"
          ; header = "Metal/MTLComputePipeline.h"
          ; signature = "NSUInteger"
          ; attributes = [ "AvailabilityAttr" ]
          }
        ]
    ; safe_api =
        Some
          { operation = "Metal.Compute_pipeline.static_threadgroup_memory_length"
          ; module_path = [ "Compute_pipeline" ]
          ; value_name = "static_threadgroup_memory_length"
          ; test_value = "test_metal4_compute_commands"
          ; test_call =
              [ "Compute_pipeline"; "static_threadgroup_memory_length" ]
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
  let definition = "\n" ^ symbol ^ "(" in
  match find_from ~needle:definition native 0 with
  | None -> fail "generated native binding is absent: %s" symbol
  | Some definition_start ->
      let start = definition_start + 1 in
      let ending =
        let after = start + String.length symbol in
        let candidates =
          [ find_from ~needle:"\nextern \"C\" CAMLprim value" native after
          ; find_from ~needle:"\n\nAPI_AVAILABLE" native after
          ]
          |> List.filter_map Fun.id
        in
        match candidates with
        | [] -> String.length native
        | candidates -> List.fold_left min max_int candidates
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
  | "Compute_pipeline" -> "raw_pipeline", "pipeline"
  | "Compute_encoder4" | "Render_encoder4" -> "raw_encoder", "encoder"
  | other -> fail "unknown golden receiver kind for %s: %s" expected.sdk_id other

let receiver_objc_type (expected : expected_binding) =
  match expected.receiver_handle_kind with
  | "Device" -> "id<MTLDevice>"
  | "Compute_pipeline" -> "id<MTLComputePipelineState>"
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

let generator_source_sha256 entry_source =
  let metal_directory =
    if Filename.dirname entry_source = "." then Sys.getcwd ()
    else Filename.dirname entry_source
  in
  let tools_directory = Filename.dirname metal_directory in
  let root = Filename.dirname tools_directory in
  [ "tools/metal/generate_bindings.ml"
  ; "tools/metal/binding_availability.ml"
  ; "tools/metal/binding_availability.mli"
  ; "tools/metal/binding_enum_codegen.ml"
  ; "tools/metal/binding_enum_codegen.mli"
  ; "tools/metal/binding_enum_implicit_plan.ml"
  ; "tools/metal/binding_enum_implicit_plan.mli"
  ; "tools/metal/binding_enum_implicit_codegen.ml"
  ; "tools/metal/binding_enum_implicit_codegen.mli"
  ; "tools/metal/binding_enum_bound_evidence.ml"
  ; "tools/metal/binding_enum_bound_evidence.mli"
  ; "tools/metal/binding_enum_public_codegen.ml"
  ; "tools/metal/binding_enum_public_codegen.mli"
  ; "tools/metal/binding_value_record_plan.ml"
  ; "tools/metal/binding_value_record_plan.mli"
  ; "tools/metal/binding_value_record_codegen.ml"
  ; "tools/metal/binding_value_record_codegen.mli"
  ; "tools/metal/binding_value_record_evidence.ml"
  ; "tools/metal/binding_value_record_evidence.mli"
  ; "tools/metal/binding_global_string_spec.ml"
  ; "tools/metal/binding_global_string_spec.mli"
  ; "tools/metal/binding_global_string_codegen.ml"
  ; "tools/metal/binding_global_string_codegen.mli"
  ; "tools/metal/binding_global_string_evidence.ml"
  ; "tools/metal/binding_global_string_evidence.mli"
  ; "tools/metal/binding_global_string_conformance_codegen.ml"
  ; "tools/metal/binding_global_string_conformance_codegen.mli"
  ; "tools/metal/binding_descriptor_property_spec.ml"
  ; "tools/metal/binding_descriptor_property_spec.mli"
  ; "tools/metal/binding_descriptor_property_plan.ml"
  ; "tools/metal/binding_descriptor_property_plan.mli"
  ; "tools/metal/binding_descriptor_property_codegen.ml"
  ; "tools/metal/binding_descriptor_property_codegen.mli"
  ; "tools/metal/binding_descriptor_property_evidence.ml"
  ; "tools/metal/binding_descriptor_property_evidence.mli"
  ; "tools/metal/binding_render_pipeline_scalar_plan.ml"
  ; "tools/metal/binding_render_pipeline_scalar_plan.mli"
  ; "tools/metal/binding_render_pipeline_scalar_codegen.ml"
  ; "tools/metal/binding_render_pipeline_scalar_codegen.mli"
  ; "tools/metal/binding_render_pipeline_scalar_evidence.ml"
  ; "tools/metal/binding_render_pipeline_scalar_evidence.mli"
  ; "tools/metal/binding_render_encoder_promotion.ml"
  ; "tools/metal/binding_render_encoder_promotion.mli"
  ; "tools/metal/binding_render_encoder_resource_plan.ml"
  ; "tools/metal/binding_render_encoder_resource_plan.mli"
  ; "tools/metal/binding_render_encoder_manifest.ml"
  ; "tools/metal/binding_render_encoder_manifest.mli"
  ; "tools/metal/binding_render_command_safe_reachability.ml"
  ; "tools/metal/binding_render_command_safe_reachability.mli"
  ; "tools/metal/binding_pipeline_state_safe_reachability.ml"
  ; "tools/metal/binding_pipeline_state_safe_reachability.mli"
  ; "tools/metal/binding_shader_safe_reachability.ml"
  ; "tools/metal/binding_shader_safe_reachability.mli"
  ; "tools/metal/render_encoder_resource_adapter.ml"
  ; "tools/metal/render_encoder_resource_adapter.mli"
  ; "tools/metal/binding_presentation_public_audit.ml"
  ; "tools/metal/binding_descriptor_default_evidence.ml"
  ; "tools/metal/binding_descriptor_default_evidence.mli"
  ; "tools/metal/binding_argument_reflection_plan.ml"
  ; "tools/metal/binding_argument_reflection_plan.mli"
  ; "tools/metal/binding_argument_reflection_codegen.ml"
  ; "tools/metal/binding_argument_reflection_codegen.mli"
  ; "tools/metal/binding_argument_reflection_evidence.ml"
  ; "tools/metal/binding_argument_reflection_evidence.mli"
  ; "tools/metal/binding_acceleration_scalar_plan.ml"
  ; "tools/metal/binding_acceleration_scalar_plan.mli"
  ; "tools/metal/binding_acceleration_scalar_codegen.ml"
  ; "tools/metal/binding_acceleration_scalar_codegen.mli"
  ; "tools/metal/binding_acceleration_scalar_evidence.ml"
  ; "tools/metal/binding_acceleration_scalar_evidence.mli"
  ; "tools/metal/binding_acceleration_ownership_plan.ml"
  ; "tools/metal/binding_acceleration_ownership_plan.mli"
  ; "tools/metal/binding_acceleration_ownership_codegen.ml"
  ; "tools/metal/binding_acceleration_ownership_codegen.mli"
  ; "tools/metal/binding_acceleration_ownership_evidence.ml"
  ; "tools/metal/binding_acceleration_ownership_evidence.mli"
  ; "tools/metal/binding_acceleration_ownership_adapter.ml"
  ; "tools/metal/binding_acceleration_ownership_adapter.mli"
  ; "tools/metal/binding_acceleration_operations_plan.ml"
  ; "tools/metal/binding_acceleration_operations_plan.mli"
  ; "tools/metal/binding_acceleration_operations_codegen.ml"
  ; "tools/metal/binding_acceleration_operations_codegen.mli"
  ; "tools/metal/binding_acceleration_operations_evidence.ml"
  ; "tools/metal/binding_acceleration_operations_evidence.mli"
  ; "tools/metal/binding_acceleration_operations_adapter.ml"
  ; "tools/metal/binding_acceleration_operations_adapter.mli"
  ; "tools/metal/binding_struct_spec.ml"
  ; "tools/metal/binding_struct_spec.mli"
  ; "tools/metal/binding_struct_plan.ml"
  ; "tools/metal/binding_struct_plan.mli"
  ; "tools/metal/binding_struct_native_codegen.ml"
  ; "tools/metal/binding_struct_native_codegen.mli"
  ; "tools/metal/binding_string_spec.ml"
  ; "tools/metal/binding_string_spec.mli"
  ; "tools/metal/binding_string_properties.ml"
  ; "tools/metal/binding_string_properties.mli"
  ; "tools/metal/binding_string_codegen.ml"
  ; "tools/metal/binding_string_codegen.mli"
  ; "tools/metal/binding_receiver_catalog.ml"
  ; "tools/metal/binding_receiver_catalog.mli"
  ]
  |> List.map (fun relative ->
    relative, read_file (Filename.concat root relative))
  |> Binding_spec.aggregate_source_sha256

let check_mechanical_enum_batch raw_ml raw_mli value =
  let batch = member_exn "mechanical_enum_batch" value in
  if member_int "enum_family_count" batch <> Some 61
     || member_int "enum_case_count" batch <> Some 326
     || member_int "enum_declaration_count" batch <> Some 448
  then fail "generated Metal mechanical enum cardinality drift";
  let identifiers = json_string_list "enum_identifiers" batch in
  if List.length identifiers <> 448
     || List.length (List.sort_uniq String.compare identifiers) <> 448
  then fail "generated Metal mechanical enum identifier closure drift";
  let families = json_list "enum_families" batch in
  if List.length families <> 61 then
    fail "generated Metal mechanical enum family list drift";
  let family_identifiers, case_count =
    List.fold_left
      (fun (identifiers, case_count) family ->
        let cases = json_list "cases" family in
        let identifiers =
          json_string "enum_id" family :: json_string "typedef_id" family
          :: List.map (json_string "id") cases
          @ identifiers
        in
        identifiers, case_count + List.length cases)
      ([], 0) families
  in
  if case_count <> 326
     || List.sort String.compare family_identifiers <> identifiers
  then fail "generated Metal mechanical enum manifest closure drift";
  let device_location =
    List.find_opt
      (fun family ->
        member_string "name" family = Some "MTLDeviceLocation")
      families
    |> Option.value ~default:(`Assoc [])
  in
  if member_string "module_name" device_location
     <> Some "Mtl_device_location"
  then fail "generated Metal device-location module name drift";
  let unspecified =
    json_list "cases" device_location
    |> List.find_opt (fun case ->
      member_string "name" case = Some "MTLDeviceLocationUnspecified")
    |> Option.value ~default:(`Assoc [])
  in
  if member_string "uint64_decimal" unspecified
     <> Some "18446744073709551615"
     || member_string "uint64_bits" unspecified
        <> Some "0xffffffffffffffff"
  then fail "generated Metal UINT64_MAX enum manifest drift";
  [ ( raw_ml
    , "let mtl_device_location_unspecified : int64 = 0xffffffffffffffffL" )
  ; raw_mli, "val mtl_device_location_unspecified : int64"
  ]
  |> List.iter (fun (contents, needle) ->
    if count_occurrences ~needle contents <> 1 then
      fail "generated Metal UINT64_MAX raw enum constant drift")

let check_implicit_enum_batch raw_ml raw_mli native value =
  let batch = member_exn "mechanical_implicit_enum_batch" value in
  if member_int "enum_family_count" batch <> Some 7
     || member_int "enum_case_count" batch <> Some 23
     || member_int "enum_declaration_count" batch <> Some 37
  then fail "generated Metal implicit enum cardinality drift";
  let identifiers = json_string_list "enum_identifiers" batch in
  if List.length identifiers <> 37
     || List.length (List.sort_uniq String.compare identifiers) <> 37
  then fail "generated Metal implicit enum identifier closure drift";
  [ raw_ml, "module Implicit_enum_constants = struct"
  ; raw_ml, "let mtl_log_level_fault : int64 = 0x0000000000000005L"
  ; raw_mli, "module Implicit_enum_constants : sig"
  ; raw_mli, "val mtl_log_level_fault : int64"
  ; ( native
    , "static_assert(static_cast<uint64_t>(MTLLogLevelFault) == UINT64_C(5)" )
  ]
  |> List.iter (fun (contents, needle) ->
    if count_occurrences ~needle contents <> 1 then
      fail "generated Metal implicit enum output drift: %s" needle);
  if count_occurrences ~needle:"Metal enum value drift:" native <> 23 then
    fail "generated Metal implicit enum static-assert count drift"

let check_struct_native_batch raw_ml raw_mli native value =
  let batch = member_exn "mechanical_struct_native_batch" value in
  if member_int "method_count" batch <> Some 19
     || member_int "property_count" batch <> Some 8
     || member_int "declaration_count" batch <> Some 27
     || member_int "safe_bound_count" batch <> Some 0
  then fail "generated Metal struct-native cardinality drift";
  let method_ids = json_string_list "method_ids" batch in
  let property_ids = json_string_list "property_ids" batch in
  if List.length method_ids <> 19 || List.length property_ids <> 8
     || List.length
          (List.sort_uniq String.compare (method_ids @ property_ids))
        <> 27
  then fail "generated Metal struct-native identifier closure drift";
  [ raw_ml, "external generated_struct_m_t_l_device_max_threads_per_threadgroup"
  ; raw_mli, "Types.handle -> (int64 * int64 * int64, string) result"
  ; native, "static MTLSize prismel_mtl_size_of_value"
  ; native, "dispatchThreadgroups:argument_0 threadsPerThreadgroup:argument_1"
  ]
  |> List.iter (fun (contents, needle) ->
    if not (contains ~needle contents) then
      fail "generated Metal struct-native output drift: %s" needle)

let check_string_batch raw_ml raw_mli native value =
  let batch = member_exn "mechanical_string_batch" value in
  if member_int "property_count" batch <> Some 5
     || member_int "declaration_count" batch <> Some 13
     || member_int "safe_bound_count" batch <> Some 0
  then fail "generated Metal NSString cardinality drift";
  let identifiers = json_string_list "identifiers" batch in
  if List.length identifiers <> 13
     || List.length (List.sort_uniq String.compare identifiers) <> 13
  then fail "generated Metal NSString identifier closure drift";
  [ raw_ml, "generated_mtl4_binary_function_name_get"
  ; raw_mli, "generated_mtl_command_queue_label_set"
  ; raw_ml, "generated_mtl_command_encoder_label_get"
  ; raw_mli, "generated_mtl_command_encoder_label_set"
  ; native, "[binary_function name]"
  ; native, "[command_queue setLabel:native_value]"
  ; native, "command_encoder_of_handle(raw_receiver)"
  ; native, "[command_encoder setLabel:native_value]"
  ; native, "copy_optional_string(native_result)"
  ]
  |> List.iter (fun (contents, needle) ->
    if not (contains ~needle contents) then
      fail "generated Metal NSString output drift: %s" needle)

let check_json_fields context expected value =
  let actual =
    match value with
    | `Assoc fields -> List.map fst fields
    | _ -> fail "%s is not a JSON object" context
  in
  let sort = List.sort String.compare in
  if sort actual <> sort expected then
    fail "%s field-set drift: expected [%s], found [%s]" context
      (String.concat ", " (sort expected))
      (String.concat ", " (sort actual))

let require_json_string context field expected value =
  let actual = json_string field value in
  if not (String.equal actual expected) then
    fail "%s %s drift: expected %s, found %s" context field expected actual

let require_json_string_list context field expected value =
  let actual = json_string_list field value in
  if actual <> expected then
    fail "%s %s drift: expected [%s], found [%s]" context field
      (String.concat ", " expected) (String.concat ", " actual)

let direct_width_string = function
  | Binding_direct_spec.Native -> "native64"
  | Binding_direct_spec.Bits32 -> "32"
  | Binding_direct_spec.Bits64 -> "64"

let check_direct_scalar sdk_id role scalar value =
  let context = Printf.sprintf "direct method %s %s" sdk_id role in
  let abi, width =
    match scalar with
    | Binding_direct_spec.Bool -> "objc_bool", None
    | Binding_direct_spec.Float64 _ -> "objc_float64", None
    | Binding_direct_spec.Signed { width; _ } ->
        "signed_integer", Some (direct_width_string width)
    | Binding_direct_spec.Unsigned { width; _ } ->
        "unsigned_bit_pattern", Some (direct_width_string width)
  in
  check_json_fields context
    ([ "abi"; "objc_type"; "ocaml_type" ]
     @ match width with None -> [] | Some _ -> [ "width" ])
    value;
  require_json_string context "abi" abi value;
  require_json_string context "objc_type"
    (Binding_direct_spec.scalar_objc_type scalar) value;
  require_json_string context "ocaml_type"
    (Binding_direct_spec.scalar_ocaml_type scalar) value;
  match width with
  | None -> ()
  | Some width -> require_json_string context "width" width value

let direct_semantics_string = function
  | Binding_direct_spec.Query -> "query"
  | Binding_direct_spec.Command -> "command"
  | Binding_direct_spec.Blocking -> "blocking"
  | Binding_direct_spec.Process_identity -> "process_identity"

type expected_direct_receiver_access =
  | Direct_object of string
  | Helper_object of
      { helper : string
      ; handle_kinds : string list
      }
  | Wrapped_object of
      { handle_kind : string
      ; wrapper_type : string
      ; property : string
      }

type expected_direct_receiver =
  { objc_type : string
  ; raw_name : string
  ; local_name : string
  ; access : expected_direct_receiver_access
  }

let expected_direct_receiver owner =
  match
    List.find_opt
      (fun (receiver : Binding_receiver_catalog.polymorphic_receiver) ->
        String.equal receiver.sdk_owner owner)
      Binding_receiver_catalog.polymorphic_receivers
  with
  | Some receiver ->
      { objc_type = receiver.objc_receiver_type
      ; raw_name = receiver.raw_name
      ; local_name = receiver.local_name
      ; access =
          Helper_object
            { helper = receiver.helper
            ; handle_kinds = receiver.accepted_handle_kinds
            }
      }
  | None ->
      (match
         List.filter
           (fun (receiver : Binding_receiver_catalog.receiver) ->
             String.equal receiver.sdk_owner owner)
           Binding_receiver_catalog.receivers
       with
       | [ receiver ] ->
           let access =
             match receiver.bridge_access with
             | Binding_receiver_catalog.Object_of_handle ->
                 Direct_object receiver.handle_kind
             | Binding_receiver_catalog.Object_of_helper helper ->
                 Helper_object
                   { helper; handle_kinds = [ receiver.handle_kind ] }
             | Binding_receiver_catalog.Wrapped_property
                 { wrapper_type; property } ->
                 Wrapped_object
                   { handle_kind = receiver.handle_kind
                   ; wrapper_type
                   ; property
                   }
           in
           { objc_type = receiver.objc_receiver_type
           ; raw_name = receiver.raw_name
           ; local_name = receiver.local_name
           ; access
           }
       | [] -> fail "direct method owner has no receiver catalog entry: %s" owner
       | _ -> fail "direct method owner has ambiguous receiver entries: %s" owner)

let check_direct_receiver_manifest sdk_id
    (expected : expected_direct_receiver) value =
  let context = "direct method " ^ sdk_id ^ " receiver" in
  let common = [ "objc_type"; "raw_name"; "local_name"; "access"; "handle_kinds" ] in
  let fields =
    match expected.access with
    | Wrapped_object _ -> common @ [ "wrapper_type"; "wrapper_property" ]
    | Direct_object _ | Helper_object _ -> common
  in
  check_json_fields context fields value;
  require_json_string context "objc_type" expected.objc_type value;
  require_json_string context "raw_name" expected.raw_name value;
  require_json_string context "local_name" expected.local_name value;
  (match expected.access with
   | Direct_object handle_kind ->
       require_json_string context "access" "object_of_handle" value;
       require_json_string_list context "handle_kinds" [ handle_kind ] value
   | Helper_object { helper; handle_kinds } ->
       require_json_string context "access" helper value;
       require_json_string_list context "handle_kinds" handle_kinds value
   | Wrapped_object { handle_kind; wrapper_type; property } ->
       require_json_string context "access" "wrapped_property" value;
       require_json_string_list context "handle_kinds" [ handle_kind ] value;
       require_json_string context "wrapper_type" wrapper_type value;
       require_json_string context "wrapper_property" property value)

let check_direct_method_manifest
    (expected : Binding_direct_spec.method_entry) value =
  let context = "direct method " ^ expected.sdk_id in
  check_json_fields context
    [ "sdk_id"; "owner"; "selector"; "header"; "signature"; "attributes"
    ; "macos_introduced"; "semantics"; "arguments"; "result"; "ocaml_name"
    ; "c_symbol"; "receiver"; "safe_api"
    ] value;
  [ "sdk_id", expected.sdk_id
  ; "owner", expected.owner
  ; "selector", expected.selector
  ; "header", expected.header
  ; "signature", expected.signature
  ; "macos_introduced",
    Binding_availability.canonical expected.macos_introduced
  ; "semantics", direct_semantics_string expected.semantics
  ; "ocaml_name", expected.ocaml_name
  ; "c_symbol", expected.c_symbol
  ]
  |> List.iter (fun (field, expected_value) ->
    require_json_string context field expected_value value);
  require_json_string_list context "attributes" expected.attributes value;
  let arguments = json_list "arguments" value in
  if List.length arguments <> List.length expected.arguments then
    fail "%s argument cardinality drift" context;
  List.iteri
    (fun index (scalar, argument) ->
      check_direct_scalar expected.sdk_id
        (Printf.sprintf "argument %d" index) scalar argument)
    (List.combine expected.arguments arguments);
  (match expected.result, member_exn "result" value with
   | None, `Null -> ()
   | None, _ -> fail "%s unexpectedly has a result" context
   | Some _, `Null -> fail "%s is missing its result" context
   | Some result, result_json ->
       check_direct_scalar expected.sdk_id "result" result result_json);
  check_direct_receiver_manifest expected.sdk_id
    (expected_direct_receiver expected.owner)
    (member_exn "receiver" value);
  if member_exn "safe_api" value <> `Null then
    fail "%s must remain raw-only" context

let check_direct_property_manifest
    (expected : Binding_direct_spec.property_entry) value =
  let context = "direct property " ^ expected.sdk_id in
  check_json_fields context
    [ "sdk_id"; "owner"; "name"; "header"; "signature"; "attributes"
    ; "macos_introduced"; "getter_sdk_id"; "setter_sdk_id"
    ] value;
  [ "sdk_id", expected.sdk_id
  ; "owner", expected.owner
  ; "name", expected.name
  ; "header", expected.header
  ; "signature", expected.signature
  ; "macos_introduced",
    Binding_availability.canonical expected.macos_introduced
  ; "getter_sdk_id", expected.getter.sdk_id
  ]
  |> List.iter (fun (field, expected_value) ->
    require_json_string context field expected_value value);
  require_json_string_list context "attributes" expected.attributes value;
  match expected.setter, member_exn "setter_sdk_id" value with
  | None, `Null -> ()
  | None, _ -> fail "%s unexpectedly has a setter" context
  | Some _, `Null -> fail "%s is missing its setter" context
  | Some setter, `String actual when String.equal actual setter.sdk_id -> ()
  | Some setter, `String actual ->
      fail "%s setter drift: expected %s, found %s" context setter.sdk_id
        actual
  | Some _, _ -> fail "%s setter_sdk_id is not a string" context

let direct_raw_external (entry : Binding_direct_spec.method_entry) =
  let result_type =
    match entry.result with
    | None -> "unit"
    | Some result -> Binding_direct_spec.scalar_ocaml_type result
  in
  let types =
    "Types.handle"
    :: List.map Binding_direct_spec.scalar_ocaml_type entry.arguments
    @ [ Printf.sprintf "(%s, string) result" result_type ]
  in
  Printf.sprintf "  external %s :\n    %s =\n    %S\n\n" entry.ocaml_name
    (String.concat " -> " types) entry.c_symbol

let direct_selector_pieces selector argument_count =
  if argument_count = 0 then [ selector ]
  else
    match List.rev (String.split_on_char ':' selector) with
    | "" :: reversed ->
        let pieces = List.rev reversed in
        if List.length pieces <> argument_count then
          fail "direct selector/argument cardinality drift: %s" selector;
        pieces
    | _ -> fail "direct selector with arguments lacks trailing colon: %s" selector

let direct_selector_call (entry : Binding_direct_spec.method_entry)
    (receiver : expected_direct_receiver) =
  match entry.arguments with
  | [] -> Printf.sprintf "[%s %s]" receiver.local_name entry.selector
  | arguments ->
      direct_selector_pieces entry.selector (List.length arguments)
      |> List.mapi (fun index piece ->
        Printf.sprintf "%s:argument_%d" piece index)
      |> String.concat " "
      |> Printf.sprintf "[%s %s]" receiver.local_name

let direct_receiver_recovery (receiver : expected_direct_receiver) =
  match receiver.access with
  | Direct_object handle_kind ->
      Printf.sprintf
        "%s %s =\n            object_of_handle(%s, Handle_kind::%s);"
        receiver.objc_type receiver.local_name receiver.raw_name handle_kind
  | Helper_object { helper; _ } ->
      Printf.sprintf "%s %s = %s(%s);" receiver.objc_type receiver.local_name
        helper receiver.raw_name
  | Wrapped_object { handle_kind; wrapper_type; property } ->
      Printf.sprintf
        "%s receiver_state =\n            object_of_handle(%s, Handle_kind::%s);\n        %s %s = receiver_state.%s;"
        wrapper_type receiver.raw_name handle_kind receiver.objc_type
        receiver.local_name property

let direct_native_signature (entry : Binding_direct_spec.method_entry)
    (receiver : expected_direct_receiver) =
  let raw_arguments =
    receiver.raw_name
    :: List.mapi (fun index _ -> Printf.sprintf "raw_argument_%d" index)
         entry.arguments
  in
  Printf.sprintf "%s(\n    %s) {" entry.c_symbol
    (raw_arguments
     |> List.map (fun argument -> "value " ^ argument)
     |> String.concat ", ")

let direct_camlparam (entry : Binding_direct_spec.method_entry)
    (receiver : expected_direct_receiver) =
  let arguments =
    receiver.raw_name
    :: List.mapi (fun index _ -> Printf.sprintf "raw_argument_%d" index)
         entry.arguments
  in
  Printf.sprintf "CAMLparam%d(%s);" (List.length arguments)
    (String.concat ", " arguments)

let direct_method_by_id sdk_id =
  match
    List.find_opt
      (fun (entry : Binding_direct_spec.method_entry) ->
        String.equal entry.sdk_id sdk_id)
      Binding_direct_plan.methods
  with
  | Some entry -> entry
  | None -> fail "representative direct method is absent from plan: %s" sdk_id

let check_direct_needles sdk_id native needles =
  let entry = direct_method_by_id sdk_id in
  let body = native_binding_body entry.c_symbol native in
  List.iter
    (fun needle ->
      if count_occurrences ~needle body <> 1 then
        fail "representative native spelling %S must occur once for %s" needle
          sdk_id)
    needles;
  entry, body

let require_ordered_needles sdk_id body needles =
  let rec loop start = function
    | [] -> ()
    | needle :: rest ->
        (match find_from ~needle body start with
         | None -> fail "native operation order drift for %s at %S" sdk_id needle
         | Some index -> loop (index + String.length needle) rest)
  in
  loop 0 needles

let check_direct_representatives native =
  let _, _ =
    check_direct_needles "method:-[MTLTexture isFramebufferOnly]" native
      [ "const BOOL native_result = [texture isFramebufferOnly];"
      ; "copied_result = Val_bool(native_result);"
      ]
  in
  let unsigned_result objc_type receiver selector =
    [ Printf.sprintf "const %s native_result = [%s %s];" objc_type receiver
        selector
    ; "copied_result = caml_copy_int64(static_cast<std::int64_t>(static_cast<std::uint64_t>(native_result)));"
    ]
  in
  let _, _ =
    check_direct_needles "method:-[MTLDevice peerCount]" native
      (unsigned_result "uint32_t" "device" "peerCount")
  in
  let _, _ =
    check_direct_needles "method:-[MTLDevice peerGroupID]" native
      (unsigned_result "uint64_t" "device" "peerGroupID")
  in
  let _, _ =
    check_direct_needles "method:-[MTLCommandBuffer GPUEndTime]" native
      [ "const CFTimeInterval native_result = [command_buffer GPUEndTime];"
      ; "copied_result = caml_copy_double(static_cast<double>(native_result));"
      ]
  in
  let _, _ =
    check_direct_needles
      "method:-[MTLComputePipelineState shaderValidation]" native
      [ "const MTLShaderValidation native_result = [compute_pipeline shaderValidation];"
      ; "copied_result = caml_copy_int64(static_cast<std::int64_t>(native_result));"
      ]
  in
  let _, _ =
    check_direct_needles
      "method:-[MTLDevice supportsRasterizationRateMapWithLayerCount:]"
      native [ "if (@available(macOS 10.15.4, *))" ]
  in
  let command4 = direct_method_by_id "method:-[MTL4CommandBuffer popDebugGroup]" in
  let command4_receiver = expected_direct_receiver command4.owner in
  let _, _ =
    check_direct_needles command4.sdk_id native
      [ direct_receiver_recovery command4_receiver
      ; "[command_buffer4 popDebugGroup];"
      ]
  in
  let resource = direct_method_by_id "method:-[MTLResource allocatedSize]" in
  let resource_receiver = expected_direct_receiver resource.owner in
  let _, _ =
    check_direct_needles resource.sdk_id native
      [ direct_receiver_recovery resource_receiver
      ; "const NSUInteger native_result = [resource allocatedSize];"
      ]
  in
  let blocking_id = "method:-[MTLCommandBuffer waitUntilScheduled]" in
  let _, blocking_body =
    check_direct_needles blocking_id native
      [ "caml_enter_blocking_section();"
      ; "[command_buffer waitUntilScheduled];"
      ; "caml_leave_blocking_section();"
      ; "if (caught_exception != nil) {"
      ]
  in
  require_ordered_needles blocking_id blocking_body
    [ "id<MTLCommandBuffer> command_buffer ="
    ; "caml_enter_blocking_section();"
    ; "[command_buffer waitUntilScheduled];"
    ; "caml_leave_blocking_section();"
    ; "if (caught_exception != nil) {"
    ];
  let identity_id = "method:-[MTLResource setOwnerWithIdentity:]" in
  let _, identity_body =
    check_direct_needles identity_id native
      [ "id<MTLResource> resource = resource_of_handle(raw_resource);"
      ; "const std::int64_t signed_argument_0 = Int64_val(raw_argument_0);"
      ; "if (signed_argument_0 < 0 || static_cast<std::uint64_t>(signed_argument_0) > UINT32_MAX) {"
      ; "unsigned Metal argument is outside 32-bit range"
      ; "const task_id_token_t argument_0 = static_cast<task_id_token_t>(static_cast<std::uint64_t>(signed_argument_0));"
      ; "const kern_return_t native_result = [resource setOwnerWithIdentity:argument_0];"
      ; "copied_result = caml_copy_int64(static_cast<std::int64_t>(native_result));"
      ]
  in
  require_ordered_needles identity_id identity_body
    [ "resource_of_handle(raw_resource)"
    ; "Int64_val(raw_argument_0)"
    ; "UINT32_MAX"
    ; "const task_id_token_t argument_0"
    ; "[resource setOwnerWithIdentity:argument_0]"
    ; "caml_copy_int64"
    ]

let check_mechanical_direct_batch raw_ml raw_mli native value =
  let batch = member_exn "mechanical_direct_handle_batch" value in
  check_json_fields "mechanical direct-call batch"
    [ "method_count"; "property_count"; "declaration_count"
    ; "safe_bound_count"; "methods"; "properties"
    ] batch;
  let expected_counts =
    [ "method_count", 59, Binding_direct_plan.expected_method_count
    ; "property_count", 40, Binding_direct_plan.expected_property_count
    ; "declaration_count", 99,
      Binding_direct_plan.expected_declaration_count
    ; "safe_bound_count", 0, 0
    ]
  in
  List.iter
    (fun (field, required, planned) ->
      if planned <> required || member_int field batch <> Some required then
        fail "generated Metal direct-call %s drift" field)
    expected_counts;
  let methods = json_list "methods" batch in
  let properties = json_list "properties" batch in
  if List.length methods <> 59 || List.length properties <> 40 then
    fail "generated Metal direct-call manifest list cardinality drift";
  let sort_manifest field =
    List.sort
      (fun left right ->
        String.compare (json_string field left) (json_string field right))
  in
  let sort_methods =
    List.sort
      (fun (left : Binding_direct_spec.method_entry) right ->
        String.compare left.sdk_id right.sdk_id)
  in
  let sort_properties =
    List.sort
      (fun (left : Binding_direct_spec.property_entry) right ->
        String.compare left.sdk_id right.sdk_id)
  in
  let methods = sort_manifest "sdk_id" methods in
  let properties = sort_manifest "sdk_id" properties in
  let expected_methods = sort_methods Binding_direct_plan.methods in
  let expected_properties = sort_properties Binding_direct_plan.properties in
  let manifest_ids =
    List.map (json_string "sdk_id") methods
    @ List.map (json_string "sdk_id") properties
  in
  let sorted_ids = List.sort String.compare manifest_ids in
  if List.length (List.sort_uniq String.compare manifest_ids) <> 99
     || sorted_ids
        <> List.sort String.compare Binding_direct_plan.inventory_ids
  then fail "generated Metal direct-call inventory ID closure drift";
  List.iter2 check_direct_method_manifest expected_methods methods;
  List.iter2 check_direct_property_manifest expected_properties properties;
  List.iter
    (fun (entry : Binding_direct_spec.method_entry) ->
      let receiver = expected_direct_receiver entry.owner in
      let body = native_binding_body entry.c_symbol native in
      [ "raw ML external", direct_raw_external entry, raw_ml
      ; "raw MLI external", direct_raw_external entry, raw_mli
      ; "native C symbol", direct_native_signature entry receiver, native
      ; "native CAMLparam", direct_camlparam entry receiver, body
      ; "native receiver recovery", direct_receiver_recovery receiver, body
      ; "native direct selector", direct_selector_call entry receiver, body
      ; ( "native availability guard"
        , Printf.sprintf "if (@available(macOS %s, *))"
            (Binding_availability.canonical entry.macos_introduced)
        , body )
      ]
      |> List.iter (fun (description, needle, contents) ->
        if count_occurrences ~needle contents <> 1 then
          fail "%s must occur exactly once for %s" description entry.sdk_id);
      let quoted_symbol = Printf.sprintf "%S" entry.c_symbol in
      [ "raw ML C symbol", raw_ml; "raw MLI C symbol", raw_mli ]
      |> List.iter (fun (description, contents) ->
        if count_occurrences ~needle:quoted_symbol contents <> 1 then
          fail "%s must occur exactly once for %s" description entry.sdk_id);
      [ "objc_msgSend"; "performSelector"; "valueForKey" ]
      |> List.iter (fun forbidden ->
        if contains ~needle:forbidden body then
          fail "direct method %s uses dynamic dispatch: %s" entry.sdk_id
            forbidden))
    expected_methods;
  check_direct_representatives native

let check_manifest inputs outputs =
  let value = read_file outputs.manifest |> Yojson.Safe.from_string in
  let plan_sha256 = Binding_plan.source_sha256 ~root:inputs.plan_root in
  let inventory_sha256 = sha256 (read_file inputs.inventory) in
  let header =
    Printf.sprintf
      "Generated by tools/metal/generate_bindings.ml.\nPlan SHA-256: %s\nInventory SHA-256: %s\nDo not edit."
      plan_sha256 inventory_sha256
  in
  [ "raw ML", "(* " ^ header ^ " *)\n\n", outputs.raw_ml
  ; "raw MLI", "(* " ^ header ^ " *)\n\n", outputs.raw_mli
  ; "native include", "/* " ^ header ^ " */\n\n", outputs.native
  ; "public enum ML", "(* " ^ header ^ " *)\n\n", outputs.public_enum_ml
  ; "public enum MLI", "(* " ^ header ^ " *)\n\n", outputs.public_enum_mli
  ; "public enum test", "(* " ^ header ^ " *)\n\n", outputs.public_enum_test
  ; "public value ML", "(* " ^ header ^ " *)\n\n", outputs.public_value_ml
  ; "public value MLI", "(* " ^ header ^ " *)\n\n", outputs.public_value_mli
  ; "public value test", "(* " ^ header ^ " *)\n\n", outputs.public_value_test
  ; "public global ML", "(* " ^ header ^ " *)\n\n", outputs.public_global_ml
  ; "public global MLI", "(* " ^ header ^ " *)\n\n", outputs.public_global_mli
  ; "public global test", "(* " ^ header ^ " *)\n\n", outputs.public_global_test
  ; "public descriptor ML", "(* " ^ header ^ " *)\n\n", outputs.public_descriptor_ml
  ; "public descriptor MLI", "(* " ^ header ^ " *)\n\n", outputs.public_descriptor_mli
  ; "public descriptor test", "(* " ^ header ^ " *)\n\n", outputs.public_descriptor_test
  ; "native descriptor test", "/* " ^ header ^ " */\n\n", outputs.native_descriptor_test
  ]
  |> List.iter (fun (description, prefix, path) ->
    if not (String.starts_with ~prefix (read_file path)) then
      fail "generated %s has stale aggregate provenance header" description);
  if member_int "entry_count" value <> Some (List.length expected_bindings) then
    fail "generated Metal manifest must record %d golden bindings"
      (List.length expected_bindings);
  if member_int "schema" value <> Some 2 then
    fail "generated Metal manifest schema drift";
  if member_string "binding_plan_source_sha256" value
     <> Some plan_sha256
  then fail "generated Metal manifest has stale plan provenance";
  if member_string "generator_source_sha256" value
     <> Some (generator_source_sha256 inputs.generator_source)
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
  check_mechanical_enum_batch raw_ml raw_mli value;
  check_implicit_enum_batch raw_ml raw_mli native value;
  check_struct_native_batch raw_ml raw_mli native value;
  check_string_batch raw_ml raw_mli native value;
  check_mechanical_direct_batch raw_ml raw_mli native value;
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
  check_plan_provenance inputs.plan_root;
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
    ; first.public_enum_ml, second.public_enum_ml
    ; first.public_enum_mli, second.public_enum_mli
    ; first.public_enum_test, second.public_enum_test
    ; first.public_value_ml, second.public_value_ml
    ; first.public_value_mli, second.public_value_mli
    ; first.public_value_test, second.public_value_test
    ; first.public_global_ml, second.public_global_ml
    ; first.public_global_mli, second.public_global_mli
    ; first.public_global_test, second.public_global_test
    ; first.public_descriptor_ml, second.public_descriptor_ml
    ; first.public_descriptor_mli, second.public_descriptor_mli
    ; first.public_descriptor_test, second.public_descriptor_test
    ; first.native_descriptor_test, second.native_descriptor_test
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
    let stale_plan_root = Filename.concat directory "stale-plan-root" in
    copy_plan_sources ~source_root:inputs.plan_root
      ~destination_root:stale_plan_root
      ~mutate:"tools/metal/binding_plan_compute.ml";
    require_failure "binding-plan provenance test"
      "Metal inventory binding-plan provenance drift"
      (run inputs ~plan_root:stale_plan_root ~inventory:inputs.inventory
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
    let direct_signature_drift_inventory =
      Filename.concat directory "direct-signature-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field ~target:"method:-[MTLDevice peerCount]"
         ~field:"signature" (`String "instance () -> uint64_t")
    |> pretty_json |> write_file direct_signature_drift_inventory;
    require_failure "direct-call SDK signature drift test"
      "Metal inventory drift"
      (run inputs ~inventory:direct_signature_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "direct-signature-drift"));
    let direct_classification_drift_inventory =
      Filename.concat directory "direct-classification-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:"method:-[MTLTexture isFramebufferOnly]"
         ~field:"classification" (`String "availability-gated")
    |> pretty_json |> write_file direct_classification_drift_inventory;
    require_failure "direct-call classification drift test"
      "generated Metal direct-call classification must be bound"
      (run inputs ~inventory:direct_classification_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "direct-classification-drift"));
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
    let compute_getter_drift_inventory =
      Filename.concat directory "compute-getter-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:
           "method:-[MTLComputePipelineState staticThreadgroupMemoryLength]"
         ~field:"signature" (`String "instance () -> NSInteger")
    |> pretty_json |> write_file compute_getter_drift_inventory;
    require_failure "SDK compute-getter signature drift test"
      "Metal inventory drift"
      (run inputs ~inventory:compute_getter_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "compute-getter-drift"));
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
    let compute_property_drift_inventory =
      Filename.concat directory "compute-property-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:
           "property:MTLComputePipelineState:staticThreadgroupMemoryLength"
         ~field:"signature" (`String "NSInteger")
    |> pretty_json |> write_file compute_property_drift_inventory;
    require_failure "SDK compute companion-property drift test"
      "Metal inventory drift"
      (run inputs ~inventory:compute_property_drift_inventory
         ~manual_native:inputs.manual_native
         (outputs directory "compute-property-drift"));
    let enum_drift_inventory = Filename.concat directory "enum-drift.json" in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:"enum-case:MTLCullMode:MTLCullModeBack"
         ~field:"constant_value" (`String "7")
    |> pretty_json |> write_file enum_drift_inventory;
    require_failure "SDK enum-value drift test" "Metal enum-case value drift"
      (run inputs ~inventory:enum_drift_inventory
         ~manual_native:inputs.manual_native (outputs directory "enum-drift"));
    let mechanical_enum_classification_drift =
      Filename.concat directory "mechanical-enum-classification-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:
           "enum-case:MTLDeviceLocation:MTLDeviceLocationUnspecified"
         ~field:"classification" (`String "availability-gated")
    |> pretty_json |> write_file mechanical_enum_classification_drift;
    require_failure "mechanical enum classification drift test"
      "expected unreviewed, bound, or scope-excluded enum case"
      (run inputs ~inventory:mechanical_enum_classification_drift
         ~manual_native:inputs.manual_native
         (outputs directory "mechanical-enum-classification-drift"));
    let mechanical_enum_value_drift =
      Filename.concat directory "mechanical-enum-value-drift.json"
    in
    read_file inputs.inventory |> Yojson.Safe.from_string
    |> replace_symbol_field
         ~target:
           "enum-case:MTLDeviceLocation:MTLDeviceLocationUnspecified"
         ~field:"constant_value" (`String "18446744073709551616")
    |> pretty_json |> write_file mechanical_enum_value_drift;
    require_failure "mechanical enum uint64 overflow test" "out of range"
      (run inputs ~inventory:mechanical_enum_value_drift
         ~manual_native:inputs.manual_native
         (outputs directory "mechanical-enum-value-drift"));
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
       let test_metal4_compute_commands pipeline encoder =\n\
       \  ignore (Compute_pipeline.static_threadgroup_memory_length pipeline);\n\
       \  ignore\n\
       \    (Command4.Compute_encoder.set_threadgroup_memory_length encoder\n\
       \       ~index:0 ~length:16)\n\
       let test_device_info device = ignore (Device.info device)\n\
       let test_generated_device_capabilities device =\n\
       \  ignore (Device.capabilities device)\n\
       let run_generated_conformance encoder pipeline compute_encoder device =\n\
       \  test_metal4_raster_state_commands encoder;\n\
       \  test_metal4_compute_commands pipeline compute_encoder;\n\
       \  test_device_info device;\n\
       \  test_generated_device_capabilities device\n\
       let main () =\n\
       \  run_generated_conformance (Obj.magic ()) (Obj.magic ())\n\
       \    (Obj.magic ()) (Obj.magic ())\n\
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
