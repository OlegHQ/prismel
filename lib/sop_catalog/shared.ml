open Prismel
open Procedural

let label fallback = function Some label -> label | None -> fallback

(* A catalog-owned operator over PDK. The generated build attaches the schema,
   whose cook key is the node's only parameter identity, so there is no
   hand-written parameter string to keep in sync. *)
let operator ~label ~operation ?(cook_mode = Node.Duplicate_input 0) inputs cook =
  Node.Private.make ~label ~operation ~version:1 ~parameters:"" ~cook_mode
    ~dependencies:Context.Dependencies.static ~inputs cook

let cooked geometry = Ok Node.Private.{ geometry; diagnostics = []; instances = None }

let pdk_cooked = function
  | Ok geometry -> cooked geometry
  | Error error -> Error (Diagnostic.error ~code:(Pdk.Error.code error)
      ~cause:(Pdk.Error.to_string error) ~hints:(Pdk.Error.hints error)
      (Pdk.Error.operation error ^ " could not produce valid geometry"))

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
    "Point", Pdk.Attribute.Point; "Vertex", Pdk.Attribute.Vertex;
    "Primitive", Pdk.Attribute.Primitive; "Detail", Pdk.Attribute.Detail;
  ]

let attribute_owner_token = function
  | Pdk.Attribute.Point -> "point"
  | Pdk.Attribute.Vertex -> "vertex"
  | Pdk.Attribute.Primitive -> "primitive"
  | Pdk.Attribute.Detail -> "detail"

let attribute_owner_of_token = function
  | "point" | "points" -> Ok Pdk.Attribute.Point
  | "vertex" | "vertices" -> Ok Pdk.Attribute.Vertex
  | "primitive" | "primitives" -> Ok Pdk.Attribute.Primitive
  | "detail" -> Ok Pdk.Attribute.Detail
  | token -> Error (Printf.sprintf "unknown attribute owner %S" token)

let encode_boundary_attributes attributes = encode_table (List.map
    (fun (attribute : Pdk.Group_ops.boundary_attribute) ->
      [attribute_owner_token attribute.boundary_attribute_owner;
       attribute.boundary_attribute_pattern]) attributes)

let decode_boundary_attributes text = Result.bind (decode_table text) (fun rows ->
    List.fold_left (fun result row -> Result.bind result (fun attributes ->
      match row with
      | [owner; pattern] -> Result.map (fun boundary_attribute_owner ->
          { Pdk.Group_ops.boundary_attribute_owner;
            boundary_attribute_pattern = pattern } :: attributes)
          (attribute_owner_of_token
            (String.lowercase_ascii (String.trim owner)))
      | row -> Error (Printf.sprintf
          "boundary attribute needs owner and pattern, got %d columns"
          (List.length row)))) (Ok []) rows |> Result.map List.rev)

let boundary_attributes_parameter = Parameter.encoded ~equal:( = )
    ~encode:encode_boundary_attributes ~decode:decode_boundary_attributes

let element_attribute_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Pdk.Attribute.Point; "Vertex", Pdk.Attribute.Vertex;
    "Primitive", Pdk.Attribute.Primitive;
  ]

let uv_owner_parameter = Parameter.choice ~equal:( = ) [
    "Point", Pdk.Attribute.Point; "Vertex", Pdk.Attribute.Vertex;
  ]

let group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Pdk.Group_ops.Group_points; "Vertices", Pdk.Group_ops.Group_vertices;
    "Primitives", Pdk.Group_ops.Group_primitives; "Edges", Pdk.Group_ops.Group_edges;
  ]

let group_owner_token = function
  | Pdk.Group_ops.Group_points -> "point"
  | Pdk.Group_ops.Group_vertices -> "vertex"
  | Pdk.Group_ops.Group_primitives -> "primitive"
  | Pdk.Group_ops.Group_edges -> "edge"

let group_owner_of_token = function
  | "point" | "points" -> Ok Pdk.Group_ops.Group_points
  | "vertex" | "vertices" -> Ok Pdk.Group_ops.Group_vertices
  | "primitive" | "primitives" -> Ok Pdk.Group_ops.Group_primitives
  | "edge" | "edges" -> Ok Pdk.Group_ops.Group_edges
  | token -> Error (Printf.sprintf "unknown group owner %S" token)

