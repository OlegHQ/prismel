module Editor=Rays_editor.Editor3
let load text=match Rays_editor.Workspace.load text with
  |Ok doc->doc|Error diagnostics->failwith(String.concat "\n"(List.map Flow.Diagnostic.to_string diagnostics))
let frame ?(keys=[]) ?(events=[]) count : Rays.Frame.t={width=640;height=360;size=640,360;
  drawable_width=640;drawable_height=360;drawable_size=640,360;pixel_scale=1.,1.;
  time=float count /. 60.;dt=1. /. 60.;fps=60.;count;mouse=(-100.,-100.);mouse_delta=0.,0.;
  mouse_buttons=[];keys;events}
let workspace effects=load("(workspace host (graph picture :context draw (draw/background \"#111827\")) "^
  "(graph actions :context host "^effects^") (graph editor :context editor "^
  "(ui/workspace (ui/canvas (ref picture)) :effects (ref actions))))")
let with_editor workspace run =
  let editor=ref(Result.get_ok(Editor.create ~workspace ~await:true ~domains:1
    ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)()))in
  Fun.protect ~finally:(fun()->Editor.close !editor)(fun()->run editor)
let ()=
  let doc=workspace "(list (host/quit (key/down \"q\")))"in
  with_editor doc(fun editor->
    editor:=Editor.update !editor(frame 0);
    assert(Editor.Private.host_stats !editor=(false,0,0,0));
    for count=1 to 2 do editor:=Editor.update !editor
      (frame ~keys:[Rays.Input.KeyChar 'q'] ~events:[Rays.Event.KeyPressed(Rays.Input.KeyChar 'q')] count)done;
    assert(Editor.Private.host_stats !editor=(true,1,0,0));
    editor:=Editor.update !editor(frame 3);
    editor:=Editor.update !editor(frame ~keys:[Rays.Input.KeyChar 'q'] 4);
    assert(Editor.Private.host_stats !editor=(true,2,0,0)));
  assert(match Rays_editor.Workspace.export ~directory:"/tmp/rays-effects-refused" ~frames:1
    (workspace "(list (host/quit true))") with
    |Error diagnostic->diagnostic.Flow.Diagnostic.code="E_EFFECT_EXPORT"|Ok()->false);
  let doc=workspace "(list (host/play (audio/synth :frequency 440.0 :duration 0.01) (key/down \"a\")) (host/play (audio/synth :frequency 440.0 :duration 0.01) (key/down \"a\")))"in
  let closed=with_editor doc(fun editor->
    editor:=Editor.update !editor(frame ~keys:[Rays.Input.KeyChar 'a'] 1);
    assert(Editor.Private.host_stats !editor=(false,2,1,0));
    editor:=Editor.update !editor(frame ~keys:[Rays.Input.KeyChar 'a'] 2);
    assert(Editor.Private.host_stats !editor=(false,2,1,0));
    !editor)in
  assert(Editor.Private.host_stats closed=(false,2,1,1));
  print_endline "host: synthetic key edge fires once, export rejects quit, two nodes share one sample, close releases once"
