open Prismel_math

let get_ok = function Ok value -> value | Error message -> invalid_arg message

let points values =
  let count = Array.length values in
  let builder = Packed.Float3.Builder.create count in
  Array.iteri (fun index (x, y, z) ->
    Packed.Float3.Builder.set builder index x y z) values;
  let positions = Packed.Float3.Builder.freeze builder in
  Geometry.create ~positions ~topology:(Topology.empty ~point_count:count) ()
  |> get_ok

let same_attribute_schema left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && String.equal (Attribute.kind_name left) (Attribute.kind_name right)

let find_matching attribute geometry =
  Geometry.attributes geometry
  |> List.find_opt (same_attribute_schema attribute)

let same_group_schema left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)

let find_matching_group group geometry =
  Geometry.groups geometry |> List.find_opt (same_group_schema group)

let find_matching_edge_group group geometry =
  Geometry.find_edge_group (Edge_group.name group) geometry

let concat_float2 attributes =
  let views = Array.map (fun attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float2 values -> Packed.Float2.Private.view values
    | _ -> assert false) attributes in
  Packed.Float2.of_owned ~x:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float2.Private.x) views)))
    ~y:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float2.Private.y) views)))
  |> get_ok

let concat_float3 attributes =
  let views = Array.map (fun attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float3 values -> Packed.Float3.Private.view values
    | _ -> assert false) attributes in
  Packed.Float3.Private.of_owned_exn
    ~x:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float3.Private.x) views)))
    ~y:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float3.Private.y) views)))
    ~z:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float3.Private.z) views)))

let concat_float4 attributes =
  let views = Array.map (fun attribute -> match Attribute.Private.storage attribute with
    | Attribute.Float4 values -> Packed.Float4.Private.view values
    | _ -> assert false) attributes in
  Packed.Float4.of_owned
    ~x:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.x) views)))
    ~y:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.y) views)))
    ~z:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.z) views)))
    ~w:(Array.concat (Array.to_list (Array.map (fun v -> v.Packed.Float4.Private.w) views)))
  |> get_ok

let concatenate_attribute template attributes =
  let storage = match Attribute.Private.storage template with
    | Attribute.Float _ -> Attribute.Float (Array.concat (Array.to_list
        (Array.map (fun a -> match Attribute.Private.storage a with Attribute.Float x -> x | _ -> assert false) attributes)))
    | Attribute.Int _ -> Attribute.Int (Array.concat (Array.to_list
        (Array.map (fun a -> match Attribute.Private.storage a with Attribute.Int x -> x | _ -> assert false) attributes)))
    | Attribute.Text _ -> Attribute.Text (Array.concat (Array.to_list
        (Array.map (fun a -> match Attribute.Private.storage a with Attribute.Text x -> x | _ -> assert false) attributes)))
    | Attribute.Float2 _ -> Attribute.Float2 (concat_float2 attributes)
    | Attribute.Float3 _ -> Attribute.Float3 (concat_float3 attributes)
    | Attribute.Float4 _ -> Attribute.Float4 (concat_float4 attributes)
    | Attribute.Int_array _ -> Attribute.Int_array (Ragged_ops.concat_int
        (Array.map (fun attribute -> match Attribute.Private.storage attribute with
          | Attribute.Int_array values -> values | _ -> assert false) attributes))
    | Attribute.Float_array _ -> Attribute.Float_array (Ragged_ops.concat_float
        (Array.map (fun attribute -> match Attribute.Private.storage attribute with
          | Attribute.Float_array values -> values | _ -> assert false) attributes)) in
  Attribute.create_owned ~name:(Attribute.name template)
    ~owner:(Attribute.owner template) storage

