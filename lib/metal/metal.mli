(** Ownership-aware bindings to Metal.framework on macOS. *)

type error_kind =
  | Native_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Invalid_state
  | Unsupported
  | Device_mismatch
  | Release_queue_overflow

type error = private
  { operation : string
  ; kind : error_kind
  ; message : string
  }

val pp_error : Format.formatter -> error -> unit

module Provenance : sig
  val sdk_version : string
  val deployment_target : string
  val target_triple : string
  val header_count : int
  val header_sha256 : string
end

module Thread : sig
  val is_initial_domain : unit -> bool
  val is_platform_main_thread : unit -> bool
end

module Release_queue : sig
  type stats =
    { pending : int
    ; dropped : int
    ; live_handles : int
    ; total_created : int64
    ; total_released : int64
    ; resident_bytes : int64
    }

  val drain : unit -> (int, error) result
  val stats : unit -> (stats, error) result
end

module Device : sig
  type t

  type family =
    | Apple1
    | Apple2
    | Apple3
    | Apple4
    | Apple5
    | Apple6
    | Apple7
    | Apple8
    | Apple9
    | Apple10
    | Mac2
    | Common1
    | Common2
    | Common3
    | Metal3
    | Metal4

  type info =
    { name : string
    ; registry_id : int64
    ; low_power : bool
    ; removable : bool
    ; headless : bool
    ; unified_memory : bool
    ; recommended_max_working_set_size : int64
    ; current_allocated_size : int64
    ; max_buffer_length : int64
    ; raytracing : bool
    ; raytracing_from_render : bool
    ; dynamic_libraries : bool
    ; function_pointers : bool
    }

  val system_default : unit -> (t, error) result
  val all : unit -> (t list, error) result
  val generation : t -> int64
  val registry_id : t -> int64
  val same : t -> t -> bool
  val destroyed : t -> bool
  val info : t -> (info, error) result
  val supports_family : t -> family -> (bool, error) result
  val destroy : t -> (unit, error) result
end

module Buffer : sig
  type t

  type storage_mode =
    | Shared
    | Managed
    | Private

  val create :
    device:Device.t -> length:int64 -> storage:storage_mode ->
    ?label:string -> unit -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val length : t -> int64
  val storage_mode : t -> storage_mode
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val set_label : t -> string -> (unit, error) result
  val write_bytes :
    t -> ?src_offset:int -> dst_offset:int64 -> bytes -> (unit, error) result
  val read_bytes : t -> offset:int64 -> length:int -> (bytes, error) result
  val destroy : t -> (unit, error) result
end

module Library : sig
  type t

  val compile_source : device:Device.t -> string -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Function : sig
  type t

  val find : library:Library.t -> string -> (t, error) result
  val name : t -> (string, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Compute_pipeline : sig
  type t

  val create : Function.t -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val thread_execution_width : t -> int
  val max_total_threads_per_threadgroup : t -> int
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Command_queue : sig
  type t

  val create : Device.t -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Command_buffer : sig
  type t

  type status =
    | Not_enqueued
    | Enqueued
    | Committed
    | Scheduled
    | Completed
    | Error of string
    | Unknown of int

  val create : Command_queue.t -> ?label:string -> unit -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val status : t -> (status, error) result
  val commit : t -> (unit, error) result
  val wait_until_completed : t -> (unit, error) result
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Compute_encoder : sig
  type t

  val create : Command_buffer.t -> (t, error) result
  val set_pipeline : t -> Compute_pipeline.t -> (unit, error) result
  val set_buffer :
    t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
  val dispatch_threads :
    t -> threads:int * int * int -> threadgroup:int * int * int ->
    (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool
end
