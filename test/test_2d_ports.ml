open Rays
module E=Flow.Eval
let ok=function Ok x->x|Error d->failwith(Flow.Diagnostic.to_string d)
let read path=In_channel.with_open_bin path In_channel.input_all
let names=["basic";"generative";"noise";"recursive_rectangles";"drawing";"audio";"file_dialog";"pxui"]
let dimensions=function "generative"->500,500|"noise"->800,450|"recursive_rectangles"->720,720
  |"drawing"->800,500|"file_dialog"->720,420|_->640,360
let frame ?(synthetic=true) name count =
  let width,height=dimensions name in
  let events=if not synthetic then []else match name,count with
    |"drawing",1->[Event.MousePressed(Input.LeftButton,(100.,140.));MouseMoved(120.,160.)]
    |"drawing",2->[Event.MouseMoved(140.,180.)]
    |"drawing",3->[Event.MouseReleased(Input.LeftButton,(160.,190.))]
    |"recursive_rectangles",1->[Event.MousePressed(Input.LeftButton,(100.,140.))]
    |"audio",1->[Event.KeyPressed(Input.KeyChar '3')]
    |"audio",3->[Event.MousePressed(Input.LeftButton,(400.,180.))]
    |"file_dialog",1->[Event.FileDropped "sample.png";FileDialog{id=1;result=Ok["a.png";"b.png"]}]
    |"file_dialog",2->[Event.FileDragMoved(90.,140.);MousePinched 1.25]
    |"file_dialog",3->[Event.FileDragEnded;FileDialog{id=2;result=Ok[]}]
    |_->[]in
  let mouse=if not synthetic then 0.,0. else if name="recursive_rectangles"then 100.,140. else -100.,-100. in
  {Frame.width;height;size=width,height;
   pixel_scale=1.,1.;time=float count/.60.;dt=1./.60.;fps=60.;count;
   mouse;mouse_delta=0.,0.;mouse_buttons=[];keys=[];events}
let load name=
  let source=read("../examples/"^name^"/sketch.rays")in
  let workspace=match Rays_editor.Workspace.load source with Ok w->w|Error ds->
    failwith(String.concat"\n"(List.map Flow.Diagnostic.to_string ds))in
  assert(Editor_document.Workspace_doc.to_text workspace=source);
  workspace
let save_roundtrip name workspace =
  let module Editor=Rays_editor.Editor in
  let source=read("../examples/"^name^"/sketch.rays")in
  let directory=Filename.temp_dir "rays-port-save-" ""in
  let rec remove directory=Array.iter(fun entry->let path=Filename.concat directory entry in
    if Sys.is_directory path then remove path else Sys.remove path)(Sys.readdir directory);
    Unix.rmdir directory in
  Fun.protect ~finally:(fun()->remove directory)(fun()->
    let file=Filename.concat directory "sketch.rays"in
    Out_channel.with_open_bin file(fun channel->output_string channel source);
    let editor=ref(Result.get_ok(Editor.create ~workspace ~await:true ~domains:1
      ~presets:(Filename.concat directory "presets")
      ~source:(Rays_editor.Source.at ~file ~digest:(Editor_document.Contexts.sha256 source))
      ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Scene3.empty)()))in
    Fun.protect ~finally:(fun()->Editor.close !editor)(fun()->
      editor:=Editor.update !editor(frame ~synthetic:false name 0);
      let inode=(Unix.stat file).st_ino in
      let save_frame={(frame ~synthetic:false name 1)with
        keys=[Input.Meta];events=[Event.KeyPressed(Input.KeyChar 's')]}in
      editor:=Editor.update !editor save_frame;
      editor:=Editor.update !editor(frame ~synthetic:false name 2);
      assert((Unix.stat file).st_ino<>inode);
      assert(read file=source);
      assert(Editor_document.Workspace_doc.to_text(Editor.workspace !editor)=source)));
  Printf.printf "port %s: Command-S atomically saves the unchanged source and comments\n%!"name
let modes=["lisp-a",false,1;"lisp-b",false,1;"cpu-1",false,1;"cpu-8",false,8;
  "reference-1",true,1;"reference-8",true,8]
