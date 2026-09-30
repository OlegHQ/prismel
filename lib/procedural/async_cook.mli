(** Bounded latest-request background cooking for interactive sketches.

    One persistent worker owns one procedural session. Submitting a newer
    request cancels the active context, replaces the single pending slot, and
    prevents stale results from being published. Prepared values must remain
    target-neutral; SDL and GPU work belongs on the initial domain after
    polling. *)

type error =
  | Cook_error of Diagnostic.error
  | Prepare_error of string
  | Uncaught_exception of string

type status =
  | Idle
  | Cooking of {
      request_id : int;
      seconds : float;
      queued : bool;
    }

type 'a completion = {
  request_id : int;
  seconds : float;
  result : ('a, error) result;
}

type 'a t

val create :
  max_entries:int -> max_payload_bytes:int -> ('a t, string) result

val submit :
  'a t ->
  context:Context.t ->
  node:Node.t ->
  prepare:(Session.output -> ('a, string) result) ->
  (int, string) result
(** Submit the newest desired graph. The request and preparation callback are
    retained only until this bounded job completes or is superseded. *)

val submit_all :
  'a t ->
  context:Context.t ->
  nodes:Node.t list ->
  prepare:(Session.output list -> ('a, string) result) ->
  (int, string) result
(** [submit] for several graphs cooked in order in the same session and
    prepared together, e.g. every visible object of a scene; the first cook
    error fails the request. *)

val set_volatile : 'a t -> (int -> bool) -> unit
(** [Session.set_volatile] on the worker's session. *)

val stats : 'a t -> Session.stats
(** The worker's session counters (hits, misses, evictions, volatile). Call
    while idle for a settled reading. *)

val await : 'a t -> 'a completion
(** Block until the newest submitted request completes and take it, like
    [poll]. For fixed-step runs only (an interactive sketch never blocks);
    raises [Invalid_argument] when nothing is pending or the worker is closed. *)

val poll : 'a t -> 'a completion option
(** Remove and return the newest completed result, if any. *)

val status : 'a t -> status
val close : 'a t -> unit
val is_closed : 'a t -> bool
val error_to_string : error -> string
