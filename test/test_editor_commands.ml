open Prismel
module Command = Editor_core.Command
module Keymap = Editor_core.Keymap
module Settings = Prismel_editor.Settings

let check condition message = if not condition then failwith message
let key k = Event.KeyPressed k
let char c = key (Input.KeyChar c)
let schema = Editor_core.Param.(schema ~name:"command-value" ~default:0
  [field ~name:"value" ~label:"Value" ~kind:(integer ~min:0 ~max:100 ())
    ~default:0 ~get:Fun.id ~set:(fun value _ -> value) ()])

let run () =
  let open Editor_core.Guide_context in
  let module L = Prismel_editor.Private.Leader in
  List.iter (fun focus ->
    List.iter (fun (events, expected) ->
      let _, actions, _ = Editor_core.Router.step L.keymap ~focus ~text_focus:false
        ~frame:(Test_editor_input.frame (500.,400.) events 1) Idle in
      check (List.map (fun (c : _ Command.t) -> c.action) actions = [expected]) "guide key failed outside or inside graph focus")
      [key Input.Shift :: [char '/'], L.Guide_toggle;
       [char '?'], L.Guide_toggle; [key Input.Space; char 'k'], L.Guide_keys])
    Pxui_shell.Layout.[View; Graph; Inspector; Timeline];
  check (Keymap.label (Chord (Input.KeyChar '/', [Input.Shift])) = "?"
      && Keymap.label (Chord (Input.ArrowLeft, [])) = "←"
      && Keymap.label (Chord (Input.KeyChar 'z', [Input.Shift; Input.Meta])) = "Cmd-Shift-z")
    "shared key labels lost a modifier or alias";
  let _, group_actions, _ = Editor_core.Router.step L.keymap
    ~focus:Pxui_shell.Layout.Graph ~text_focus:false
    ~frame:(Test_editor_input.frame (500., 400.)
      [key Input.Meta; char 'g'] 1) Idle in
  check (List.map (fun (c : _ Command.t) -> c.action) group_actions = [L.Group])
    "compound group chord was not routed through the shared command table";
  let _, ungroup_actions, _ = Editor_core.Router.step L.keymap
    ~focus:Pxui_shell.Layout.Graph ~text_focus:false
    ~frame:(Test_editor_input.frame ~keys:[Input.Meta; Input.Shift]
      (500., 400.) [char 'g'] 2) Idle in
  check (List.map (fun (c : _ Command.t) -> c.action) ungroup_actions = [L.Ungroup])
    "compound ungroup chord was not routed through the shared command table";
  check (List.exists (fun (c : _ Command.t) ->
    c.id = "graph.make-unique" && c.action = L.Make_unique) L.keymap)
    "make unique is missing from the shared command palette";
  let ids context = Command.for_guide Pxui_graph.bindings ~focus:() ~context
    |> List.map (fun (c : _ Command.t) -> c.id) in
  let walks = ["graph.walk.left"; "graph.walk.down"; "graph.walk.up"; "graph.walk.right"] in
  List.iter (fun (context, expected) -> check (ids context = expected)
      ("guide contents/order differ for " ^ Editor_core.Guide_context.name context))
    Editor_core.Guide_context.[
      Canvas, ["graph.paste"; "graph.frame-all"; "graph.open-all"; "graph.point-all"]
        @ walks @ ["graph.add"; "graph.repeat"; "graph.show-wireless";
          "graph.find"; "graph.frame-tile"];
      Node, ["graph.copy"; "graph.cut"; "graph.paste"; "graph.duplicate";
        "graph.frame-all"; "graph.open"; "graph.point"; "graph.open-all"; "graph.point-all"]
        @ walks @ ["graph.add"; "graph.repeat"; "graph.connect-hint";
          "graph.bind"; "graph.show-wireless"; "graph.display";
          "graph.mute"; "graph.delete"; "graph.dissolve"; "graph.find"; "graph.frame-tile"];
      Multi, ["graph.copy"; "graph.cut"; "graph.paste"; "graph.duplicate";
        "graph.frame-all"; "graph.open"; "graph.point"; "graph.open-all"; "graph.point-all"]
        @ walks @ ["graph.add"; "graph.show-wireless"; "graph.mute";
          "graph.delete"; "graph.dissolve";
          "graph.find"; "graph.frame-tile"];
      Wire, ["graph.add"; "graph.bind"; "graph.show-wireless";
        "graph.delete"]; Row, ["graph.row-pin"; "graph.row-reset";
          "graph.row-expression"];
      Search, []; Text, []];
  let host_ids focus context = Command.for_guide L.keymap ~focus ~context
    |> List.map (fun (c : _ Command.t) -> c.id) in
  check (List.mem "guide.toggle" (host_ids Pxui_shell.Layout.View Canvas)
      && not (List.mem "graph.add" (host_ids Pxui_shell.Layout.View Canvas))
      && List.mem "graph.projection" (host_ids Pxui_shell.Layout.Graph List)
      && List.mem "preset.save" (host_ids Pxui_shell.Layout.Graph Leader))
    "host guide lost a context or ignored command scope";
  check (List.length (Command.for_guide Pxui_graph.hint_bindings ~focus:() ~context:Hints) = 28)
    "hint guide lost target letters, back or cancel";
  let table = List.map (fun (command : _ Command.t) ->
    {command with scope = Some Pxui_shell.Layout.Graph}) Pxui_graph.bindings in
  List.iter (fun (pressed, modifiers, expected) ->
    let input = Test_editor_input.frame ~keys:[] (500.,400.)
      (List.map key modifiers @ [key pressed]) 1 in
    let route focus = let _, actions, _ = Editor_core.Router.step table ~focus
      ~text_focus:false ~frame:input Idle in List.map (fun (c : _ Command.t) -> c.action) actions in
    check (route Pxui_shell.Layout.Graph = [expected]) "Flow grammar key routed the wrong action";
    check (route Pxui_shell.Layout.View = [] && route Pxui_shell.Layout.Inspector = [])
      "a Flow grammar key escaped graph scope")
    Pxui_graph.[Input.KeyChar 'h', [], Walk Left; Input.ArrowLeft, [], Walk Left;
      Input.KeyChar 'j', [], Walk Down; Input.ArrowDown, [], Walk Down;
      Input.KeyChar 'k', [], Walk Up; Input.ArrowUp, [], Walk Up;
      Input.KeyChar 'l', [], Walk Right; Input.ArrowRight, [], Walk Right;
      Input.Tab, [], Add; Input.KeyChar '.', [], Repeat; Input.KeyChar 'c', [], Connect_hint;
      Input.KeyChar 'v', [], Display; Input.KeyChar 'm', [], Mute;
      Input.KeyChar 's', [], Row_pin;
      Input.KeyChar 'x', [], Delete; Input.Delete, [], Delete; Input.Backspace, [], Delete;
      Input.KeyChar 'x', [Input.Shift], Dissolve; Input.KeyChar '/', [], Find;
      Input.KeyChar 'f', [], Frame_selection];
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
      make ~scope:Pxui_shell.Layout.View ~id:"test.view"
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
  let graph = Procedural.Sop.box ~size:(Vec3.create 1. 1. 1.) () in
  let module E3 = Prismel_editor.Editor3 in
  exercise ~name:"Editor3"
    ~create:(fun commands -> E3.create ~graph ~commands ~settings:(Settings.make schema 0)
      ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ _ -> Scene3.empty) ())
    ~update:E3.update ~close:E3.close ~settings:E3.settings ~set_settings:E3.set_settings;
  let module E2 = Prismel_editor.Editor2 in
  exercise ~name:"Editor2"
    ~create:(fun commands -> E2.create ~graph ~commands ~settings:(Settings.make schema 0)
      ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ _ -> []) ())
    ~update:E2.update ~close:E2.close ~settings:E2.settings ~set_settings:E2.set_settings;
  let directory = Filename.temp_dir "prismel-guide" "" in
  let filename = Filename.concat directory "preferences.json" in
  let previous = Sys.getenv_opt "PRISMEL_EDITOR_PREFERENCES" in
  Unix.putenv "PRISMEL_EDITOR_PREFERENCES" filename;
  let create () = E2.create ~graph ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ _ -> []) ()
    |> Result.get_ok in
  let current = ref (create ()) in
  Fun.protect ~finally:(fun () ->
    E2.close !current;
    Unix.putenv "PRISMEL_EDITOR_PREFERENCES" (Option.value ~default:"" previous);
    Array.iter (fun file -> Sys.remove (Filename.concat directory file)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    let step events count = current := E2.update !current
      (Test_editor_input.frame (100.,300.) events count) in
    let enabled () = Editor_core.Store.Settings.load ~sketch:"prismel-editor" filename
      |> Result.get_ok |> fun values -> Editor_core.Store.Settings.bool values "guide" in
    step [] 0; step [char '?'] 1;
    check (enabled () = Some false) "guide did not default on and persist off";
    check (not (E2.can_undo !current)) "guide preference entered document history";
    E2.close !current; current := create (); step [] 2; step [char '?'] 3;
    check (enabled () = Some true) "a new host did not load the saved guide preference";
    (* A sheet owns input until shared modal dismissal, then shortcuts resume. *)
    step [key Input.Space; char 'k'] 4; step [char '?'] 5;
    check (enabled () = Some true) "guide key escaped the key-sheet modal";
    step [key Input.Escape] 6; step [char '?'] 7;
    check (enabled () = Some false) "key-sheet dismissal kept keyboard focus";
    (* Toggle preserves unrelated preferences, and Hide follows the same save path. *)
    Editor_core.Store.Settings.save ~sketch:"prismel-editor" filename
      ["guide", Bool false; "other", Int 7] |> Result.get_ok;
    step [key Input.Shift; char '/'; Event.KeyReleased Input.Shift] 8;
    let point = (500.,500.) in
    step [Event.MousePressed (Input.LeftButton, point);
      Event.MouseReleased (Input.LeftButton, point)] 9;
    let x,y,w,h = (E2.panes !current (Test_editor_input.frame (100.,300.) [] 9)).status in
    let hide = float (x+w-21), float (y+h/2) in
    current := E2.update !current (Test_editor_input.frame hide [Event.MouseMoved hide] 10);
    current := E2.update !current (Test_editor_input.frame hide
      [Event.MousePressed (Input.LeftButton, hide); Event.MouseReleased (Input.LeftButton, hide)] 11);
    let values = Editor_core.Store.Settings.load ~sketch:"prismel-editor" filename |> Result.get_ok in
    check (Editor_core.Store.Settings.bool values "guide" = Some false
      && Editor_core.Store.Settings.int values "other" = Some 7)
      "Hide did not save off or discarded another preference";
    let contents = "invalid saved preferences" in
    Out_channel.with_open_bin filename (fun out -> output_string out contents);
    step [char '?'] 12;
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
    step [key Input.Ctrl; char 'c'; Event.KeyReleased Input.Ctrl] 13;
    E2.crash_dump !current directory;
    check (contains (dump ()) "key hud: Ctrl-c · copy\n")
      "key HUD displayed a different alias from the routed chord";
    step [] 200; E2.crash_dump !current directory;
    check (contains (dump ()) "key hud: -\n") "key HUD outlived 1.5 seconds");
  print_endline "editor commands: both hosts reject ambiguity and share alias/scoped keyboard/palette actions"
