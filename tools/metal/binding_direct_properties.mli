(** Audited mechanical property/accessor shard for handle-backed Metal
    receivers. These entries describe private raw/native generation only. *)

val entries : Binding_direct_spec.property_entry list

val property_count : int
val getter_count : int
val setter_count : int
val declaration_count : int
val declaration_ids : string list

(** Recheck cardinality, SDK-ID uniqueness, property/accessor correspondence,
    exact scalar signatures, and the single writable-property boundary. *)
val validate : unit -> unit
