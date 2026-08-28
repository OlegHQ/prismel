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
type auxiliary_resource = {
  key : string;
  buffer : bytes;
  texture : sampled_texture;
}

(** Packs a software shadow snapshot into a deterministic RGBA8 depth texture
    and a copied float32 parameter block. No backend allocation occurs here. *)
val shadow_resource : key:string -> Raster2.Shadow_map.snapshot ->
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
val destroy : t -> (unit, Ogpu.Error.t) result
