type size = { width : int; height : int; depth : int }

type 'function_ mesh =
  { label : string option
  ; object_function : 'function_ option
  ; mesh_function : 'function_
  ; fragment_function : 'function_ option
  ; max_total_threads_per_object_threadgroup : int
  ; max_total_threads_per_mesh_threadgroup : int
  ; required_threads_per_mesh_threadgroup : size
  ; raster_sample_count : int
  ; alpha_to_coverage_enabled : bool
  ; alpha_to_one_enabled : bool
  ; rasterization_enabled : bool
  ; max_vertex_amplification_count : int
  }

type 'function_ tile =
  { label : string option
  ; tile_function : 'function_
  ; raster_sample_count : int
  ; threadgroup_size_matches_tile_size : bool
  ; max_total_threads_per_threadgroup : int
  ; required_threads_per_threadgroup : size
  }

val validate_mesh : 'a mesh -> (unit, string) result
val validate_tile : 'a tile -> (unit, string) result
