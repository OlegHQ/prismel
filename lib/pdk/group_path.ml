open Prismel

type mode = Through_each | Start_end_pairs
type ending = Stop_at_end | Close_path

exception Invalid of string

let fail message = raise (Invalid ("Group Find Path: " ^ message))
let byte_count length = (length + 7) / 8

let bit_mem bits index =
  Char.code (Bytes.unsafe_get bits (index lsr 3))
  land (1 lsl (index land 7)) <> 0

let bit_set bits index =
  let byte = index lsr 3 and mask = 1 lsl (index land 7) in
  Bytes.unsafe_set bits byte
    (Char.chr (Char.code (Bytes.unsafe_get bits byte) lor mask))

let[@inline always] distance ax ay az bx by bz =
  let dx = bx -. ax and dy = by -. ay and dz = bz -. az in
  let scale = max (abs_float dx) (max (abs_float dy) (abs_float dz)) in
  if not (Float.is_finite scale) then Float.infinity
  else if scale = 0. then 0.
  else
    let x = dx /. scale and y = dy /. scale and z = dz /. scale in
    let length = scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
    if Float.is_finite length then length else Float.infinity

let check_positions ?cancel ~grain geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let point_count = Geometry.point_count geometry in
  let invalid_points = Bytes.make point_count '\000' in
  if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(point_count - 1) (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if not (Float.is_finite positions.x.(point)
            && Float.is_finite positions.y.(point)
            && Float.is_finite positions.z.(point)) then
          Bytes.unsafe_set invalid_points point '\001');
  let point = ref 0 in
  while !point < point_count && Bytes.unsafe_get invalid_points !point = '\000' do
    incr point
  done;
  if !point < point_count then
    fail (Printf.sprintf "point %d has a non-finite position" !point);
  positions

let checked_edge_lengths ?cancel ~grain geometry index =
  let positions = check_positions ?cancel ~grain geometry
  and view = Topology_index.Private.view index in
  let edge_count = Array.length view.edge_a in
  let lengths = Array.make edge_count 0.
  and invalid_edges = Bytes.make edge_count '\000' in
  if edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(edge_count - 1) (fun edge ->
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
        let length = distance positions.x.(a) positions.y.(a) positions.z.(a)
            positions.x.(b) positions.y.(b) positions.z.(b) in
        if Float.is_finite length then lengths.(edge) <- length
        else Bytes.unsafe_set invalid_edges edge '\001');
  let edge = ref 0 in
  while !edge < edge_count && Bytes.unsafe_get invalid_edges !edge = '\000' do
    incr edge
  done;
  if !edge < edge_count then
    fail (Printf.sprintf "edge %d length is not representable" !edge);
  lengths

type primitive_graph = {
  topology : Topology.Private.view;
  index : Topology_index.Private.view;
}

type graph =
  | Point_graph of Topology_index.Private.view
  | Primitive_graph of primitive_graph

let graph_owner = function
  | Point_graph _ -> Group.Point
  | Primitive_graph _ -> Group.Primitive

let graph_count = function
  | Point_graph view -> Array.length view.point_edge_offsets - 1
  | Primitive_graph graph -> Bytes.length graph.topology.primitive_kinds

let graph_relation_count = function
  | Point_graph view -> Array.length view.edge_a
  | Primitive_graph graph -> Array.length graph.index.edge_a

