type feature = Buffer | Texture | Sampler | Compute_pipeline | Render_pipeline
  | Queue | Surface | Memory | Event_synchronization
  | Timeline_fence | Timestamp_queries | Ray_tracing | Ray_tracing_curves | Function_tables | Metal_fx | Sparse_memory
  | Heaps | Residency_sets | Fences
  | Mesh_shaders | Tile_shaders | Dynamic_libraries | Binary_archives
  | Unknown of string

type limits =
  { max_buffer_size : int64
  ; max_texture_dimension_2d : int
  ; max_bind_groups : int
  ; max_sample_count : int
  }

type t =
  { limits : limits
  ; compute_pipeline : bool
  ; render_pipeline : bool
  ; ray_tracing : bool
  ; function_tables : bool
  ; ray_tracing_curves : bool
  ; metal_fx : bool
  ; timestamp_queries : bool
  ; sparse_memory : bool
  ; heaps : bool  (** Placement heaps whose resources may alias. *)
  ; residency_sets : bool
  ; fences : bool  (** Intra-queue fences between encoders. *)
  ; event_synchronization : bool  (** Host-visible timeline events. *)
  ; mesh_shaders : bool  (** Object/mesh pipelines drawn by threadgroups. *)
  ; tile_shaders : bool  (** Tile pipelines dispatched inside a render pass. *)
  ; dynamic_libraries : bool
  ; binary_archives : bool
  ; conservative_limits : string list
  }

let minimum_m1 =
  { limits = { max_buffer_size = 268_435_456L
             ; max_texture_dimension_2d = 16_384
             ; max_bind_groups = 4
             ; max_sample_count = 4 }
  ; compute_pipeline = true; render_pipeline = true; ray_tracing = false; function_tables = false; ray_tracing_curves = false; metal_fx = false
  ; timestamp_queries = false; sparse_memory = false; heaps = false; residency_sets = false; fences = false
  ; event_synchronization = false; mesh_shaders = false; tile_shaders = false; dynamic_libraries = false
  ; binary_archives = false; conservative_limits = [] }

let validate value =
  let limits = value.limits in
  if limits.max_buffer_size <= 0L || limits.max_texture_dimension_2d <= 0
     || limits.max_bind_groups <= 0 || limits.max_sample_count <= 0 then
    Error (Error.make "Ogpu.Caps.validate" Error.Invalid_argument
      "limits must be positive")
  else Ok ()

let create value ~timestamp_queries ~sparse_memory ~conservative_limits =
  Result.map (fun () ->
    { value with timestamp_queries; sparse_memory; conservative_limits })
    (validate value)

let has value = function
  | Buffer | Texture | Sampler | Queue
  | Surface | Memory -> true
  | Event_synchronization -> value.event_synchronization
  | Heaps -> value.heaps
  | Residency_sets -> value.residency_sets
  | Fences -> value.fences
  | Mesh_shaders -> value.mesh_shaders
  | Tile_shaders -> value.tile_shaders
  | Dynamic_libraries -> value.dynamic_libraries
  | Binary_archives -> value.binary_archives
  | Compute_pipeline -> value.compute_pipeline
  | Render_pipeline -> value.render_pipeline
  | Timeline_fence -> false
  | Timestamp_queries -> value.timestamp_queries
  | Ray_tracing -> value.ray_tracing
  | Function_tables -> value.function_tables
  | Ray_tracing_curves -> value.ray_tracing_curves
  | Metal_fx -> value.metal_fx
  | Sparse_memory -> value.sparse_memory
  | Unknown _ -> false

let require ?(operation="Ogpu.Caps.require") value feature =
  if has value feature then Ok ()
  else Error (Error.make operation Error.Unsupported
    "operation is unavailable on this adapter profile")
