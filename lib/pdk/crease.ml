open Prismel

type operation = Crease_add | Crease_set | Crease_delete

let fail message = Error ("Pdk.Ops.crease: " ^ message)

let atomic_min target candidate =
  let rec update current =
    if candidate >= current then ()
    else if Atomic.compare_and_set target current candidate then ()
    else update (Atomic.get target)
  in
  update (Atomic.get target)

let block_count length grain =
  if length = 0 then 0 else 1 + ((length - 1) / grain)

let block_bounds length grain block =
  let first = block * grain in
  let remaining = length - first in
  first, if grain >= remaining then length else first + grain

let run ?cancel ~grain count operation =
  let blocks = block_count count grain in
  if blocks > 0 then
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(blocks - 1) (fun block ->
      Cancel.check_opt cancel;
      let first, last = block_bounds count grain block in
      for index = first to last - 1 do
        if index land 4095 = 0 then Cancel.check_opt cancel;
        operation index
      done)

let validate_edges topology edge_count = function
  | None -> Ok ()
  | Some edges
      when Edge_group.topology_data_id edges <> Topology.data_id topology ->
      fail "edge group belongs to a different topology"
  | Some edges when Edge_group.length edges <> edge_count ->
      fail (Printf.sprintf "edge group length %d does not match edge count %d"
        (Edge_group.length edges) edge_count)
  | Some _ -> Ok ()

let selected edges edge = match edges with
  | None -> true
  | Some edges -> Edge_group.mem edge edges

let existing_weights geometry =
  match Geometry.find_attribute ~owner:Attribute.Vertex "creaseweight" geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> Ok (Some values)
       | _ -> fail (Printf.sprintf
           "vertex creaseweight must have scalar float storage, not %s"
           (Attribute.kind_name attribute)))

let validate_weights ?cancel ~grain values =
  let count = Array.length values in
  let first_invalid = Atomic.make count in
  run ?cancel ~grain count (fun vertex ->
    let value = Array.unsafe_get values vertex in
    if not (Float.is_finite value) || value < 0. then
      atomic_min first_invalid vertex);
  let invalid = Atomic.get first_invalid in
  if invalid = count then Ok ()
  else fail (Printf.sprintf
      "vertex creaseweight contains a non-finite or negative value at vertex %d"
      invalid)

let edge_max index values edge =
  let first = Array.unsafe_get index.Topology_index.Private.edge_offsets edge
  and last = Array.unsafe_get index.edge_offsets (edge + 1) in
  let maximum = ref 0. in
  for at = first to last - 1 do
    let vertex = Array.unsafe_get index.edge_vertices at in
    let value = Array.unsafe_get values vertex in
    if value > !maximum then maximum := value
  done;
  !maximum

let add_edge_values ?cancel ~grain ~edges index weight values =
  let edge_count = Array.length index.Topology_index.Private.edge_a in
  let output = Array.make edge_count 0. in
  let first_overflow = Atomic.make edge_count in
  run ?cancel ~grain edge_count (fun edge ->
    if selected edges edge then begin
      let old = match values with
        | None -> 0.
        | Some values -> edge_max index values edge in
      let value = old +. weight in
      if not (Float.is_finite value) then atomic_min first_overflow edge
      else Array.unsafe_set output edge value
    end);
  let invalid = Atomic.get first_overflow in
  if invalid < edge_count then fail (Printf.sprintf
      "adding crease weight exceeds finite floating-point range at edge %d"
      invalid)
  else Ok output

