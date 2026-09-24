include module type of Binding_spec

val expected_sdk_version : string

(** Every schema, shard, and aggregator source covered by plan provenance. *)
val source_paths : string list

(** Computes the framed aggregate digest of [source_paths] below [root]. *)
val source_sha256 : root:string -> string

val entries : entry list
val generated_entries : entry list
val bound_identifiers : string list
