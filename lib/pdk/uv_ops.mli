type projection =
  | Planar of {
      origin : Prismel.Vec3.t;
      u_axis : Prismel.Vec3.t;
      v_axis : Prismel.Vec3.t;
    }
  | Cylindrical of {
      origin : Prismel.Vec3.t;
      axis : Prismel.Vec3.t;
      seam : Prismel.Vec3.t;
      height : float;
    }
  | Spherical of {
      origin : Prismel.Vec3.t;
      axis : Prismel.Vec3.t;
      seam : Prismel.Vec3.t;
    }

type unitize_mode = Per_face | Islands

val project :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?u_range:float * float ->
  ?v_range:float * float ->
  ?fix_seams:bool ->
  ?fix_poles:bool ->
  projection ->
  Geometry.t ->
  (Geometry.t, string) result

val transform :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?selection:Group.t ->
  owner:Attribute.owner ->
  ?translate:Prismel.Vec2.t ->
  ?scale:Prismel.Vec2.t ->
  ?angle:float ->
  ?pivot:Prismel.Vec2.t ->
  Geometry.t ->
  (Geometry.t, string) result

val auto_seam :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?angle:float ->
  ?include_boundaries:bool ->
  ?include_non_manifold:bool ->
  ?partition_attribute:string ->
  ?existing_uv:string ->
  ?uv_tolerance:float ->
  ?island_attribute:string ->
  Geometry.t ->
  (Geometry.t, string) result

val unitize :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?seams:Group.t ->
  ?edge_seams:Edge_group.t ->
  ?tolerance:float ->
  ?uniform:bool ->
  unitize_mode ->
  Geometry.t ->
  (Geometry.t, string) result

val flatten :
  ?cancel:Cancel.t -> ?grain:int -> ?name:string -> ?seams:Group.t ->
  ?edge_seams:Edge_group.t -> ?iterations:int -> ?tolerance:float ->
  Geometry.t -> (Geometry.t, string) result

val relax :
  ?cancel:Cancel.t -> ?grain:int -> ?name:string -> ?seams:Group.t ->
  ?edge_seams:Edge_group.t -> ?uv_tolerance:float -> ?iterations:int ->
  ?tolerance:float -> Geometry.t -> (Geometry.t, string) result
