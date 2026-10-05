open Rays
module Command = Editor_core.Command
module Keymap = Editor_core.Keymap
module Settings = Rays_editor.Settings

let check condition message = if not condition then failwith message
let key k = Event.KeyPressed k
let char c = key (Input.KeyChar c)
let schema = Editor_core.Param.(schema ~name:"command-value" ~default:0
  [field ~name:"value" ~label:"Value" ~kind:(integer ~min:0 ~max:100 ())
    ~default:0 ~get:Fun.id ~set:(fun value _ -> value) ()])

let run () =
  let open Editor_core.Guide_context in
  let module L = Rays_editor.Private.Leader in
  List.iter (fun focus ->
    List.iter (fun (events, expected) ->
      let _, actions, _ = Editor_core.Router.step L.keymap ~focus ~text_focus:false
        ~frame:(Test_editor_input.frame (500.,400.) events 1) Idle in
      check (List.map (fun (c : _ Command.t) -> c.action) actions = [expected]) "guide key failed outside or inside graph focus")
      [key Input.Shift :: [char '/'], L.Guide_toggle;
       [char '?'], L.Guide_toggle; [key Input.Space; char '?'], L.Guide_keys])
    Pxui_shell.Layout.[View ""; View "v1.0"; Graph; List; Lisp; Inspector; Outline; Timeline];
  (* Tab is the graph's own key for the add menu ("Tab add after" on the strip), and no other pane's *)
  List.iter (fun (focus, expected) ->
    let _, actions, _ = Editor_core.Router.step L.keymap ~focus ~text_focus:false
      ~frame:(Test_editor_input.frame (500.,400.) [key Input.Tab] 1) Idle in
    check (List.map (fun (c : _ Command.t) -> c.action) actions = expected) "Tab is not the graph's add key alone")
    Pxui_shell.Layout.[Graph, [L.Add_node]; View "", []; Outline, []; Inspector, []];
  check (Keymap.label (Chord (Input.KeyChar '/', [Input.Shift])) = "?"
      && Keymap.label (Chord (Input.ArrowLeft, [])) = "←"
      && Keymap.label (Chord (Input.KeyChar 'z', [Input.Shift; Input.Meta])) = "⌘⇧Z")
    "shared key labels lost a modifier or alias";
  let module Scope = Pxui_graph.Scope in
  let ids context = Command.for_guide Scope.bindings ~focus:() ~context
    |> List.map (fun (c : _ Command.t) -> c.id) in
  (* the strip lists a key where it does something: walking and framing on the empty canvas;
     editing needs a selection; duplicate and delete take several nodes, rename and view one *)
  check (List.mem "scope.walk.left" (ids Canvas) && List.mem "scope.frame-all" (ids Canvas)
         && not (List.mem "scope.delete" (ids Canvas)) && not (List.mem "scope.duplicate" (ids Canvas))
         && List.mem "scope.delete" (ids Node) && List.mem "scope.rename" (ids Node)
         && List.mem "scope.display" (ids Node) && List.mem "scope.fold" (ids Node)
         && List.mem "scope.duplicate" (ids Multi) && List.mem "scope.repeat" (ids Multi)
         && not (List.mem "scope.display" (ids Multi)) && not (List.mem "scope.fold" (ids Multi))
         && ids Search = [] && ids Text = [] && ids List = [] && ids Leader = [] && ids Hints = [])
    "the workspace pane's guide lost or misplaced a key for its contexts";
  check (List.for_all (fun (c : _ Command.t) -> c.guide <> []) Scope.bindings)
    "a workspace pane key is listed in no guide context";
  let host_ids focus context = Command.for_guide L.keymap ~focus ~context
    |> List.map (fun (c : _ Command.t) -> c.id) in
  check (List.mem "guide.toggle" (host_ids (Pxui_shell.Layout.View "") Canvas)
      && not (List.mem "graph.add" (host_ids (Pxui_shell.Layout.View "") Canvas))
      && List.mem "panel.list" (host_ids Pxui_shell.Layout.Graph Leader)
      && List.mem "preset.save" (host_ids Pxui_shell.Layout.Graph Leader))
    "host guide lost a context or ignored command scope";
  (* Enter needs a selected object, up a level does not; the list has both *)
  check (List.mem "scene.enter" (host_ids Pxui_shell.Layout.Graph Node)
         && not (List.mem "scene.enter" (host_ids Pxui_shell.Layout.Graph Canvas))
         && List.mem "scene.up" (host_ids Pxui_shell.Layout.Graph Canvas)
         && List.mem "scene.enter" (host_ids Pxui_shell.Layout.Graph List)
         && List.mem "guide.keys" (host_ids Pxui_shell.Layout.Graph Hints)
         && List.mem "list.up" (host_ids Pxui_shell.Layout.Graph List)
         && not (List.mem "list.up" (host_ids Pxui_shell.Layout.Graph Canvas)))
    "the host guide contexts changed";
  (* the list walks with j and k as with the arrows *)
  let list_step key_char expected =
    let _, actions, _ = Editor_core.Router.step L.keymap ~focus:Pxui_shell.Layout.Graph ~text_focus:false
      ~frame:(Test_editor_input.frame (500., 400.) [ char key_char ] 1) Idle in
    List.exists (fun (c : _ Command.t) -> c.action = L.List_command expected) actions in
  check (list_step 'j' Pxui_shell.Tree.Down && list_step 'k' Pxui_shell.Tree.Up) "j and k do not walk the list";
  (* focus is a panel; commands are scoped by its kind: every viewport is one scope, and the
     list and lisp panels are graph-pane projections *)
  let module P = Pxui_shell.Layout in
  check (List.for_all (fun panel -> L.scope panel = P.Graph) [P.Graph; P.List; P.Lisp]
      && L.scope (P.View "v1.2") = P.View "" && L.scope (P.View "main") = L.scope (P.View "v0")
      && L.scope P.Inspector = P.Inspector && L.scope P.Outline = P.Outline)
    "panel kinds do not map to the scopes commands use";
  check (host_ids (L.scope P.Lisp) Canvas = host_ids P.Graph Canvas
      && host_ids (L.scope (P.View "v3")) Canvas = host_ids (P.View "") Canvas
      && host_ids (L.scope P.Outline) Canvas <> host_ids P.Graph Canvas)
    "a lisp or second viewport panel routed to the wrong scope";
  let table = List.map (fun (command : _ Command.t) ->
    {command with scope = Some Pxui_shell.Layout.Graph}) Scope.bindings in
  List.iter (fun (pressed, modifiers, expected) ->
    let input = Test_editor_input.frame ~keys:[] (500.,400.)
      (List.map key modifiers @ [key pressed]) 1 in
    let route focus = let _, actions, _ = Editor_core.Router.step table ~focus
      ~text_focus:false ~frame:input Idle in List.map (fun (c : _ Command.t) -> c.action) actions in
    check (route Pxui_shell.Layout.Graph = [expected]) "a graph pane key routed the wrong action";
    check (route (Pxui_shell.Layout.View "") = [] && route Pxui_shell.Layout.Inspector = [])
      "a graph pane key escaped graph scope")
    Scope.[Input.ArrowLeft, [], Walk Left; Input.ArrowDown, [], Walk Down;
      Input.ArrowUp, [], Walk Up; Input.ArrowRight, [], Walk Right;
      Input.KeyChar 'x', [], Delete; Input.Delete, [], Delete; Input.Backspace, [], Delete;
      Input.KeyChar 'b', [], Bypass; Input.KeyChar 'r', [], Wrap_repeat;
      Input.KeyChar 'r', [Input.Shift], Wrap_iterate; Input.KeyChar 'c', [], Collapse;
      Input.KeyChar 'm', [], Make_macro; Input.Home, [], Frame_all];
  let exercise ~name ~create ~update ~close ~settings ~set_settings =
    let set n env = set_settings env (Settings.make schema n) in
    let bump = set 3 in
    let make ?scope ?(id = "test.bump") trigger action =
      Command.make ~id ~label:"bump command" ~trigger ?scope action in
    let rejected commands message = match create commands with
      | Error reason -> check (String.length reason > 0) (name ^ ": empty command error")
      | Ok env -> close env; failwith (name ^ ": " ^ message) in
    rejected [make (Keymap.Leader "qj") bump; make (Leader "j") (set 4)]
      "different actions sharing an id were accepted";
    rejected [make ~id:"edit.undo" (Leader "qj") bump] "reserved id was accepted";
    rejected [make (Leader "s") bump] "built-in leader collision was accepted";
    rejected [make (Chord (Input.KeyChar 'Z', [Input.Meta])) bump]
      "built-in chord collision was accepted";
    rejected [make (Leader "qj") bump; make ~id:"test.other" (Leader "QJ") (set 4)]
      "case-equivalent triggers were accepted";
    rejected [make (Leader "qj") bump; make ~id:"test.other" (Leader "qjj") (set 4)]
      "unreachable leader prefix was accepted";
    rejected [make (Chord (Input.Space, [])) bump] "unreachable Space chord was accepted";
    rejected [make (Leader "") bump] "empty leader was accepted";
    rejected [make (Chord (Input.KeyChar 'k', [Input.Shift])) bump;
      make ~id:"test.other" (Chord (Input.KeyChar 'k', [Input.Alt])) (set 4)]
      "equal-specificity overlapping chords were accepted";
    rejected [make (Chord (Input.KeyChar 'k', [Input.Enter])) bump]
      "non-modifier chord key was accepted";
    rejected [make ~id:"" (Leader "qj") bump] "empty id was accepted";
    let commands = [make (Leader "QJ") bump; make (Leader "qq") bump;
      make ~id:"test.modifier" (Chord (Input.KeyChar 'm', [Input.Meta])) (set 30);
      make ~scope:(Pxui_shell.Layout.View "") ~id:"test.view"
        (Chord (Input.KeyChar 'g', [])) (set 10);
      make ~scope:Pxui_shell.Layout.Graph ~id:"test.graph"
        (Chord (Input.KeyChar 'g', [])) (set 20)] in
    let current = ref (create commands |> Result.get_ok) and count = ref 0 in
    Fun.protect ~finally:(fun () -> close !current) (fun () ->
      let step ?(mouse = (100., 300.)) ?(keys = []) events =
        incr count;
        current := update !current (Test_editor_input.frame ~keys mouse events !count) in
      let value () = Settings.get schema (settings !current) in
      step []; step [key Input.Space; char 'q'; char 'j'];
      check (value () = 3) (name ^ ": canonical leader action did not run");
      current := set 0 !current;
      step [key Input.Space; char 'q'; char 'q'];
      check (value () = 3) (name ^ ": alias action differed");
      current := set 0 !current;
      step [key Input.Space; char '/']; step [Event.TextInput "bump command"];
      step [key Input.Enter]; step [];
      check (value () = 3) (name ^ ": palette action differed");
      current := set 0 !current;
      step [key Input.Meta; char 'm'; Event.KeyReleased Input.Meta];
      check (value () = 30) (name ^ ": same-frame Command release changed chord dispatch");
      current := set 0 !current;
      step ~keys:[Input.Meta] [char 'm'; key Input.Meta];
      check (value () = 0) (name ^ ": a later modifier press changed an earlier chord");
      step [char 'g'];
      check (value () = 10) (name ^ ": view-scoped chord did not run");
      let point = 500., 500. in
      step ~mouse:point [Event.MousePressed (Input.LeftButton, point);
        Event.MouseReleased (Input.LeftButton, point)];
      step [char 'g'];
      check (value () = 20) (name ^ ": graph-scoped chord did not run")) in
  let workspace = Ws_fixture.box () in
  let module E3 = Rays_editor.Editor3 in
  exercise ~name:"Editor3"
    ~create:(fun commands -> E3.create ~workspace ~commands ~settings:(Settings.make schema 0)
      ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ _ -> Scene3.empty) ())
    ~update:E3.update ~close:E3.close ~settings:E3.settings ~set_settings:E3.set_settings;
  let module E2 = Rays_editor.Editor2 in
  exercise ~name:"Editor2"
    ~create:(fun commands -> E2.create ~workspace ~commands ~settings:(Settings.make schema 0)
      ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ _ -> []) ())
    ~update:E2.update ~close:E2.close ~settings:E2.settings ~set_settings:E2.set_settings;
  let directory = Filename.temp_dir "rays-guide" "" in
  let filename = Filename.concat directory "preferences.rays" in
  let previous = Sys.getenv_opt "RAYS_EDITOR_PREFERENCES" in
  Unix.putenv "RAYS_EDITOR_PREFERENCES" filename;
  let create () = E2.create ~workspace ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ _ -> []) ()
    |> Result.get_ok in
  let current = ref (create ()) in
  Fun.protect ~finally:(fun () ->
    E2.close !current;
    Unix.putenv "RAYS_EDITOR_PREFERENCES" (Option.value ~default:"" previous);
    Array.iter (fun file -> Sys.remove (Filename.concat directory file)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    let step events count = current := E2.update !current
      (Test_editor_input.frame (100.,300.) events count) in
    let enabled () = Editor_core.Store.Settings.load ~sketch:"rays-editor" filename
      |> Result.get_ok |> fun values -> Editor_core.Store.Settings.bool values "guide" in
    step [] 0; step [char '?'] 1;
    check (enabled () = Some false) "guide did not default on and persist off";
    check (not (E2.can_undo !current)) "guide preference entered document history";
    E2.close !current; current := create (); step [] 2; step [char '?'] 3;
    check (enabled () = Some true) "a new host did not load the saved guide preference";
    (* A sheet owns input until shared modal dismissal, then shortcuts resume. *)
    step [key Input.Space; char '?'] 4; step [char '?'] 5;
    check (enabled () = Some true) "guide key escaped the key-sheet modal";
    step [key Input.Escape] 6; step [char '?'] 7;
    check (enabled () = Some false) "key-sheet dismissal kept keyboard focus";
    (* Toggle preserves unrelated preferences, and Hide follows the same save path. *)
    Editor_core.Store.Settings.save ~sketch:"rays-editor" filename
      ["guide", Bool false; "other", Int 7] |> Result.get_ok;
    step [key Input.Shift; char '/'; Event.KeyReleased Input.Shift] 8;
    (* the strip's keys are the sheets' own and carry no "toggle guide" pair: the key is the control,
       and it saves through the same path, keeping the other preferences *)
    step [char '?'] 9;
    let values = Editor_core.Store.Settings.load ~sketch:"rays-editor" filename |> Result.get_ok in
    check (Editor_core.Store.Settings.bool values "guide" = Some false
      && Editor_core.Store.Settings.int values "other" = Some 7)
      "Hide did not save off or discarded another preference";
    let contents = "invalid saved preferences" in
    Out_channel.with_open_bin filename (fun out -> output_string out contents);
    step [char '?'] 10;
    check (In_channel.with_open_bin filename In_channel.input_all = contents)
      "guide toggle overwrote an unreadable preference file";
    E2.crash_dump !current directory;
    let dump () = In_channel.with_open_bin (Filename.concat directory "editor.txt")
      In_channel.input_all in
    let contains text piece = let n = String.length piece in
      List.exists (fun i -> String.sub text i n = piece)
        (List.init (max 0 (String.length text-n+1)) Fun.id) in
    check (contains (dump ()) "key hud: ? · toggle guide\n")
      "key HUD did not use the routed command label";
    step [key Input.Ctrl; char 'z'; Event.KeyReleased Input.Ctrl] 13;
    E2.crash_dump !current directory;
    check (contains (dump ()) "key hud: ⌃Z · undo\n")
      "key HUD displayed a different alias from the routed chord";
    step [] 200; E2.crash_dump !current directory;
    check (contains (dump ()) "key hud: -\n") "key HUD outlived 1.5 seconds");
  print_endline "editor commands: both hosts reject ambiguity and share alias/scoped keyboard/palette actions"
