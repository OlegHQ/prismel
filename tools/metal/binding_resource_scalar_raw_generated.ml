module Make (Types : sig type handle end) = struct
  external buffer_remove_all_debug_markers : Types.handle -> (unit,string) result = "caml_prismel_metal_generated_buffer_remove_all_debug_markers"
  external device_sparse_tile_size : Types.handle -> int64 -> int64 -> int64 -> ((int64*int64*int64),string) result = "caml_prismel_metal_generated_device_sparse_tile_size"
  external heap_resource_options : Types.handle -> (int64,string) result = "caml_prismel_metal_generated_heap_resource_options"
  external resource_allocated_size : Types.handle -> (int64,string) result = "caml_prismel_metal_generated_resource_allocated_size"
  external resource_options : Types.handle -> (int64,string) result = "caml_prismel_metal_generated_resource_options"
  external texture_framebuffer_only : Types.handle -> (bool,string) result = "caml_prismel_metal_generated_texture_framebuffer_only"
end
