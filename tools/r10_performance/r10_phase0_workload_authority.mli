val commit : string
val source_path : string
val source_sha256 : string
val source_bytes : int
val expected : R10_scene2_legacy_equivalent.scenario -> int * string
val scenario_name : R10_scene2_legacy_equivalent.scenario -> string
val validate_descriptor : R10_scene2_legacy_equivalent.scenario ->
  R10_scene2_legacy_equivalent.descriptor -> unit
val verify_frozen_source : unit -> unit
val validate_all : width:int -> height:int -> unit