let checked_primitive_lengths ?cancel ~grain geometry index =
  if Topology_index.non_manifold_edge_count index > 0 then
    fail "primitive paths require manifold topology";
  let positions = check_positions ?cancel ~grain geometry
  and topology = Topology.Private.view (Geometry.topology geometry)
  and view = Topology_index.Private.view index in
  let primitive_count = Bytes.length topology.primitive_kinds
  and edge_count = Array.length view.edge_a in
  let cx = Array.make primitive_count 0.
  and cy = Array.make primitive_count 0.
  and cz = Array.make primitive_count 0.
  and invalid_primitives = Bytes.make primitive_count '\000' in
  if primitive_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(primitive_count - 1) (fun primitive ->
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        let count = last - first in
        cx.(primitive) <- 0.;
        for vertex = first to last - 1 do
          let point = topology.vertex_points.(vertex) in
          let x = abs_float positions.x.(point) in
          if x > cx.(primitive) then cx.(primitive) <- x;
          let y = abs_float positions.y.(point) in
          if y > cx.(primitive) then cx.(primitive) <- y;
          let z = abs_float positions.z.(point) in
          if z > cx.(primitive) then cx.(primitive) <- z
        done;
        let scale = cx.(primitive) in
        if count <= 0 || not (Float.is_finite scale) then
          Bytes.unsafe_set invalid_primitives primitive '\001'
        else if scale > 0. then begin
          cx.(primitive) <- 0.;
          for vertex = first to last - 1 do
            let point = topology.vertex_points.(vertex) in
            cx.(primitive) <- cx.(primitive) +. (positions.x.(point) /. scale);
            cy.(primitive) <- cy.(primitive) +. (positions.y.(point) /. scale);
            cz.(primitive) <- cz.(primitive) +. (positions.z.(point) /. scale)
          done;
          let divisor = float_of_int count in
          cx.(primitive) <- (cx.(primitive) /. divisor) *. scale;
          cy.(primitive) <- (cy.(primitive) /. divisor) *. scale;
          cz.(primitive) <- (cz.(primitive) /. divisor) *. scale;
          if not (Float.is_finite cx.(primitive)
              && Float.is_finite cy.(primitive)
              && Float.is_finite cz.(primitive)) then
            Bytes.unsafe_set invalid_primitives primitive '\001'
        end);
  let primitive = ref 0 in
  while !primitive < primitive_count
      && Bytes.unsafe_get invalid_primitives !primitive = '\000' do
    incr primitive
  done;
  if !primitive < primitive_count then
    fail (Printf.sprintf "primitive %d centroid is not representable" !primitive);
  let lengths = Array.make edge_count 0.
  and invalid_edges = Bytes.make edge_count '\000' in
  if edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(edge_count - 1) (fun edge ->
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        let first = view.edge_offsets.(edge)
        and last = view.edge_offsets.(edge + 1) in
        if last - first = 2 then begin
          let left = view.primitive_of_vertex.(view.edge_vertices.(first))
          and right = view.primitive_of_vertex.(view.edge_vertices.(first + 1)) in
          let length = distance cx.(left) cy.(left) cz.(left)
              cx.(right) cy.(right) cz.(right) in
          if Float.is_finite length then lengths.(edge) <- length
          else Bytes.unsafe_set invalid_edges edge '\001'
        end);
  let edge = ref 0 in
  while !edge < edge_count && Bytes.unsafe_get invalid_edges !edge = '\000' do
    incr edge
  done;
  if !edge < edge_count then
    fail (Printf.sprintf
      "primitive-center distance across edge %d is not representable" !edge);
  Primitive_graph { topology; index = view }, lengths

let validate_group ~label ~owner ~length group =
  if Group.owner group <> owner then
    fail (label ^ " has the wrong owner")
  else if Group.length group <> length then
    fail (Printf.sprintf "%s length %d does not match %s count %d"
      label (Group.length group)
      (match owner with Group.Point -> "point" | Group.Vertex -> "vertex"
       | Group.Primitive -> "primitive") length)

type scratch = {
  depths : int array;
  distances : float array;
  previous : int array;
  queue : int array;
}

let create_scratch point_count = {
  depths = Array.make point_count (-1);
  distances = Array.make point_count 0.;
  previous = Array.make point_count (-1);
  queue = Array.make point_count 0;
}

