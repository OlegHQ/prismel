(* The editor factories of the nodes declared in this library. [Sop_catalog]
   registers each one under its stable key; a node's typed constructor is the
   [Sop] value of the same operation. *)
module Group_non_planar = Sop_groups.Group_non_planar
module Group_backface = Sop_groups.Group_backface
module Group_unshared = Sop_groups.Group_unshared
