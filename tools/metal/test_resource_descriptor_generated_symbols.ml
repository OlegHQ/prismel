let read path = let channel=open_in_bin path in let length=in_channel_length channel in let value=really_input_string channel length in close_in channel;value
let contains text needle =
  let n=String.length needle in let rec loop i=i+n<=String.length text&&(String.sub text i n=needle||loop(i+1)) in loop 0
let () =
  if Array.length Sys.argv <> 2 then failwith "expected generated descriptor include";
  let source=read Sys.argv.(1) in
  let symbols=
    [ "buffer_layout_create"; "buffer_layout_stride"; "buffer_layout_set_stride"
    ; "buffer_layout_step_rate"; "buffer_layout_set_step_rate"; "buffer_layout_step_function"
    ; "buffer_layout_set_step_function"; "sample_attachment_create"; "sample_attachment_start"
    ; "sample_attachment_set_start"; "sample_attachment_end"; "sample_attachment_set_end"
    ; "view_pool_descriptor_create"; "view_pool_descriptor_count"
    ; "view_pool_descriptor_set_count"; "view_pool_descriptor_label"
    ; "view_pool_descriptor_set_label" ]
  in
  List.iter(fun symbol->let full="caml_prismel_metal_resource_"^symbol in if not(contains source full)then failwith("missing symbol "^full))symbols;
  List.iter(fun needle->if not(contains source needle)then failwith("missing unwind/root convention "^needle))
    ["CAMLparam";"CAMLlocal";"@catch(NSException";"result_error";"object_of_handle";"allocate_handle"];
  Printf.printf "resource descriptor shard: %d callable symbols with roots/unwind conventions green\n" (List.length symbols)
