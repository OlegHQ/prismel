open Prismel_math

type projection = Uv_ops.projection =
  | Planar of { origin : Vec3.t; u_axis : Vec3.t; v_axis : Vec3.t }
  | Cylindrical of {
      origin : Vec3.t; axis : Vec3.t; seam : Vec3.t; height : float;
    }
  | Spherical of { origin : Vec3.t; axis : Vec3.t; seam : Vec3.t }

type unitize_mode = Uv_ops.unitize_mode = Per_face | Islands

let project ?cancel ?grain ?name ?primitives ?u_range ?v_range
    ?fix_seams ?fix_poles projection geometry =
  Error.guard ~operation:"uv_project" ~code:"invalid_projection" (fun () ->
    Uv_ops.project ?cancel ?grain ?name ?primitives ?u_range ?v_range
      ?fix_seams ?fix_poles projection geometry)

let transform ?cancel ?grain ?name ?selection ~owner ?translate ?scale
    ?angle ?pivot geometry =
  Error.guard ~operation:"uv_transform" ~code:"invalid_attribute" (fun () ->
    Uv_ops.transform ?cancel ?grain ?name ?selection ~owner ?translate ?scale
      ?angle ?pivot geometry)

let auto_seam ?cancel ?grain ?name ?primitives ?angle
    ?include_boundaries ?include_non_manifold ?partition_attribute ?existing_uv
    ?uv_tolerance ?island_attribute geometry =
  Error.guard ~operation:"uv_auto_seam" ~code:"invalid_topology" (fun () ->
    Uv_ops.auto_seam ?cancel ?grain ?name ?primitives ?angle
      ?include_boundaries ?include_non_manifold ?partition_attribute
      ?existing_uv ?uv_tolerance ?island_attribute geometry)

let unitize ?cancel ?grain ?name ?primitives ?seams ?edge_seams
    ?tolerance ?uniform mode geometry =
  Error.guard ~operation:"uv_unitize" ~code:"invalid_uv" (fun () ->
    Uv_ops.unitize ?cancel ?grain ?name ?primitives ?seams ?edge_seams
      ?tolerance ?uniform mode geometry)

let flatten ?cancel ?grain ?name ?seams ?edge_seams ?iterations
    ?tolerance geometry =
  Error.guard ~operation:"uv_flatten" ~code:"invalid_uv" (fun () ->
    Uv_ops.flatten ?cancel ?grain ?name ?seams ?edge_seams ?iterations
      ?tolerance geometry)

let relax ?cancel ?grain ?name ?seams ?edge_seams ?uv_tolerance
    ?iterations ?tolerance geometry =
  Error.guard ~operation:"uv_relax" ~code:"invalid_uv" (fun () ->
    Uv_ops.relax ?cancel ?grain ?name ?seams ?edge_seams ?uv_tolerance
      ?iterations ?tolerance geometry)
