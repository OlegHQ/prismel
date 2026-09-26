type t
val device : t -> Ogpu.Backend.device
val queue : t -> Ogpu.Backend.queue

(** The owned RGBA8 texture every submission renders into; a shared-device
    renderer's callers may sample it directly between completed submissions. *)
val target : t -> Ogpu.Backend.texture
type mesh = {
  key : string;
  vertices : bytes;
  vertex_count : int;
  indices : bytes;
  index_count : int;
  primitive : Ogpu.Render_pass.primitive;
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
type pipeline_family = Scene2 | Scene2_textured | Scene3 | Scene3_points | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil | Ui
(** Exact number of family/blend variants required for each supported sample
    count. Cache owners use this value so adding a family cannot silently
    evict a still-live pipeline during renderer construction. *)
val pipeline_variants_per_sample : int
type texture_level = { width:int; height:int; bytes:bytes }
type sampled_texture = {
  key:string;
  levels:texture_level array;
  sampler:Ogpu.Types.sampler_descriptor;
  gpu:Ogpu.Backend.texture option;
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

type auxiliary_resource = {
  key : string;
  buffer : bytes;
  texture : sampled_texture;
}

type sampled_draw = {
  family : pipeline_family;
  blend : Ogpu.Pipeline.blend;
  texture : sampled_texture option;
  auxiliary : auxiliary_resource option;
  samples : int;
  draw : draw;
}
type scene3_entry = sampled_draw
type prepared_scene3 = {
  clear : float * float * float * float;
  clear_depth : float;
  clear_stencil : int;
  entries : scene3_entry array;
}

(** Validates and copies a native Scene3 submission description. Nested byte
    resources remain borrowed and must be retained by the staging owner. *)
val prepare_scene3 : clear:(float * float * float * float) ->
  clear_depth:float -> clear_stencil:int -> scene3_entry array ->
  (prepared_scene3, Ogpu.Error.t) result

(** Packs a renderer-neutral shadow snapshot into a deterministic RGBA8 depth texture
    and a copied float32 parameter block. No backend allocation occurs here. *)
val shadow_resource : key:string -> shadow_snapshot ->
  (shadow_resource, Ogpu.Error.t) result

(** Creates a renderer with one pipeline per family, blend, and supported
    sample count. The factory receives the renderer's device and returns owned
    OGPU render pipelines (see [Ogpu.Backend.create_render_pipeline]); the
    renderer destroys them. Scene2 and Scene2_textured draws both run through
    the Scene2_textured pipeline, which binds its texture and sampler through a
    fragment argument buffer at index 1 and must be created with
    [~indirect:true].

    With [~offscreen:true] the renderer owns a texture target without creating,
    acquiring, or presenting a platform surface. Submissions complete before
    the call returns, so exact readback and explicit destruction have the same
    contract as surface-backed execution. With [?device], the renderer borrows
    that device (the driver is unused) and never destroys it, so a Canvas can
    share the presenting window's GPU. *)
val create : ?device:Ogpu.Backend.device -> offscreen:bool ->
  Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  (Ogpu.Backend.device -> pipeline_family -> Ogpu.Pipeline.blend -> int ->
    (Ogpu.Backend.pipeline, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result

val render : ?clear:(float * float * float * float) -> t -> draw list ->
  (bool, Ogpu.Error.t) result
val render_sampled_resources : ?after_prepare:(unit -> unit) -> ?clear:(float * float * float * float) -> t ->
  sampled_draw list ->
  (bool, Ogpu.Error.t) result
val render_prepared_sampled_resources :
  ?after_prepare:(unit -> unit) -> ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  sampled_draw list ->
  (bool, Ogpu.Error.t) result
val replay_prepared_sampled_resources :
  ?clear:(float * float * float * float) -> identity:string -> version:int64 -> t ->
  ((bool * int) option, Ogpu.Error.t) result
val resize : t -> Ogpu.Surface.configuration -> (unit, Ogpu.Error.t) result
val upload_bytes : t -> int64
module Private : sig
  val cache_count_for_report : t -> int
end

(** Indirect-command replay plans: one automatic plan admitted after two
    identical frames and one identity-keyed prepared plan. [plan_entries]
    counts the live indirect command buffers across both. *)
type retained_stats = { plan_builds:int64; plan_hits:int64; plan_misses:int64; plan_evictions:int64;
  plan_executions:int64; plan_failures:int64; plan_last_failure:string option; plan_entries:int; plan_capacity:int }
val retained_stats : t -> retained_stats
val pipeline_count : t -> int
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val read_pixels_into : t -> bytes_per_row:int -> destination:bytes ->
  (unit, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
