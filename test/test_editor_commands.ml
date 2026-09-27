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
  let exercise ~name ~create ~update ~close ~settings ~set_settings =
    let set n env = set_settings env (Settings.make schema n) in
    let bump = set 3 in
    let make ?scope ?(id = "test.bump") trigger action =
      Command.make ~id ~label:"bump command" ~trigger ?scope action in
    let rejected commands message = match create commands with
      | Error reason -> check (String.length reason > 0) (name ^ ": empty command error")
      | Ok env -> close env; failwith (name ^ ": " ^ message) in
    rejected [make (Keymap.Leader "k") bump; make (Leader "j") (set 4)]
      "different actions sharing an id were accepted";
    rejected [make ~id:"edit.undo" (Leader "k") bump] "reserved id was accepted";
    rejected [make (Leader "s") bump] "built-in leader collision was accepted";
    rejected [make (Chord (Input.KeyChar 'Z', [Input.Meta])) bump]
      "built-in chord collision was accepted";
    rejected [make (Leader "k") bump; make ~id:"test.other" (Leader "K") (set 4)]
      "case-equivalent triggers were accepted";
    rejected [make (Leader "k") bump; make ~id:"test.other" (Leader "kk") (set 4)]
      "unreachable leader prefix was accepted";
    rejected [make (Chord (Input.Space, [])) bump] "unreachable Space chord was accepted";
    rejected [make (Leader "") bump] "empty leader was accepted";
    rejected [make (Chord (Input.KeyChar 'k', [Input.Shift])) bump;
      make ~id:"test.other" (Chord (Input.KeyChar 'k', [Input.Alt])) (set 4)]
      "equal-specificity overlapping chords were accepted";
    rejected [make (Chord (Input.KeyChar 'k', [Input.Enter])) bump]
      "non-modifier chord key was accepted";
    rejected [make ~id:"" (Leader "k") bump] "empty id was accepted";
    let commands = [make (Leader "K") bump; make (Leader "qq") bump;
      make ~id:"test.modifier" (Chord (Input.KeyChar 'm', [Input.Meta])) (set 30);
      make ~scope:Pxui_shell.Layout.View ~id:"test.view"
        (Chord (Input.KeyChar 'j', [])) (set 10);
      make ~scope:Pxui_shell.Layout.Graph ~id:"test.graph"
        (Chord (Input.KeyChar 'j', [])) (set 20)] in
    let current = ref (create commands |> Result.get_ok) and count = ref 0 in
    Fun.protect ~finally:(fun () -> close !current) (fun () ->
      let step ?(mouse = (100., 300.)) ?(keys = []) events =
        incr count;
        current := update !current (Test_editor_input.frame ~keys mouse events !count) in
      let value () = Settings.get schema (settings !current) in
      step []; step [key Input.Space; char 'k'];
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
      step [char 'j'];
      check (value () = 10) (name ^ ": view-scoped chord did not run");
      let point = 500., 500. in
      step ~mouse:point [Event.MousePressed (Input.LeftButton, point);
        Event.MouseReleased (Input.LeftButton, point)];
      step [char 'j'];
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
  print_endline "editor commands: both hosts reject ambiguity and share alias/scoped keyboard/palette actions"
