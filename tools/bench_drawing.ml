(* Run alone: ten warm-up and 200 timed 800x600 editor frames. *)
module Editor = Rays_editor.Editor3

let frame count : Rays.Frame.t = {
  width=800; height=600; size=800,600; drawable_width=800; drawable_height=600;
  drawable_size=800,600; pixel_scale=1.,1.; time=float count /. 60.;
  dt=1. /. 60.; fps=60.; count; mouse=(-100.,-100.); mouse_delta=0.,0.;
  mouse_buttons=[]; keys=[]; events=[] }

let workspace kind count dynamic =
  let position = if dynamic then "[(mod (+ i (* t 30)) 800) (mod i 600) 0]"
    else "[(mod i 800) (mod i 600) 0]" in
  let drawing = match kind with
    | "points" -> Printf.sprintf "(draw/points (map (fn [i] %s) (array/range %d)))" position count
    | kind -> let shape = match kind with
      | "circle" -> "(draw/circles positions :radius 3 :fill \"#00ffff\")"
      | "rect" -> "(draw/rects positions [6 6 0] :fill \"#00ffff\")"
      | "line" -> "(draw/lines positions (map (fn [p] (+ p [6 6 0])) positions) :color \"#00ffff\")"
      | _ -> invalid_arg kind in
      Printf.sprintf "(let* [positions (map (fn [i] %s) (array/range %d))] %s)" position count shape in
  let text = Printf.sprintf "(workspace bench (graph picture :context draw %s) (graph editor :context editor (ui/workspace (ui/canvas (ref picture) :focus true))))" drawing in
  match Rays_editor.Workspace.load text with Ok doc -> doc
  | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds))

let benchmark kind count dynamic =
  let workspace = workspace kind count dynamic in
  let editor = ref (Result.get_ok (Editor.create ~workspace ~await:true ~domains:1
    ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.empty) ())) in
  Fun.protect ~finally:(fun () -> Editor.close !editor) (fun () ->
    editor := Editor.update !editor (frame 0);
    editor := Rays_editor.Reduce.step !editor [Rays_editor.Private.Leader.Play_pause] (frame 0);
    let step i = editor := Editor.update !editor (frame i) in
    for i=1 to 10 do step i done;
    let times=Array.make 200 0. in
    Gc.full_major (); let before=Gc.allocated_bytes () in
    Array.iteri (fun i _ -> let started=Unix.gettimeofday () in
      step (i+11); times.(i)<-Unix.gettimeofday () -. started) times;
    let bytes=(Gc.allocated_bytes () -. before) /. float (Array.length times) in
    let evaluated=Result.get_ok(Flow.Eval.static workspace.checked)in
    let scene=Result.get_ok(Sketch_support.Drawing.render evaluated.plan
      (List.assoc "picture" evaluated.results)
      ~live:(Frame_input.at_time (211. /. 60.)) ~size:(800,600))in
    let commands=Array.length (Rays.Scene.Private.commands scene) in
    Array.sort Float.compare times;
    Printf.printf "%s_%s,%d,%.9f,%.9f,%.0f,%d\n%!" kind
      (if dynamic then "moving" else "static") count times.(100) times.(190) bytes commands)

let () =
  Printf.printf "name,count,median_s,p95_s,bytes_per_frame,commands\n%!";
  let counts=if Array.length Sys.argv>1 then [int_of_string Sys.argv.(1)] else [1000;10000;100000] in
  List.iter (fun count -> List.iter (fun kind ->
    benchmark kind count true; benchmark kind count false)
    ["circle";"rect";"line";"points"]) counts