let update_weights ?cancel ~grain ~edges ~operation ~weight index existing =
  let vertex_count = Array.length index.Topology_index.Private.edge_of_vertex in
  let edge_values = match operation with
    | Crease_add when weight = 0. -> Ok None
    | Crease_add ->
        Result.map Option.some
          (add_edge_values ?cancel ~grain ~edges index weight existing)
    | Crease_set | Crease_delete -> Ok None in
  Result.map (fun edge_values ->
    let output = match existing with
      | None -> Array.make vertex_count 0.
      | Some values -> Array.copy values in
    let blocks = block_count vertex_count grain in
    let changed_blocks = Bytes.make blocks '\000' in
    if blocks > 0 then
      Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(blocks - 1)
        (fun block ->
          Cancel.check_opt cancel;
          let first, last = block_bounds vertex_count grain block in
          let changed = ref false in
          for vertex = first to last - 1 do
            if vertex land 4095 = 0 then Cancel.check_opt cancel;
            let edge = Array.unsafe_get index.edge_of_vertex vertex in
            if edge >= 0 && selected edges edge then begin
              let value = match operation with
                | Crease_add when weight = 0. -> Array.unsafe_get output vertex
                | Crease_add -> Array.unsafe_get (Option.get edge_values) edge
                | Crease_set -> weight
                | Crease_delete -> 0. in
              if value <> Array.unsafe_get output vertex then begin
                Array.unsafe_set output vertex value;
                changed := true
              end
            end
          done;
          if !changed then Bytes.unsafe_set changed_blocks block '\001');
    output, Bytes.exists (fun value -> value <> '\000') changed_blocks)
    edge_values

let effective_edge_weights ?cancel ~grain index values =
  let edge_count = Array.length index.Topology_index.Private.edge_a in
  let output = Array.make edge_count 0. in
  run ?cancel ~grain edge_count (fun edge ->
    Array.unsafe_set output edge (edge_max index values edge));
  output

let validate_color ?cancel ~grain values =
  let view = Packed.Float4.Private.view values in
  let count = Array.length view.x in
  let first_invalid = Atomic.make count in
  run ?cancel ~grain count (fun vertex ->
    if not (Float.is_finite (Array.unsafe_get view.x vertex)
        && Float.is_finite (Array.unsafe_get view.y vertex)
        && Float.is_finite (Array.unsafe_get view.z vertex)
        && Float.is_finite (Array.unsafe_get view.w vertex)) then
      atomic_min first_invalid vertex);
  let invalid = Atomic.get first_invalid in
  if invalid = count then Ok view
  else fail (Printf.sprintf
      "vertex Cd contains a non-finite value at vertex %d" invalid)

let visualization_attribute ?cancel ~grain geometry topology index weights =
  let edge_weights = effective_edge_weights ?cancel ~grain index weights in
  if not (Array.exists (fun value -> value > 0.) edge_weights) then Ok None
  else
    let vertex_count = Array.length index.Topology_index.Private.edge_of_vertex in
    let existing = Geometry.find_attribute ~owner:Attribute.Vertex "Cd" geometry in
    let existing_values = match existing with
      | None -> Ok None
      | Some attribute ->
          (match Attribute.Private.storage attribute with
           | Attribute.Float4 values -> Result.map Option.some
               (validate_color ?cancel ~grain values)
           | _ -> fail (Printf.sprintf
               "vertex Cd must have float4 storage, not %s"
               (Attribute.kind_name attribute))) in
    Result.bind existing_values (fun existing_values ->
      let topology = Topology.Private.view topology in
      let point_color_result = match existing_values,
          Geometry.find_attribute ~owner:Attribute.Point "Cd" geometry with
        | Some _, _ -> Ok None
        | None, Some attribute ->
            (match Attribute.Private.storage attribute with
             | Attribute.Float4 values -> Result.map Option.some
                 (validate_color ?cancel ~grain values)
             | _ -> Ok None)
        | None, None -> Ok None in
      Result.bind point_color_result (fun point_color ->
      let make channel default = match existing_values with
        | Some values -> Array.copy (channel values)
        | None ->
            (match point_color with
             | Some values -> Array.init vertex_count (fun vertex ->
                 Array.unsafe_get (channel values)
                   (Array.unsafe_get topology.vertex_points vertex))
             | None -> Array.make vertex_count default) in
      let x = make (fun view -> view.Packed.Float4.Private.x) 1.
      and y = make (fun view -> view.Packed.Float4.Private.y) 1.
      and z = make (fun view -> view.Packed.Float4.Private.z) 1.
      and w = make (fun view -> view.Packed.Float4.Private.w) 1. in
      let blocks = block_count vertex_count grain in
      let changed_blocks = Bytes.make blocks '\000' in
      if blocks > 0 then
        Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(blocks - 1)
          (fun block ->
            Cancel.check_opt cancel;
            let first, last = block_bounds vertex_count grain block in
            let changed = ref false in
            for vertex = first to last - 1 do
              if vertex land 4095 = 0 then Cancel.check_opt cancel;
              let outgoing = Array.unsafe_get index.edge_of_vertex vertex in
              let previous = Array.unsafe_get index.previous_vertex vertex in
              let incoming = if previous < 0 then -1
                else Array.unsafe_get index.edge_of_vertex previous in
              let creased =
                (outgoing >= 0 && Array.unsafe_get edge_weights outgoing > 0.)
                || (incoming >= 0 && Array.unsafe_get edge_weights incoming > 0.) in
              if creased && (Array.unsafe_get x vertex <> 1.
                  || Array.unsafe_get y vertex <> 0.
                  || Array.unsafe_get z vertex <> 0.
                  || Array.unsafe_get w vertex <> 1.) then begin
                Array.unsafe_set x vertex 1.;
                Array.unsafe_set y vertex 0.;
                Array.unsafe_set z vertex 0.;
                Array.unsafe_set w vertex 1.;
                changed := true
              end
            done;
            if !changed then Bytes.unsafe_set changed_blocks block '\001');
      let changed = Bytes.exists (fun value -> value <> '\000') changed_blocks in
      if not changed && Option.is_some existing then Ok None
      else
        Result.bind (Packed.Float4.of_owned ~x ~y ~z ~w) (fun values ->
          Result.map Option.some
            (Attribute.create_owned ~name:"Cd" ~owner:Attribute.Vertex
              (Attribute.Float4 values)))))

