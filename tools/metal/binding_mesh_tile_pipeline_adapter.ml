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

let positive label value =
  if value > 0 then Ok () else Error (label ^ " must be positive")

let size label value =
  if value.width > 0 && value.height > 0 && value.depth > 0 then Ok ()
  else Error (label ^ " dimensions must be positive")

let ( let* ) value continuation = Result.bind value continuation

let validate_mesh descriptor =
  let* () =
    positive "max_total_threads_per_object_threadgroup"
      descriptor.max_total_threads_per_object_threadgroup
  in
  let* () =
    positive "max_total_threads_per_mesh_threadgroup"
      descriptor.max_total_threads_per_mesh_threadgroup
  in
  let* () =
    size "required_threads_per_mesh_threadgroup"
      descriptor.required_threads_per_mesh_threadgroup
  in
  let required = descriptor.required_threads_per_mesh_threadgroup in
  if
    required.width * required.height * required.depth
    > descriptor.max_total_threads_per_mesh_threadgroup
  then Error "required mesh threadgroup exceeds the declared maximum"
  else
    let* () = positive "raster_sample_count" descriptor.raster_sample_count in
    positive "max_vertex_amplification_count"
      descriptor.max_vertex_amplification_count

let validate_tile descriptor =
  let* () =
    positive "max_total_threads_per_threadgroup"
      descriptor.max_total_threads_per_threadgroup
  in
  let* () =
    size "required_threads_per_threadgroup"
      descriptor.required_threads_per_threadgroup
  in
  let required = descriptor.required_threads_per_threadgroup in
  if
    required.width * required.height * required.depth
    > descriptor.max_total_threads_per_threadgroup
  then Error "required tile threadgroup exceeds the declared maximum"
  else positive "raster_sample_count" descriptor.raster_sample_count
