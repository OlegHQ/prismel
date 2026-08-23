let fail format = Printf.ksprintf failwith format

let contains haystack needle =
  let rec loop offset =
    offset + String.length needle <= String.length haystack
    && (String.sub haystack offset (String.length needle) = needle
       || loop (offset + 1))
  in
  loop 0

let () =
  let entries = Binding_string_codegen.qualified_entries () in
  let ids = List.concat_map Binding_string_spec.inventory_ids entries in
  if List.length entries <> 5 then fail "expected 5 qualified properties";
  if List.length ids <> 13 then fail "expected 13 qualified inventory IDs";
  let raw_ml = Binding_string_codegen.render_raw_ml entries in
  let raw_mli = Binding_string_codegen.render_raw_mli entries in
  let raw_body = Binding_string_codegen.render_raw_body entries in
  let native = Binding_string_codegen.render_native entries in
  if not (String.equal raw_ml raw_mli) then fail "raw ML/MLI signature drift";
  if contains raw_body "module Make" then fail "raw insertion body contains wrapper";
  [ "generated_mtl4_binary_function_name_get"
  ; "generated_mtl_command_queue_label_get"
  ; "generated_mtl_command_queue_label_set"
  ; "generated_mtl_command_encoder_label_get"
  ; "generated_mtl_command_encoder_label_set"
  ; "generated_mtl_function_handle_name_get"
  ; "generated_mtl_fence_label_get"
  ; "generated_mtl_fence_label_set"
  ]
  |> List.iter (fun symbol ->
         if not (contains raw_ml symbol) then
           fail "missing raw symbol %s in:\n%s" symbol raw_ml;
         if not (contains native ("caml_prismel_metal_" ^ symbol)) then
           fail "missing native symbol %s" symbol);
  [ "id<MTL4BinaryFunction> binary_function"
  ; "id<MTLCommandQueue> command_queue"
  ; "id<MTLCommandEncoder> command_encoder"
  ; "id<MTLFunctionHandle> function_handle"
  ; "id<MTLFence> fence"
  ; "[binary_function name]"
  ; "[command_queue label]"
  ; "[command_queue setLabel:native_value]"
  ; "command_encoder_of_handle(raw_receiver)"
  ; "[command_encoder label]"
  ; "[command_encoder setLabel:native_value]"
  ; "[function_handle name]"
  ; "[fence label]"
  ; "copy_optional_string(native_result)"
  ; "raw_value == Val_none ? nil : string_from_ocaml(Field(raw_value, 0))"
  ; "@available(macOS 26.0, *)"
  ; "@available(macOS 10.11, *)"
  ]
  |> List.iter (fun golden ->
         if not (contains native golden) then fail "missing native golden: %s" golden);
  [ "objc_msgSend"; "performSelector"; "valueForKey" ]
  |> List.iter (fun forbidden ->
         if contains native forbidden then fail "dynamic dispatch emitted: %s" forbidden);
  Printf.printf "Metal NSString codegen: %d qualified properties, %d inventory IDs\n"
    (List.length entries) (List.length ids)
