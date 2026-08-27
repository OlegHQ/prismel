type t
val create : unit -> t
val copy_buffer : t -> source:Buffer.t -> source_offset:int64 ->
  destination:Buffer.t -> destination_offset:int64 -> length:int64 ->
  (unit,Ogpu.Error.t) result
val compute : t -> source:string -> entry:string -> buffer:Buffer.t ->
  threads:int -> (unit,Ogpu.Error.t) result
val clear : t -> Texture.t -> color:float*float*float*float -> (unit,Ogpu.Error.t) result
val end_ : t -> (unit,Ogpu.Error.t) result
val descriptions : t -> Ogpu.Command.description array

module Private : sig
  type operation =
    | Copy of Buffer.t*int64*Buffer.t*int64*int64
    | Compute of string*string*Buffer.t*int
    | Clear of Texture.t*(float*float*float*float)
  val portable : t -> Ogpu.Command.t
  val operations : t -> operation list
end
