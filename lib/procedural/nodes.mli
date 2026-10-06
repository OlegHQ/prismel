(** Editor factories of the SOP nodes declared once in this library: each
    [parameters] record derives its schema, this factory and the typed [Sop]
    constructor of the same operation, so the three never drift. *)
module Group_non_planar : sig val factory : Edit_graph.factory end
module Group_backface : sig val factory : Edit_graph.factory end
module Group_unshared : sig val factory : Edit_graph.factory end
module Group_edges : sig val factory : Edit_graph.factory end
module Group_random : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?seed:int -> probability:float ->
    owner:Rdk.Group_ops.owner -> name:string ->
    Node.t -> Node.t
end
module Group_edge_depth : sig val factory : Edit_graph.factory end
module Group_boundary_components : sig val factory : Edit_graph.factory end
module Group_from_attribute_boundary : sig val factory : Edit_graph.factory end
module Groups_from_name : sig val factory : Edit_graph.factory end
module Name_from_groups : sig val factory : Edit_graph.factory end
module Group_promote_boundary : sig val factory : Edit_graph.factory end
module Group_delete : sig val factory : Edit_graph.factory end
module Group_rename : sig val factory : Edit_graph.factory end
module Group_copy : sig val factory : Edit_graph.factory end
module Group_transfer : sig val factory : Edit_graph.factory end
module Group_find_path : sig val factory : Edit_graph.factory end
module Delete_edge_group : sig val factory : Edit_graph.factory end
module Rename_edge_group : sig val factory : Edit_graph.factory end
