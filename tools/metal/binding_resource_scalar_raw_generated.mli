module Make (Types : sig type handle end) : sig
  val buffer_remove_all_debug_markers : Types.handle -> (unit,string) result
  val device_sparse_tile_size : Types.handle -> int64 -> int64 -> int64 -> ((int64*int64*int64),string) result
  val heap_resource_options : Types.handle -> (int64,string) result
  val resource_allocated_size : Types.handle -> (int64,string) result
  val resource_options : Types.handle -> (int64,string) result
  val texture_framebuffer_only : Types.handle -> (bool,string) result
end
