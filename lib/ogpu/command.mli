type pass = Transfer | Render | Compute | Acceleration
type access = Read | Write | Read_write
type stage = Transfer_stage | Vertex | Fragment | Compute_stage | Acceleration_stage
type resource_access = { resource_id:int64; access:access; stages:stage list }
type description =
  | Begin_encoder | Begin_pass of pass | End_pass of pass
  | Push_debug of string | Pop_debug
  | Declare_resource of resource_access | End_encoder | Present
type t
val begin_encoder : unit -> t
val begin_pass : t -> pass -> (unit,Error.t) result
val end_pass : t -> (unit,Error.t) result
val push_debug : t -> string -> (unit,Error.t) result
val pop_debug : t -> (unit,Error.t) result
val declare_resource : t -> resource_id:int64 -> access:access -> stages:stage list -> (unit,Error.t) result
val end_encoder : t -> (unit,Error.t) result
val present : t -> (unit,Error.t) result
val descriptions : t -> description array
