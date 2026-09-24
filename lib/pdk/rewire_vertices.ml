open Prismel

exception Rewire_error of string
let fail message = raise (Rewire_error message)

let parallel_for ?cancel ~grain count work =
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
    (fun element ->
      if element land 4095 = 0 then Cancel.check_opt cancel;
      work element)

let target_group_owner = function
  | Attribute.Point -> Group.Point
  | Attribute.Vertex -> Group.Vertex
  | Attribute.Primitive -> Group.Primitive
  | Attribute.Detail -> fail "Rewire Vertices target owner cannot be detail"

let validate_name label name =
  if String.trim name = "" then fail ("Rewire Vertices " ^ label ^ " is empty")

let resolve_selection ?cancel ~grain owner selection topology = match selection with
  | None -> None
  | Some selection ->
      let destination = target_group_owner owner in
      (match Element_selection.promote ?cancel ~grain ~destination selection topology with
       | Ok group -> Some group
       | Error message -> fail ("Rewire Vertices selection: " ^ message))

let resolve_recursive ?cancel target point_count =
  let successor = Array.init point_count (fun point ->
    let destination = target.(point) in
    if destination >= 0 && destination < point_count then destination else point) in
  let resolved = Array.make point_count 0
  and state = Bytes.make point_count '\000'
  and stack = Array.make point_count 0 in
  for start = 0 to point_count - 1 do
    if start land 4095 = 0 then Cancel.check_opt cancel;
    if Bytes.get state start = '\000' then begin
      let top = ref 0 and current = ref start in
      while Bytes.get state !current = '\000' do
        if !top land 4095 = 0 then Cancel.check_opt cancel;
        Bytes.set state !current '\001';
        stack.(!top) <- !current;
        incr top;
        current := successor.(!current)
      done;
      if Bytes.get state !current = '\002' then begin
        let terminal = resolved.(!current) in
        for index = !top - 1 downto 0 do
          if index land 4095 = 0 then Cancel.check_opt cancel;
          let point = stack.(index) in
          resolved.(point) <- terminal;
          Bytes.set state point '\002'
        done
      end else begin
        let cycle_start = ref (!top - 1) in
        while stack.(!cycle_start) <> !current do decr cycle_start done;
        for index = !cycle_start to !top - 1 do
          if index land 4095 = 0 then Cancel.check_opt cancel;
          let point = stack.(index) in
          resolved.(point) <- point;
          Bytes.set state point '\002'
        done;
        for index = !cycle_start - 1 downto 0 do
          if index land 4095 = 0 then Cancel.check_opt cancel;
          let point = stack.(index) in
          resolved.(point) <- !current;
          Bytes.set state point '\002'
        done
      end
    end
  done;
  resolved

let remap_edge_groups ?cancel ~grain ~source_topology ~target_topology groups =
  match groups with
  | [] -> []
  | groups ->
      let source_index = Topology_index.create ?cancel source_topology in
      let source = Topology_index.Private.view source_index
      and target = Topology.Private.view target_topology in
      let target_index = Topology_index.create ?cancel target_topology in
      let target_edge_count = Topology_index.edge_count target_index
      and vertex_count = Array.length source.edge_of_vertex in
      let target_of_vertex = Array.make vertex_count (-1) in
      parallel_for ?cancel ~grain vertex_count (fun vertex ->
        if source.edge_of_vertex.(vertex) >= 0 then begin
          let next = source.next_vertex.(vertex) in
          let edge = Topology_index.find_edge_index target_index
              ~a:target.vertex_points.(vertex) ~b:target.vertex_points.(next) in
          if edge < 0 then fail "Rewire Vertices lost a target corner edge";
          target_of_vertex.(vertex) <- edge
        end);
      let offsets = Array.make (target_edge_count + 1) 0 in
      for vertex = 0 to vertex_count - 1 do
        if vertex land 16_383 = 0 then Cancel.check_opt cancel;
        let edge = target_of_vertex.(vertex) in
        if edge >= 0 then offsets.(edge + 1) <- offsets.(edge + 1) + 1
      done;
      for edge = 0 to target_edge_count - 1 do
        if edge land 16_383 = 0 then Cancel.check_opt cancel;
        offsets.(edge + 1) <- offsets.(edge + 1) + offsets.(edge)
      done;
      let ancestry = Array.make offsets.(target_edge_count) 0
      and cursor = Array.copy offsets in
      for vertex = 0 to vertex_count - 1 do
        if vertex land 16_383 = 0 then Cancel.check_opt cancel;
        let target_edge = target_of_vertex.(vertex) in
        if target_edge >= 0 then begin
          let at = cursor.(target_edge) in
          ancestry.(at) <- source.edge_of_vertex.(vertex);
          cursor.(target_edge) <- at + 1
        end
      done;
      List.map (fun group ->
        let byte_count = (target_edge_count + 7) / 8 in
        let bits = Bytes.make byte_count '\000' in
        parallel_for ?cancel ~grain byte_count (fun byte ->
          let packed = ref 0 in
          for bit = 0 to 7 do
            let edge = (byte lsl 3) + bit in
            if edge < target_edge_count then begin
              let member = ref false and at = ref offsets.(edge) in
              while not !member && !at < offsets.(edge + 1) do
                member := Edge_group.mem ancestry.(!at) group;
                incr at
              done;
              if !member then packed := !packed lor (1 lsl bit)
            end
          done;
          Bytes.unsafe_set bits byte (Char.unsafe_chr !packed));
        Edge_group.Private.of_owned_bits ~topology:target_topology
          ~edge_count:target_edge_count ~name:(Edge_group.name group) bits)
        groups

