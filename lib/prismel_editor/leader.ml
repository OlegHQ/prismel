open Prismel

open Editor_core.Keymap
type action =
  | Save_preset | Browse_presets
  | Toggle_timeline | Toggle_graph | Toggle_inspector | Hide_ui | Open_camera
  | Play_pause | Reset | Stop
  | Add_node | Layout | Frame_tile | Frame_camera
  | Look_through | Fly
  | Undo | Redo
  | Graph_command of Pxui_graph.command

type binding = (Workspace.column, action) Editor_core.Keymap.binding

type state = Editor_core.Router.state = Idle | Pending

(* One table drives both dispatch and the which-key panel. *)
let keymap = [
  { trigger = Leader 's'; label = "save preset"; scope = None; action = Save_preset };
  { trigger = Leader 'b'; label = "browse presets"; scope = None; action = Browse_presets };
  { trigger = Leader 't'; label = "toggle timeline"; scope = None; action = Toggle_timeline };
  { trigger = Leader 'g'; label = "toggle graph"; scope = None; action = Toggle_graph };
  { trigger = Leader 'i'; label = "toggle inspector"; scope = None; action = Toggle_inspector };
  { trigger = Leader 'h'; label = "hide all UI"; scope = None; action = Hide_ui };
  { trigger = Leader 'c'; label = "camera section"; scope = None; action = Open_camera };
  { trigger = Leader 'p'; label = "play / pause"; scope = None; action = Play_pause };
  { trigger = Leader 'r'; label = "reset"; scope = None; action = Reset };
  { trigger = Leader 'x'; label = "stop"; scope = None; action = Stop };
  { trigger = Leader 'a'; label = "add node"; scope = Some Workspace.Graph; action = Add_node };
  { trigger = Leader 'l'; label = "layout"; scope = Some Workspace.Graph; action = Layout };
  { trigger = Leader 'f'; label = "frame displayed tile"; scope = Some Workspace.Graph;
    action = Frame_tile };
  { trigger = Chord (Input.KeyChar 'f', []);
    label = "frame displayed tile"; scope = Some Workspace.Graph;
    action = Frame_tile };
  { trigger = Chord (Input.KeyChar 'f', []);
    label = "focus camera on displayed node"; scope = Some Workspace.View;
    action = Frame_camera };
] @ List.concat_map (fun modifier -> [
  { trigger = Chord (Input.KeyChar 'z', [modifier]);
    label = "undo"; scope = None; action = Undo };
  { trigger = Chord (Input.KeyChar 'z', [modifier; Input.Shift]);
    label = "redo"; scope = None; action = Redo };
  { trigger = Chord (Input.KeyChar 'y', [modifier]);
    label = "redo"; scope = None; action = Redo }]) [Input.Meta; Input.Ctrl]
@ List.map (fun (trigger, label, command) ->
  { trigger; label; scope = Some Workspace.Graph;
    action = Graph_command command }) Pxui_graph.bindings

(* Bindings only the 3D environment has. *)
let keymap3 = keymap @ [
  { trigger = Leader 'w'; label = "fly (WASD, Q/E, Esc)"; scope = Some Workspace.View; action = Fly };
  { trigger = Leader 'v'; label = "look through render camera"; scope = Some Workspace.View;
    action = Look_through };
]

let pane_name = function
  | Workspace.View -> "View" | Graph -> "Graph" | Inspector -> "Inspector"
  | Timeline -> "Timeline"
