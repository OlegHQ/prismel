open Prismel_math

let finite value = Float.is_finite value

let remap_attribute ?cancel ~grain vertex_map primitive_map attribute =
  match Attribute.owner attribute with
  | Attribute.Point | Attribute.Detail -> Ok attribute
  | Attribute.Vertex ->
      Ok (Topology_remap.attribute ?cancel ~grain vertex_map attribute)
  | Attribute.Primitive ->
      Ok (Topology_remap.attribute ?cancel ~grain primitive_map attribute)

let remap_group ~grain vertex_map primitive_map group =
  match Group.owner group with
  | Group.Point -> group
  | Group.Vertex -> Topology_remap.group ~grain vertex_map group
  | Group.Primitive -> Topology_remap.group ~grain primitive_map group

let edge_flip ?cancel ?(grain = 16_384) ?edges ?(cycles = 1)
    ?(cycle_vertex_attributes = true) ?(recompute_point_normals = false)
    geometry =
  try
    if grain <= 0 then invalid_arg "Pdk.Ops.edge_flip: grain must be positive";
    if cycles < 0 then invalid_arg
        "Pdk.Ops.edge_flip: cycles must be non-negative";
    Cancel.check_opt cancel;
    let source_topology = Geometry.topology geometry in
    let source = Topology.Private.view source_topology in
    let source_index_value = Topology_index.create ?cancel source_topology in
    let source_index = Topology_index.Private.view source_index_value in
    let edge_count = Array.length source_index.edge_a
    and primitive_count = Bytes.length source.primitive_kinds
    and point_count = source.point_count in
    (match edges with
     | Some group when Edge_group.topology_data_id group
         <> Topology.data_id source_topology ->
         invalid_arg "Pdk.Ops.edge_flip: edge selection belongs to a different topology"
     | Some group when Edge_group.length group <> edge_count ->
         invalid_arg
           "Pdk.Ops.edge_flip: edge selection length does not match topology edge count"
     | None | Some _ -> ());
    if cycles = 0 || (match edges with None -> true
        | Some group -> Edge_group.cardinality group = 0) then Ok geometry
    else begin
      let selected edge = match edges with
        | None -> false
        | Some group -> Edge_group.mem edge group in
      let plan_vertex_a = Array.make edge_count (-1)
      and plan_vertex_b = Array.make edge_count (-1)
      and plan_primitive_a = Array.make edge_count (-1)
      and plan_primitive_b = Array.make edge_count (-1)
      and plan_size_a = Array.make edge_count 0
      and plan_size_b = Array.make edge_count 0
      and plan_shift = Array.make edge_count 0
      and primitive_owner = Array.make primitive_count (-1)
      and point_stamp = Array.make point_count (-1) in
      let first_error = ref None and changed = ref 0 in
      let fail edge message = match !first_error with
        | None -> first_error := Some (edge, message)
        | Some (known, _) when edge < known -> first_error := Some (edge, message)
        | Some _ -> () in
      let advance first size vertex amount =
        first + (((vertex - first) + amount) mod size) in
      let ring_point vertex_a vertex_b size_a size_b index =
        let primitive_a = source_index.primitive_of_vertex.(vertex_a)
        and primitive_b = source_index.primitive_of_vertex.(vertex_b) in
        let first_a = source.primitive_offsets.(primitive_a)
        and first_b = source.primitive_offsets.(primitive_b) in
        if index = 0 then source.vertex_points.(vertex_a)
        else if index < size_b - 1 then
          source.vertex_points.(advance first_b size_b vertex_b (index + 1))
        else if index = size_b - 1 then
          source.vertex_points.(source_index.next_vertex.(vertex_a))
        else source.vertex_points.(advance first_a size_a vertex_a
            (index - size_b + 2)) in
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      for edge = 0 to edge_count - 1 do
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        if selected edge then begin
          let first_incidence = source_index.edge_offsets.(edge)
          and last_incidence = source_index.edge_offsets.(edge + 1) in
          if last_incidence - first_incidence <> 2 then fail edge
              "selected edge must have exactly two incident polygons"
          else begin
            let vertex_a = source_index.edge_vertices.(first_incidence)
            and vertex_b = source_index.edge_vertices.(first_incidence + 1) in
            let primitive_a = source_index.primitive_of_vertex.(vertex_a)
            and primitive_b = source_index.primitive_of_vertex.(vertex_b) in
            if primitive_a = primitive_b then fail edge
                "selected edge occurs twice in one polygon"
            else if Bytes.get source.primitive_kinds primitive_a <> '\000'
                || Bytes.get source.primitive_kinds primitive_b <> '\000'
            then fail edge "selected edge must join two polygon primitives"
            else begin
              let next_a = source_index.next_vertex.(vertex_a)
              and next_b = source_index.next_vertex.(vertex_b) in
              if next_a < 0 || next_b < 0
                  || source.vertex_points.(vertex_a)
                     <> source.vertex_points.(next_b)
                  || source.vertex_points.(next_a)
                     <> source.vertex_points.(vertex_b)
              then fail edge
                  "selected polygons have inconsistent orientation across their edge"
              else begin
                let size_a = source.primitive_offsets.(primitive_a + 1)
                    - source.primitive_offsets.(primitive_a)
                and size_b = source.primitive_offsets.(primitive_b + 1)
                    - source.primitive_offsets.(primitive_b) in
                if size_a < 3 || size_b < 3 then fail edge
                    "selected edge is incident to an under-cardinality polygon"
                else if size_a > max_int - size_b + 2 then fail edge
                    "joined polygon boundary exceeds integer limits"
                else begin
                  let ring_size = size_a + size_b - 2 in
                  let shift = cycles mod ring_size
                  and attribute_a = cycles mod size_a
                  and attribute_b = cycles mod size_b in
                  let effective = shift <> 0 || cycle_vertex_attributes
                      && (attribute_a <> 0 || attribute_b <> 0) in
                  if effective then begin
                    if primitive_owner.(primitive_a) >= 0
                        || primitive_owner.(primitive_b) >= 0 then fail edge
                        "selected edges may not share an incident polygon; sequence dependent flips as separate nodes"
                    else begin
                      let duplicate = ref (-1) in
                      for index = 0 to ring_size - 1 do
                        let point = ring_point vertex_a vertex_b size_a size_b index in
                        if point_stamp.(point) = edge then duplicate := point
                        else point_stamp.(point) <- edge
                      done;
                      if !duplicate >= 0 then fail edge (Printf.sprintf
                          "joined polygon boundary repeats point %d" !duplicate)
                      else begin
                        let valid_diagonal = ref true in
                        if shift <> 0 then begin
                          let left = ring_point vertex_a vertex_b size_a size_b shift
                          and right = ring_point vertex_a vertex_b size_a size_b
                              ((shift + size_b - 1) mod ring_size) in
                          let existing = Topology_index.find_edge_index
                              source_index_value ~a:left ~b:right in
                          if left = right then begin
                            valid_diagonal := false;
                            fail edge "flipped edge would reference one point twice"
                          end else if existing >= 0 && existing <> edge then begin
                            valid_diagonal := false;
                            fail edge (Printf.sprintf
                              "flipped edge would duplicate source edge %d" existing)
                          end else if not (finite positions.x.(left)
                              && finite positions.y.(left)
                              && finite positions.z.(left)
                              && finite positions.x.(right)
                              && finite positions.y.(right)
                              && finite positions.z.(right)) then begin
                            valid_diagonal := false;
                            fail edge "flipped edge has a non-finite endpoint"
                          end else if positions.x.(left) = positions.x.(right)
                              && positions.y.(left) = positions.y.(right)
                              && positions.z.(left) = positions.z.(right) then begin
                            valid_diagonal := false;
                            fail edge "flipped edge would have zero geometric length"
                          end
                        end;
                        if !valid_diagonal && !first_error = None then begin
                          primitive_owner.(primitive_a) <- edge;
                          primitive_owner.(primitive_b) <- edge;
                          plan_vertex_a.(edge) <- vertex_a;
                          plan_vertex_b.(edge) <- vertex_b;
                          plan_primitive_a.(edge) <- primitive_a;
                          plan_primitive_b.(edge) <- primitive_b;
                          plan_size_a.(edge) <- size_a;
                          plan_size_b.(edge) <- size_b;
                          plan_shift.(edge) <- shift;
                          incr changed
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      done;
      match !first_error with
      | Some (edge, message) -> Error (Printf.sprintf
          "Pdk.Ops.edge_flip: edge %d: %s" edge message)
      | None when !changed = 0 -> Ok geometry
      | None ->
          let vertex_points = Array.copy source.vertex_points
          and vertex_map = Array.init (Array.length source.vertex_points) Fun.id in
          let fill_plan edge =
            let vertex_a = plan_vertex_a.(edge) in
            if vertex_a >= 0 then begin
              let vertex_b = plan_vertex_b.(edge)
              and primitive_a = plan_primitive_a.(edge)
              and primitive_b = plan_primitive_b.(edge)
              and size_a = plan_size_a.(edge)
              and size_b = plan_size_b.(edge)
              and shift = plan_shift.(edge) in
              let ring_size = size_a + size_b - 2
              and first_a = source.primitive_offsets.(primitive_a)
              and first_b = source.primitive_offsets.(primitive_b) in
              let diagonal_b = (shift + size_b - 1) mod ring_size in
              for local = 0 to size_a - 1 do
                let target = advance first_a size_a vertex_a local in
                let ring = if local = 0 then shift
                  else if local = 1 then diagonal_b
                  else (diagonal_b + local - 1) mod ring_size in
                vertex_points.(target) <-
                  ring_point vertex_a vertex_b size_a size_b ring;
                if cycle_vertex_attributes then vertex_map.(target) <-
                    advance first_a size_a vertex_a
                      ((local + (cycles mod size_a)) mod size_a)
              done;
              for local = 0 to size_b - 1 do
                let target = advance first_b size_b vertex_b local in
                let ring = if local = 0 then diagonal_b
                  else if local = 1 then shift
                  else (shift + local - 1) mod ring_size in
                vertex_points.(target) <-
                  ring_point vertex_a vertex_b size_a size_b ring;
                if cycle_vertex_attributes then vertex_map.(target) <-
                    advance first_b size_b vertex_b
                      ((local + (cycles mod size_b)) mod size_b)
              done
            end in
          Parallel.for_ ~chunk_size:(max 1 (grain / 4)) ~start:0
            ~finish:(edge_count - 1) (fun edge ->
              if edge land 4095 = 0 then Cancel.check_opt cancel;
              fill_plan edge);
          let output_topology = Topology.Private.create_validated_owned
              ~point_count ~vertex_points
              ~primitive_offsets:(Array.copy source.primitive_offsets)
              ~primitive_kinds:(Bytes.copy source.primitive_kinds) in
          let output_view = Topology.Private.view output_topology in
          let validation_grain = max 1 (grain / 4) in
          let block_count = (edge_count + validation_grain - 1)
              / validation_grain in
          let first_failure = Atomic.make max_int in
          let rec record_failure edge =
            let known = Atomic.get first_failure in
            if edge < known
                && not (Atomic.compare_and_set first_failure known edge) then
              record_failure edge in
          Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(block_count - 1)
            (fun block ->
              let scratch = Polygon_triangulation.create_scratch () in
              let first = block * validation_grain
              and last = min (edge_count - 1)
                  (((block + 1) * validation_grain) - 1) in
              for edge = first to last do
                if edge land 4095 = 0 then Cancel.check_opt cancel;
                if edge < Atomic.get first_failure
                    && plan_vertex_a.(edge) >= 0 && plan_shift.(edge) <> 0
                then begin
                  let valid primitive =
                    match Polygon_triangulation.primitive ?cancel ~positions
                        ~topology:output_view ~scratch primitive
                        ~emit:(fun _ _ _ _ -> ()) with
                    | Ok () -> true
                    | Error _ -> false in
                  if not (valid plan_primitive_a.(edge))
                      || not (valid plan_primitive_b.(edge)) then
                    record_failure edge
                end
              done);
          let failure = Atomic.get first_failure in
          (if failure <> max_int then
             let scratch = Polygon_triangulation.create_scratch () in
             let rec diagnose = function
               | [] -> Error (Printf.sprintf
                   "Pdk.Ops.edge_flip: edge %d creates an invalid polygon"
                   failure)
               | primitive :: rest ->
                   match Polygon_triangulation.primitive ?cancel ~positions
                       ~topology:output_view ~scratch primitive
                       ~emit:(fun _ _ _ _ -> ()) with
                   | Ok () -> diagnose rest
                   | Error message -> Error (Printf.sprintf
                       "Pdk.Ops.edge_flip: edge %d creates invalid polygon %d: %s"
                       failure primitive message) in
             diagnose [plan_primitive_a.(failure); plan_primitive_b.(failure)]
           else
              let had_point_normals = Geometry.find_attribute
                  ~owner:Attribute.Point "N" geometry <> None in
              let primitive_map = Array.init primitive_count Fun.id in
              let rec remap_attributes result = function
                | [] -> Ok (List.rev result)
                | attribute :: rest ->
                    if String.equal (Attribute.name attribute) "N"
                        && (Attribute.owner attribute = Attribute.Point
                            || Attribute.owner attribute = Attribute.Vertex)
                    then remap_attributes result rest
                    else if cycle_vertex_attributes
                        && Attribute.owner attribute = Attribute.Vertex then
                      Result.bind (remap_attribute ?cancel ~grain vertex_map
                          primitive_map attribute) (fun mapped ->
                        remap_attributes (mapped :: result) rest)
                    else remap_attributes (attribute :: result) rest in
              Result.bind (remap_attributes [] (Geometry.attributes geometry))
                (fun attributes ->
                  let groups = Geometry.groups geometry |> List.map (fun group ->
                    if cycle_vertex_attributes
                        && Group.owner group = Group.Vertex then
                      remap_group ~grain vertex_map primitive_map group
                    else group) in
                  let target_index = Topology_index.create ?cancel output_topology in
                  let target_edge_count = Topology_index.edge_count target_index in
                  let source_of_target = Array.init target_edge_count (fun target ->
                    let a, b = Topology_index.edge_points target_index target in
                    Topology_index.find_edge_index source_index_value ~a ~b) in
                  for edge = 0 to edge_count - 1 do
                    if plan_vertex_a.(edge) >= 0 && plan_shift.(edge) <> 0 then begin
                      let vertex_a = plan_vertex_a.(edge)
                      and vertex_b = plan_vertex_b.(edge)
                      and size_a = plan_size_a.(edge)
                      and size_b = plan_size_b.(edge)
                      and shift = plan_shift.(edge) in
                      let ring_size = size_a + size_b - 2 in
                      let a = ring_point vertex_a vertex_b size_a size_b shift
                      and b = ring_point vertex_a vertex_b size_a size_b
                          ((shift + size_b - 1) mod ring_size) in
                      let target = Topology_index.find_edge_index target_index
                          ~a ~b in
                      if target < 0 then invalid_arg
                          "Pdk.Ops.edge_flip: flipped edge is absent from output";
                      source_of_target.(target) <- edge
                    end
                  done;
                  if Array.exists (( = ) (-1)) source_of_target then Error
                      "Pdk.Ops.edge_flip: output edge has no source ancestry"
                  else begin
                    let edge_groups = Geometry.edge_groups geometry
                        |> List.map (fun group ->
                          Edge_group.init ~grain ~topology:output_topology
                            ~index:target_index ~name:(Edge_group.name group)
                            (fun target -> Edge_group.mem
                              source_of_target.(target) group)) in
                    Result.bind (Geometry.create
                        ~positions:(Geometry.positions geometry)
                        ~topology:output_topology ~attributes ~groups
                        ~edge_groups ()) (fun output ->
                      if not recompute_point_normals || not had_point_normals
                      then Ok output
                      else Deform.normals ?cancel ~grain output)
                  end))
    end
  with Invalid_argument message -> Error message

let run = edge_flip

let run_checked ?cancel ?grain ?edges ?cycles ?cycle_vertex_attributes
    ?recompute_point_normals geometry =
  Error.guard ~operation:"edge_flip" ~code:"invalid_topology" (fun () ->
    run ?cancel ?grain ?edges ?cycles ?cycle_vertex_attributes
      ?recompute_point_normals geometry)
