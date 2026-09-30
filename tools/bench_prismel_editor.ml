(* Prismel Editor edit frames on a large workspace graph: one full [Editor3.update]
   per sample while a node drag records into the undo document, plus the
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

(* Layers of two-input merges over a row of point sources, as a workspace text. *)
let workspace count =
  let width = 64 in
  let b = Buffer.create 65_536 in
  Buffer.add_string b "(workspace bench\n  (graph g :context sop\n    (let* [";
  let layer = ref (Array.init width (fun index ->
    let name = Printf.sprintf "s%d" index in
    Buffer.add_string b (Printf.sprintf "%s (sop/points :points 1)\n           " name); name))
  and created = ref width and generation = ref 0 in
  while !created < count - 1 do
    let size = min width (count - 1 - !created) and previous = !layer in
    layer := Array.init size (fun index ->
      let name = Printf.sprintf "n%d_%d" !generation index in
      Buffer.add_string b (Printf.sprintf "%s (sop/merge %s %s)\n           " name
        previous.(index mod Array.length previous) previous.((index + 1) mod Array.length previous));
      name);
    created := !created + size;
    incr generation
  done;
  Buffer.add_string b (Printf.sprintf "output (sop/merge %s)]\n      output)))\n"
    (String.concat " " (Array.to_list !layer)));
  match Prismel_editor.Workspace.load (Buffer.contents b) with
  | Ok workspace -> workspace, Array.to_list !layer
  | Error diagnostics -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string diagnostics))

let report name nodes samples bytes =
  Printf.printf "%s,%d,%.9f,%.9f,%.0f\n%!" name nodes
    (percentile samples 0.5) (percentile samples 0.95)
    (bytes /. float_of_int (Array.length samples))

let measure nodes =
  let module E = Prismel_editor.Editor3 in
  let workspace, names = workspace nodes in
  let environment = E.create ~workspace
      ~max_entries:4 ~max_payload_bytes:(1024 * 1024)
      ~prepare:(fun _ _ -> Ok ())
      ~scene3:(fun _ () -> Prismel.Scene3.create []) () |> Result.get_ok in
  let environment = ref (E.update environment (frame 0)) and count = ref 1 in
  let step ?mouse ?buttons ?events () =
    environment := E.update !environment (frame ?mouse ?buttons ?events !count);
    incr count in
  let gx, gy, gw, gh = (E.panes !environment (frame 0)).graph in
  (* The scene opens as a list: focus it, arrow to the object, and enter it. *)
  let inside = gx + 20, gy + gh - 20 in
  step ~mouse:inside ();
  step ~mouse:inside ~events:[Prismel.Event.MousePressed (Prismel.Input.LeftButton, pointer inside);
    Prismel.Event.MouseReleased (Prismel.Input.LeftButton, pointer inside)] ();
  let key k = Prismel.Event.KeyPressed k in
  while Option.map Node.label (E.selected_node !environment) <> Some "g" do
    step ~events:[key Prismel.Input.ArrowDown] ()
  done;
  step ~events:[key (Prismel.Input.KeyChar 'i')] ();
  step ();
  let x, y, width, height = List.find_map (fun name ->
      match E.node_box !environment [ "g"; name ] with
      | Some (x, y, width, height) when x >= gx && y >= gy && x + width < gx + gw
          && y + height < gy + gh -> Some (x, y, width, height)
      | _ -> None) ("output" :: names) |> Option.get in
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

let measure_world () =
  let open Prismel in
  let module E = Prismel_editor.Editor3 in
  Parallel.run ~domains:1 (fun () ->
    let workspace = match Prismel_editor.Workspace.load
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
      report "prismel_editor_world_frame" 1 samples bytes))

let () =
  if Array.to_list Sys.argv = [Sys.argv.(0); "--world"] then begin
    print_endline "name,objects,median_s,p95_s,bytes_per_frame";
    for _ = 1 to 3 do measure_world () done
  end else begin
  let sizes = match Array.to_list Sys.argv with
    | _ :: (_ :: _ as sizes) -> List.map int_of_string sizes
    | _ -> [200; 2_000] in
  print_endline "name,nodes,median_s,p95_s,bytes_per_frame";
  List.iter measure sizes
  end
