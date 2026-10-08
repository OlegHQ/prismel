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

let benchmark ?(profile=false) kind count dynamic =
  let workspace = workspace kind count dynamic in
  let editor = ref (Result.get_ok (Editor.create ~workspace ~await:true ~domains:1
    ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.empty) ())) in
  Fun.protect ~finally:(fun () -> Editor.close !editor) (fun () ->
    editor := Editor.update !editor (frame 0);
    editor := Rays_editor.Reduce.step !editor [Rays_editor.Private.Leader.Play_pause] (frame 0);
    let step i = editor := Editor.update !editor (frame i) in
    for i=1 to 10 do step i done;
    let times=Array.make 200 0. in
    Gc.full_major ();
    let samples=Hashtbl.create 64 in
    let sample allocation=
      let stack=Printexc.raw_backtrace_to_string allocation.Gc.Memprof.callstack in
      Hashtbl.replace samples stack
        (allocation.n_samples+Option.value ~default:0(Hashtbl.find_opt samples stack));None in
    if profile then ignore(Gc.Memprof.start ~sampling_rate:0.001 ~callstack_size:20
      {Gc.Memprof.null_tracker with alloc_minor=sample;alloc_major=sample});
    let before=Gc.allocated_bytes () in
    Array.iteri (fun i _ -> let started=Unix.gettimeofday () in
      step (i+11); times.(i)<-Unix.gettimeofday () -. started) times;
    let bytes=(Gc.allocated_bytes () -. before) /. float (Array.length times) in
    if profile then begin
      Gc.Memprof.stop();
      Printf.printf "PROFILE: allocation sampling distorts times and bytes/frame\n%!";
      let categories=Hashtbl.create 16 in
      Hashtbl.iter(fun stack count->
        let calls=String.split_on_char '\n' stack in
        let has prefix=List.exists(String.starts_with ~prefix)calls in
        let category=List.find_opt(fun(_,prefix)->has prefix)
          ["camera decoding","Called from Editor_document__Objects.Camera.of_node";
           "UI batch snapshot","Called from Scene_command__Ui_batch.Builder.publish";
           "UI arrange","Called from Pxui__Ui.arrange";
           "UI paint","Called from Pxui__Ui.paint_all";
           "UI other","Called from Pxui__Ui.";
           "keymap routing","Called from Rays_editor__Core_actions.routed";
           "editor reduction","Called from Rays_editor__Core_reduce.reduce"]in
        let name=Option.fold ~none:"other editor work" ~some:fst category in
        Hashtbl.replace categories name(count+Option.value ~default:0(Hashtbl.find_opt categories name)))samples;
      Hashtbl.to_seq categories|>List.of_seq|>List.sort(fun(_,a)(_,b)->Int.compare b a)
        |>List.iter(fun(name,count)->Printf.printf "PROFILE TOTAL %s: %d sampled words\n%!" name count);
      Hashtbl.to_seq samples|>List.of_seq|>List.sort(fun(_,a)(_,b)->Int.compare b a)
      |>List.filteri(fun i _->i<16)|>List.iter(fun(stack,count)->
        Printf.printf "PROFILE %s_%s: %d sampled words\n%s\n%!" kind
          (if dynamic then "moving"else "static") count stack)
    end;
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
  let args=Array.to_list Sys.argv|>List.tl in
  let static=List.mem "--static" args and profile=List.mem "--profile" args in
  let args=List.filter(fun arg->arg<>"--static"&&arg<>"--profile")args in
  let counts=match args with []->[1000;10000;100000]|[count]->[int_of_string count]
    |_->invalid_arg "bench_drawing [count] [--static] [--profile]"in
  if profile && not static then invalid_arg "allocation profiling requires --static";
  List.iter(fun count->if static then benchmark ~profile "circle" count false else
    List.iter (fun kind ->benchmark kind count true; benchmark kind count false)
      ["circle";"rect";"line";"points"])counts
