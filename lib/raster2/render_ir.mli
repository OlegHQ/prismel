(** Immutable backend-neutral software-rendering command streams. *)
type rect = { x:float; y:float; width:float; height:float }
type transform = { xx:float; xy:float; yx:float; yy:float; tx:float; ty:float }
type geometry = { vertices:float array; indices:int array; color:int32 }
type image = { resource_id:int; source:rect; destination:rect }
type glyph = { glyph_id:int; x:float; y:float }
type glyphs = { resource_id:int; color:int32; glyphs:glyph array }
type debug_text = { x:float; y:float; text:string; color:int32 }
type command = Clear of int32 | Set_blend of Composite.blend | Push_clip of rect | Pop_clip | Push_transform of transform | Pop_transform | Geometry of geometry | Image of image | Glyphs of glyphs | Debug_text of debug_text
type batch_kind = State | Geometry_batch of int32 | Image_batch of int | Glyph_batch of int | Debug_text_batch of int32
type batch = { first:int; count:int; kind:batch_kind }
type t
type error = Non_finite | Invalid_extent | Invalid_cardinality | Invalid_index of int | Invalid_resource_id of int | Invalid_glyph_id of int | Invalid_debug_text | Unbalanced_clip | Unbalanced_transform | Complexity_limit
val create : command array -> (t,error) result
val commands : t -> command array
val batches : t -> batch array
module Private : sig
  (** Borrowed validated command storage for synchronous audited consumers.
      The returned array and every nested payload must be treated as read-only
      and must not escape the dynamic extent of the consuming operation. *)
  val commands_readonly : t -> command array
  (* Validates and takes ownership of a freshly allocated command graph. The
     caller must retain no mutable aliases to arrays nested in [input]. *)
  val create_owned : command array -> (t,error) result
end
(* Stable, explicitly little-endian, versioned encoding. *)
val serialize : t -> bytes
val hash : t -> int64
