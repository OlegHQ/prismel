type group =
  | Draw_dispatch | Stage_binding | Fixed_state | Store_action
  | Synchronization | Residency | Indirect_commands | Counter_sample | Query

type obligation =
  | Encoder_open | Pipeline_bound | Same_device | Range_checked
  | Finite_values | Capability_checked | Retain_until_completion

type disposition = Active | Deprecated_alias

type entry =
  { id : string
  ; group : group
  ; obligations : obligation list
  ; disposition : disposition
  }

val select : Binding_render_encoder_evidence.symbol list -> entry list
val expected_group_counts : (group * int) list
val deprecated_ids : string list
val group_name : group -> string
