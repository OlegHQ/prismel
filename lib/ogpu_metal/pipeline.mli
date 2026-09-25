type t

(** A compute pipeline for one entry point of a shared library, specialized
    with function constants; [interface] is checked exactly against Metal
    reflection. The caller owns it (no cache). *)
val create_compute_from_library : ?linked:string list -> ?archives:Metal.Binary_archive.t list -> ?archive_only:bool -> Device.t -> Library.t -> entry:string ->
  constants:(string * Ogpu_core.Shader.constant_value) list ->
  interface:Ogpu_core.Shader.binding list -> (t,Ogpu_core.Error.t) result
val create_render_owned : ?indirect:bool -> ?primitive_topology:Metal.Render_pipeline.primitive_topology -> ?blend:Ogpu_core.Pipeline.blend -> Device.t -> Ogpu_core.Pipeline.render_descriptor -> (t,Ogpu_core.Error.t) result
val create_mesh : ?label:string -> ?blend:Ogpu_core.Pipeline.blend -> archives:Metal.Binary_archive.t list -> archive_only:bool -> Device.t -> Library.t ->
  object_entry:string option -> mesh_entry:string -> fragment_entry:string -> color:Ogpu_core.Pipeline.color_format ->
  mesh_threads:int * int * int -> object_threads:(int * int * int) option -> (t,Ogpu_core.Error.t) result
val create_tile : ?label:string -> archives:Metal.Binary_archive.t list -> archive_only:bool -> Device.t -> Library.t ->
  tile_entry:string -> color:Ogpu_core.Pipeline.color_format -> tile_threads:int * int * int -> (t,Ogpu_core.Error.t) result
val key : t -> string
val label : t -> string option
val device_id : t -> int64
val generation : t -> int64
val destroyed : t -> bool
val validate : Device.t -> t -> (unit,Ogpu_core.Error.t) result
val destroy : t -> (unit,Ogpu_core.Error.t) result

module Private : sig
  type native = Compute of Metal.Compute_pipeline.t | Render of Metal.Render_pipeline.t
  val native : t -> native
  val functions : t -> Metal.Function.t list
  val portable : t -> Ogpu_core.Pipeline.t
  val native_identity : t -> int64 * int64
  val argument_encoder : t -> buffer_index:int64 -> (Metal.Shader_argument_encoder.t,Ogpu_core.Error.t) result
  val argument_function : t -> Metal.Function.t option
  val linked_function : t -> string -> Metal.Function.t option
  val retain_submission : t -> (unit,Ogpu_core.Error.t) result
  val release_submission : t -> unit
end
