(** Read-only diagnostics for qualification harnesses. *)

type t = { active:bool; resource_count:int; cache_entries:int;
  release_queue_pending:int option; release_queue_live_handles:int option;
  release_queue_total_created:int64 option;
  release_queue_total_released:int64 option }

type release_queue = { pending:int; live_handles:int; total_created:int64;
  total_released:int64 }
val native_release_queue : unit -> release_queue option
(** Explicit process-global Metal ownership snapshot, including before the
    first Sketch coordinator is created. *)

val snapshot : unit -> t
(** Snapshot the active Sketch coordinator, or the last coordinator after its
    ordered teardown.  Before the first run all counts are zero. *)

module Private : sig
  val install : Prismel_next_execution.t -> unit
  val record : Prismel_next_execution.t -> unit
end
