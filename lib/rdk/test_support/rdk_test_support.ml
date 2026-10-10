(* The helpers the rdk and sop tests share. A test file opens this module and keeps
   only the helpers that are its own. tools/dedupe removes a local copy when the compiler
   resolves it to the same definition as the one here, so change a definition only together
   with every file that relies on it. *)
open Rdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_rdk = function Ok value -> value | Error error -> fail (Error.to_string error)
let get = function Ok value -> value | Error message -> fail message
let get_string = function Ok value -> value | Error message -> fail message
let get_string_ok = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec search offset =
    offset + String.length pattern <= String.length text
    && (String.sub text offset (String.length pattern) = pattern || search (offset + 1)) in
  pattern = "" || search 0

let near ?(epsilon = 1e-10) left right = abs_float (left -. right) <= epsilon

let expect_code code = function
  | Error error when String.equal (Error.code error) code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, received %s" code
      (Error.to_string error))
  | Ok _ -> fail ("expected error " ^ code)

let positions geometry = Packed.Float3.Private.view (Geometry.positions geometry)

let same_float_array left right =
  Array.length left = Array.length right
  && let same = ref true in
     for index = 0 to Array.length left - 1 do
       if Int64.bits_of_float left.(index) <> Int64.bits_of_float right.(index)
       then same := false
     done;
     !same

let equal_storage left right = match Attribute.storage left, Attribute.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Float4 left, Attribute.Float4 right ->
      let left = Packed.Float4.Private.view left
      and right = Packed.Float4.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
      && left.w = right.w
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_attribute left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
  && equal_storage left right

(* Exact authored bytes, excluding allocation IDs and derived caches. *)
let geometry_bytes geometry =
  let encode value = Marshal.to_string value [Marshal.No_sharing] in
  let attribute attribute =
    let storage = match Attribute.storage attribute with
      | Float values -> encode values | Int values -> encode values | Text values -> encode values
      | Int_array values -> encode (Packed.Int_array.Private.view values)
      | Float_array values -> encode (Packed.Float_array.Private.view values)
      | Float2 values -> let v = Packed.Float2.Private.view values in encode (v.x, v.y)
      | Float3 values -> let v = Packed.Float3.Private.view values in encode (v.x, v.y, v.z)
      | Float4 values -> let v = Packed.Float4.Private.view values in encode (v.x, v.y, v.z, v.w) in
    Attribute.owner attribute, Attribute.name attribute, Attribute.kind_name attribute, storage in
  let group group = Group.owner group, Group.name group,
    Array.init (Group.length group) (fun i -> Group.mem i group), Group.ordered_elements group in
  let edge_group group = Edge_group.name group,
    Array.init (Edge_group.length group) (fun i -> Edge_group.mem i group) in
  let p = Packed.Float3.Private.view (Geometry.positions geometry) in
  encode (p.x, p.y, p.z, Topology.Private.view (Geometry.topology geometry),
    List.map attribute (Geometry.attributes geometry), List.map group (Geometry.groups geometry),
    List.map edge_group (Geometry.edge_groups geometry))

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && Group.ordered_elements left = Group.ordered_elements right
  && begin
    let equal = ref true in
    for element = 0 to Group.length left - 1 do
      if Group.mem element left <> Group.mem element right then equal := false
    done;
    !equal
  end

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let equal = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
    done;
    !equal
  end

let equal_geometry left right =
  let lp = Packed.Float3.Private.view (Geometry.positions left)
  and rp = Packed.Float3.Private.view (Geometry.positions right)
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal (fun left right ->
       Attribute.owner left = Attribute.owner right
       && String.equal (Attribute.name left) (Attribute.name right)
       && equal_storage left right)
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group
       (Geometry.edge_groups left) (Geometry.edge_groups right)

(* Polygon topologies for these fixtures: the builder offers polylines only. *)
module Tb = struct
  type t = { point_count : int; mutable polygons : int array list; builder : Topology.Builder.t }
  let create ~point_count () =
    { point_count; polygons = []; builder = Topology.Builder.create ~point_count () }
  let add_triangle t a b c = t.polygons <- [| a; b; c |] :: t.polygons
  let add_polygon t points = t.polygons <- points :: t.polygons
  let add_open_polyline t points = Topology.Builder.add_open_polyline t.builder points
  let freeze t = match List.rev t.polygons with
    | [] -> Topology.Builder.freeze t.builder
    | polygons ->
        let offsets = List.fold_left (fun acc p -> (List.hd acc + Array.length p) :: acc) [ 0 ] polygons in
        Topology.polygons_owned ~point_count:t.point_count ~vertex_points:(Array.concat polygons)
          ~primitive_offsets:(Array.of_list (List.rev offsets)) |> Result.get_ok
end
