type control
val create : ?device:Device.t -> ?layer:Metal.Metal_layer.t ->
  ?retained_plan_capacity:int -> ?retained_plan_owner_byte_capacity:int64 ->
  ?classic_submission_byte_capacity:int64 ->
  ?retained_metadata_byte_capacity:int64 ->
  unit -> Ogpu.Backend.driver * control
val register_pipeline : control -> Pipeline.t -> unit
val sampler_cache_entries : control -> int
val retained_plan_entries : control -> int
val retired_plan_entries : control -> int
val classic_submission_entries : control -> int
val classic_invalidator_entries : control -> int
(* Capacities aggregate the currently live per-queue caches. *)
type classic_submission_stats=
  { entries:int
  ; retained_bytes:int64
  ; queues:int
  ; entry_capacity:int
  ; byte_capacity:int64
  }
val classic_submission_stats : control -> classic_submission_stats
(* Retained metadata totals use conservative accounted bytes for every rooted
   portable graph and native pass. Capacities aggregate live per-queue caches. *)
type retained_metadata_stats=
  { identity_entries:int
  ; replay_entries:int
  ; retained_bytes:int64
  ; queues:int
  ; identity_entry_capacity:int
  ; replay_entry_capacity:int
  ; byte_capacity:int64
  }
val retained_metadata_stats : control -> retained_metadata_stats
type retained_plan_stats=
  { builds:int64
  ; hits:int64
  ; misses:int64
  ; evictions:int64
  ; executions:int64
  ; entries:int
  ; capacity:int
  ; icb_retained_bytes:int64
  ; icb_byte_capacity:int64
  ; owner_retained_bytes:int64
  ; owner_byte_capacity:int64
  ; retired_bytes:int64
  }
val retained_plan_stats : control -> retained_plan_stats
module Private : sig
  val disable_retained_plans_for_test : control -> unit
  val inject_next_active_queue_error : control -> unit
  val inject_next_active_queue_completion_error : control -> unit
  val retained_owner_pass_entries : control -> int
end
