type t
type mesh = {
  key : string;
  vertices : bytes;
  vertex_count : int;
  indices : bytes;
  index_count : int;
}
type state = {
  viewport : int * int * int * int;
  scissor : int * int * int * int;
  cull : Ogpu.Render_pass.cull;
  depth_compare : Ogpu.Render_pass.comparison;
  depth_write : bool;
  depth_load : Ogpu.Render_pass.load;
  depth_clear : float;
  transform_uniforms : bytes option;
  stencil_state : Ogpu.Render_pass.stencil_state option;
  stencil_load : Ogpu.Render_pass.load;
  stencil_clear : int;
}
type draw = { mesh : mesh; state : state }
type pipeline_family = Scene2 | Scene2_textured | Scene3 | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil
(** Exact number of family/blend variants required for each supported sample
    count. Cache owners use this value so adding a family cannot silently
    evict a still-live pipeline during renderer construction. *)
val pipeline_variants_per_sample : int
type texture_level = { width:int; height:int; bytes:bytes }
type sampled_texture = {
  key:string;
  levels:texture_level array;
  sampler:Ogpu.Types.sampler_descriptor;
}
type shadow_resource = {
  texture : sampled_texture;
  parameters : bytes;
}
type shadow_kernel = Tap1 | Tap4 | Tap9 | Tap25
type shadow_bias = { constant : float; slope : float }
type shadow_snapshot = {
  width : int;
  height : int;
  depths : float array;
  matrix : float array;
  bias : shadow_bias;
  kernel : shadow_kernel;
  strength : float;
}

(** Renderer-neutral values accepted by the native Scene2 lowering boundary.
    This is a command vocabulary, not a rasterizer or an execution API. *)
module Scene2_command : sig
  type rect = { x : float; y : float; width : float; height : float }
  type transform = {
    xx : float; xy : float; yx : float; yy : float; tx : float; ty : float;
  }
  type geometry = { vertices : float array; indices : int array; color : int32 }
  type debug_text = { x : float; y : float; text : string; color : int32 }
  type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
  type t =
    | Clear of int32
    | Set_blend of blend
    | Push_clip of rect
    | Pop_clip
    | Push_transform of transform
    | Pop_transform
    | Geometry of geometry
    | Debug_text of debug_text
end
type auxiliary_resource = {
  key : string;
  buffer : bytes;
  texture : sampled_texture;
}

(** Packs a renderer-neutral shadow snapshot into a deterministic RGBA8 depth texture
    and a copied float32 parameter block. No backend allocation occurs here. *)
val shadow_resource : key:string -> shadow_snapshot ->
  (shadow_resource, Ogpu.Error.t) result

val create : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  (t, Ogpu.Error.t) result
val create_variants : ?canonical_scene2_argument:bool -> Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  (t, Ogpu.Error.t) result
val create_with_pipeline : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  ?before_device_destroy:(unit -> (unit, Ogpu.Error.t) result) ->
  (Ogpu.Backend.device -> (Ogpu.Pipeline.t, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result
val create_with_pipeline_variants : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  ?before_device_destroy:(unit -> (unit, Ogpu.Error.t) result) ->
  (Ogpu.Backend.device -> pipeline_family -> Ogpu.Pipeline.blend ->
    (Ogpu.Pipeline.t, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result
val create_with_sampled_pipeline_variants : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  ?before_device_destroy:(unit -> (unit, Ogpu.Error.t) result) ->
  ?canonical_scene2_argument:bool ->
  (Ogpu.Backend.device -> pipeline_family -> Ogpu.Pipeline.blend -> int ->
    (Ogpu.Pipeline.t, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t -> draw list ->
  (bool, Ogpu.Error.t) result
val render_blended : ?clear:(float * float * float * float) -> t ->
  (Ogpu.Pipeline.blend * draw) list -> (bool, Ogpu.Error.t) result
val render_family : ?clear:(float * float * float * float) -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * draw) list ->
  (bool, Ogpu.Error.t) result
val render_textured : ?clear:(float * float * float * float) -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * sampled_texture option * draw) list ->
  (bool, Ogpu.Error.t) result
val render_resources : ?clear:(float * float * float * float) -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * sampled_texture option *
    auxiliary_resource option * draw) list ->
  (bool, Ogpu.Error.t) result
val render_sampled_resources : ?clear:(float * float * float * float) -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * sampled_texture option *
    auxiliary_resource option * int * draw) list ->
  (bool, Ogpu.Error.t) result
val render_prepared_sampled_resources :
  ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * sampled_texture option *
    auxiliary_resource option * int * draw) list ->
  (bool, Ogpu.Error.t) result
val resize : t -> Ogpu.Surface.configuration -> (unit, Ogpu.Error.t) result
val upload_bytes : t -> int64
val cache_entries : t -> int
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val read_pixels_into : t -> bytes_per_row:int -> destination:bytes ->
  (unit, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
