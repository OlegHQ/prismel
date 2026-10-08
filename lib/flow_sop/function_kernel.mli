(** Language-owned compiled bulk functions behind the Procedural payload boundary. *)
val node : ?state:Flow.Eval.state -> ?reference:bool ->
  ?elems:(string * Flow.Eval.value) list ->
  identity:int -> signature:Flow.Ty.fn_signature -> fn:Flow.Eval.fn ->
  sources:int list -> Procedural.Node.t list -> Procedural.Node.t