let ordinary_group_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Pdk.Group.Point; "Vertices", Pdk.Group.Vertex;
    "Primitives", Pdk.Group.Primitive;
  ]

let group_normal_owner_parameter = Parameter.choice ~equal:( = ) [
    "Points", Pdk.Group_ops.Group_points; "Primitives", Pdk.Group_ops.Group_primitives;
    "Edges", Pdk.Group_ops.Group_edges;
  ]

let group_merge_parameter = Parameter.choice ~equal:( = ) [
    "Replace", Pdk.Group_ops.Group_replace; "Union", Pdk.Group_ops.Group_union;
    "Intersection", Pdk.Group_ops.Group_intersection;
    "Subtract", Pdk.Group_ops.Group_subtract; "Exclusive or", Pdk.Group_ops.Group_xor;
  ]

let group_boolean_token = function
  | Pdk.Group_ops.Group_replace -> "replace"
  | Pdk.Group_ops.Group_union -> "union"
  | Pdk.Group_ops.Group_intersection -> "intersection"
  | Pdk.Group_ops.Group_subtract -> "subtract"
  | Pdk.Group_ops.Group_xor -> "xor"

let group_boolean_of_token = function
  | "replace" -> Ok Pdk.Group_ops.Group_replace
  | "union" -> Ok Pdk.Group_ops.Group_union
  | "intersection" -> Ok Pdk.Group_ops.Group_intersection
  | "subtract" -> Ok Pdk.Group_ops.Group_subtract
  | "xor" -> Ok Pdk.Group_ops.Group_xor
  | token -> Error (Printf.sprintf "unknown group operation %S" token)

let attribute_promotion_method_parameter = Parameter.choice ~equal:( = ) [
    "First", Pdk.Attribute_ops.First;
    "Last", Pdk.Attribute_ops.Last;
    "Average", Pdk.Attribute_ops.Average;
    "Minimum", Pdk.Attribute_ops.Minimum;
    "Maximum", Pdk.Attribute_ops.Maximum;
    "Mode", Pdk.Attribute_ops.Mode;
    "Median", Pdk.Attribute_ops.Median;
    "Sum", Pdk.Attribute_ops.Sum;
    "Sum of squares", Pdk.Attribute_ops.Sum_squares;
    "Root mean square", Pdk.Attribute_ops.Root_mean_square;
    "Array of all", Pdk.Attribute_ops.Array_all;
    "Unique values", Pdk.Attribute_ops.Unique_values;
  ]

let group_rename_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Pdk.Group_ops.Rename_skip; "Error", Pdk.Group_ops.Rename_error;
    "Overwrite", Pdk.Group_ops.Rename_overwrite; "Union", Pdk.Group_ops.Rename_union;
  ]

let delete_topology_policy_parameter = Parameter.choice ~equal:( = ) [
    "Destroy touched primitives", Pdk.Deletion.Destroy_touched_primitives;
    "Heal primitives", Pdk.Deletion.Heal_primitives;
  ]

let group_copy_conflict_parameter = Parameter.choice ~equal:( = ) [
    "Skip", Pdk.Group_ops.Copy_skip; "Overwrite", Pdk.Group_ops.Copy_overwrite;
    "Add suffix", Pdk.Group_ops.Copy_add_suffix;
  ]

let edge_transport_direction_parameter = Parameter.choice ~equal:( = ) [
    "Forward", Pdk.Edge_transport.Transport_forward;
    "Backward", Pdk.Edge_transport.Transport_backward;
  ]

let edge_transport_operation_parameter = Parameter.choice ~equal:( = ) [
    "Transport", Pdk.Edge_transport.Transport;
    "From root", Pdk.Edge_transport.Transport_from_root;
    "Total", Pdk.Edge_transport.Transport_total;
    "Maximum", Pdk.Edge_transport.Transport_maximum;
    "Minimum", Pdk.Edge_transport.Transport_minimum;
  ]

