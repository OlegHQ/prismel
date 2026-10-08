(* Rays Editor edit frames on a large workspace graph: one full [Editor3.update]
   per sample while a node drag records into the undo document, plus the
   undo frame that restores the layout. Prints CSV:
   name,nodes,median_s,p95_s,bytes_per_frame.
   [--panels [nodes]] measures idle frames (the pointer moving over the viewport) of layouts
   with one and three graph panels and one and two inspectors over the same graph. *)
open Procedural

let pointer (x, y) = float x, float y

let frame ?(mouse = 0, 0) ?(buttons = []) ?(events = []) count : Rays.Frame.t = {
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

(* Layers of two-input nodes over a row of point sources, as a workspace text.  The nodes are
   switches, not merges: a merge of two nodes of the layer before doubles the geometry every
   layer (2^30 points at 2000 nodes), and the bench measures the editor, not that cook. *)
let workspace_text count =
  let width = 64 in
  let b = Buffer.create 65_536 in
  Buffer.add_string b "(workspace bench\n  (graph g :context sop\n    (let* [";
  let layer = ref (Array.init width (fun index ->
    let name = Printf.sprintf "s%d" index in
    Buffer.add_string b (Printf.sprintf "%s (sop/points :points 1)\n           " name); name))
  and created = ref width and generation = ref 0 and all = ref [] in
  while !created < count - 1 do
    let size = min width (count - 1 - !created) and previous = !layer in
    layer := Array.init size (fun index ->
      let name = Printf.sprintf "n%d_%d" !generation index in
      Buffer.add_string b (Printf.sprintf "%s (sop/switch %s %s)\n           " name
        previous.(index mod Array.length previous) previous.((index + 1) mod Array.length previous));
      all := name :: !all;
      name);
    created := !created + size;
    incr generation
  done;
  Buffer.add_string b (Printf.sprintf "output (sop/merge %s)]\n      output)))\n"
    (String.concat " " (Array.to_list !layer)));
  (* the last layer first: the card the drag bench looks for, then every other layer *)
  Buffer.contents b, Array.to_list !layer @ !all

let load text = match Rays_editor.Workspace.load text with
  | Ok workspace -> workspace
  | Error diagnostics -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string diagnostics))

let workspace count = let text, names = workspace_text count in load text, names

let report name nodes samples bytes =
  Printf.printf "%s,%d,%.9f,%.9f,%.0f\n%!" name nodes
    (percentile samples 0.5) (percentile samples 0.95)
    (bytes /. float_of_int (Array.length samples))

