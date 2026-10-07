module E = Flow.Eval
module V = Flow.Value
module P = Flow_graph.Projection
module F = Flow_graph.Flow_edit
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let read path = In_channel.with_open_bin path In_channel.input_all
let catalog = Result.get_ok (Rays_editor.workspace_catalog ())
let doc text = match Rays_editor.Workspace.load text with Ok d -> d
  | Error ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds))
let bits = Int64.bits_of_float
type particle = {x : float; y : float; vx : float; vy : float}
let initial () = Array.init 10000 (fun i -> let angle = float i *. 0.1 in
  let speed = 30. +. float (i mod 70) in
  {x = 400.; y = 300.; vx = cos angle *. speed; vy = sin angle *. speed})
let step dt particles = Array.map (fun p ->
  let x = p.x +. p.vx *. dt and y = p.y +. p.vy *. dt in
  {x; y; vx = (if x < 0. || x >= 800. then -.p.vx else p.vx);
         vy = (if y < 0. || y >= 600. then -.p.vy else p.vy)}) particles
let edited source op = fst (ok (F.apply_checked catalog source op))
let checked source = match Flow.Workspace.check catalog source with
  | Some w, _ -> w | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds))

let pure workspace =
  let all_draws = doc {|(workspace drawing (graph picture :context draw
    (draw/merge (draw/background "#080a10")
      (draw/point [1 2 0]) (draw/points (array/vec3 4 [2 3 0]))
      (draw/line [0 0 0] [10 10 0] :width 2)
      (draw/rect [5 5 0] [20 10 0] :fill "#ffffff")
      (draw/circle [15 15 0] 4 :stroke [0 1 1])
      (draw/text [30 10 0] "text" :size 16)
      (draw/translate [10 20 0] (draw/point [1 2 0])))))|} in
  let all = ok (E.static all_draws.checked) in
  let kinds = Array.to_list all.plan.nodes |> List.map (fun (n : E.node) -> n.kind)
    |> List.sort_uniq String.compare in
  assert (kinds = (Flow.Op.all |> List.filter_map (fun (o : Flow.Op.t) ->
    if o.ctx = Flow.Context.draw then Some o.name else None) |> List.sort String.compare));
  assert (ok (Sketch_support.Drawing.render all.plan (List.assoc "picture" all.results)
    ~live:(Frame_input.at_time 0.) ~size:(800, 600)) <> []);
  let invalid = ok (E.static (doc "(workspace invalid (graph g :context draw (draw/background \"invalid\")))").checked) in
  assert (match Sketch_support.Drawing.render invalid.plan (List.assoc "g" invalid.results)
    ~live:(Frame_input.at_time 0.) ~size:(800, 600) with
    | Error d -> d.Flow.Diagnostic.code = "E_DRAW_COLOR" | Ok _ -> false);
  let evaluated = ok (E.static ~inputs:workspace.Editor_document.Workspace_doc.inputs workspace.checked) in
  assert (Array.length evaluated.plan.nodes = 3);
  Array.iter (fun (n : E.node) -> assert (n.ty = Flow.Ty.drawing)) evaluated.plan.nodes;
  let drawing = List.assoc "picture" evaluated.results in
  assert (match drawing with E.Deferred ((Flow.Ty.Named "drawing"), _) -> true | _ -> false);
  let scope = P.of_graph catalog workspace.checked "picture" in
  let state_card = Option.get (P.find scope ["picture"; "particles"]) in
  let zone = Option.get state_card.zone in
  assert (zone.kind = P.State);
  assert (List.exists (fun (r : P.rail_row) -> r.role = P.Acc && r.name = "previous") zone.rail);
  assert (P.find scope ["picture"; "@result#drawing#2"] <> None ||
    List.exists (fun (n : P.node) -> n.ty = Flow.Ty.drawing) scope.nodes);
  let state = E.create_state () in
  let points = Array.find_opt (fun (n : E.node) -> n.kind = "draw/points") evaluated.plan.nodes |> Option.get in
  let positions = List.assoc "positions" points.args in
  let oracle = ref (initial ()) in
  List.iteri (fun frame dt ->
    oracle := step dt !oracle;
    let live = {(Frame_input.at_time (float frame *. dt)) with frame; dt; size = (800, 600)} in
    let xs = ok (E.force ~state positions ~live) in
    assert (V.array_length xs = 10000);
    Array.iteri (fun i p -> let x, y, z = V.comps (V.array_get xs i) in
      (* Native OCaml can fuse multiply-add on ARM; the Lisp arithmetic has
         separately rounded IEEE operations. Points still land on the same pixel. *)
      if abs_float (x -. p.x) > 1e-9 || abs_float (y -. p.y) > 1e-9
         || int_of_float x <> int_of_float p.x || int_of_float y <> int_of_float p.y || bits z <> bits 0. then
        failwith (Printf.sprintf "particle %d frame %d: got (%h,%h,%h), expected (%h,%h,0)" i frame x y z p.x p.y)) !oracle;
    ignore (ok (Sketch_support.Drawing.render ~state evaluated.plan drawing ~live ~size:live.size)))
    [1. /. 60.; 1. /. 60.; 0.125; 20.; 20.; 0.125];
  (* The same source edits used by the pane add a fold and change its seed. *)
  let source = edited workspace.source (F.Add_node {scope = ["picture"]; name = "elapsed";
    expr = List.hd (ok (Flow.Syntax.parse "(state [seconds 0.0] (+ seconds (frame/dt)))"))}) in
  let source = edited source (F.Set_arg {node = ["picture"; "elapsed"]; key = F.Bv (1, 1);
    sub = []; value = Flow.Syntax.make (Flow.Syntax.Num "2.0")}) in
  let w = checked source in
  let n = Option.get (P.find (P.of_graph catalog w "picture") ["picture"; "elapsed"]) in
  assert ((Option.get n.zone).kind = P.State);
  let panel_source = ok (Flow.Syntax.parse "(workspace canvas (graph g :context draw (draw/merge)) (graph editor :context editor (let* [pane (ui/lisp)] (ui/workspace pane))))") in
  let panel_source = edited panel_source (F.Set_panel_kind {node = ["editor"; "pane"]; kind = "canvas"}) in
  let panel_workspace = doc (fst (Flow.Lisp.print panel_source)) in
  let panel_document = ok (Editor_document.Contexts.of_workspace ~factories:Sop_catalog.Editor.factories panel_workspace) in
  assert (match (Option.get panel_document.shell).tree with Editor_core.Panels.Leaf (Canvas _) -> true | _ -> false);
  let input_text = "(workspace inputs (graph g :context draw [(radius : float 5)] (draw/circle [10 10 0] radius :fill \"#00ffff\")) (graph editor :context editor (ui/workspace (ui/canvas (ref g)))))" in
  let inputs = ["g", ["radius", E.Float 9.]] in
  let workspace = {(doc input_text) with inputs} in
  let document = ok (Editor_document.Contexts.of_workspace ~factories:Sop_catalog.Editor.factories workspace) in
  let _, lower = document.workspace in
  assert (List.assoc "radius" lower.plan.nodes.(0).args = E.Float 9.);
  let source = edited workspace.source (F.Set_arg {node = ["g"; "@result"]; key = F.Pos 0;
    sub = []; value = List.hd (ok (Flow.Syntax.parse "[20 20 0]"))}) in
  let workspace = {workspace with source; checked = checked source} in
  let after = ok (Editor_document.Contexts.of_workspace ~factories:Sop_catalog.Editor.factories ~previous:document workspace) in
  assert (List.assoc "radius" (snd after.workspace).plan.nodes.(0).args = E.Float 9.);
  let bad = {workspace with inputs = ["g", ["radius", E.Text "wrong"]]} in
  assert (Result.is_error (Editor_document.Contexts.of_workspace ~factories:Sop_catalog.Editor.factories bad));
  let module Editor = Rays_editor.Editor3 in
  let editor = Result.get_ok (Editor.create ~workspace ~await:true
    ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.create []) ()) in
  Fun.protect ~finally:(fun () -> Editor.close editor) (fun () ->
    let frame : Rays.Frame.t = {width = 800; height = 600; size = (800, 600);
      drawable_width = 800; drawable_height = 600; drawable_size = (800, 600);
      pixel_scale = (1., 1.); time = 0.; dt = 0.125; fps = 8.; count = 0;
      mouse = (-100., -100.); mouse_delta = (0., 0.); mouse_buttons = []; keys = []; events = []} in
    let editor = Editor.update editor frame in
    match Rays.Scene.Private.stage_native ~width:800 ~height:600 (Editor.scene editor frame) with
    | Ok staged ->
        assert (List.exists (function Rays.Scene.Private.Scene2_layer _ -> true | _ -> false) staged.layers);
        let allocation count =
          let workspace = doc (Printf.sprintf "(workspace static (graph g :context draw \
            (draw/points (array/vec3 %d [20 40 0]))) \
            (graph editor :context editor (ui/workspace (ui/canvas (ref g)))))" count) in
          let editor = ref (Result.get_ok (Editor.create ~workspace ~await:true
            ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.create []) ())) in
          Fun.protect ~finally:(fun () -> Editor.close !editor) (fun () ->
            let step i = editor := Editor.update !editor {frame with count = i; time = float i /. 8.} in
            for i = 0 to 4 do step i done;
            let before = Gc.allocated_bytes () in
            for i = 5 to 24 do step i done;
            (Gc.allocated_bytes () -. before) /. 20.) in
        let small = allocation 4 and large = allocation 10000 in
        assert (large <= small +. 32768.);
        Printf.printf "Static Canvas allocated bytes/frame: 4 points %.0f, 10000 points %.0f\n" small large
    | Error message -> failwith message);
  print_endline "Drawing: typed plan, packed particles, editable folds, canvas and host inputs passed"

