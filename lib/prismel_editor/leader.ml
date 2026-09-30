open Prismel

open Editor_core.Keymap
type action =
  | Save_preset | Browse_presets
  | Save_source  (* Command-S: rewrite the sketch's .plisp, else a preset *)
  | Toggle_timeline | Toggle_graph | Toggle_inspector | Hide_ui | Open_camera
  | Play_pause | Reset | Stop
  | Add_node
  | Frame_tile | Frame_camera
  | Look_through | Fly | Tool of int  (* 0 none, 1 translate, 2 rotate, 3 scale *)
  | Undo | Redo
  | Panel_split of Pxui_shell.Layout.axis | Panel_close | Panel_retype of Pxui_shell.Layout.panel
      (* Space o ...: the focused panel, as the header menu does *)
  | Toggle_projection | Restore_layout | Enter | Up | Go_world
  | World_emit | World_reseed | World_time of float | World_play | World_preset of int
  | Scope_command of Pxui_graph.Scope.command  (* the workspace pane, see [Core.scope_name] *)
  | List_command of Pxui_shell.Tree.command
  | Guide_toggle | Guide_keys
  | Command_palette
  | Sketch_command of string  (* the id of a sketch [Editor_core.Command] *)

(* A command's scope is a kind of panel: any viewport is [View ""], and the list and the
   lisp panel are the graph pane's other projections. *)
type command = (Pxui_shell.Layout.panel, action) Editor_core.Command.t

let scope : Pxui_shell.Layout.panel -> Pxui_shell.Layout.panel = function
  | View _ -> View "" | List | Lisp -> Graph | panel -> panel

type state = Editor_core.Router.state = Idle | Pending of string

let command ?trigger ?scope ?(guide = []) ~id ~label action =
  let guide = match trigger with Some (Leader _) -> Editor_core.Guide_context.Leader :: guide
    | _ -> guide in
  Editor_core.Command.make ?trigger ?scope ~guide ~id ~label action
let graph = Pxui_shell.Layout.Graph and view = Pxui_shell.Layout.View ""

(* One table drives dispatch, which-key, and the command palette. *)
let keymap = [
  command ~id:"guide.toggle" ~label:"toggle guide"
    ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; Hints; Leader; List]
    ~trigger:(Chord (Input.KeyChar '/', [Input.Shift])) Guide_toggle;
  command ~id:"guide.toggle" ~label:"toggle guide"
    ~trigger:(Chord (Input.KeyChar '?', [])) Guide_toggle;
  command ~id:"guide.keys" ~label:"all Flow keys"
    ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; Hints; List] ~trigger:(Leader "k") Guide_keys;
  command ~id:"preset.save" ~label:"save preset" ~trigger:(Leader "s") Save_preset;
  command ~id:"preset.browse" ~label:"browse presets" ~trigger:(Leader "b") Browse_presets;
  command ~id:"workspace.toggle-timeline" ~label:"toggle timeline" ~trigger:(Leader "t")
    Toggle_timeline;
  command ~id:"workspace.toggle-graph" ~label:"toggle graph" ~trigger:(Leader "g") Toggle_graph;
  command ~id:"workspace.toggle-inspector" ~label:"toggle inspector" ~trigger:(Leader "i")
    Toggle_inspector;
  command ~id:"workspace.hide-ui" ~label:"hide all UI" ~trigger:(Leader "h") Hide_ui;
  command ~id:"workspace.camera-section" ~label:"camera section" ~trigger:(Leader "c")
    Open_camera;
  command ~id:"timeline.play-pause" ~label:"play / pause" ~trigger:(Leader "p") Play_pause;
  command ~id:"timeline.reset" ~label:"reset" ~trigger:(Leader "r") Reset;
  command ~id:"sketch.stop" ~label:"stop" ~trigger:(Leader "x") Stop;
  command ~id:"workspace.command-palette" ~label:"command palette" ~trigger:(Leader "/")
    Command_palette;
  command ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; List] ~id:"graph.projection" ~label:"graph / list / text" ~trigger:(Leader "l") Toggle_projection;
  command ~id:"workspace.restore-layout" ~label:"restore layout" ~trigger:(Leader "z")
    Restore_layout;
  command ~id:"panel.split-right" ~label:"split panel, side by side" ~trigger:(Leader "oh")
    (Panel_split `H);
  command ~id:"panel.split-below" ~label:"split panel, stacked" ~trigger:(Leader "ov")
    (Panel_split `V);
  command ~id:"panel.close" ~label:"close panel" ~trigger:(Leader "ox") Panel_close;
  command ~id:"panel.graph" ~label:"panel becomes graph" ~trigger:(Leader "og") (Panel_retype Graph);
  command ~id:"panel.list" ~label:"panel becomes list" ~trigger:(Leader "ol") (Panel_retype List);
  command ~id:"panel.lisp" ~label:"panel becomes text" ~trigger:(Leader "ot") (Panel_retype Lisp);
  command ~id:"panel.inspector" ~label:"panel becomes inspector" ~trigger:(Leader "oi")
    (Panel_retype Inspector);
  command ~id:"panel.outline" ~label:"panel becomes outline" ~trigger:(Leader "ou")
    (Panel_retype Outline);
  command ~id:"panel.timeline" ~label:"panel becomes timeline" ~trigger:(Leader "om")
    (Panel_retype Timeline);
  command ~id:"panel.viewport" ~label:"panel becomes viewport" ~trigger:(Leader "ow")
    (Panel_retype (View ""));
  command ~id:"scene.world" ~label:"World" ~trigger:(Leader "e") Go_world;
  command ~id:"graph.add-node" ~label:"add (menu)" ~trigger:(Leader "a") Add_node;
  command ~guide:Editor_core.Guide_context.[Node; List]
    ~id:"world.emit" ~label:"dome / light" ~trigger:(Chord (Input.KeyChar 't', []))
    ~scope:graph World_emit;
  command ~guide:Editor_core.Guide_context.[Node; List]
    ~id:"world.reseed" ~label:"reseed" ~trigger:(Chord (Input.KeyChar 'n', []))
    ~scope:graph World_reseed;
  command ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; List]
    ~id:"world.earlier" ~label:"time -30 min" ~trigger:(Chord (Input.KeyChar '[', []))
    ~scope:graph (World_time (-0.5));
  command ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; List]
    ~id:"world.later" ~label:"time +30 min" ~trigger:(Chord (Input.KeyChar ']', []))
    ~scope:graph (World_time 0.5);
  command ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; List]
    ~id:"world.play" ~label:"play day cycle" ~trigger:(Chord (Input.KeyChar 'd', []))
    ~scope:graph World_play;
] @ List.mapi (fun index (name, _) ->
  command ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; List]
    ~id:("world.preset." ^ string_of_int (index + 1)) ~label:("preset " ^ name)
    ~trigger:(Chord (Input.KeyChar (Char.chr (Char.code '1' + index)), []))
    ~scope:graph (World_preset index)) World.presets
