(* Helpers shared by the node declarations ([Sop_groups], ...) and the
   hand-written SOPs in [Sop]. A node declaration is one [parameters] record
   deriving [sop_params, sop_node]: the editor schema, the factory and, with
   [[@@sop.fn]], the typed [Sop] constructor all come from it. *)

open Rays_math

(* [rays.ppx] names the generated schema and node code [Procedural.X]; inside
   this library those units are the bare [X]. *)
module Procedural = struct
  module Parameter = Parameter
  module Node = Node
  module Edit_graph = Edit_graph
end

let finite value = Float.is_finite value
let vec3_copy value = Vec3.create value.Vec3.x value.y value.z

let cooked geometry = Ok Node.Private.{ geometry; diagnostics = []; instances = None }
let rdk_error ?(hints = []) operation message =
  Error (Diagnostic.error ~code:(operation ^ "_failed") ~cause:message ~hints
    (operation ^ " could not produce valid geometry"))

let structured_rdk_error error =
  Error (Diagnostic.error ~code:(Rdk.Error.code error)
    ~cause:(Rdk.Error.to_string error) ~hints:(Rdk.Error.hints error)
    (Rdk.Error.operation error ^ " could not produce valid geometry"))

let optional_text value =
  let value = String.trim value in
  if value = "" then None else Some value

let group_merge_parameter = Parameter.choice ~equal:( = ) [
    "Replace", Rdk.Group_ops.Group_replace; "Union", Rdk.Group_ops.Group_union;
    "Intersection", Rdk.Group_ops.Group_intersection;
    "Subtract", Rdk.Group_ops.Group_subtract; "Exclusive or", Rdk.Group_ops.Group_xor;
  ]

let group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Rdk.Group_ops.Group_points; "Vertices", Rdk.Group_ops.Group_vertices;
    "Primitives", Rdk.Group_ops.Group_primitives; "Edges", Rdk.Group_ops.Group_edges;
  ]
