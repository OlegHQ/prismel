(** Factories for the three structural nodes of a compound definition.
    They are rebuilt from its interface when a preset loads. *)
val key : name:string -> [ `Inputs | `Outputs | `Instance ] -> string

val factories :
  name:string ->
  inputs:Network.interface_port list ->
  outputs:Network.interface_port list ->
  Procedural.Edit_graph.factory list
