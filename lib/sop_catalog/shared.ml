open Rays
open Procedural

let label fallback = function Some label -> label | None -> fallback

(* A catalog-owned operator over RDK. The generated build attaches the schema,
   whose cook key is the node's only parameter identity, so there is no
   hand-written parameter string to keep in sync. *)
let operator ~label ~operation ?(cook_mode = Node.Duplicate_input 0) inputs cook =
  Node.Private.make ~label ~operation ~version:1 ~parameters:"" ~cook_mode
    ~dependencies:Context.Dependencies.static ~inputs cook

let cooked geometry = Ok Node.Private.{ geometry; diagnostics = []; instances = None }

let rdk_cooked = function
  | Ok geometry -> cooked geometry
  | Error error -> Error (Diagnostic.error ~code:(Rdk.Error.code error)
      ~cause:(Rdk.Error.to_string error) ~hints:(Rdk.Error.hints error)
      (Rdk.Error.operation error ^ " could not produce valid geometry"))

let optional_text value =
  let value = String.trim value in
  if value = "" then None else Some value

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

let bool_token value = if value then "true" else "false"
let bool_of_token value = match String.lowercase_ascii (String.trim value) with
  | "true" | "1" | "yes" -> Ok true
  | "false" | "0" | "no" -> Ok false
  | token -> Error (Printf.sprintf "expected boolean, got %S" token)
let int_of_token value = match int_of_string_opt (String.trim value) with
  | Some value -> Ok value
  | None -> Error (Printf.sprintf "expected integer, got %S" value)
let float_of_token value = match float_of_string_opt (String.trim value) with
  | Some value when Float.is_finite value -> Ok value
  | Some _ | None -> Error (Printf.sprintf "expected finite float, got %S" value)

type element_owner = Element_point | Element_vertex
  | Element_primitive | Element_edge

let element_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Element_point; "Vertex", Element_vertex;
    "Primitive", Element_primitive; "Edge", Element_edge;
  ]

let optional_element_group owner name = match optional_text name with
  | None -> None
  | Some name -> Some (match owner with
      | Element_point -> Sop.Point_group name
      | Element_vertex -> Sop.Vertex_group name
      | Element_primitive -> Sop.Primitive_group name
      | Element_edge -> Sop.Edge_group name)

let attribute_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Rdk.Attribute.Point; "Vertex", Rdk.Attribute.Vertex;
    "Primitive", Rdk.Attribute.Primitive; "Detail", Rdk.Attribute.Detail;
  ]

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

let uv_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Rdk.Attribute.Point; "Vertex", Rdk.Attribute.Vertex;
  ]

let group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Rdk.Group_ops.Group_points; "Vertices", Rdk.Group_ops.Group_vertices;
    "Primitives", Rdk.Group_ops.Group_primitives; "Edges", Rdk.Group_ops.Group_edges;
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

let ordinary_group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Rdk.Group.Point; "Vertices", Rdk.Group.Vertex;
    "Primitives", Rdk.Group.Primitive;
  ]

let group_normal_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Rdk.Group_ops.Group_points; "Primitives", Rdk.Group_ops.Group_primitives;
    "Edges", Rdk.Group_ops.Group_edges;
  ]

let group_merge_parameter = Parameter.choice ~equal:( = ) [
    "Replace", Rdk.Group_ops.Group_replace; "Union", Rdk.Group_ops.Group_union;
    "Intersection", Rdk.Group_ops.Group_intersection;
    "Subtract", Rdk.Group_ops.Group_subtract; "Exclusive or", Rdk.Group_ops.Group_xor;
  ]

let group_boolean_token = function
  | Rdk.Group_ops.Group_replace -> "replace"
  | Rdk.Group_ops.Group_union -> "union"
  | Rdk.Group_ops.Group_intersection -> "intersection"
  | Rdk.Group_ops.Group_subtract -> "subtract"
  | Rdk.Group_ops.Group_xor -> "xor"

let group_boolean_of_token = function
  | "replace" -> Ok Rdk.Group_ops.Group_replace
  | "union" -> Ok Rdk.Group_ops.Group_union
  | "intersection" -> Ok Rdk.Group_ops.Group_intersection
  | "subtract" -> Ok Rdk.Group_ops.Group_subtract
  | "xor" -> Ok Rdk.Group_ops.Group_xor
  | token -> Error (Printf.sprintf "unknown group operation %S" token)

let attribute_promotion_method_parameter = Parameter.choice ~equal:( = ) [
    "First", Rdk.Attribute_ops.First;
    "Last", Rdk.Attribute_ops.Last;
    "Average", Rdk.Attribute_ops.Average;
    "Minimum", Rdk.Attribute_ops.Minimum;
    "Maximum", Rdk.Attribute_ops.Maximum;
    "Mode", Rdk.Attribute_ops.Mode;
    "Median", Rdk.Attribute_ops.Median;
    "Sum", Rdk.Attribute_ops.Sum;
    "Sum of squares", Rdk.Attribute_ops.Sum_squares;
    "Root mean square", Rdk.Attribute_ops.Root_mean_square;
    "Array of all", Rdk.Attribute_ops.Array_all;
    "Unique values", Rdk.Attribute_ops.Unique_values;
  ]

let group_rename_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Rdk.Group_ops.Rename_skip; "Error", Rdk.Group_ops.Rename_error;
    "Overwrite", Rdk.Group_ops.Rename_overwrite; "Union", Rdk.Group_ops.Rename_union;
  ]

let delete_topology_policy_parameter = Parameter.choice ~equal:( = ) [
    "Destroy touched primitives", Rdk.Deletion.Destroy_touched_primitives;
    "Heal primitives", Rdk.Deletion.Heal_primitives;
  ]

