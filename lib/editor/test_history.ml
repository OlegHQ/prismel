let () =
  let open Editor.History in
  let h = create ~capacity:3 0 in
  let h = record 1 h |> record 2 |> record ~merge:Repair 3 in
  assert (present h = 3 && depth h = 2);
  let h = Option.get (undo h) in
  assert (present h = 1 && can_redo h);
  let h = Option.get (redo h) in
  assert (present h = 3 && not (can_redo h));
  let h = record 4 h |> record 5 |> record 6 in
  assert (depth h = 3);
  let rec bottom h = match undo h with Some h -> bottom h | None -> h in
  assert (present (bottom h) = 3 && not (can_undo (bottom h)));
  let h = record ~merge:(Gesture 7) 7 h
    |> record ~merge:(Gesture 7) 8 in
  assert (present h = 8 && depth h = 3);
  let h = seal h |> record ~merge:(Gesture 7) 9 in
  assert (present (Option.get (undo h)) = 8);
  let burst at value h = record
      ~merge:(Burst { key = "view"; at; window = 0.25 }) value h in
  let h = create 0 |> burst 1. 1 |> burst 1.2 2 in
  assert (depth h = 1 && present (Option.get (undo h)) = 0);
  let h = burst 1.5 3 h in
  assert (depth h = 2 && present (Option.get (undo h)) = 2);
  let h = Option.get (undo h) in
  let h = record ~merge:Repair 10 h in
  assert (present h = 10 && not (can_redo h));
  print_endline "editor history: merge, seal, undo/redo, capacity ok"

type scope = View | Graph

let bindings : (scope, [ `Toggle | `Layout | `Undo | `Redo | `Delete | `Frame ])
    Editor.Keymap.binding list = [
  { trigger = Leader 'g'; label = "toggle graph"; scope = None; action = `Toggle };
  { trigger = Leader 'l'; label = "layout"; scope = Some Graph; action = `Layout };
  { trigger = Chord (Prismel.Input.KeyChar 'z', [Prismel.Input.Meta]);
    label = "undo"; scope = None; action = `Undo };
  { trigger = Chord (Prismel.Input.KeyChar 'z',
      [Prismel.Input.Meta; Prismel.Input.Shift]);
    label = "redo"; scope = None; action = `Redo };
  { trigger = Chord (Prismel.Input.Delete, []);
    label = "delete"; scope = Some Graph; action = `Delete };
  { trigger = Chord (Prismel.Input.KeyChar 'f', []);
    label = "frame"; scope = Some Graph; action = `Frame };
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
  let chord ?(focus = View) ?(text_focus = false) keys events =
    Editor.Router.step bindings ~focus ~text_focus
      ~frame:{ (frame events) with keys } Idle in
  let _, actions, passed = chord [Input.Meta] [Event.KeyPressed (Input.KeyChar 'Z');
      Event.TextInput "z"] in
  assert (actions = [`Undo] && passed.events = []);
  let _, actions, _ = chord [Input.Meta; Input.Shift]
      [Event.KeyPressed (Input.KeyChar 'z')] in
  assert (actions = [`Redo]);
  let _, actions, _ = chord ~focus:Graph [] [Event.KeyPressed Input.Delete] in
  assert (actions = [`Delete]);
  let _, actions, _ = chord ~focus:Graph []
      [Event.KeyPressed (Input.KeyChar 'F')] in
  assert (actions = [`Frame]);
  let _, actions, passed = chord ~focus:Graph [Input.Meta]
      [Event.KeyPressed (Input.KeyChar 'f')] in
  assert (actions = [] && passed.events = [Event.KeyPressed (Input.KeyChar 'f')]);
  let _, actions, passed = chord [] [Event.KeyPressed Input.Delete] in
  assert (actions = [] && passed.events = [Event.KeyPressed Input.Delete]);
  let _, actions, passed = chord ~text_focus:true [Input.Meta]
      [Event.KeyPressed (Input.KeyChar 'z')] in
  assert (actions = [] && passed.events = [Event.KeyPressed (Input.KeyChar 'z')]);
  print_endline "editor router: leader/chord scope, text focus, event consumption ok"
