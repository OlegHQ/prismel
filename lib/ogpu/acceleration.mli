type buffer_range = { buffer:unit Handle.t; buffer_size:int64; offset:int64; length:int64 }
type geometry =
  | Triangles of { vertices:buffer_range; vertex_stride:int; vertex_count:int }
  | Bounding_boxes of { boxes:buffer_range; stride:int; count:int }
  | Curves of { control_points:buffer_range; radii:buffer_range; control_point_count:int }
  | Motion of { keyframes:int; geometry:geometry }
type descriptor = Blas of { geometries:geometry array; allow_refit:bool } | Tlas of { instances:buffer_range; instance_stride:int; instance_count:int; allow_refit:bool }
type t
type description = Build of int64 | Refit of int64 | Copy of {source:int64;destination:int64} | Compact of int64
val create : Handle.device -> ray_tracing:bool -> descriptor -> (t,Error.t) result
val build : Handle.device -> t -> (description,Error.t) result
val refit : Handle.device -> t -> (description,Error.t) result
val copy : Handle.device -> t -> (t * description,Error.t) result
val compact : Handle.device -> t -> (description,Error.t) result
val destroy : t -> unit
val id : t -> int64
