let () =
  let open Editor.History in
  let h = create ~capacity:3 0 in
  let h = commit 1 h |> commit 2 |> amend 3 in
  assert (present h = 3 && depth h = 2);
  let h = Option.get (undo h) in
  assert (present h = 1 && can_redo h);
  let h = Option.get (redo h) in
  assert (present h = 3 && not (can_redo h));
  let h = commit 4 h |> commit 5 |> commit 6 in
  assert (depth h = 3);
  let rec bottom h = match undo h with Some h -> bottom h | None -> h in
  assert (present (bottom h) = 3 && not (can_undo (bottom h)));
  assert (commit 6 h == h);
  print_endline "editor history: commit/amend/undo/redo/bounded ok"

type scope = View | Graph

let bindings : (scope, [ `Toggle | `Layout ]) Editor.Keymap.binding list = [
  { key = 'g'; label = "toggle graph"; scope = None; action = `Toggle };
  { key = 'l'; label = "layout"; scope = Some Graph; action = `Layout };
]

let frame events : Prismel.Frame.t = {
  width = 10; height = 10; size = 10, 10;
  drawable_width = 10; drawable_height = 10; drawable_size = 10, 10;
  pixel_scale = 1., 1.; time = 0.; dt = 0.; fps = 0.; count = 0;
  mouse = 0., 0.; mouse_delta = 0., 0.; keys = []; mouse_buttons = [];
  events;
}

let () =
  let open Prismel in
  let open Editor.Router in
  let step ?(focus = View) ?(text_focus = false) state keys =
    Editor.Router.step bindings ~focus ~text_focus
      ~frame:(frame (List.map (fun key -> Event.KeyPressed key) keys)) state in
  let state, actions, passed = step Idle [Input.Space; Input.KeyChar 'g'] in
  assert (state = Idle && actions = [`Toggle] && passed.events = []);
  let state, actions, _ = Editor.Router.step bindings ~focus:View
      ~text_focus:false ~frame:(frame [Event.KeyPressed Input.Space;
        Event.TextInput " "]) Idle in
  assert (state = Pending && actions = []);
  let state, actions, passed = Editor.Router.step bindings ~focus:View
      ~text_focus:false ~frame:(frame [Event.KeyPressed (Input.KeyChar 'g');
        Event.TextInput "g"]) state in
  assert (state = Idle && actions = [`Toggle] && passed.events = []);
  let state, actions, _ = step Idle [Input.Space] in
  assert (state = Pending && actions = []);
  let state, actions, passed = step state [Input.Escape] in
  assert (state = Idle && actions = [] && passed.events = []);
  let _, actions, _ = step Idle [Input.Space; Input.KeyChar 'l'] in
  assert (actions = []);
  let _, actions, _ = step ~focus:Graph Idle [Input.Space; Input.KeyChar 'l'] in
  assert (actions = [`Layout]);
  let state, actions, passed = step ~text_focus:true Idle [Input.Space] in
  assert (state = Idle && actions = []
      && passed.events = [Event.KeyPressed Input.Space]);
  print_endline "editor router: leader scope, text focus and event consumption ok"