let select_float ?cancel ~grain mapping source =
  let output = Array.make (Array.length mapping) 0. in
  parallel_for ?cancel ~grain (Array.length mapping) (fun element ->
    output.(element) <- source.(mapping.(element)));
  output

let compact_plan ?cancel source_points target_points point_count =
  let source_used = Bytes.make point_count '\000'
  and target_used = Bytes.make point_count '\000' in
  for vertex = 0 to Array.length source_points - 1 do
    if vertex land 16_383 = 0 then Cancel.check_opt cancel;
    Bytes.set source_used source_points.(vertex) '\001';
    Bytes.set target_used target_points.(vertex) '\001'
  done;
  let retained = ref 0 in
  for point = 0 to point_count - 1 do
    if point land 16_383 = 0 then Cancel.check_opt cancel;
    if Bytes.get source_used point = '\000'
        || Bytes.get target_used point = '\001' then incr retained
  done;
  if !retained = point_count then None
  else begin
    let old_to_new = Array.make point_count (-1)
    and new_to_old = Array.make !retained 0 and next = ref 0 in
    for point = 0 to point_count - 1 do
      if point land 16_383 = 0 then Cancel.check_opt cancel;
      if Bytes.get source_used point = '\000'
          || Bytes.get target_used point = '\001' then begin
        old_to_new.(point) <- !next;
        new_to_old.(!next) <- point;
        incr next
      end
    done;
    Some (old_to_new, new_to_old)
  end