let measure nodes =
  let module E = Rays_editor.Editor3 in
  let workspace, names = workspace nodes in
  let environment = E.create ~workspace
      ~domains:1 ~presets:(Filename.temp_dir "rays-editor-bench" "")
      ~max_entries:4 ~max_payload_bytes:(1024 * 1024)
      ~prepare:(fun _ _ -> Ok ())
      ~scene3:(fun _ () -> Rays.Scene3.create []) () |> Result.get_ok in
  let environment = ref (E.update environment (frame 0)) and count = ref 1 in
  let step ?mouse ?buttons ?events () =
    environment := E.update !environment (frame ?mouse ?buttons ?events !count);
    incr count in
  let gx, gy, gw, gh = (E.panes !environment (frame 0)).graph in
  (* The scene opens as a list: focus it, arrow to the object, and enter it. *)
  let inside = gx + 20, gy + gh - 20 in
  step ~mouse:inside ();
  step ~mouse:inside ~events:[Rays.Event.MousePressed (Rays.Input.LeftButton, pointer inside);
    Rays.Event.MouseReleased (Rays.Input.LeftButton, pointer inside)] ();
  let key k = Rays.Event.KeyPressed k in
  while Option.map Node.label (E.selected_node !environment) <> Some "g" do
    step ~events:[key Rays.Input.ArrowDown] ()
  done;
  step ~events:[key (Rays.Input.KeyChar 'i')] ();
  step ();
  (* a large graph opens with its cards outside the pane: frame all of it, then take one inside *)
  let x, y, width, height = match List.find_map (fun name ->
      match E.node_box !environment [ "g"; name ] with
      | Some (x, y, width, height) when x >= gx && y >= gy && x + width < gx + gw
          && y + height < gy + gh -> Some (x, y, width, height)
      | _ -> None) ("output" :: names) with
    | Some box -> box
    | None ->
        step ~mouse:inside ~events:[key Rays.Input.Home] (); step ~mouse:inside ();
        List.find_map (fun name ->
      match E.node_box !environment [ "g"; name ] with
      | Some (x, y, width, height) when x >= gx && y >= gy && x + width < gx + gw
          && y + height < gy + gh -> Some (x, y, width, height)
      | _ -> None) ("output" :: names) |> Option.get in
  let start = x + (width / 2), y + min 12 (height / 2) in
  step ~mouse:start ();  (* hover: hit testing uses the last frame *)
  step ~mouse:start ~buttons:[Rays.Input.LeftButton]
    ~events:[Rays.Event.MousePressed (Rays.Input.LeftButton, pointer start)] ();
  let samples = Array.make 200 0. in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  Array.iteri (fun index _ ->
    let point = fst start + 10 + (index mod 2), snd start in
    let started = Unix.gettimeofday () in
    step ~mouse:point ~buttons:[Rays.Input.LeftButton]
      ~events:[Rays.Event.MouseMoved (pointer point)] ();
    samples.(index) <- Unix.gettimeofday () -. started) samples;
  report "rays_editor_drag_frame" nodes samples (Gc.allocated_bytes () -. before);
  let finish = fst start + 11, snd start in
  step ~mouse:finish
    ~events:[Rays.Event.MouseReleased (Rays.Input.LeftButton, pointer finish)] ();
  let undo = [|0.|] in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let started = Unix.gettimeofday () in
  environment := E.update !environment
      { (frame ~events:[Rays.Event.KeyPressed (Rays.Input.KeyChar 'z')] !count)
        with keys = [Rays.Input.Meta] };
  undo.(0) <- Unix.gettimeofday () -. started;
  report "rays_editor_undo_frame" nodes undo (Gc.allocated_bytes () -. before);
  if E.can_redo !environment |> not then failwith "undo did not step the history";
  (* The same open graph and frame as the drag: change one literal parameter,
     then run the entire next editor frame, with the pointer still held.  The edit row is the
     frame without its cook phase: the recook the changed value requires is work a drag
     never does, so it is the row compared with the drag. *)
  let phases = List.map (fun phase -> phase, Array.make 200 0.) Flow.Phase_timer.phases in
  let samples = Array.make 200 0. in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  Array.iteri (fun index _ ->
    let started = Unix.gettimeofday () in
    let (), edited = Flow.Phase_timer.sample ~clock:Unix.gettimeofday (fun () ->
    environment := E.edit !environment (Flow_graph.Flow_edit.Set_arg {
      node = ["g"; "s0"]; key = Flow_graph.Flow_edit.Kw "points"; sub = [];
      value = Flow.Syntax.make (Flow.Syntax.Num (string_of_int (1 + index mod 2))) }) |> Result.get_ok;
    step ~mouse:finish ~buttons:[Rays.Input.LeftButton] ()) in
    samples.(index) <- Unix.gettimeofday () -. started;
    List.iter (fun (phase, column) -> column.(index) <- Flow.Phase_timer.seconds edited phase) phases) samples;
  let bytes = Gc.allocated_bytes () -. before in
  report "rays_editor_scrub_frame" nodes samples bytes;
  report "rays_editor_scrub_edit_frame" nodes
    (Array.map2 (fun frame cook -> frame -. cook) samples (List.assoc Flow.Phase_timer.Cook phases)) bytes;
  List.iter (fun (phase, samples) ->
    Printf.printf "scrub_phase,%d,%s,%.9f\n%!" nodes (Flow.Phase_timer.name phase) (percentile samples 0.5)) phases;
  E.close !environment

