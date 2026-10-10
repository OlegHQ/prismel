open Rdk
open Rdk_test_support

let add storage ~owner ~name geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let add_group ~owner ~name elements geometry =
  let length = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  let group = Group.ordered ~owner ~name ~length elements |> Result.get_ok in
  Geometry.with_group group geometry |> Result.get_ok

let group_values ~owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | None -> fail ("missing group " ^ name)
  | Some group -> Array.init (Group.length group) (fun element ->
      Group.mem element group)

let packed3 values =
  let count = Array.length values in
  Packed.Float3.Private.of_owned_exn
    ~x:(Array.init count (fun index -> let x, _, _ = values.(index) in x))
    ~y:(Array.init count (fun index -> let _, y, _ = values.(index) in y))
    ~z:(Array.init count (fun index -> let _, _, z = values.(index) in z))

let make_geometry positions add_primitives =
  let topology = Topology.Builder.create ~point_count:(Array.length positions) () in
  add_primitives topology;
  Geometry.create ~positions:(packed3 positions)
    ~topology:(Topology.Builder.freeze topology) () |> Result.get_ok

let points count =
  Geometry.create
    ~positions:(Packed.Float3.Private.of_owned_exn
      ~x:(Array.make count 0.) ~y:(Array.make count 0.) ~z:(Array.make count 0.))
    ~topology:(Topology.empty ~point_count:count) () |> Result.get_ok

let add_drivers ~owner primitives uvw geometry =
  geometry
  |> add (Attribute.Int primitives) ~owner ~name:"source_primitive"
  |> add (Attribute.Float3 (packed3 uvw)) ~owner ~name:"source_uvw"

let int_rows rows =
  let offsets = Array.make (Array.length rows + 1) 0 in
  Array.iteri (fun row values ->
    offsets.(row + 1) <- offsets.(row) + Array.length values) rows;
  Packed.Int_array.create_owned ~offsets
    ~values:(Array.concat (Array.to_list rows)) |> Result.get_ok

let float_rows rows =
  let offsets = Array.make (Array.length rows + 1) 0 in
  Array.iteri (fun row values ->
    offsets.(row + 1) <- offsets.(row) + Array.length values) rows;
  Packed.Float_array.create_owned ~offsets
    ~values:(Array.concat (Array.to_list rows)) |> Result.get_ok

let add_weight_drivers ~owner numbers weights geometry =
  geometry
  |> add (Attribute.Int_array (int_rows numbers)) ~owner ~name:"source_elements"
  |> add (Attribute.Float_array (float_rows weights)) ~owner ~name:"source_weights"

let float_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail ("wrong float storage for " ^ name))
  | None -> fail ("missing " ^ name)

let int_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("wrong int storage for " ^ name))
  | None -> fail ("missing " ^ name)

let text_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values -> values
       | _ -> fail ("wrong text storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float2_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values -> Packed.Float2.Private.view values
       | _ -> fail ("wrong float2 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float3_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail ("wrong float3 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float4_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail ("wrong float4 storage for " ^ name))
  | None -> fail ("missing " ^ name)

let int_array_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int_array values -> values
       | _ -> fail ("wrong int-array storage for " ^ name))
  | None -> fail ("missing " ^ name)

let float_array_values ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float_array values -> values
       | _ -> fail ("wrong float-array storage for " ^ name))
  | None -> fail ("missing " ^ name)

let interpolate ?grain ?selection ?pre_scale ?blend ?unmatched ~target_owner
    ~attributes ~source target =
  Attribute_ops.interpolate ?grain ?selection ?pre_scale ?blend ?unmatched
    ~target_owner ~attributes ~source ~target () |> get_ok

let near left right = Float.abs (left -. right) <= 1e-12

let test_packed_array_storage_and_structural_ops () =
  List.iter (fun (offsets, values) ->
    match Packed.Int_array.create_owned ~offsets ~values with
    | Error _ -> ()
    | Ok _ -> fail "invalid CSR integer array accepted")
    [([||], [||]); ([|1|], [||]); ([|0;2;1|], [|1;2|]);
      ([|0;3|], [|1;2|]); ([|0;1|], [|1;2|])];
  let packed = int_rows [|[|1;2|]; [||]; [|3|]|] in
  let copy = Packed.Int_array.get packed 0 in
  copy.(0) <- 99;
  if Packed.Int_array.length packed <> 3
      || Packed.Int_array.value_count packed <> 3
      || Packed.Int_array.get packed 0 <> [|1;2|]
      || Packed.Int_array.payload_bytes packed
         <> ((4 + 3) * (Sys.word_size / 8)) then
    fail "packed integer-array invariants/copy/payload";
  let base = points 3
      |> add (Attribute.Int_array packed) ~owner:Attribute.Point ~name:"neighbors"
      |> add (Attribute.Float_array (float_rows
        [|[|0.25;0.75|]; [||]; [|1.|]|]))
           ~owner:Attribute.Point ~name:"weights" in
  let duplicated = Instance_copy.duplicate ~copies:2 base |> Result.get_ok in
  let rows = int_array_values ~owner:Attribute.Point "neighbors" duplicated in
  if Packed.Int_array.length rows <> 9
      || Array.init 9 (Packed.Int_array.get rows)
         <> [|[|1;2|];[||];[|3|];[|1;2|];[||];[|3|];
              [|1;2|];[||];[|3|]|] then
    fail "Duplicate did not remap packed array rows";
  let merged = Mesh_merge.run [base; base] |> Result.get_ok in
  let rows = int_array_values ~owner:Attribute.Point "neighbors" merged in
  if Array.init 6 (Packed.Int_array.get rows)
      <> [|[|1;2|];[||];[|3|];[|1;2|];[||];[|3|]|] then
    fail "Merge did not concatenate packed array rows";
  let fused = Fuse_grid.fuse ~tolerance:0. base |> Result.get_ok in
  if Geometry.point_count fused <> 1
      || Packed.Int_array.get
           (int_array_values ~owner:Attribute.Point "neighbors" fused) 0
         <> [|1;2|] then
    fail "Fuse did not select the stable first packed array row"

let expect_code code label = function
  | Error error when String.equal (Error.code error) code -> ()
  | _ -> fail label

let run () =
  test_packed_array_storage_and_structural_ops ();
  print_endline "attribute interpolate tests passed"
