type control
val create : ?device:Device.t -> ?layer:Metal.Metal_layer.t -> ?retained_plan_capacity:int -> unit -> Ogpu.Backend.driver * control
val register_pipeline : control -> Pipeline.t -> unit
val sampler_cache_entries : control -> int
val retained_plan_entries : control -> int
val retired_plan_entries : control -> int
val classic_submission_entries : control -> int
val classic_invalidator_entries : control -> int
type retained_plan_stats={builds:int64;hits:int64;misses:int64;evictions:int64;executions:int64;entries:int;capacity:int}
val retained_plan_stats : control -> retained_plan_stats
module Private : sig
  val disable_retained_plans_for_test : control -> unit
  val inject_next_active_queue_error : control -> unit
  val inject_next_active_queue_completion_error : control -> unit
end