(* Idle frames of one graph under layouts that differ only in how many graph panels and
   inspectors they hold: what an extra panel instance costs a frame. *)
let measure_panels nodes =
  let module E = Rays_editor.Editor3 in
  let text, _ = workspace_text nodes in
  let body = String.sub text 0 (String.length text - 2) in  (* without the workspace's closing bracket *)
  let graphs n = if n = 1 then "(ui/graph \"g\")"
    else "(ui/tile " ^ String.concat " " (List.init n (fun _ -> "(ui/graph \"g\")")) ^ ")" in
  let inspectors n = if n = 1 then "(ui/inspector)" else "(ui/split \"vertical\" (ui/inspector) (ui/inspector))" in
  List.iter (fun (name, g, i) ->
    let workspace = load (Printf.sprintf
      "%s\n  (graph scene :context scene (scene/merge (scene/geometry (ref g))))\n  \
       (graph editor :context editor\n    (ui/workspace (ui/split-at \"horizontal\" 0.3 (ui/viewport (ref scene))\n      \
       (ui/split \"horizontal\" %s %s :second_size 300)))))\n" body (graphs g) (inspectors i)) in
    let environment = ref (E.create ~workspace ~await:true
        ~domains:1 ~presets:(Filename.temp_dir "rays-editor-bench" "")
        ~max_entries:4 ~max_payload_bytes:(1024 * 1024)
        ~prepare:(fun _ _ -> Ok ())
        ~scene3:(fun _ () -> Rays.Scene3.create []) () |> Result.get_ok) in
    let count = ref 0 in
    let step mouse =
      environment := E.update !environment (frame ~mouse ~events:[Rays.Event.MouseMoved (pointer mouse)] !count);
      incr count in
    for _ = 1 to 20 do step (100, 300) done;
    let samples = Array.make 300 0. in
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    Array.iteri (fun index _ ->
      let started = Unix.gettimeofday () in
      step (100 + (index mod 50), 300);
      samples.(index) <- Unix.gettimeofday () -. started) samples;
    report name nodes samples (Gc.allocated_bytes () -. before);
    E.close !environment)
    [ "panels_1_graph_1_inspector", 1, 1; "panels_3_graphs_1_inspector", 3, 1;
      "panels_1_graph_2_inspectors", 1, 2; "panels_3_graphs_2_inspectors", 3, 2 ]

let measure_spreadsheet () =
  let module E = Rays_editor.Editor3 in
  let workspace = load {|(workspace sheet
    (graph g :context sop (sop/grid :counts "Point counts" :connectivity "Points" :rows 1000 :columns 1000))
    (graph editor :context editor (let* [gpanel (ui/graph "g" :focus true)]
      (ui/workspace (ui/split "horizontal" gpanel (ui/spreadsheet :of gpanel))))))|} in
  let environment = ref (E.create ~workspace ~await:true ~domains:1
    ~presets:(Filename.temp_dir "rays-sheet-bench" "")
    ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.empty) () |> Result.get_ok) in
  Fun.protect ~finally:(fun () -> E.close !environment) (fun () ->
    environment := Rays_editor.Reduce.select_path !environment ["g"; "@result"];
    let step ?(events = []) count = environment := E.update !environment (frame ~mouse:(900,300) ~events count) in
    for i = 0 to 19 do step i done;
    let geometry = snd (Rays_editor.Reduce.spreadsheet !environment [1]) |> Option.get in
    assert (Rdk.Geometry.point_count geometry = 1_000_000);
    Gc.full_major ();
    let before = Gc.allocated_bytes () and samples = Array.make 300 0. in
    Array.iteri (fun index _ -> let started = Unix.gettimeofday () in step (index+20);
      samples.(index) <- Unix.gettimeofday () -. started) samples;
    report "panels_spreadsheet" 1_000_000 samples (Gc.allocated_bytes () -. before);
    let events = [Rays.Event.MouseMoved (900., 300.); Rays.Event.MouseScrolled (0., -3.)] in
    for i = 320 to 339 do step ~events i done;
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    Array.iteri (fun index _ -> let started = Unix.gettimeofday () in step ~events (index+340);
      samples.(index) <- Unix.gettimeofday () -. started) samples;
    let allocated = Gc.allocated_bytes () -. before in
    assert (Rdk.Geometry.point_count (snd (Rays_editor.Reduce.spreadsheet !environment [1]) |> Option.get) = 1_000_000);
    report "panels_spreadsheet_scroll" 1_000_000 samples allocated)

