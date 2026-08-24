type descriptor_kind = Function | Stitched_library | Mesh_pipeline | Render_pipeline | Tile_pipeline
type owned = { token : int; device : int; destroyed : bool }
type descriptor = { owned : owned; kind : descriptor_kind }
type archive
val callable_ids : string list
val create : device:int -> archive
val add_function : archive -> descriptor:descriptor -> library:owned -> native_result:(unit, string) result -> (unit, string) result
val add_library : archive -> descriptor:descriptor -> native_result:(unit, string) result -> (unit, string) result
val add_mesh_pipeline : archive -> descriptor:descriptor -> native_result:(unit, string) result -> (unit, string) result
val add_render_pipeline : archive -> descriptor:descriptor -> native_result:(unit, string) result -> (unit, string) result
val add_tile_pipeline : archive -> descriptor:descriptor -> native_result:(unit, string) result -> (unit, string) result
val retained_tokens : archive -> int list
val destroy : archive -> unit
val validate_handoff : unit -> unit
