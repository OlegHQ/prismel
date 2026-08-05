open Prismel

let select ?cancel ~grain mapping source =
  let count = Array.length mapping in
  if count = 0 then [||]
  else begin
    let output = Array.make count source.(mapping.(0)) in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(count - 1) (fun index ->
      if index land 4095 = 0 then Cancel.check_opt cancel;
      output.(index) <- source.(mapping.(index)));
    output
  end

let attribute ?cancel ~grain mapping attribute =
  let storage = match Attribute.Private.storage attribute with
    | Attribute.Float values -> Attribute.Float (select ?cancel ~grain mapping values)
    | Attribute.Int values -> Attribute.Int (select ?cancel ~grain mapping values)
    | Attribute.Text values -> Attribute.Text (select ?cancel ~grain mapping values)
    | Attribute.Int_array values ->
        Attribute.Int_array (Ragged_ops.remap_int ?cancel ~grain mapping values)
    | Attribute.Float_array values ->
        Attribute.Float_array (Ragged_ops.remap_float ?cancel ~grain mapping values)
    | Attribute.Float2 values ->
        let values = Packed.Float2.Private.view values in
        Attribute.Float2 (Packed.Float2.of_owned
          ~x:(select ?cancel ~grain mapping values.x)
          ~y:(select ?cancel ~grain mapping values.y) |> Result.get_ok)
    | Attribute.Float3 values ->
        let values = Packed.Float3.Private.view values in
        Attribute.Float3 (Packed.Float3.Private.of_owned_exn
          ~x:(select ?cancel ~grain mapping values.x)
          ~y:(select ?cancel ~grain mapping values.y)
          ~z:(select ?cancel ~grain mapping values.z))
    | Attribute.Float4 values ->
        let values = Packed.Float4.Private.view values in
        Attribute.Float4 (Packed.Float4.of_owned
          ~x:(select ?cancel ~grain mapping values.x)
          ~y:(select ?cancel ~grain mapping values.y)
          ~z:(select ?cancel ~grain mapping values.z)
          ~w:(select ?cancel ~grain mapping values.w) |> Result.get_ok) in
  Attribute.create_owned ~name:(Attribute.name attribute)
    ~owner:(Attribute.owner attribute) storage |> Result.get_ok

let group ?cancel ~grain mapping group =
  let output = Group.init ~grain ~owner:(Group.owner group)
      ~name:(Group.name group) (Array.length mapping)
      (fun output ->
        if output land 4095 = 0 then Cancel.check_opt cancel;
        Group.mem mapping.(output) group) in
  Group.Private.remap_order ~source:group ~source_of_target:mapping output

let attributes ?cancel ~grain ~point_map ~vertex_map ~primitive_map geometry =
  List.map (fun value -> match Attribute.owner value with
    | Attribute.Point -> attribute ?cancel ~grain point_map value
    | Attribute.Vertex -> attribute ?cancel ~grain vertex_map value
    | Attribute.Primitive -> attribute ?cancel ~grain primitive_map value
    | Attribute.Detail -> value) (Geometry.attributes geometry)

let groups ?cancel ~grain ~point_map ~vertex_map ~primitive_map geometry =
  List.map (fun value -> match Group.owner value with
    | Group.Point -> group ?cancel ~grain point_map value
    | Group.Vertex -> group ?cancel ~grain vertex_map value
    | Group.Primitive -> group ?cancel ~grain primitive_map value)
    (Geometry.groups geometry)

