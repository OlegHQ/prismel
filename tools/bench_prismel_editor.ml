(* Prismel Editor edit frames on a large graph: one full [Editor3.update]
   per sample while a tile drag records into the undo document, plus the
   undo frame that restores the layout. Prints CSV:
   name,nodes,median_s,p95_s,bytes_per_frame. *)
open Procedural

let pointer (x, y) = float x, float y

let frame ?(mouse = 0, 0) ?(buttons = []) ?(events = []) count : Prismel.Frame.t = {
  width = 1_200; height = 760; size = 1_200, 760;
  drawable_width = 1_200; drawable_height = 760;
  drawable_size = 1_200, 760; pixel_scale = 1., 1.;
  time = float_of_int count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse = pointer mouse; mouse_delta = 0., 0.; keys = [];
  mouse_buttons = buttons; events;
}

let percentile values fraction =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(min (Array.length values - 1)
    (max 0 (int_of_float (Float.ceil
      (fraction *. float_of_int (Array.length values))) - 1)))

(* Layers of two-input merges over a row of point sources. *)
let graph count =
  let width = 64 in
  let layer = ref (Array.init width (fun index ->
    Sop.points ~label:(Printf.sprintf "source-%d" index)
      [|float_of_int index, 0., 0.|])) and created = ref width in
  let generation = ref 0 in
  while !created < count - 1 do
    let size = min width (count - 1 - !created) and previous = !layer in
    layer := Array.init size (fun index ->
      Sop.merge ~label:(Printf.sprintf "node-%d-%d" !generation index)
        [previous.(index mod Array.length previous);
         previous.((index + 1) mod Array.length previous)]);
    created := !created + size;
    incr generation
  done;
  Sop.merge ~label:"output" (Array.to_list !layer)

let report name nodes samples bytes =
  Printf.printf "%s,%d,%.9f,%.9f,%.0f\n%!" name nodes
    (percentile samples 0.5) (percentile samples 0.95)
    (bytes /. float_of_int (Array.length samples))

let measure nodes =
  let module E = Prismel_editor.Editor3 in
  let environment = E.create ~graph:(graph nodes)
      ~max_entries:4 ~max_payload_bytes:(1024 * 1024)
      ~prepare:(fun _ _ -> Ok ())
      ~scene3:(fun _ () -> Prismel.Scene3.create []) () |> Result.get_ok in
  let environment = ref (E.update environment (frame 0)) and count = ref 1 in
  let step ?mouse ?buttons ?events () =
    environment := E.update !environment (frame ?mouse ?buttons ?events !count);
    incr count in
  let gx, gy, gw, gh = (E.panes !environment (frame 0)).graph in
  let tile = List.find (fun (node : Pxui_graph.node_view) ->
      let x, y, width, height = node.bounds in
      x >= gx && y >= gy && x + width < gx + gw && y + height < gy + gh)
      (E.graph_nodes !environment) in
  let x, y, width, height = tile.bounds in
  let start = x + (width / 2), y + (height / 2) in
  step ~mouse:start ();  (* hover: hit testing uses the last frame *)
  step ~mouse:start ~buttons:[Prismel.Input.LeftButton]
    ~events:[Prismel.Event.MousePressed (Prismel.Input.LeftButton, pointer start)] ();
  let samples = Array.make 200 0. in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  Array.iteri (fun index _ ->
    let point = fst start + 1 + (index mod 2), snd start in
    let started = Unix.gettimeofday () in
    step ~mouse:point ~buttons:[Prismel.Input.LeftButton]
      ~events:[Prismel.Event.MouseMoved (pointer point)] ();
    samples.(index) <- Unix.gettimeofday () -. started) samples;
  report "prismel_editor_drag_frame" nodes samples (Gc.allocated_bytes () -. before);
  step ~mouse:start
    ~events:[Prismel.Event.MouseReleased (Prismel.Input.LeftButton, pointer start)] ();
  let undo = [|0.|] in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let started = Unix.gettimeofday () in
  environment := E.update !environment
      { (frame ~events:[Prismel.Event.KeyPressed (Prismel.Input.KeyChar 'z')] !count)
        with keys = [Prismel.Input.Meta] };
  undo.(0) <- Unix.gettimeofday () -. started;
  report "prismel_editor_undo_frame" nodes undo (Gc.allocated_bytes () -. before);
  if E.can_redo !environment |> not then failwith "undo did not step the history";
  E.close !environment

let () =
  let sizes = match Array.to_list Sys.argv with
    | _ :: (_ :: _ as sizes) -> List.map int_of_string sizes
    | _ -> [200; 2_000] in
  print_endline "name,nodes,median_s,p95_s,bytes_per_frame";
  List.iter measure sizes