let merge ?cancel ?(grain = 16_384) geometries =
  if grain <= 0 then invalid_arg "Pdk.Mesh_merge.merge: grain must be positive";
  match geometries with
  | [] -> Ok (points [||])
  | first :: _ ->
      let first_attributes = Geometry.attributes first in
      let first_groups = Geometry.groups first in
      let first_edge_groups = Geometry.edge_groups first in
      let exact_schema geometry =
        let attributes = Geometry.attributes geometry in
        List.length attributes = List.length first_attributes
        && List.for_all (fun template -> find_matching template geometry <> None)
             first_attributes in
      let exact_group_schema geometry =
        let groups = Geometry.groups geometry in
        List.length groups = List.length first_groups
        && List.for_all (fun template -> find_matching_group template geometry <> None)
             first_groups in
      let exact_edge_group_schema geometry =
        let groups = Geometry.edge_groups geometry in
        List.length groups = List.length first_edge_groups
        && List.for_all (fun template ->
          find_matching_edge_group template geometry <> None) first_edge_groups in
      if not (List.for_all exact_schema geometries) then
        Error "Pdk.Mesh_merge.merge: attribute schemas must match exactly"
      else if not (List.for_all exact_group_schema geometries) then
        Error "Pdk.Mesh_merge.merge: group schemas must match exactly"
      else if not (List.for_all exact_edge_group_schema geometries) then
        Error "Pdk.Mesh_merge.merge: edge group schemas must match exactly"
      else if List.exists (fun attribute -> Attribute.owner attribute = Attribute.Detail)
          first_attributes then
        Error "Pdk.Mesh_merge.merge: detail attributes need an explicit merge policy"
      else
        let point_count = List.fold_left (fun n g -> n + Geometry.point_count g) 0 geometries
        and vertex_count = List.fold_left (fun n g -> n + Geometry.vertex_count g) 0 geometries
        and primitive_count = List.fold_left (fun n g -> n + Geometry.primitive_count g) 0 geometries in
        let px = Array.make point_count 0. and py = Array.make point_count 0.
        and pz = Array.make point_count 0. in
        let vertex_points = Array.make vertex_count 0
        and primitive_offsets = Array.make (primitive_count + 1) 0
        and primitive_kinds = Bytes.make primitive_count '\000' in
        let point_at = ref 0 and vertex_at = ref 0 and primitive_at = ref 0 in
        List.iter (fun geometry ->
          Cancel.check_opt cancel;
          let positions = Packed.Float3.Private.view (Geometry.positions geometry)
          and topology = Topology.Private.view (Geometry.topology geometry) in
          let points_here = Geometry.point_count geometry
          and vertices_here = Geometry.vertex_count geometry
          and primitives_here = Geometry.primitive_count geometry in
          Array.blit positions.x 0 px !point_at points_here;
          Array.blit positions.y 0 py !point_at points_here;
          Array.blit positions.z 0 pz !point_at points_here;
          let point_offset = !point_at and vertex_offset = !vertex_at
          and primitive_offset = !primitive_at in
          if vertices_here > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(vertices_here - 1) (fun index ->
                if index land 16383 = 0 then Cancel.check_opt cancel;
                vertex_points.(vertex_offset + index) <-
                  topology.vertex_points.(index) + point_offset);
          if primitives_here > 0 then Parallel.for_ ~chunk_size:grain ~start:1
              ~finish:primitives_here (fun index ->
                if index land 16383 = 0 then Cancel.check_opt cancel;
                primitive_offsets.(primitive_offset + index) <-
                  topology.primitive_offsets.(index) + vertex_offset);
          Bytes.blit topology.primitive_kinds 0 primitive_kinds !primitive_at primitives_here;
          point_at := !point_at + points_here;
          vertex_at := !vertex_at + vertices_here;
          primitive_at := !primitive_at + primitives_here) geometries;
        let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
        let topology = Topology.Private.create_validated_owned ~point_count
            ~vertex_points ~primitive_offsets ~primitive_kinds in
        let topology_result = Ok topology in
        Result.bind topology_result (fun topology ->
          let rec build result = function
            | [] -> Ok (List.rev result)
            | template :: rest ->
                let values = Array.of_list (List.map (fun geometry ->
                  Option.get (find_matching template geometry)) geometries) in
                Result.bind (concatenate_attribute template values)
                  (fun attribute -> build (attribute :: result) rest) in
          Result.bind (build [] first_attributes) (fun attributes ->
            let owner_count geometry = function
              | Group.Point -> Geometry.point_count geometry
              | Group.Vertex -> Geometry.vertex_count geometry
              | Group.Primitive -> Geometry.primitive_count geometry in
            let groups = List.map (fun template ->
              let total = List.fold_left (fun count geometry ->
                count + owner_count geometry (Group.owner template)) 0 geometries in
              let builder = Group.Builder.create ~owner:(Group.owner template)
                  ~name:(Group.name template) total in
              let offset = ref 0 in
              let sources = List.map (fun geometry ->
                let group = Option.get (find_matching_group template geometry) in
                Group.iter (fun index -> Group.Builder.set builder (!offset + index) true) group;
                let source_offset = !offset in
                offset := !offset + owner_count geometry (Group.owner template);
                source_offset, group) geometries in
              let target = Group.Builder.freeze builder in
              if not (List.exists (fun (_, group) -> Group.is_ordered group) sources)
              then target
              else begin
                let order = Array.make (Group.cardinality target) 0
                and output = ref 0 in
                List.iter (fun (source_offset, group) ->
                  Group.iter_ordered (fun element ->
                    order.(!output) <- source_offset + element;
                    incr output) group) sources;
                Group.Private.with_owned_order order target
              end) first_groups in
            let edge_groups = match first_edge_groups with
              | [] -> []
              | templates ->
                  let target_index = Topology_index.create ?cancel topology in
                  List.map (fun template ->
                    let builder = Edge_group.Builder.create ~topology
                        ~index:target_index ~name:(Edge_group.name template) in
                    let point_offset = ref 0 in
                    List.iter (fun geometry ->
                      let source_index = Topology_index.create ?cancel
                          (Geometry.topology geometry) in
                      let group = Option.get
                          (find_matching_edge_group template geometry) in
                      Edge_group.iter (fun edge ->
                        let a, b = Topology_index.edge_points source_index edge in
                        match Topology_index.find_edge target_index
                            ~a:(a + !point_offset) ~b:(b + !point_offset) with
                        | None -> ()
                        | Some target -> Edge_group.Builder.set builder target true)
                        group;
                      point_offset := !point_offset + Geometry.point_count geometry)
                      geometries;
                    Edge_group.Builder.freeze builder) templates in
            Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ()))

let run ?cancel ?grain geometries =
  Error.guard ~operation:"merge" ~code:"schema_mismatch"
    (fun () -> merge ?cancel ?grain geometries)