let group_copy_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Rdk.Group_ops.Copy_skip; "Overwrite", Rdk.Group_ops.Copy_overwrite;
    "Add suffix", Rdk.Group_ops.Copy_add_suffix;
  ]

let edge_transport_direction_parameter = Parameter.choice ~equal:( = ) [
    "Forward", Rdk.Edge_transport.Transport_forward;
    "Backward", Rdk.Edge_transport.Transport_backward;
  ]

let edge_transport_operation_parameter = Parameter.choice ~equal:( = ) [
    "Transport", Rdk.Edge_transport.Transport;
    "From root", Rdk.Edge_transport.Transport_from_root;
    "Total", Rdk.Edge_transport.Transport_total;
    "Maximum", Rdk.Edge_transport.Transport_maximum;
    "Minimum", Rdk.Edge_transport.Transport_minimum;
  ]

let edge_transport_root_value_parameter = Parameter.choice ~equal:( = ) [
    "Zero", Rdk.Edge_transport.Transport_root_zero;
    "Hold", Rdk.Edge_transport.Transport_root_hold;
  ]

let edge_transport_normalization_parameter = Parameter.choice ~equal:( = ) [
    "None", Rdk.Edge_transport.Transport_no_normalization;
    "Per component", Rdk.Edge_transport.Transport_normalize_components;
    "Global", Rdk.Edge_transport.Transport_normalize_global;
  ]

let edge_transport_split_parameter = Parameter.choice ~equal:( = ) [
    "Copy", Rdk.Edge_transport.Transport_copy; "Split", Rdk.Edge_transport.Transport_split;
  ]

let edge_transport_merge_parameter = Parameter.choice ~equal:( = ) [
    "Add", Rdk.Edge_transport.Transport_merge_add;
    "Maximum", Rdk.Edge_transport.Transport_merge_maximum;
    "Minimum", Rdk.Edge_transport.Transport_merge_minimum;
  ]

type numeric_kind = Numeric_scalar | Numeric_vec2 | Numeric_vec3 | Numeric_vec4
let numeric_kind_parameter = Parameter.choice ~equal:( = ) [
    "Scalar", Numeric_scalar; "Vector 2", Numeric_vec2;
    "Vector 3", Numeric_vec3; "Vector 4", Numeric_vec4;
  ]
let numeric_value kind x y z w = match kind with
  | Numeric_scalar -> Rdk.Attribute_ops.Scalar x
  | Numeric_vec2 -> Rdk.Attribute_ops.Vec2 (Vec2.create x y)
  | Numeric_vec3 -> Rdk.Attribute_ops.Vec3 (Vec3.create x y z)
  | Numeric_vec4 -> Rdk.Attribute_ops.Vec4 (x, y, z, w)

let soft_falloff_parameter = Parameter.choice ~equal:( = ) [
    "Linear", Rdk.Transform_ops.Soft_linear; "Quadratic", Rdk.Transform_ops.Soft_quadratic;
    "Cubic", Rdk.Transform_ops.Soft_cubic;
  ]

type distance_radius_mode = Radius_fixed | Radius_maximum
let distance_radius_parameter = Parameter.choice ~equal:( = ) [
    "Fixed", Radius_fixed; "Maximum distance", Radius_maximum;
  ]
let distance_radius mode value = match mode with
  | Radius_fixed -> Rdk.Transform_ops.Distance_fixed value
  | Radius_maximum -> Rdk.Transform_ops.Distance_maximum

type transport_roots = Transport_first | Transport_last | Transport_group
let transport_roots_parameter = Parameter.choice ~equal:( = ) [
    "First point", Transport_first; "Last point", Transport_last;
    "Root group", Transport_group;
  ]
let transport_roots mode group = match mode with
  | Transport_first -> None, Rdk.Edge_transport.Transport_first_point
  | Transport_last -> None, Rdk.Edge_transport.Transport_last_point
  | Transport_group -> optional_text group, Rdk.Edge_transport.Transport_first_point

type transfer_mode = Transfer_nearest | Transfer_inverse | Transfer_links
  | Transfer_renderman | Transfer_hart
let transfer_mode_parameter = Parameter.choice ~equal:( = ) [
    "Nearest", Transfer_nearest; "Inverse distance", Transfer_inverse;
    "Links kernel", Transfer_links; "RenderMan kernel", Transfer_renderman;
    "Hart kernel", Transfer_hart;
  ]
type transfer_falloff = Transfer_linear | Transfer_smoothstep | Transfer_uniform
let transfer_falloff_parameter = Parameter.choice ~equal:( = ) [
    "Linear", Transfer_linear; "Smoothstep", Transfer_smoothstep;
    "Uniform", Transfer_uniform;
  ]
let transfer_unmatched_parameter = Parameter.choice ~equal:( = ) [
    "Keep target", Rdk.Attribute_ops.Keep_target;
    "Default value", Rdk.Attribute_ops.Default_value;
  ]
let transfer_mode mode neighbors power radius = match mode with
  | Transfer_nearest -> Rdk.Attribute_ops.Nearest
  | Transfer_inverse -> Rdk.Attribute_ops.Inverse_distance { neighbors; power }
  | Transfer_links -> Rdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Rdk.Attribute_ops.Links }
  | Transfer_renderman -> Rdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Rdk.Attribute_ops.RenderMan }
  | Transfer_hart -> Rdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Rdk.Attribute_ops.Hart }
let transfer_falloff falloff bias = match falloff with
  | Transfer_linear -> Rdk.Attribute_ops.Linear
  | Transfer_smoothstep -> Rdk.Attribute_ops.Smoothstep
  | Transfer_uniform -> Rdk.Attribute_ops.Uniform bias
let exact_or_pattern exact pattern = match optional_text pattern with
  | Some pattern -> None, Some pattern
  | None -> optional_text exact, None
