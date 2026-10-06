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
module Edge_divide : sig val factory : Edit_graph.factory end
module Edge_collapse : sig val factory : Edit_graph.factory end
module Dissolve : sig val factory : Edit_graph.factory end
module Triangulate : sig val factory : Edit_graph.factory end
module Edge_flip : sig val factory : Edit_graph.factory end
module Edge_cusp : sig val factory : Edit_graph.factory end
module Edge_straighten : sig val factory : Edit_graph.factory end
module Poly_extrude : sig val factory : Edit_graph.factory end
module Poly_fill : sig val factory : Edit_graph.factory end
module Convert_line : sig val factory : Edit_graph.factory end
module Blast : sig
  val factory : Edit_graph.factory
  val create :
    ?label:string -> ?selected:bool -> ?compact_points:bool ->
    owner:Rdk.Group.owner -> group:string ->
    Node.t -> Node.t
end
module Uv_flatten : sig val factory : Edit_graph.factory end
module Uv_relax : sig val factory : Edit_graph.factory end
module Rename_attributes : sig val factory : Edit_graph.factory end
module Line : sig val factory : Edit_graph.factory end
module Mirror : sig val factory : Edit_graph.factory end
module Match_axis : sig val factory : Edit_graph.factory end
module Noise_displace : sig val factory : Edit_graph.factory end
