(** Small reusable bridge between a [Sketch] frame loop and background SOP
    cooking. Geometry graph construction remains in sketch code; worker,
    context, cancellation, and pointer-release commit policy do not. *)

type 'prepared t

val create :
  ?seed:int64 ->
  ?grain:int ->
  ?domains:int ->
  max_entries:int ->
  max_payload_bytes:int ->
  unit ->
  ('prepared t, string) result

val submit :
  'prepared t ->
  frame:Prismel.Frame.t ->
  node:Procedural.Node.t ->
  prepare:(Procedural.Session.output -> ('prepared, string) result) ->
  (int, string) result

val submit_context :
  'prepared t ->
  context:Procedural.Context.t ->
  node:Procedural.Node.t ->
  prepare:(Procedural.Session.output -> ('prepared, string) result) ->
  (int, string) result

val submit_timeline :
  'prepared t ->
  timeline:Timeline.t ->
  node:Procedural.Node.t ->
  prepare:(Procedural.Session.output -> ('prepared, string) result) ->
  (int, string) result

val poll : 'prepared t -> 'prepared Procedural.Async_cook.completion option
val status : 'prepared t -> Procedural.Async_cook.status
val cancel : 'prepared t -> unit
val close : 'prepared t -> unit
val error_to_string : Procedural.Async_cook.error -> string

type gate
val clean : gate

val gate :
  gate ->
  effects:Procedural.Parameter.effects ->
  frame:Prismel.Frame.t ->
  gate * bool
(** Accumulate cook-affecting parameter changes while the primary pointer is
    held. The returned Boolean fires once on release, or immediately for a
    non-pointer change. View/export effects never dirty the gate. *)

(** Effect- and dependency-aware cook scheduler. It fires initially, after a
    committed cook parameter change, after [force], and whenever the sketch
    clock changed and any reachable node declares [Time] or [Frame]. While a
    primary-pointer edit is held, only the latest desired cook is retained. *)
type schedule
val schedule_initial : schedule
val schedule :
  schedule ->
  graph:Procedural.Graph.t ->
  effects:Procedural.Parameter.effects ->
  context_changed:bool ->
  force:bool ->
  busy:bool ->
  frame:Prismel.Frame.t ->
  schedule * bool
