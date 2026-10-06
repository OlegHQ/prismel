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

let label fallback = function Some label -> label | None -> fallback

let stable_string_hash value =
  let hash = ref 0xcbf29ce484222325L in
  String.iter (fun character ->
    hash := Int64.mul (Int64.logxor !hash (Int64.of_int (Char.code character)))
        0x100000001b3L) value;
  !hash

let mixed_seed context identity =
  let mixed = Int64.logxor (Context.seed context)
      (Int64.mul identity 0x9e3779b97f4a7c15L) in
  Int64.to_int (Int64.logxor mixed (Int64.shift_right_logical mixed 32))

let encode_table rows =
  let encode_cell value =
    let buffer = Buffer.create (String.length value) in
    String.iter (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\t' -> Buffer.add_string buffer "\\t"
      | '\n' -> Buffer.add_string buffer "\\n"
      | character -> Buffer.add_char buffer character) value;
    Buffer.contents buffer in
  rows |> List.map (fun row -> String.concat "\t" (List.map encode_cell row))
       |> String.concat "\n"

let decode_table text =
  if text = "" then Ok [] else
  let rows = ref [] and row = ref [] and cell = Buffer.create 32 in
  let finish_cell () =
    row := Buffer.contents cell :: !row;
    Buffer.clear cell in
  let finish_row () = finish_cell (); rows := List.rev !row :: !rows; row := [] in
  let escaped = ref false and error = ref None in
  String.iter (fun character -> if Option.is_none !error then
    if !escaped then begin
      escaped := false;
      match character with
      | '\\' -> Buffer.add_char cell '\\'
      | 't' -> Buffer.add_char cell '\t'
      | 'n' -> Buffer.add_char cell '\n'
      | character -> error := Some (Printf.sprintf
          "unsupported table escape \\%c" character)
    end else match character with
      | '\\' -> escaped := true
      | '\t' -> finish_cell ()
      | '\n' -> finish_row ()
      | character -> Buffer.add_char cell character) text;
  match !error with
  | Some error -> Error error
  | None when !escaped -> Error "trailing table escape"
  | None -> finish_row (); Ok (List.rev !rows)

let attribute_owner_token = function
  | Rdk.Attribute.Point -> "point"
  | Rdk.Attribute.Vertex -> "vertex"
  | Rdk.Attribute.Primitive -> "primitive"
  | Rdk.Attribute.Detail -> "detail"

let attribute_owner_of_token = function
  | "point" | "points" -> Ok Rdk.Attribute.Point
  | "vertex" | "vertices" -> Ok Rdk.Attribute.Vertex
  | "primitive" | "primitives" -> Ok Rdk.Attribute.Primitive
  | "detail" -> Ok Rdk.Attribute.Detail
  | token -> Error (Printf.sprintf "unknown attribute owner %S" token)

let encode_boundary_attributes attributes = encode_table (List.map
    (fun (attribute : Rdk.Group_ops.boundary_attribute) ->
      [attribute_owner_token attribute.boundary_attribute_owner;
       attribute.boundary_attribute_pattern]) attributes)

let decode_boundary_attributes text = Result.bind (decode_table text) (fun rows ->
    List.fold_left (fun result row -> Result.bind result (fun attributes ->
      match row with
      | [owner; pattern] -> Result.map (fun boundary_attribute_owner ->
          { Rdk.Group_ops.boundary_attribute_owner;
            boundary_attribute_pattern = pattern } :: attributes)
          (attribute_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
      | row -> Error (Printf.sprintf
          "boundary attribute needs owner and pattern, got %d columns"
          (List.length row)))) (Ok []) rows |> Result.map List.rev)

let boundary_attributes_parameter = Parameter.encoded ~equal:( = )
    ~encode:encode_boundary_attributes ~decode:decode_boundary_attributes

let element_attribute_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Rdk.Attribute.Point; "Vertex", Rdk.Attribute.Vertex;
    "Primitive", Rdk.Attribute.Primitive;
  ]

let group_owner_token = function
  | Rdk.Group_ops.Group_points -> "point"
  | Rdk.Group_ops.Group_vertices -> "vertex"
  | Rdk.Group_ops.Group_primitives -> "primitive"
  | Rdk.Group_ops.Group_edges -> "edge"

let group_owner_of_token = function
  | "point" | "points" -> Ok Rdk.Group_ops.Group_points
  | "vertex" | "vertices" -> Ok Rdk.Group_ops.Group_vertices
  | "primitive" | "primitives" -> Ok Rdk.Group_ops.Group_primitives
  | "edge" | "edges" -> Ok Rdk.Group_ops.Group_edges
  | token -> Error (Printf.sprintf "unknown group owner %S" token)

let group_copy_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Rdk.Group_ops.Copy_skip; "Overwrite", Rdk.Group_ops.Copy_overwrite;
    "Add suffix", Rdk.Group_ops.Copy_add_suffix;
  ]

let ordinary_group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Rdk.Group.Point; "Vertices", Rdk.Group.Vertex;
    "Primitives", Rdk.Group.Primitive;
  ]

let group_owner_key = function
  | Rdk.Group.Point -> "point"
  | Rdk.Group.Vertex -> "vertex"
  | Rdk.Group.Primitive -> "primitive"

let delete_topology_policy_parameter = Parameter.choice ~equal:( = ) [
    "Destroy touched primitives", Rdk.Deletion.Destroy_touched_primitives;
    "Heal primitives", Rdk.Deletion.Heal_primitives;
  ]

let uv_parameterize_seams operation input = function
  | None -> Ok (None, None)
  | Some group_name ->
      (match Rdk.Geometry.find_edge_group group_name input with
       | Some value -> Ok (Some value, None)
       | None ->
           match Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex group_name input with
           | Some value -> Ok (None, Some value)
           | None -> Error (Diagnostic.error ~code:"missing_group"
               ~hints:["Create a native edge group or compatibility vertex-edge group before " ^ operation]
               (Printf.sprintf "%s could not find edge or vertex seam group %S"
                 operation group_name)))
