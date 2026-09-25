open Procedural
let pointer (x, y) = float x, float y
let mouse_press (button, point) = Prismel.Event.MousePressed (button, pointer point)
let mouse_release (button, point) = Prismel.Event.MouseReleased (button, pointer point)
let mouse_move point = Prismel.Event.MouseMoved (pointer point)

let repeats = 10_000
let move_repeats = 10

let frame ?(mouse = 0, 0) ?(events = []) () : Prismel.Frame.t = {
  width = 1_200; height = 760; size = 1_200, 760;
  drawable_width = 1_200; drawable_height = 760;
  drawable_size = 1_200, 760; pixel_scale = 1., 1.;
  time = 0.; dt = 1. /. 60.; fps = 60.; count = 0;
  mouse = (float (fst mouse), float (snd mouse));
  mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events;
}

let percentile values fraction =
  Array.sort Float.compare values;
  values.(min (Array.length values - 1)
    (max 0 (int_of_float (Float.ceil
      (fraction *. float_of_int (Array.length values))) - 1)))

let rec take count values = match count, values with
  | count, _ when count <= 0 -> []
  | _, [] -> []
  | count, value :: rest -> value :: take (count - 1) rest

let graph count =
  let rec divisor candidate =
    if candidate <= 2 || count mod candidate = 0 then candidate
    else divisor (candidate - 1) in
  let width = divisor (min count 64) in
  let created = ref width in
  let generation = ref 0 in
  let layer = ref (Array.init width (fun index ->
    Sop.points ~label:(Printf.sprintf "source-%d" index)
      [|float_of_int index, 0., 0.|])) in
  while !created < count do
    let size = min width (count - !created) in
    let previous = !layer in
    layer := Array.init size (fun index ->
      let left = previous.(index mod Array.length previous)
      and right = previous.((index + 1) mod Array.length previous) in
      Sop.merge ~label:(Printf.sprintf "node-%d-%d" !generation index)
        [left; right]);
    created := !created + size;
    incr generation
  done;
  Sop.merge ~label:"output" (Array.to_list !layer)

(* One UI handle; each step is a full UI frame (build, layout, paint). *)
let ui = Pxui.Ui.create ()
let step view (frame : Prismel.Frame.t) =
  Pxui.Ui.frame ui frame (fun ui -> Pxui_graph.update view ui frame)
let paint view (frame : Prismel.Frame.t) =
  let view, _ = step view { frame with events = [] } in
  ignore (Sys.opaque_identity (Pxui.Ui.scene ui)); view