let find ?cancel ~scratch ~graph ~lengths ~allowed ~used ~blocked_elements
    ~blocked_edges ~start ~finish () =
  let element_count = graph_count graph in
  if Array.length scratch.depths <> element_count then
    invalid_arg "Group Find Path: scratch length does not match owner count";
  Array.fill scratch.depths 0 element_count (-1);
  let depths = scratch.depths and distances = scratch.distances
  and previous = scratch.previous and queue = scratch.queue in
  let element_allowed element =
    element = start || element = finish
    || (allowed element
        && (match used with None -> true | Some bits -> not (bit_mem bits element))
        && (match blocked_elements with
            | None -> true | Some bits -> not (bit_mem bits element))) in
  let owner_name = match graph_owner graph with
    | Group.Point -> "point" | Group.Vertex -> "vertex"
    | Group.Primitive -> "primitive" in
  if not (allowed start) then
    fail (Printf.sprintf "start %s %d is constrained" owner_name start);
  if not (allowed finish) then
    fail (Printf.sprintf "end %s %d is constrained" owner_name finish);
  depths.(start) <- 0;
  distances.(start) <- 0.;
  queue.(0) <- start;
  let head = ref 0 and tail = ref 1 and overflow = ref false in
  let[@inline always] relax element edge next =
    if element_allowed next then begin
      let next_depth = depths.(element) + 1
      and next_distance = distances.(element) +. lengths.(edge) in
      if not (Float.is_finite next_distance) then overflow := true
      else if depths.(next) < 0
          || next_depth < depths.(next)
          || (next_depth = depths.(next)
              && (next_distance < distances.(next)
                  || (next_distance = distances.(next)
                      && element < previous.(next)))) then begin
        if depths.(next) < 0 then begin
          queue.(!tail) <- next;
          incr tail
        end;
        depths.(next) <- next_depth;
        distances.(next) <- next_distance;
        previous.(next) <- element
      end
    end in
  while !head < !tail
      && (depths.(finish) < 0 || depths.(queue.(!head)) < depths.(finish)) do
    let element = queue.(!head) in
    if !head land 4095 = 0 then Cancel.check_opt cancel;
    incr head;
    match graph with
    | Point_graph view ->
        let first = view.point_edge_offsets.(element)
        and last = view.point_edge_offsets.(element + 1) in
        for slot = first to last - 1 do
          let edge = view.point_edges.(slot) in
          if match blocked_edges with None -> true
              | Some bits -> not (bit_mem bits edge) then begin
            let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
            relax element edge (if a = element then b else a)
          end
        done
    | Primitive_graph graph ->
        let first = graph.topology.primitive_offsets.(element)
        and last = graph.topology.primitive_offsets.(element + 1) in
        for vertex = first to last - 1 do
          let edge = graph.index.edge_of_vertex.(vertex) in
          if edge >= 0
              && (match blocked_edges with None -> true
                  | Some bits -> not (bit_mem bits edge)) then begin
            let edge_first = graph.index.edge_offsets.(edge)
            and edge_last = graph.index.edge_offsets.(edge + 1) in
            if edge_last - edge_first = 2 then begin
              let left = graph.index.primitive_of_vertex.(
                  graph.index.edge_vertices.(edge_first))
              and right = graph.index.primitive_of_vertex.(
                  graph.index.edge_vertices.(edge_first + 1)) in
              relax element edge (if left = element then right else left)
            end
          end
        done
  done;
  if !overflow then fail "accumulated path length is not representable";
  if depths.(finish) < 0 then
    Error (Printf.sprintf "no path from %s %d to %s %d"
      owner_name start owner_name finish)
  else begin
    let path = Array.make (depths.(finish) + 1) start and element = ref finish in
    for output = Array.length path - 1 downto 0 do
      path.(output) <- !element;
      if output > 0 then element := previous.(!element)
    done;
    Ok path
  end

let join_contiguous paths =
  let total = Array.fold_left (fun total path ->
      total + Array.length path) 0 paths
      - max 0 (Array.length paths - 1) in
  let output = Array.make total 0 and at = ref 0 in
  Array.iteri (fun path_index path ->
    let first = if path_index = 0 then 0 else 1 in
    for index = first to Array.length path - 1 do
      output.(!at) <- path.(index);
      incr at
    done) paths;
  output

