(** Packed, renderer-neutral retained 2D command segments. *)

type t
type segment = t

val fresh_id : unit -> int64

type stats = {
  command_capacity : int;
  command_length : int;
  high_water : int;
  growths : int;
}

module Builder : sig
  type t
  val create : ?capacity:int -> unit -> t
  val reserve : t -> int -> unit
  val reset : t -> unit
  val clear : t -> int32 -> unit
  val set_blend : t -> Render_ir.blend -> unit
  val solid_rect : t -> x:float -> y:float -> width:float -> height:float ->
    color:int32 -> unit
  val push_clip : t -> x:float -> y:float -> width:float -> height:float -> unit
  val pop_clip : t -> unit
  val push_transform : t -> Render_ir.transform -> unit
  val pop_transform : t -> unit
  val geometry : t -> Render_ir.geometry -> unit
  val image : t -> resource_id:int -> source:Render_ir.rect ->
    destination:Render_ir.rect -> unit
  val glyphs : t -> resource_id:int -> color:int32 -> Render_ir.glyph array ->
    unit
  val debug_text : t -> x:float -> y:float -> color:int32 -> string -> unit
  val publish : t -> id:int64 -> version:int64 ->
    (segment, Render_ir.error) result
  val stats : t -> stats
end

val id : t -> int64
val version : t -> int64
val source_bytes : t -> int
val render_ir : t -> Render_ir.t
