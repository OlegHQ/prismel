let expected =
  [ "caml_prismel_metal_generated_buffer_remove_all_debug_markers"
  ; "caml_prismel_metal_generated_device_sparse_tile_size"
  ; "caml_prismel_metal_generated_heap_resource_options"
  ; "caml_prismel_metal_generated_resource_allocated_size"
  ; "caml_prismel_metal_generated_resource_options"
  ; "caml_prismel_metal_generated_texture_framebuffer_only" ]
let () =
  if List.length (List.sort_uniq String.compare expected)<>6 then failwith "symbol collision";
  print_endline "resource existing-handle scalar wrappers: 6 callable methods / 10 inventory IDs"
