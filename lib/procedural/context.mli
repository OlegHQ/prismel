(** Target-neutral facts available while cooking a procedural graph. *)

module Cancel = Pdk.Cancel

module Dependencies : sig
  type fact = Frame | Time | Seed | Domains | Grain
  type t

  val static : t
  val one : fact -> t
  val of_list : fact list -> t
  val union : t -> t -> t
  val mem : fact -> t -> bool
  val to_list : t -> fact list
  val to_string : t -> string
end

type t

val create :
  ?frame:int64 ->
  ?time:float ->
  ?seed:int64 ->
  ?domains:int ->
  ?grain:int ->
  ?cancel:Cancel.t ->
  unit ->
  (t, string) result

val of_frame :
  ?seed:int64 -> ?domains:int -> ?grain:int -> Prismel.Frame.t ->
  (t, string) result
(** Copy target-neutral timing facts from a Prismel frame. No canvas,
    renderer, input resource, or backend handle is retained. *)

val frame : t -> int64
val time : t -> float
val seed : t -> int64
val domains : t -> int
val grain : t -> int
val cancel_token : t -> Cancel.t
val cancelled : t -> bool

(** Exact cache-key projection for the declared facts. Static dependencies
    always return the same projection, independent of the context. *)
val cache_projection : Dependencies.t -> t -> string
