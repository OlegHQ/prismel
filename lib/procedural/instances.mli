(** Immutable procedural render instances. The prototype remains a normal SOP
    node; transforms are retained separately so editable topology is not
    multiplied until an explicit future materialization boundary. *)

type t

val create : ?transforms:Prismel_math.Mat4.t array -> Node.t -> t
val source : t -> Node.t
val count : t -> int
val transforms : t -> Prismel_math.Mat4.t array
val payload_bytes : t -> int

val transform : Prismel_math.Mat4.t -> t -> t
(** Left-compose one transform onto every instance. *)

val duplicate :
  ?copies:int -> ?cumulative:bool -> ?transform:Prismel_math.Mat4.t -> t -> t
(** Append transformed instance copies in source-instance-major order. Copy
    [i] is transformed by [transform] to power [i] in world space. *)