let pictures ?(synthetic=true) ?(first=0) name workspace reference domains = Parallel.run ~domains(fun()->
  let evaluated=ok(E.static ~inputs:workspace.Editor_document.Workspace_doc.inputs workspace.checked)in
  let prepared=ok(Rays_editor.Drawing.prepare ~states:evaluated.states evaluated.plan
    (List.assoc "picture" evaluated.results))in
  let state=E.create_state()in
  Array.init 4(fun count->let frame=frame ~synthetic name (first+count) in
    let live=Rays_editor.Live_frame.of_frame frame in
    ok(Rays_editor.Drawing.render_prepared ~state ~reference prepared ~live ~size:frame.size)))
let serialize scene=Scene.Private.commands scene |> Scene_command.Render_ir.create |> Result.get_ok
  |> Scene_command.Render_ir.serialize
let mode_parity ()=List.iter(fun name->
  let workspace=load name in
  let expected=Array.map serialize(pictures name workspace false 1)in
  List.iter(fun(_,reference,domains)->
    let actual=Array.map serialize(pictures name workspace reference domains)in
    assert(actual=expected))modes;
  Printf.printf "port %s: source roundtrip, four synthetic frames, six-mode command parity\n%!"name)names

let pure ()=
  mode_parity();
  List.iter(fun name->save_roundtrip name(load name))names
let moving_circles ()=match Rays_editor.Workspace.load {|(workspace moving
 (graph picture :context draw (let* [phase (state [p 0.0] (+ p (frame/dt)))
  positions (map (fn [i] [(+ (mod i 640) (* 5 (sin phase))) (mod (int/div i 640) 360) 0]) (array/range 10000))]
  (draw/merge (draw/background "#111827") (draw/circles positions :radius 2.0 :fill "#22d3ee"))))
 (graph window :context settings (settings/config :width 640 :height 360)))|}with
 |Ok workspace->workspace|Error ds->failwith(String.concat"\n"(List.map Flow.Diagnostic.to_string ds))
let native_modes directory name workspace =
  let width,height=dimensions name in
  let config={Sketch.default_config with width;height;clock=Sketch.Fixed(1./.60.);fps=None}in
  let all=List.map(fun(mode,reference,domains)->mode,pictures ~synthetic:false ~first:1 name workspace reference domains)modes in
  (* A native export counts frames from one, like Workspace.export. *)
  List.iter(fun(mode,scenes)->
    let directory=directory^"/"^name^"/"^mode in
    if mode="lisp-a" || mode="lisp-b" then
      ignore(ok(Rays_editor.Workspace.export ~directory ~frames:4 workspace))else
    Parallel.run ~domains:(if String.ends_with ~suffix:"8" mode then 8 else 1)(fun()->
      ignore(Sketch.export_state ~config ~directory ~frames:4 ~init:(fun _->())
        ~update:(fun () _->()) ~view:(fun () frame->scenes.(frame.Frame.count-1))())))all;
  for count=0 to 3 do
    let path mode=Printf.sprintf "%s/%s/%s/frame-%06d.png" directory name mode count in
    let expected=read(path"lisp-a")in
    List.iter(fun(mode,_,_)->if read(path mode)<>expected then
      failwith(Printf.sprintf "%s frame %d: %s differs from lisp-a" name count mode))modes
  done
let native directory=
  native_modes directory "moving_circles" (moving_circles());
  List.iter(fun name->
    native_modes directory name (load name);
    Printf.printf "port %s: six PNG modes byte-identical\n%!"name)names
let ()=if Array.length Sys.argv>1 then native Sys.argv.(1)else begin
  pure();
  let workspace=moving_circles()in
  let expected=Array.map serialize(pictures "moving_circles" workspace false 1)in
  List.iter(fun(_,reference,domains)->
    assert(Array.map serialize(pictures "moving_circles" workspace reference domains)=expected))modes;
  assert(expected.(0)<>expected.(3));
  print_endline "10000 moving circles: four synthetic frames, six-mode command parity"
end
