(** Parameterized custom SOP authoring.

    This is the OCaml wrangle-like extension boundary: user code receives
    immutable exposed parameters, a declared cook context, and immutable PDK
    inputs. The builder automatically creates stable cache identity, attaches
    node-owned inspector metadata, and rebuilds the cook closure after edits.
    It is deliberately typed OCaml/PDK code rather than a VEX interpreter. *)

val node :
  ?label:string ->
  operation:string ->
  schema:'parameters Parameter.schema ->
  values:'parameters ->
  Node.t list ->
  (label:string -> inputs:Node.t list -> parameters:'parameters -> Node.t) ->
  Node.t
(** Attach node-owned parameters to any existing SOP composition without
    writing the recursive [Node.parameterize] reconstruction boilerplate. The
    callback must build the unparameterized local operator from its supplied
    label, current graph inputs, and immutable parameter record. *)

val create :
  ?label:string ->
  ?version:int ->
  ?cook_mode:Node.cook_mode ->
  ?dependencies:Context.Dependencies.t ->
  operation:string ->
  schema:'parameters Parameter.schema ->
  values:'parameters ->
  Node.t list ->
  (parameters:'parameters -> context:Context.t -> Pdk.Geometry.t array ->
   (Pdk.Geometry.t, string) result) ->
  Node.t
(** Define a generator or multi-input custom SOP. Long-running callbacks must
    poll [Context.cancel_token]; callbacks must not mutate or retain the input
    array. Context facts used by the callback must be listed in [dependencies]. *)

val map :
  ?label:string ->
  ?version:int ->
  ?cook_mode:Node.cook_mode ->
  ?dependencies:Context.Dependencies.t ->
  operation:string ->
  schema:'parameters Parameter.schema ->
  values:'parameters ->
  Node.t ->
  (parameters:'parameters -> context:Context.t -> Pdk.Geometry.t ->
   (Pdk.Geometry.t, string) result) ->
  Node.t
(** Unary convenience for attribute/topology wrangle-like transforms. *)
