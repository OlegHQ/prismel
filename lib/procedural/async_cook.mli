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

val poll : 'a t -> 'a completion option
(** Remove and return the newest completed result, if any. *)

val status : 'a t -> status
val cancel : 'a t -> unit
val close : 'a t -> unit
val is_closed : 'a t -> bool
val error_to_string : error -> string
