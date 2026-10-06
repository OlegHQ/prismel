(* The editor factories of the nodes declared in this library. [Sop_catalog]
   registers each one under its stable key; a node's typed constructor is the
   [Sop] value of the same operation. *)
module Group_non_planar = Sop_groups.Group_non_planar
module Group_backface = Sop_groups.Group_backface
module Group_unshared = Sop_groups.Group_unshared
module Group_edges = Sop_groups.Group_edges
module Group_random = Sop_groups.Group_random
module Group_edge_depth = Sop_groups.Group_edge_depth
module Group_boundary_components = Sop_groups.Group_boundary_components
module Group_from_attribute_boundary = Sop_groups.Group_from_attribute_boundary
module Groups_from_name = Sop_groups.Groups_from_name
module Name_from_groups = Sop_groups.Name_from_groups
module Group_promote_boundary = Sop_groups.Group_promote_boundary
module Group_delete = Sop_groups.Group_delete
module Group_rename = Sop_groups.Group_rename
module Group_copy = Sop_groups.Group_copy
module Group_transfer = Sop_groups.Group_transfer
module Group_find_path = Sop_groups.Group_find_path
module Delete_edge_group = Sop_groups.Delete_edge_group
module Rename_edge_group = Sop_groups.Rename_edge_group