let crease ?cancel ?(grain = 16_384) ?edges ?(operation = Crease_add)
    ?(weight = 1.) ?(add_vertex_color = false) geometry =
  Cancel.check_opt cancel;
  if grain <= 0 then fail "grain must be positive"
  else if operation <> Crease_delete
      && (not (Float.is_finite weight) || weight < 0.) then
    fail "crease weight must be finite and non-negative"
  else
    let topology = Geometry.topology geometry in
    let index_value = Topology_index.create ?cancel topology in
    let index = Topology_index.Private.view index_value in
    let edge_count = Array.length index.edge_a in
    Result.bind (validate_edges topology edge_count edges) (fun () ->
    Result.bind (existing_weights geometry) (fun existing ->
    Result.bind (match existing with
      | None -> Ok ()
      | Some values -> validate_weights ?cancel ~grain values) (fun () ->
    let changes_crease = match operation, existing with
      | Crease_delete, None -> false
      | Crease_add, _ when weight = 0. -> false
      | Crease_set, None when weight = 0. -> false
      | _ -> edge_count > 0
          && (match edges with None -> true | Some group -> Edge_group.cardinality group > 0) in
    let updated = if changes_crease then
        update_weights ?cancel ~grain ~edges ~operation ~weight index existing
      else Ok (Option.value ~default:[||] existing, false) in
    Result.bind updated (fun (updated, changed) ->
      let final_weights = if changed then Some updated else existing in
      Result.bind (if add_vertex_color then match final_weights with
        | None -> Ok None
        | Some values ->
            visualization_attribute ?cancel ~grain geometry topology index values
        else Ok None) (fun color ->
      let geometry_result =
        if not changed then Ok geometry
        else if (operation = Crease_delete || weight = 0.)
            && Array.for_all (fun value -> value = 0.) updated then
          Ok (Geometry.without_attribute ~owner:Attribute.Vertex
            "creaseweight" geometry)
        else
          Result.bind
            (Attribute.create_owned ~name:"creaseweight" ~owner:Attribute.Vertex
              (Attribute.Float updated))
            (fun attribute -> Geometry.with_attribute attribute geometry) in
      Result.bind geometry_result (fun output -> match color with
        | None -> Ok output
        | Some attribute -> Geometry.with_attribute attribute output)
      )))))