let close ?cancel ~scratch ~index ~graph ~lengths ~allowed ~used primary =
  let element_count = graph_count graph
  and edge_count = graph_relation_count graph in
  if Array.length primary < 2 then Error "cannot close a zero-length path"
  else
    let blocked_elements = Bytes.make (byte_count element_count) '\000'
    and blocked_edges = Bytes.make (byte_count edge_count) '\000' in
    for path_index = 1 to Array.length primary - 2 do
      bit_set blocked_elements primary.(path_index)
    done;
    let block_connection left right = match graph with
      | Point_graph _ ->
          (match Topology_index.find_edge index ~a:left ~b:right with
           | None -> false
           | Some edge -> bit_set blocked_edges edge; true)
      | Primitive_graph graph ->
          let first = graph.topology.primitive_offsets.(left)
          and last = graph.topology.primitive_offsets.(left + 1)
          and found = ref false in
          for vertex = first to last - 1 do
            let edge = graph.index.edge_of_vertex.(vertex) in
            if edge >= 0 then begin
              let edge_first = graph.index.edge_offsets.(edge)
              and edge_last = graph.index.edge_offsets.(edge + 1) in
              for slot = edge_first to edge_last - 1 do
                let primitive = graph.index.primitive_of_vertex.(
                    graph.index.edge_vertices.(slot)) in
                if primitive = right then begin
                  bit_set blocked_edges edge;
                  found := true
                end
              done
            end
          done;
          !found in
    for path_index = 0 to Array.length primary - 2 do
      if not (block_connection primary.(path_index) primary.(path_index + 1)) then
        fail "internal path relation is missing from the topology index"
    done;
    Result.map (fun secondary ->
      let internal = max 0 (Array.length secondary - 2) in
      let output = Array.make (Array.length primary + internal) 0 in
      Array.blit primary 0 output 0 (Array.length primary);
      if internal > 0 then
        Array.blit secondary 1 output (Array.length primary) internal;
      output)
      (find ?cancel ~scratch ~graph ~lengths ~allowed ~used
        ~blocked_elements:(Some blocked_elements)
        ~blocked_edges:(Some blocked_edges)
        ~start:primary.(Array.length primary - 1) ~finish:primary.(0) ())