@ [
  command ~guide:Editor_core.Guide_context.[Node; List] ~id:"scene.enter" ~label:"enter object"
    ~trigger:(Chord (Input.KeyChar 'i', [])) Enter;
  command ~guide:Editor_core.Guide_context.[Canvas; Node; Multi; List] ~id:"scene.up" ~label:"up a level"
    ~trigger:(Chord (Input.KeyChar 'u', [])) Up;
  (* Rare: the graph context menu and the palette, no leader key. *)
  command ~id:"graph.frame-tile" ~label:"frame displayed tile" ~trigger:(Leader "f")
    ~scope:graph Frame_tile;
  command ~guide:Editor_core.Guide_context.[List] ~id:"graph.frame-tile" ~label:"reveal list selection"
    ~trigger:(Chord (Input.KeyChar 'f', [])) ~scope:graph Frame_tile;
  command ~id:"view.frame-camera" ~label:"focus camera on displayed node"
    ~trigger:(Chord (Input.KeyChar 'f', [])) ~scope:view Frame_camera;
] @ List.concat_map (fun modifier -> [
  command ~id:"file.save" ~label:"save sketch" ~trigger:(Chord (Input.KeyChar 's', [modifier])) Save_source;
  command ~id:"edit.undo" ~label:"undo" ~trigger:(Chord (Input.KeyChar 'z', [modifier])) Undo;
  command ~id:"edit.redo" ~label:"redo"
    ~trigger:(Chord (Input.KeyChar 'z', [modifier; Input.Shift])) Redo;
  command ~id:"edit.redo" ~label:"redo" ~trigger:(Chord (Input.KeyChar 'y', [modifier])) Redo])
  [Input.Meta; Input.Ctrl]
@ List.map (fun (c : _ Editor_core.Command.t) ->
  { c with scope = Some graph; action = Scope_command c.action }) Pxui_graph.Scope.bindings
@ List.map (fun (c : _ Editor_core.Command.t) ->
  { c with scope = Some graph; guide = [Editor_core.Guide_context.List];
    action = List_command c.action }) Pxui_shell.Tree.bindings

(* Commands only the 3D environment has. *)
let keymap3 = keymap @ [
  command ~id:"view.fly" ~label:"fly (WASD, Q/E, Esc)" ~trigger:(Leader "w") ~scope:view Fly;
  command ~id:"view.look-through" ~label:"look through render camera" ~trigger:(Leader "v")
    ~scope:view Look_through;
  command ~id:"view.translate" ~label:"translate handles"
    ~trigger:(Chord (Input.KeyChar 'w', [])) ~scope:view (Tool 1);
  command ~id:"view.rotate" ~label:"rotate handles"
    ~trigger:(Chord (Input.KeyChar 'e', [])) ~scope:view (Tool 2);
  command ~id:"view.scale" ~label:"scale handles"
    ~trigger:(Chord (Input.KeyChar 'r', [])) ~scope:view (Tool 3);
  command ~id:"view.orbit" ~label:"orbit only (hide handles)"
    ~trigger:(Chord (Input.Escape, [])) ~scope:view (Tool 0);
]

let pane_name = function
  | Pxui_shell.Layout.View _ -> "View" | Graph -> "Graph" | List -> "List" | Lisp -> "Lisp"
  | Inspector -> "Inspector" | Outline -> "Outline" | Timeline -> "Timeline"
