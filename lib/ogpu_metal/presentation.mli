type t
type render_result = Completed | Committed_with_error of Ogpu.Error.t

val create : Device.t -> (t, Ogpu.Error.t) result

(** [encode_classic value commands ~source ~target] appends the presentation
    render pass to a caller-owned classic command buffer.  The command buffer
    is never committed or destroyed here. *)
val encode_classic :
  t -> Metal.Command_buffer.t -> ?present:Metal.Drawable.t ->
  source:Metal.Texture.t -> target:Metal.Texture.t -> unit ->
  (unit, Ogpu.Error.t) result

(** [render value ~source ~target] performs a synchronous GPU-only, one-to-one
    presentation draw.  It accepts only a single-sample RGBA8 shader-readable
    source and an equally sized single-sample BGRA8 render target. *)
val render :
  t -> queue:Metal.Command_queue.t -> ?present:Metal.Drawable.t ->
  ?on_commit:(unit -> unit) ->
  source:Metal.Texture.t ->
  target:Metal.Texture.t -> unit ->
  (render_result, Ogpu.Error.t) result

val copy :
  t -> queue:Metal.Command_queue.t -> source:Metal.Texture.t ->
  target:Metal.Texture.t ->
  (unit, Ogpu.Error.t) result

val destroy : t -> unit