let native workspace directory =
  let path name = Filename.concat directory name in
  let config = {Rays.Sketch.default_config with width = 800; height = 600; fps = None} in
  let frames = 4 in
  ignore (Rays.Sketch.export_state ~config ~directory:(path "ocaml") ~frames
    ~init:(fun _ -> initial ())
    ~update:(fun particles frame -> step frame.Rays.Frame.dt particles)
    ~view:(fun particles _ -> Rays.Scene.clear (Rays.Color.rgb 8 10 16) ::
      Array.to_list (Array.map (fun p -> Rays.Scene.point ~at:(int_of_float p.x, int_of_float p.y)
        ~color:Rays.Color.cyan ()) particles)) ());
  List.iter (fun name -> ignore (ok (Rays_editor.Workspace.export ~directory:(path name) ~frames workspace))) ["lisp-a"; "lisp-b"];
  let evaluated = ok (E.static ~inputs:workspace.Editor_document.Workspace_doc.inputs workspace.checked) in
  let prepared = ok (Sketch_support.Drawing.prepare ~states:evaluated.states evaluated.plan
    (List.assoc "picture" evaluated.results)) in
  List.iter (fun (reference, domains) -> Rays.Parallel.run ~domains (fun () ->
    let state = E.create_state () in
    let name = (if reference then "reference-" else "cpu-") ^ string_of_int domains in
    ignore (Rays.Sketch.export_state ~config ~directory:(path name) ~frames
      ~init:(fun _ -> ()) ~update:(fun () _ -> ())
      ~view:(fun () frame ->
        let live = {(Frame_input.at_time frame.Rays.Frame.time) with dt = 1. /. 60.; frame = frame.count; size = 800, 600} in
        ok (Sketch_support.Drawing.render_prepared ~state ~reference prepared ~live ~size:live.size)) ())))
    [false, 1; false, 8; true, 1; true, 8];
  for i = 0 to frames - 1 do
    let file name = Filename.concat (path name) (Printf.sprintf "frame-%06d.png" i) in
    let baseline = read (file "ocaml") in
    assert (baseline = read (file "lisp-a"));
    assert (baseline = read (file "lisp-b"));
    assert (baseline = read (file "cpu-1"));
    assert (baseline = read (file "cpu-8"));
    assert (baseline = read (file "reference-1"));
    assert (baseline = read (file "reference-8"))
  done;
  assert (read (Filename.concat (path "lisp-a") "frame-000000.png") <>
          read (Filename.concat (path "lisp-a") "frame-000003.png"));
  Printf.printf "Particles native exports match byte for byte: %s\n" directory

