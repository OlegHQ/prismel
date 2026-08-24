let () =
  let ids = Binding_command_buffer19_safe_closure.callable_ids in
  if List.length ids <> 19 then failwith "CommandBuffer19 closure cardinality drift";
  if List.sort_uniq String.compare ids <> List.sort String.compare ids then
    failwith "CommandBuffer19 closure contains duplicates";
  let native = In_channel.with_open_text
      "tools/metal/test_command_buffer19_descriptor_lifecycle_native.mm"
      In_channel.input_all in
  let contains text needle =
    let n = String.length needle in
    let rec loop i = i + n <= String.length text &&
      (String.sub text i n = needle || loop (i + 1)) in
    loop 0 in
  List.iter (fun id ->
    if not (contains native (Printf.sprintf "\"%s\"" id))
    then failwith ("CommandBuffer19 native evidence missing " ^ id)) ids;
  print_endline "CommandBuffer19 exact19 safe closure: ok"