let run ?cancel ?(grain = 16_384) ?(mode = Through_each)
    ?(ending = Stop_at_end) ?(avoid_self_intersection = true) ?collision
    ?(contain = false) ~base ~name geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    if String.trim name = "" then fail "output group name must not be empty";
    Cancel.check_opt cancel;
    let owner = Group.owner base in
    let element_count = match owner with
      | Group.Point -> Geometry.point_count geometry
      | Group.Primitive -> Geometry.primitive_count geometry
      | Group.Vertex -> fail "vertex paths are not supported" in
    validate_group ~label:"base group" ~owner ~length:element_count base;
    let base_order = match Group.Private.order_view base with
      | Some order -> order
      | None -> fail "base group must have an explicit order" in
    if Array.length base_order = 0 then fail "base group must not be empty";
    Option.iter (validate_group ~label:"collision group" ~owner
      ~length:element_count) collision;
    if contain && collision = None then
      fail "contain requires a collision group";
    (match mode with
     | Through_each -> ()
     | Start_end_pairs when Array.length base_order land 1 <> 0 ->
         fail "start/end-pair mode requires an even number of base elements"
     | Start_end_pairs -> ());
    let topology = Geometry.topology geometry in
    let index = Topology_index.create ?cancel topology in
    let view = Topology_index.Private.view index in
    let graph, lengths = match owner with
      | Group.Point ->
          Point_graph view, checked_edge_lengths ?cancel ~grain geometry index
      | Group.Primitive ->
          checked_primitive_lengths ?cancel ~grain geometry index
      | Group.Vertex -> assert false in
    let allowed element = match collision with
      | None -> true
      | Some group ->
          if contain then Group.mem element group
          else not (Group.mem element group) in
    let owner_name = match owner with
      | Group.Point -> "point" | Group.Primitive -> "primitive"
      | Group.Vertex -> assert false in
    Array.iter (fun element ->
      if not (allowed element) then
        fail (Printf.sprintf "base %s %d is constrained" owner_name element))
      base_order;
    let pairs = match mode with
      | Through_each -> Array.init (max 0 (Array.length base_order - 1))
          (fun pair -> base_order.(pair), base_order.(pair + 1))
      | Start_end_pairs -> Array.init (Array.length base_order / 2)
          (fun pair -> base_order.(pair * 2), base_order.((pair * 2) + 1)) in
    let scratch_mutex = Mutex.create () and free_scratch = ref [] in
    let with_scratch operation =
      Mutex.lock scratch_mutex;
      let available = match !free_scratch with
        | scratch :: rest -> free_scratch := rest; Some scratch
        | [] -> None in
      Mutex.unlock scratch_mutex;
      let scratch = match available with
        | Some scratch -> scratch
        | None -> create_scratch element_count in
      Fun.protect ~finally:(fun () ->
        Mutex.lock scratch_mutex;
        free_scratch := scratch :: !free_scratch;
        Mutex.unlock scratch_mutex)
        (fun () -> operation scratch) in
    let no_elements = None and no_edges = None in
    let shortest scratch used (start, finish) =
      find ?cancel ~scratch ~graph ~lengths ~allowed ~used
        ~blocked_elements:no_elements ~blocked_edges:no_edges ~start ~finish () in
    let first_error results =
      let error = ref None in
      Array.iteri (fun pair -> function
        | Ok _ -> ()
        | Error message when !error = None ->
            error := Some (Printf.sprintf "segment %d: %s" pair message)
        | Error _ -> ()) results;
      !error in
    let solve_primary_segments used =
      if used = None then
        Parallel.init_array ~grain:1 (Array.length pairs) (fun pair ->
          with_scratch (fun scratch -> shortest scratch None pairs.(pair)))
      else begin
        let results = Array.make (Array.length pairs) (Ok [||])
        and failed = ref false in
        with_scratch (fun scratch ->
          for pair = 0 to Array.length pairs - 1 do
            if not !failed then begin
              let result = shortest scratch used pairs.(pair) in
              results.(pair) <- result;
              match result, used with
              | Error _, _ -> failed := true
              | Ok path, Some used -> Array.iter (bit_set used) path
              | Ok _, None -> assert false
            end
          done);
        results
      end in
    let paths = match mode with
      | Through_each ->
          let used = if avoid_self_intersection
            then Some (Bytes.make (byte_count element_count) '\000') else None in
          let segments = solve_primary_segments used in
          begin match first_error segments with
          | Some message -> Error message
          | None ->
              let segments = Array.map Result.get_ok segments in
              let primary = if Array.length segments = 0
                then Array.copy base_order else join_contiguous segments in
              begin match ending with
              | Stop_at_end -> Ok [|primary|]
              | Close_path -> with_scratch (fun scratch ->
                  Result.map (fun path -> [|path|])
                    (close ?cancel ~scratch ~index ~graph ~lengths ~allowed
                      ~used primary))
              end
          end
      | Start_end_pairs when not avoid_self_intersection ->
          let results = Parallel.init_array ~grain:1 (Array.length pairs)
              (fun pair -> with_scratch (fun scratch ->
                Result.bind (shortest scratch None pairs.(pair))
                  (fun primary -> match ending with
                    | Stop_at_end -> Ok primary
                    | Close_path -> close ?cancel ~scratch ~index ~graph ~lengths
                        ~allowed ~used:None primary))) in
          begin match first_error results with
          | Some message -> Error message
          | None -> Ok (Array.map Result.get_ok results)
          end
      | Start_end_pairs ->
          let used = Bytes.make (byte_count element_count) '\000'
          and results = Array.make (Array.length pairs) (Ok [||])
          and failed = ref false in
          with_scratch (fun scratch ->
            for pair = 0 to Array.length pairs - 1 do
              if not !failed then begin
                let result = Result.bind
                    (shortest scratch (Some used) pairs.(pair)) (fun primary ->
                      Array.iter (bit_set used) primary;
                      match ending with
                      | Stop_at_end -> Ok primary
                      | Close_path -> close ?cancel ~scratch ~index ~graph ~lengths
                          ~allowed ~used:(Some used) primary) in
                results.(pair) <- result;
                match result with
                | Error _ -> failed := true
                | Ok path -> Array.iter (bit_set used) path
              end
            done);
          begin match first_error results with
          | Some message -> Error message
          | None -> Ok (Array.map Result.get_ok results)
          end in
    match paths with
    | Error message -> Error message
    | Ok paths ->
        let seen = Bytes.make (byte_count element_count) '\000'
        and order = Array.make element_count 0 and count = ref 0 in
        Array.iter (Array.iter (fun point ->
          if not (bit_mem seen point) then begin
            bit_set seen point;
            order.(!count) <- point;
            incr count
          end)) paths;
        let order = Array.sub order 0 !count in
        Result.bind (Group.ordered ~owner ~name
            ~length:element_count order) (fun group ->
          Geometry.with_group group geometry)
  with
  | Invalid message -> Error message
  | Invalid_argument message -> Error message