let benchmark workspace =
  let module Editor = Rays_editor.Editor3 in
  let editor = ref (Result.get_ok (Editor.create ~workspace ~await:true ~domains:1
    ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.empty) ())) in
  Fun.protect ~finally:(fun () -> Editor.close !editor) (fun () ->
    let frame count : Rays.Frame.t = {width = 800; height = 600; size = 800, 600;
      drawable_width = 800; drawable_height = 600; drawable_size = 800, 600;
      pixel_scale = 1., 1.; time = float count /. 60.; dt = 1. /. 60.; fps = 60.; count;
      mouse = -100., -100.; mouse_delta = 0., 0.; mouse_buttons = []; keys = []; events = []} in
    editor := Editor.update !editor (frame 0);
    editor := Rays_editor.Reduce.step !editor [Rays_editor.Private.Leader.Play_pause] (frame 0);
    let step i = editor := Editor.update !editor (frame i) in
    for i = 1 to 10 do step i done;
    let times = Array.make 200 0. in
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    Array.iteri (fun i _ ->
      let started = Unix.gettimeofday () in
      step (i + 11);
      times.(i) <- Unix.gettimeofday () -. started) times;
    let bytes = (Gc.allocated_bytes () -. before) /. float (Array.length times) in
    Array.sort Float.compare times;
    assert (Sketch_support.Timeline.frame (Editor.timeline !editor) > 100L);
    Printf.printf "particles_dynamic_frame,10000,%.9f,%.9f,%.0f\n%!"
      times.(100) times.(190) bytes)

let () =
  let workspace = doc (read Sys.argv.(1)) in
  if Array.length Sys.argv > 2 && Sys.argv.(2) = "--bench" then benchmark workspace
  else if Array.length Sys.argv > 2 then native workspace Sys.argv.(2) else pure workspace
