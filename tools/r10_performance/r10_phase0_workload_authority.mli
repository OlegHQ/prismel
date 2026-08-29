val commit : string
val source_path : string
val source_sha256 : string
val source_bytes : int
val expected : R10_scene2_legacy_equivalent.scenario -> int * string
type runtime_evidence = {
  draws_per_frame : int;
  passes_per_frame : int;
  submissions_per_frame : int;
  uploads_full_frame_per_frame : bool;
}
val runtime_evidence :
  R10_scene2_legacy_equivalent.scenario -> runtime_evidence
val scenario_name : R10_scene2_legacy_equivalent.scenario -> string
val validate_descriptor : R10_scene2_legacy_equivalent.scenario ->
  R10_scene2_legacy_equivalent.descriptor -> unit
val verify_frozen_source : unit -> unit
val validate_all : width:int -> height:int -> unit
