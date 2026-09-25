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

val minimum_m1 : t
val validate : t -> (unit, Error.t) result
val create : t -> timestamp_queries:bool -> sparse_memory:bool ->
  conservative_limits:string list -> (t, Error.t) result
val has : t -> feature -> bool
val require : ?operation:string -> t -> feature -> (unit, Error.t) result
