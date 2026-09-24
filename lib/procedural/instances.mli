(** Immutable procedural render instances. The prototype remains a normal SOP
    node; transforms are retained separately so editable topology is not
    multiplied until an explicit future materialization boundary. *)

type t

val create : ?transforms:Prismel.Mat4.t array -> Node.t -> t
val source : t -> Node.t
val count : t -> int
val transforms : t -> Prismel.Mat4.t array
val payload_bytes : t -> int

val transform : Prismel.Mat4.t -> t -> t
(** Left-compose one transform onto every instance. *)

val duplicate :
  ?copies:int -> ?cumulative:bool -> ?transform:Prismel.Mat4.t -> t -> t
(** Append transformed instance copies in source-instance-major order. Copy
    [i] is transformed by [transform] to power [i] in world space. *)

module Private : sig
  val scene3 :
    ?material:Prismel.Material.t ->
    ?texture:Prismel.Scene3.texture ->
    ?shader:Prismel.Shader3.t ->
    ?mode:Prismel.Scene3.render_mode ->
    ?cull:Prismel.Scene3.cull ->
    ?shading:Prismel.Scene3.shading ->
    Prismel.Mesh.t -> t -> Prismel.Scene3.node
end