let preserving_points ?cancel ~grain ~topology ~vertex_map ~primitive_map geometry =
  let source_topology = Geometry.topology geometry in
  if Topology.point_count topology <> Geometry.point_count geometry then
    Error "Topology_remap.preserving_points: point count changed"
  else begin
    let attributes = List.map (fun value -> match Attribute.owner value with
      | Attribute.Point | Attribute.Detail -> value
      | Attribute.Vertex -> attribute ?cancel ~grain vertex_map value
      | Attribute.Primitive -> attribute ?cancel ~grain primitive_map value)
        (Geometry.attributes geometry)
    and groups = List.map (fun value -> match Group.owner value with
      | Group.Point -> value
      | Group.Vertex -> group ?cancel ~grain vertex_map value
      | Group.Primitive -> group ?cancel ~grain primitive_map value)
        (Geometry.groups geometry) in
    let edge_groups = match Geometry.edge_groups geometry with
      | [] -> Ok []
      | values ->
          let source_index = Topology_index.create ?cancel source_topology
          and target_index = Topology_index.create ?cancel topology
          and point_map = Array.init (Geometry.point_count geometry) Fun.id in
          let rec loop result = function
            | [] -> Ok (List.rev result)
            | value :: rest ->
                Result.bind (Edge_group.remap ?cancel ~source_index
                    ~target_topology:topology ~target_index ~point_map value)
                  (fun value -> loop (value :: result) rest) in
          loop [] values in
    Result.bind edge_groups (fun edge_groups ->
      Geometry.create ~positions:(Geometry.positions geometry) ~topology
        ~attributes ~groups ~edge_groups ())
  end

let split_point_edge_groups ?cancel ~grain ~source_index ~target_topology groups =
  if grain <= 0 then invalid_arg
      "Topology_remap.split_point_edge_groups: grain must be positive";
  match groups with
  | [] -> Ok []
  | groups ->
      let source = Topology_index.Private.view source_index
      and target = Topology.Private.view target_topology in
      if Array.length target.vertex_points <> Array.length source.next_vertex then
        Error "split-point edge remap requires unchanged corner cardinality"
      else begin
        let affinity_error = List.find_opt (fun group ->
          Edge_group.topology_data_id group
            <> Topology_index.topology_data_id source_index) groups in
        match affinity_error with
        | Some group -> Error (Printf.sprintf
            "split-point edge group %S belongs to a different topology"
            (Edge_group.name group))
        | None ->
            let lookup = Topology_edge_lookup.create ?cancel target in
            let edge_count = Topology_edge_lookup.count lookup in
            let source_of_target = Array.make edge_count (-1)
            and failure = ref None in
            for source_edge = 0 to Array.length source.edge_a - 1 do
              if source_edge land 4_095 = 0 then Cancel.check_opt cancel;
              for at = source.edge_offsets.(source_edge)
                  to source.edge_offsets.(source_edge + 1) - 1 do
                let vertex = source.edge_vertices.(at) in
                let next = source.next_vertex.(vertex) in
                if next < 0 then failure := Some
                    "source topology exposed an incomplete edge"
                else begin
                  let target_edge = Topology_edge_lookup.find lookup
                      ~a:target.vertex_points.(vertex)
                      ~b:target.vertex_points.(next) in
                  if target_edge < 0 then failure := Some
                      "target topology lost a source corner edge"
                  else if source_of_target.(target_edge) >= 0
                      && source_of_target.(target_edge) <> source_edge then
                    failure := Some
                      "target split edge has conflicting source ancestry"
                  else source_of_target.(target_edge) <- source_edge
                end
              done
            done;
            (match !failure with
             | Some message -> Error message
             | None ->
                 let missing = ref (-1) in
                 for edge = 0 to edge_count - 1 do
                   if source_of_target.(edge) < 0 then missing := edge
                 done;
                 if !missing >= 0 then Error (Printf.sprintf
                     "target split edge %d has no source ancestry" !missing)
                 else
                   Ok (List.map (fun group ->
                     let byte_count = (edge_count + 7) / 8 in
                     let bits = Bytes.make byte_count '\000' in
                     if byte_count > 0 then Parallel.for_
                         ~chunk_size:(max 1 (grain / 8)) ~start:0
                         ~finish:(byte_count - 1) (fun byte ->
                           if byte land 511 = 0 then Cancel.check_opt cancel;
                           let value = ref 0 in
                           for bit = 0 to 7 do
                             let edge = (byte lsl 3) + bit in
                             if edge < edge_count
                                 && Edge_group.mem source_of_target.(edge) group
                             then value := !value lor (1 lsl bit)
                           done;
                           Bytes.unsafe_set bits byte (Char.unsafe_chr !value));
                     Edge_group.Private.of_owned_bits ~topology:target_topology
                       ~edge_count ~name:(Edge_group.name group) bits) groups))
      end