let run ?cancel ?(grain = 16_384) ?selection ?(recursive = false)
    ?(delete_target_attribute = false) ?(keep_unused_points = false)
    ?original_point_attribute ~owner ~target_attribute geometry =
  try
    if grain <= 0 then fail "Rewire Vertices grain must be positive";
    validate_name "target attribute" target_attribute;
    Option.iter (validate_name "original point attribute") original_point_attribute;
    Option.iter (fun name -> if String.equal name "N" then
      fail "Rewire Vertices original point attribute cannot be N")
      original_point_attribute;
    if recursive && owner <> Attribute.Point then
      fail "Rewire Vertices recursive mode requires a point target attribute";
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value
    and point_count = Geometry.point_count geometry in
    let target = match Geometry.find_attribute ~owner target_attribute geometry with
      | None -> fail (Printf.sprintf
          "Rewire Vertices could not find target attribute %S" target_attribute)
      | Some attribute ->
          (match Attribute.Private.storage attribute with
           | Attribute.Int values -> values
           | _ -> fail "Rewire Vertices target attribute must be scalar integer") in
    let selected = resolve_selection ?cancel ~grain owner selection topology_value in
    let recursive_target = if recursive then
        Some (resolve_recursive ?cancel target point_count) else None in
    let source_points = topology.vertex_points
    and target_points = Array.copy topology.vertex_points in
    let valid_target destination = destination >= 0 && destination < point_count in
    (match owner with
     | Attribute.Point ->
         let rewire vertex =
           let point = source_points.(vertex) in
           let destination = match recursive_target with
             | Some values -> values.(point) | None -> target.(point) in
           if valid_target destination && destination <> point then
             target_points.(vertex) <- destination in
         (match selected with
          | None -> parallel_for ?cancel ~grain (Array.length source_points) rewire
          | Some group ->
              parallel_for ?cancel ~grain (Array.length source_points) (fun vertex ->
                if Group.mem source_points.(vertex) group then rewire vertex))
     | Attribute.Vertex ->
         let rewire vertex =
             let destination = target.(vertex) in
             if valid_target destination && destination <> source_points.(vertex)
             then target_points.(vertex) <- destination in
         (match selected with
          | None -> parallel_for ?cancel ~grain (Array.length source_points) rewire
          | Some group ->
              parallel_for ?cancel ~grain (Array.length source_points) (fun vertex ->
                if Group.mem vertex group then rewire vertex))
     | Attribute.Primitive ->
         let rewire primitive =
               let first = topology.primitive_offsets.(primitive)
               and last = topology.primitive_offsets.(primitive + 1)
               and destination = target.(primitive) in
               if valid_target destination then
                 for vertex = first to last - 1 do
                   if destination <> source_points.(vertex) then begin
                     target_points.(vertex) <- destination
                   end
                 done
             in
         (match selected with
          | None -> parallel_for ?cancel ~grain
              (Topology.primitive_count topology_value) rewire
          | Some group -> parallel_for ?cancel ~grain
              (Topology.primitive_count topology_value) (fun primitive ->
                if Group.mem primitive group then rewire primitive))
     | Attribute.Detail -> assert false);
    let changed = ref false and vertex = ref 0 in
    while not !changed && !vertex < Array.length source_points do
      if !vertex land 16_383 = 0 then Cancel.check_opt cancel;
      changed := source_points.(!vertex) <> target_points.(!vertex);
      incr vertex
    done;
    let changed = !changed in
    let compaction = if changed && not keep_unused_points then
        compact_plan ?cancel source_points target_points point_count else None in
    let final_point_count, new_to_old = match compaction with
      | None -> point_count, None
      | Some (old_to_new, new_to_old) ->
          parallel_for ?cancel ~grain (Array.length target_points) (fun vertex ->
            target_points.(vertex) <- old_to_new.(target_points.(vertex)));
          Array.length new_to_old, Some new_to_old in
    let final_topology = if changed then
        Topology.Private.create_validated_owned ~point_count:final_point_count
          ~vertex_points:target_points
          ~primitive_offsets:(Array.copy topology.primitive_offsets)
          ~primitive_kinds:(Bytes.copy topology.primitive_kinds)
      else topology_value in
    let remove_attribute attribute =
      (delete_target_attribute && Attribute.owner attribute = owner
        && String.equal (Attribute.name attribute) target_attribute)
      || (changed && (Attribute.owner attribute = Attribute.Point
          || Attribute.owner attribute = Attribute.Vertex)
          && String.equal (Attribute.name attribute) "N") in
    let attributes = Geometry.attributes geometry
      |> List.filter (fun attribute -> not (remove_attribute attribute))
      |> List.map (fun attribute -> match new_to_old, Attribute.owner attribute with
        | Some mapping, Attribute.Point ->
            Topology_remap.attribute ?cancel ~grain mapping attribute
        | _ -> attribute) in
    let groups = Geometry.groups geometry |> List.map (fun group ->
      match new_to_old, Group.owner group with
      | Some mapping, Group.Point -> Topology_remap.group ?cancel ~grain mapping group
      | _ -> group) in
    let positions = match new_to_old with
      | None -> Geometry.positions geometry
      | Some mapping ->
          let source = Packed.Float3.Private.view (Geometry.positions geometry) in
          Packed.Float3.Private.of_owned_exn
            ~x:(select_float ?cancel ~grain mapping source.x)
            ~y:(select_float ?cancel ~grain mapping source.y)
            ~z:(select_float ?cancel ~grain mapping source.z) in
    let edge_groups = if changed then remap_edge_groups ?cancel ~grain
        ~source_topology:topology_value ~target_topology:final_topology
        (Geometry.edge_groups geometry) else Geometry.edge_groups geometry in
    let output = Geometry.create ~positions ~topology:final_topology
        ~attributes ~groups ~edge_groups ()
      |> function Ok output -> output | Error message -> fail message in
    let output = match original_point_attribute with
      | None -> output
      | Some name ->
          let attribute = Attribute.create_owned ~owner:Attribute.Vertex ~name
              (Attribute.Int (Array.copy source_points))
            |> function Ok value -> value | Error message -> fail message in
          Geometry.with_attribute attribute output
          |> function Ok value -> value | Error message -> fail message in
    if not changed && not delete_target_attribute
        && original_point_attribute = None then Ok geometry
    else Ok output
  with Rewire_error message -> Error message