let measure count =
  let view = Pxui_graph.create ~width:1200 ~height:760 (graph count) in
  ignore (paint view (frame ()));
  Gc.full_major ();
  let static_before = Gc.allocated_bytes () in
  let static_samples = Array.make 100 0. in
  for index = 0 to Array.length static_samples - 1 do
    let started = Unix.gettimeofday () in
    ignore (paint view (frame ()));
    static_samples.(index) <- Unix.gettimeofday () -. started
  done;
  Printf.printf "pxui_graph_static_frame,%d,%.9f,%.9f,%.0f\n%!"
    count (percentile (Array.copy static_samples) 0.5)
    (percentile static_samples 0.95)
    ((Gc.allocated_bytes () -. static_before) /. float (Array.length static_samples));
  let nodes = Pxui_graph.node_views view in
  let targets = nodes |> List.to_seq |> Seq.take 32 |> Array.of_seq
    |> Array.map (fun node ->
      let x, y, width, height = node.Pxui_graph.bounds in
      x + (width / 2), y + (height / 2)) in
  let wire_targets = Pxui_graph.Private.edge_query_points view ~limit:32 in
  let samples = Array.make repeats 0.
  and edge_samples = Array.make repeats 0. in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let hits = ref 0 and max_candidates = ref 0
  and max_edge_candidates = ref 0 in
  for index = 0 to repeats - 1 do
    let point = targets.(index mod Array.length targets) in
    let started = Unix.gettimeofday () in
    if Option.is_some (Pxui_graph.Private.hit_node_id view point) then incr hits;
    samples.(index) <- Unix.gettimeofday () -. started;
    max_candidates := max !max_candidates
      (Pxui_graph.Private.hit_candidates view point);
    max_edge_candidates := max !max_edge_candidates
      (Pxui_graph.Private.hit_edge_candidates view
        wire_targets.(index mod Array.length wire_targets));
    let edge_point = wire_targets.(index mod Array.length wire_targets) in
    let started = Unix.gettimeofday () in
    ignore (Pxui_graph.Private.hit_edge_id view edge_point);
    edge_samples.(index) <- Unix.gettimeofday () -. started
  done;
  let allocated = Gc.allocated_bytes () -. before in
  let first_node = List.find (fun (node : Pxui_graph.node_view) ->
    let x, y, width, height = node.bounds in
    x >= 0 && y >= 0 && x + width < 1_200 && y + height < 760) nodes in
  let node_x, node_y, node_width, node_height = first_node.bounds in
  let start = node_x + (node_width / 2), node_y + (node_height / 2) in
  let moving, _ = step (paint (Pxui_graph.select first_node.id view)
      (frame ~mouse:start ()))
      (frame ~mouse:start ~events:[mouse_press
        (Prismel.Input.LeftButton, start)] ()) in
  let moving = ref moving and move_samples = Array.make move_repeats 0. in
  ignore (paint !moving (frame ~mouse:start ()));
  Gc.full_major ();
  let move_before = Gc.allocated_bytes () in
  for index = 0 to move_repeats - 1 do
    let point = fst start + index + 1, snd start + index + 1 in
    let started = Unix.gettimeofday () in
    let next, _ = step !moving
        (frame ~mouse:point ~events:[mouse_move point] ()) in
    ignore (Sys.opaque_identity (Pxui.Ui.scene ui));
    move_samples.(index) <- Unix.gettimeofday () -. started;
    moving := next
  done;
  let move_allocated = Gc.allocated_bytes () -. move_before in
  Gc.full_major ();
  let release_before = Gc.allocated_bytes () in
  let release_started = Unix.gettimeofday () in
  let _, _ = step !moving
      (frame ~mouse:(fst start + move_repeats, snd start + move_repeats)
        ~events:[mouse_release (Prismel.Input.LeftButton,
          (fst start + move_repeats, snd start + move_repeats))] ()) in
  ignore (Sys.opaque_identity (Pxui.Ui.scene ui));
  let release_seconds = Unix.gettimeofday () -. release_started
  and release_allocated = Gc.allocated_bytes () -. release_before in
  let bulk_count = min 100 (List.length nodes) in
  let bulk_ids = first_node.id :: (nodes
      |> List.filter (fun (node : Pxui_graph.node_view) ->
        node.id <> first_node.id)
      |> take (bulk_count - 1)
      |> List.map (fun (node : Pxui_graph.node_view) -> node.id)) in
  let bulk, _ = step (paint (Pxui_graph.select_nodes bulk_ids view)
      (frame ~mouse:start ()))
      (frame ~mouse:start ~events:[mouse_press
        (Prismel.Input.LeftButton, start)] ()) in
  let bulk_target = fst start + 2, snd start + 2 in
  let bulk, _ = step bulk
      (frame ~mouse:bulk_target ~events:[mouse_move bulk_target] ()) in
  Gc.full_major ();
  let bulk_before = Gc.allocated_bytes () and bulk_started = Unix.gettimeofday () in
  let _, _ = step bulk
      (frame ~mouse:bulk_target ~events:[mouse_release
        (Prismel.Input.LeftButton, bulk_target)] ()) in
  ignore (Sys.opaque_identity (Pxui.Ui.scene ui));
  let bulk_seconds = Unix.gettimeofday () -. bulk_started
  and bulk_allocated = Gc.allocated_bytes () -. bulk_before in
  (* Zoom fully out, then pan: every frame re-describes the canvas. *)
  let centre = 600, 380 in
  let zoomed, _ = step (paint view (frame ~mouse:centre ())) (frame ~mouse:centre
      ~events:(List.init 20 (fun _ -> Prismel.Event.MouseScrolled (0., (-1.)))) ()) in
  let panning, _ = step zoomed (frame ~mouse:centre
      ~events:[mouse_press (Prismel.Input.RightButton, centre)] ()) in
  let panning = ref panning and pan_samples = Array.make move_repeats 0. in
  ignore (paint !panning (frame ~mouse:centre ()));
  Gc.full_major ();
  let pan_before = Gc.allocated_bytes () in
  for index = 0 to move_repeats - 1 do
    let point = fst centre + (3 * (index + 1)), snd centre + (2 * (index + 1)) in
    let started = Unix.gettimeofday () in
    let next, _ = step !panning
        (frame ~mouse:point ~events:[mouse_move point] ()) in
    ignore (Sys.opaque_identity (Pxui.Ui.scene ui));
    pan_samples.(index) <- Unix.gettimeofday () -. started;
    panning := next
  done;
  let pan_allocated = Gc.allocated_bytes () -. pan_before in
  let pan_batches = match Prismel.Scene.Private.stage_native_render ~width:1200
      ~height:760 (Pxui.Ui.scene ui) with
    | Ok staged -> List.fold_left (fun total -> function
        | Prismel.Scene.Private.Ui_layer (batch, _) ->
            total + Array.length (Scene_command.Ui_batch.batches batch)
        | _ -> total) 0 staged.layers
    | Error message -> failwith message in
  let stats = Pxui_graph.stats view in
  Printf.printf
    "pxui_graph_min_zoom_pan,%d,%.9f,%.0f,%d\n%!" count
    (percentile pan_samples 0.5) pan_allocated pan_batches;
  Printf.printf
    "pxui_graph,%d,%d,%d,%d,%.9f,%.9f,%.9f,%.0f,%.9f,%.0f,%.9f,%.0f,%d,%.9f,%.0f,%d,%d,%d,%d,%d\n%!"
    count stats.nodes stats.wires !hits
    (percentile (Array.copy samples) 0.5)
    (percentile samples 0.99) (percentile edge_samples 0.99) allocated
    (percentile move_samples 0.5) move_allocated release_seconds
    release_allocated bulk_count bulk_seconds bulk_allocated stats.visible_nodes
    !max_candidates !max_edge_candidates stats.spatial_cells
    stats.spatial_edge_cells

let () =
  Printf.printf
    "benchmark,requested_nodes,nodes,wires,hits,median_seconds,p99_seconds,edge_p99_seconds,allocated_bytes,move_median_seconds,move_10_allocated_bytes,release_seconds,release_allocated_bytes,bulk_nodes,bulk_release_seconds,bulk_release_allocated_bytes,visible_nodes,max_candidates,max_edge_candidates,spatial_cells,spatial_edge_cells\n%!";
  List.iter measure [100; 1_000; 10_000]
