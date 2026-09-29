(** Layout-independent Flow text for one saved network. [precision] defaults
    to 17 significant digits for exact numeric round trips; use 6 for display. *)
type t = { text : string; binding_lines : (int * int) list }
(** [binding_lines] maps node ids in the displayed level to 1-based source
    lines, for selection in the read-only text projection. *)

val network :
  ?qualified:bool ->
  ?precision:int ->
  name:string ->
  context:Flow.Context.t ->
  catalog:Flow.Check.catalog ->
  display:int option ->
  definitions:Network.definition Network.String_map.t ->
  Network.t ->
  (t, Flow.Diagnostic.t) result

val definition :
  ?qualified:bool ->
  ?precision:int ->
  catalog:Flow.Check.catalog ->
  definitions:Network.definition Network.String_map.t ->
  string ->
  (t, Flow.Diagnostic.t) result
(** One open compound's body, with binding lines relative to its [defgraph]. *)