let edge_transport_root_value_parameter = Parameter.choice ~equal:( = ) [
    "Zero", Pdk.Edge_transport.Transport_root_zero;
    "Hold", Pdk.Edge_transport.Transport_root_hold;
  ]

let edge_transport_normalization_parameter = Parameter.choice ~equal:( = ) [
    "None", Pdk.Edge_transport.Transport_no_normalization;
    "Per component", Pdk.Edge_transport.Transport_normalize_components;
    "Global", Pdk.Edge_transport.Transport_normalize_global;
  ]

let edge_transport_split_parameter = Parameter.choice ~equal:( = ) [
    "Copy", Pdk.Edge_transport.Transport_copy; "Split", Pdk.Edge_transport.Transport_split;
  ]

let edge_transport_merge_parameter = Parameter.choice ~equal:( = ) [
    "Add", Pdk.Edge_transport.Transport_merge_add;
    "Maximum", Pdk.Edge_transport.Transport_merge_maximum;
    "Minimum", Pdk.Edge_transport.Transport_merge_minimum;
  ]

type numeric_kind = Numeric_scalar | Numeric_vec2 | Numeric_vec3 | Numeric_vec4
let numeric_kind_parameter = Parameter.choice ~equal:( = ) [
    "Scalar", Numeric_scalar; "Vector 2", Numeric_vec2;
    "Vector 3", Numeric_vec3; "Vector 4", Numeric_vec4;
  ]
let numeric_value kind x y z w = match kind with
  | Numeric_scalar -> Pdk.Attribute_ops.Scalar x
  | Numeric_vec2 -> Pdk.Attribute_ops.Vec2 (Vec2.create x y)
  | Numeric_vec3 -> Pdk.Attribute_ops.Vec3 (Vec3.create x y z)
  | Numeric_vec4 -> Pdk.Attribute_ops.Vec4 (x, y, z, w)

let soft_falloff_parameter = Parameter.choice ~equal:( = ) [
    "Linear", Pdk.Transform_ops.Soft_linear; "Quadratic", Pdk.Transform_ops.Soft_quadratic;
    "Cubic", Pdk.Transform_ops.Soft_cubic;
  ]

type distance_radius_mode = Radius_fixed | Radius_maximum
let distance_radius_parameter = Parameter.choice ~equal:( = ) [
    "Fixed", Radius_fixed; "Maximum distance", Radius_maximum;
  ]
let distance_radius mode value = match mode with
  | Radius_fixed -> Pdk.Transform_ops.Distance_fixed value
  | Radius_maximum -> Pdk.Transform_ops.Distance_maximum

type transport_roots = Transport_first | Transport_last | Transport_group
let transport_roots_parameter = Parameter.choice ~equal:( = ) [
    "First point", Transport_first; "Last point", Transport_last;
    "Root group", Transport_group;
  ]
let transport_roots mode group = match mode with
  | Transport_first -> None, Pdk.Edge_transport.Transport_first_point
  | Transport_last -> None, Pdk.Edge_transport.Transport_last_point
  | Transport_group -> optional_text group, Pdk.Edge_transport.Transport_first_point

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
    "Keep target", Pdk.Attribute_ops.Keep_target;
    "Default value", Pdk.Attribute_ops.Default_value;
  ]
let transfer_mode mode neighbors power radius = match mode with
  | Transfer_nearest -> Pdk.Attribute_ops.Nearest
  | Transfer_inverse -> Pdk.Attribute_ops.Inverse_distance { neighbors; power }
  | Transfer_links -> Pdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Pdk.Attribute_ops.Links }
  | Transfer_renderman -> Pdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Pdk.Attribute_ops.RenderMan }
  | Transfer_hart -> Pdk.Attribute_ops.Kernel {
      neighbors; radius; kernel = Pdk.Attribute_ops.Hart }
let transfer_falloff falloff bias = match falloff with
  | Transfer_linear -> Pdk.Attribute_ops.Linear
  | Transfer_smoothstep -> Pdk.Attribute_ops.Smoothstep
  | Transfer_uniform -> Pdk.Attribute_ops.Uniform bias
let exact_or_pattern exact pattern = match optional_text pattern with
  | Some pattern -> None, Some pattern
  | None -> optional_text exact, None
