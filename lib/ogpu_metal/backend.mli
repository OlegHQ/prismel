type control
val create : ?device:Device.t -> ?layer:Metal.Metal_layer.t -> ?retained_plan_capacity:int -> unit -> Ogpu.Backend.driver * control
val register_pipeline : control -> Pipeline.t -> unit
val sampler_cache_entries : control -> int
val retained_plan_entries : control -> int
val retired_plan_entries : control -> int
module Private : sig val disable_retained_plans_for_test : control -> unit end