let measure_world () =
  let open Rays in
  let module E = Rays_editor.Editor3 in
  Parallel.run ~domains:1 (fun () ->
    let workspace = match Rays_editor.Workspace.load
        "(workspace w (graph g :context sop (sop/points :points 1)))" with
      | Ok workspace -> workspace | Error _ -> failwith "the World fixture does not check" in
    let environment = ref (E.create ~domains:1 ~workspace
      ~world:{ World.default with layers = []; background = World.Transparent }
      ~camera:(Easy_camera.create ~inertia:false ())
      ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Scene3.empty) () |> Result.get_ok) in
    Fun.protect ~finally:(fun () -> E.close !environment) (fun () ->
      let input count x events = { (frame ~mouse:(100, 300) ~buttons:[Input.LeftButton]
          ~events count) with width = 900; height = 640; size = 900, 640;
          drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
          mouse = x, 300.; mouse_delta = 0.02, 0.; keys = [Input.Shift] } in
      let deadline = Unix.gettimeofday () +. 2. in
      while E.prepared !environment = None do
        if Unix.gettimeofday () >= deadline then failwith "initial cook did not settle";
        environment := E.update !environment (frame 0);
        Unix.sleepf 0.001
      done;
      environment := E.update !environment { (input 1 100.
        [Event.MousePressed (Input.LeftButton, (100., 300.))]) with mouse_delta = 0., 0. };
      let samples = Array.make 16 0. in
      Gc.full_major ();
      let allocated = Gc.allocated_bytes () in
      Array.iteri (fun index _ ->
        let x = 100. +. float (index + 1) *. 0.02 in
        let input = input (index + 2) x [Event.MouseMoved (x, 300.)] in
        let started = Unix.gettimeofday () in
        environment := E.update !environment input;
        samples.(index) <- Unix.gettimeofday () -. started) samples;
      let bytes = Gc.allocated_bytes () -. allocated in
      let rotation = E.scene_document !environment |> Edit_graph.inspect
        |> List.find_map (fun (info : Edit_graph.node_info) ->
          if info.operation <> "world" then None else Node.parameter_fields info.node
          |> List.find_map (fun (field : Parameter.field_view) -> match field.name, field.current with
            | "rotation", Parameter.Float_value value -> Some value | _ -> None)) |> Option.get in
      if abs_float (rotation -. 0.16) > 1e-9 then failwith "World input benchmark did not rotate 0.16 degrees";
      report "rays_editor_world_frame" 1 samples bytes))

let () =
  if Array.to_list Sys.argv = [Sys.argv.(0); "--world"] then begin
    print_endline "name,objects,median_s,p95_s,bytes_per_frame";
    for _ = 1 to 3 do measure_world () done
  end else if Array.length Sys.argv > 1 && Sys.argv.(1) = "--panels" then begin
    print_endline "name,nodes,median_s,p95_s,bytes_per_frame";
    List.iter measure_panels (match Array.to_list Sys.argv with
      | _ :: _ :: (_ :: _ as sizes) -> List.map int_of_string sizes | _ -> [ 200; 800; 2_000 ]);
    measure_spreadsheet ()
  end else begin
  let sizes = match Array.to_list Sys.argv with
    | _ :: (_ :: _ as sizes) -> List.map int_of_string sizes
    | _ -> [200; 2_000] in
  print_endline "name,nodes,median_s,p95_s,bytes_per_frame";
  List.iter measure sizes
  end
