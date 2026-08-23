let fail format = Printf.ksprintf failwith format

let contains haystack needle =
  let rec loop offset =
    offset + String.length needle <= String.length haystack
    && (String.sub haystack offset (String.length needle) = needle
       || loop (offset + 1))
  in
  loop 0

let () =
  let entries = Binding_global_string_spec.entries in
  if List.length entries <> Binding_global_string_spec.expected_count then
    fail "expected %d global strings, got %d"
      Binding_global_string_spec.expected_count (List.length entries);
  let ids = List.map (fun entry -> entry.Binding_global_string_spec.sdk_id) entries in
  if List.length (List.sort_uniq String.compare ids) <> List.length ids then
    fail "duplicate Metal global string inventory ID";
  let raw = Binding_global_string_codegen.render_raw_ml entries in
  let native = Binding_global_string_codegen.render_native entries in
  let safe_ml = Binding_global_string_codegen.render_safe_ml entries in
  let safe_mli = Binding_global_string_codegen.render_safe_mli entries in
  [ "generated_global_mtl_command_buffer_error_domain"
  ; "generated_global_mtl_common_counter_timestamp"
  ; "generated_global_mtl_device_was_added_notification"
  ; "generated_global_mtl_tensor_domain"
  ]
  |> List.iter (fun symbol ->
         if not (contains raw symbol) then fail "missing raw global %s" symbol;
         if not (contains native ("caml_prismel_metal_" ^ symbol)) then
           fail "missing native global %s" symbol);
  [ "std::is_same_v<decltype(MTLCommandBufferErrorDomain), NSErrorDomain const>"
  ; "std::is_same_v<decltype(MTLCommonCounterTimestamp), MTLCommonCounter const>"
  ; "std::is_same_v<decltype(MTLDeviceWasAddedNotification), MTLDeviceNotificationName const>"
  ; "@available(macOS 10.11, *)"
  ; "@available(macOS 26.4, *)"
  ; "caml_copy_string(native_value.UTF8String)"
  ]
  |> List.iter (fun golden ->
         if not (contains native golden) then fail "missing native golden: %s" golden);
  [ "objc_msgSend"; "performSelector"; "valueForKey" ]
  |> List.iter (fun forbidden ->
         if contains native forbidden then fail "dynamic dispatch emitted: %s" forbidden);
  if not (contains safe_ml "let mtl_common_counter_timestamp ()") then
    fail "safe implementation missing counter";
  if not (contains safe_mli "val mtl_common_counter_timestamp") then
    fail "safe signature missing counter";
  Printf.printf "Metal global NSString codegen: %d safe copied constants\n"
    (List.length entries)
