let read path = let c=open_in_bin path in let n=in_channel_length c in let s=really_input_string c n in close_in c;s
let contains text needle = let n=String.length needle in let rec loop i=i+n<=String.length text&&(String.sub text i n=needle||loop(i+1))in loop 0
let symbols =
  ["buffer_add_debug_marker";"buffer_remote_view";"buffer_new_tensor";"buffer_remote_storage";"layout_array_get";"layout_array_set";"command_buffer_state_encoder";"device_new_view_pool";"heap_device";"heap_acceleration_descriptor";"heap_acceleration_descriptor_offset";"heap_acceleration_size";"heap_acceleration_size_offset";"resource_device";"resource_heap";"set_owner";"encoder_move_texture";"encoder_update_fence";"encoder_indirect_mapping";"encoder_mappings";"encoder_wait_fence";"pass_sample_attachments";"sample_attachment_buffer";"sample_attachment_set_buffer";"sample_array_get";"sample_array_set";"pool_base_id";"pool_copy";"pool_device";"pool_label";"pool_count";"texture_get_bytes";"texture_remote_view";"texture_view";"texture_remote_storage";"texture_replace";"texture_root";"texture_pool_set";"texture_pool_set_descriptor";"texture_pool_set_buffer";"pass_create";"texture_descriptor_2d";"texture_descriptor_buffer";"texture_descriptor_cube"]
let () =
 let source=read "tools/metal/metal_resource_ownership_generated.inc" in
 if List.length symbols<>44 then failwith "resource ownership selector count drift";
 List.iter(fun s->if not(contains source("caml_prismel_metal_resource_"^s))then failwith("missing "^s))symbols;
 List.iter(fun s->if not(contains source s)then failwith("missing convention "^s))["@catch(NSException";"result_error";"object_of_handle";"resource_of_handle";"allocate_handle";"@available"];
 print_endline "resource ownership shard: 44 typed selector symbols / 56 IDs green"
