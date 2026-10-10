(** Owned bulk functions supplied by a language host. Packed columns are borrowed
    immutable inputs; the result owns its storage. *)
type column = Floats of float array | Vec3s of float array
type runner = Context.t -> (column, Diagnostic.error) result
type t
val create : payload_bytes:int -> (column list -> (runner, Diagnostic.error) result) -> t
val data_id : t -> int
val payload_bytes : t -> int
val prepare : t -> column list -> (runner, Diagnostic.error) result
