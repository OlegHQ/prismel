(* Cross-representation checks: authored text, derived state, saved state and the picture. *)
open Prismel
module D = Editor_document
module E = Prismel_editor.Editor3
module F = Flow_sop.Flow_edit
module S = Flow.Syntax

let check condition message = if not condition then failwith message
let factories = Sop_catalog.Editor.factories
let catalog = D.Contexts.catalog ~version:1 factories |> Result.get_ok
let parse text = match S.parse text with Ok [form] -> form | _ -> failwith text
let workspace ?settings text = D.Workspace_doc.of_text ?settings catalog text |> Result.get_ok
let build ?previous ws = D.Contexts.of_workspace ~factories ?previous ws |> Result.get_ok
let frame n = Test_editor_input.frame (450., 300.) [] n
let step e n = E.update e (frame n)
let create ?settings ?presets ?source ws = E.create ?settings ?presets ?source ~await:true ~workspace:ws
  ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
    |> Result.map_error Pdk.Error.to_string)
  ~scene3:(fun _ mesh -> Scene3.create [Scene3.mesh mesh]) () |> Result.get_ok

let with_dir f =
  let dir = Filename.temp_dir "prismel-consistency" "" in
  Fun.protect ~finally:(fun () -> Test_workspace_source.remove_tree dir) (fun () -> f dir)
let with_editor ws f = with_dir (fun presets ->
  let e = ref (create ~presets ws) in
  Fun.protect ~finally:(fun () -> E.close !e) (fun () -> e := step !e 1; f e))

let settings_schema = Editor_core.Param.(schema ~name:"consistency" ~default:(0., "default")
  [field ~name:"amount" ~label:"Amount" ~kind:(floating ~min:0. ~max:10. ()) ~default:0.
     ~get:fst ~set:(fun x (_, s) -> x, s) ();
   field ~name:"mode" ~label:"Mode" ~kind:Text ~default:"default"
     ~get:snd ~set:(fun s (x, _) -> x, s) ()])
let settings x = D.Settings.make settings_schema x
let plain = "(workspace consistency (graph g :context sop (sop/box)))"

let settings_authority () =
  let ws = workspace ~settings:(settings (0., "default")) (plain ^ "\n(settings :amount 3.0)") in
  with_editor ws (fun e ->
    check (Prismel_editor.Settings.get settings_schema (E.settings !e) = (3., "default"))
      "opening a checked workspace discarded its saved settings";
    e := E.set_settings !e (Prismel_editor.Settings.make settings_schema (7., "changed"));
    check (D.Settings.get settings_schema (E.workspace !e).settings = (7., "changed"))
      "set_settings left Workspace_doc.settings behind";
    e := E.edit !e (F.Set_graph {name = "g"; form = parse "(graph g :context sop (sop/box :size [2 2 2]))"}) |> Result.get_ok;
    check (D.Settings.get settings_schema (E.workspace !e).settings = (7., "changed"))
      "a graph edit rolled settings back")

let settings_rebuild () =
  let old = build (workspace ~settings:(settings (2., "old")) plain) in
  let edited = workspace ~settings:old.settings (plain ^ "\n(settings :amount 4.0)") in
  let doc = build ~previous:old edited in
  check (D.Settings.get settings_schema doc.settings = (4., "default"))
    "lowering preferred previous settings over explicit text or retained omitted fields";
  let ws = {edited with settings = settings (9., "explicit")} in
  check (D.Settings.get settings_schema (build ~previous:doc ws).settings = (9., "explicit"))
    "lowering ignored authored workspace settings"

let settings_presets () = with_dir (fun dir ->
  let doc = build (workspace ~settings:(settings (0., "default")) plain) in
  let path = D.Preset.save ~directory:dir ~name:"defaults" ~doc ~view:(parse "{}") |> Result.get_ok in
  let loaded = D.Preset.load ~path ~factories ~settings:(settings (8., "running")) |> Result.get_ok in
  check (D.Settings.get settings_schema loaded.doc.settings = (0., "default"))
    "loading a preset inherited current values for omitted default settings")

let settings_graph_writeback () =
  let ws = workspace "(workspace settings (graph config :context settings (settings/config :fps 60)))" in
  with_editor ws (fun e ->
    let schema = Editor_core.Param.(schema ~name:"fps" ~default:60
      [field ~name:"fps" ~label:"FPS" ~kind:(integer ~min:1 ~max:120 ()) ~default:60
        ~get:Fun.id ~set:(fun x _ -> x) ()]) in
    e := E.set_settings !e (Prismel_editor.Settings.make schema 90);
    let loaded = build (workspace (D.Workspace_doc.to_text (E.workspace !e))) in
    check (List.exists (fun (f : Editor_core.Param.field_view) ->
      f.name = "fps" && f.current = Int_value 90) (D.Settings.fields loaded.settings))
      "set_settings changed a graph-owned value without writing the settings graph")

let layers e =
  match Scene.Private.stage_native ~width:900 ~height:640 (E.scene e (frame 1)) with
  | Error m -> failwith m
  | Ok staged -> List.filter_map (function
      | Scene.Private.Scene3_layer s -> Some (Array.to_list s.entries |> List.map (fun entry ->
          entry.Scene_execution.draw.state.transform_uniforms, entry.draw.mesh.vertices))
      | _ -> None) staged.layers

let scene_text = {|(workspace picture
  (graph g :context sop (sop/box))
  (graph scene :context scene
    (let* [object (scene/geometry (ref g) :name "box")
           lamp (scene/light :intensity 1)] (scene/merge object lamp)))
  (graph editor :context editor (ui/workspace (ui/viewport (ref scene)))))|}

let scene_picture () = with_editor (workspace scene_text) (fun e ->
  let before = layers !e and prepared = E.prepared !e in
  e := E.edit !e (F.Set_arg {node = ["scene"; "object"]; key = Kw "translate"; sub = [];
    value = parse "[3 0 0]"}) |> Result.get_ok;
  e := step !e 2;
  check (E.prepared !e = prepared) "moving an object changed its SOP output";
  check (layers !e <> before) "a scene-only host edit left the picture stale";
  let after = layers !e in
  e := step !e 3;
  check (layers !e = after) "an idle frame changed the picture")

let preview_text = {|(workspace previews
  (graph g :context sop (sop/box))
  (graph scene :context scene [(lamp : float 1)]
    (let* [object (scene/geometry (ref g)) light (scene/light :intensity lamp)]
      (scene/merge object light)))
  (graph empty :context scene (scene/merge))
  (graph editor :context editor
    (let* [main (ui/viewport (ref scene))
           comparison (ui/viewport (ref scene :lamp 2))
           blank (ui/viewport (ref empty))]
      (ui/workspace (ui/tile main comparison blank)))))|}

let empty_preview () =
  let doc = build (workspace preview_text) in
  check (List.assoc_opt "v2" (Option.get doc.shell).views = Some [])
    "an empty scene instance lost its viewport identity";
  with_editor (workspace preview_text) (fun e ->
    check (List.map List.length (layers !e) = [1; 1; 0])
      "an empty preview rendered the primary scene")

let preview_lights () = with_editor (workspace preview_text) (fun e ->
  let before = layers !e in
  e := E.edit !e (F.Set_arg {node = ["editor"; "comparison"]; key = Pos 0; sub = [];
    value = parse "(ref scene :lamp 5)"}) |> Result.get_ok;
  e := step !e 2;
  let after = layers !e in
  check (List.hd after = List.hd before) "a comparison viewport changed the primary scene's lighting";
  check (List.nth after 1 <> List.nth before 1) "a comparison viewport did not update its own lighting")

let refuse_empty_2d () = with_dir (fun presets ->
  let module E2 = Prismel_editor.Editor2 in
  let e = E2.create ~presets ~workspace:(workspace plain) ~prepare:(fun _ _ -> Ok ())
    ~scene2:(fun _ _ -> []) () |> Result.get_ok in
  Fun.protect ~finally:(fun () -> E2.close e) (fun () ->
    check (Result.is_error (E2.edit e (F.Set_graph {name = "g"; form = parse "(graph g :context value 1)"})))
      "an edit removing the last 2D network was accepted"))

let document_forms () =
  List.iter (fun extra -> check (Result.is_error (D.Workspace_doc.of_text catalog (plain ^ extra)))
    ("a document silently discarded " ^ extra))
    ["\n(workspace other)"; "\n(settngs :amount 4)"; "\n(layout)\n(layout)"; "\n(settings)\n(settings)"];
  let layout = D.Layout_by_path.{empty with at = Path_map.singleton ["g"] (20., 30.)} in
  check ((D.Workspace_doc.of_text ~layout catalog plain |> Result.get_ok).layout = layout)
    "omitting layout discarded its fallback";
  check (D.Layout_by_path.is_empty
    (D.Workspace_doc.of_text ~layout catalog (plain ^ "\n(layout)") |> Result.get_ok).layout)
    "an explicit empty layout did not clear its fallback"

let lisp_apply () =
  let text = Test_text_pane.replace scene_text ~from:"(ui/viewport (ref scene))"
    ~by:"(ui/split \"horizontal\" (ui/lisp) (ui/viewport (ref scene)))" in
  let ws = workspace ~settings:(settings (3., "kept"))
    (text ^ "\n(layout (node [\"g\"] :at [24 48]))") in
  with_editor ws (fun e ->
    let geometry = Pxui_shell.Layout.geometry ~hidden:[Timeline] ~top:28
      (Option.get (build ws).shell).tree (frame 1) in
    let leaf = Pxui_shell.Layout.find geometry Lisp |> Option.get in
    let x, y, _, h = leaf.body and count = ref 1 in
    let run ?(mouse = (450., 300.)) ?(keys = []) events =
      incr count; e := E.update !e (Test_editor_input.frame ~keys mouse events !count) in
    let click p = run ~mouse:p [Event.MouseMoved p];
      run ~mouse:p [Event.MousePressed (Input.LeftButton, p); Event.MouseReleased (Input.LeftButton, p)] in
    click (float (x + 160), float (y + 12)); (* Document tab *)
    click (float (x + 180), float (y + 80));
    (* Applying the text already shown keeps metadata; a subsequent source reload sees it too. *)
    run ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'a')];
    run [Event.TextInput (Test_text_pane.replace (D.Workspace_doc.to_text ws)
      ~from:"(sop/box)" ~by:"(sop/box :size [2 2 2])")];
    let before = E.prepared !e and picture = layers !e in
    click (float (x + 60), float (y + h - 36));
    check (E.undo_label !e = Some "Edit text") "Lisp apply made no document edit";
    check (E.prepared !e <> before && layers !e <> picture)
      "Lisp applied after the frame's cook or composition";
    check ((E.workspace !e).layout = ws.layout
      && D.Settings.get settings_schema (E.workspace !e).settings = (3., "kept"))
      "Lisp apply lost layout or sketch settings")

let hidden_preview () = with_editor (workspace preview_text) (fun e ->
  (* Focus the authored empty preview, then hide the UI. The fullscreen image remains empty. *)
  let doc = build (workspace preview_text) in
  let geometry = Pxui_shell.Layout.geometry ~hidden:[Timeline] ~top:28
    (Option.get doc.shell).tree (frame 1) in
  let leaf = Pxui_shell.Layout.find geometry (View "v2") |> Option.get in
  let x, y, w, h = leaf.body in
  let p = float (x + w / 2), float (y + h / 2) in
  e := E.update !e (Test_editor_input.frame p
    [Event.MousePressed (Input.LeftButton, p); Event.MouseReleased (Input.LeftButton, p)] 2);
  e := E.update !e (Test_editor_input.frame p
    [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'h')] 3);
  check (List.map List.length (layers !e) = [0])
    "hiding the UI switched the focused preview to the primary scene")

let named_inspector () = with_dir (fun presets ->
  let factories = Test_editor_transactions.factory :: factories in
  let ws = Ws_fixture.of_text ~factories {|(workspace named
    (graph g :context sop (let* [a (sop/test_source :value 1)] a))
    (graph editor :context editor
      (ui/workspace (ui/split-at "horizontal" 0.6 (ui/graph "g") (ui/inspector)))))|} in
  let e = ref (E.create ~presets ~await:true ~workspace:ws ~factories ~prepare:(fun _ _ -> Ok ())
    ~scene3:(fun _ _ -> Scene3.empty) () |> Result.get_ok) in
  Fun.protect ~finally:(fun () -> E.close !e) (fun () ->
    e := step !e 1;
    let x, y, w, _ = E.node_box !e ["g"; "a"] |> Option.get in
    let p = float (x + w / 2), float (y + 10) in
    e := E.update !e (Test_editor_input.frame p
      [Event.MousePressed (Input.LeftButton, p); Event.MouseReleased (Input.LeftButton, p)] 2);
    e := step !e 3;
    check (E.level !e = None) "fixture left the scene level";
    let doc = D.Contexts.of_workspace ~factories (E.workspace !e) |> Result.get_ok in
    let tree = (Option.get doc.shell).tree in
    let leaf = Pxui_shell.Layout.find
      (Pxui_shell.Layout.geometry ~hidden:[Timeline] ~top:28 tree (frame 1)) Inspector |> Option.get in
    let ix, iy, iw, _ = leaf.body in
    let from = float ix +. max 96. (min 150. (float iw *. 0.34)) +. 10., float (iy + 190) in
    let to_ = fst from +. 50., snd from in
    e := E.update !e (Test_editor_input.frame ~buttons:[Input.LeftButton] from
      [Event.MousePressed (Input.LeftButton, from)] 4);
    e := E.update !e (Test_editor_input.frame ~buttons:[Input.LeftButton] to_
      [Event.MouseMoved to_] 5);
    e := E.update !e (Test_editor_input.frame to_ [Event.MouseReleased (Input.LeftButton, to_)] 6);
    check (E.undo_label !e = Some "Edit value")
      "a named SOP pane at the scene level had no editable inspector fields"))

let overlapping_renderers () =
  let ws = workspace {|(workspace overlap
    (graph g :context sop [(size : float 1)] (sop/box :size [size size size]))
    (graph scene :context scene [(size : float 1)] (scene/geometry (ref g :size size)))
    (graph editor :context editor
      (let* [main (ui/viewport (ref scene))
             one (ui/viewport (ref scene :size 2))
             two (ui/viewport (ref scene :size 3))]
        (ui/workspace (ui/tile main one two)))))
    (layout (panel ["editor" "one"] :window [150 120 320 280])
            (panel ["editor" "two"] :window [150 120 320 280]))|} in
  with_editor ws (fun e ->
    e := step (E.set_renderer !e Prismel_editor.Renderer.Wireframe) 2;
    let pictures = layers !e in
    check (List.length pictures = 3) "an overlapping viewport did not render";
    check (List.nth pictures 1 <> List.nth pictures 2)
      "coincident floating bounds made two renderers paint the same slot")

let run_native () = with_dir (fun directory ->
  let ws = workspace {|(workspace failures
    (graph g :context sop [(size : float 1)] (sop/box :size [size size size]))
    (graph scene :context scene [(size : float 1)] (scene/geometry (ref g :size size)))
    (graph editor :context editor
      (ui/workspace (ui/tile (ui/viewport (ref scene))
        (ui/viewport (ref scene :size 2)) (ui/viewport (ref scene :size 3))))))|} in
  let path = Filename.concat directory "failure.png" in
  ignore (Sketch.run_state ~max_frames:8
    ~config:{Sketch.default_config with width = 900; height = 640; domains = Some 1;
      title = "Preview failure isolation"}
    ~init:(fun _ -> E.create ~await:true ~workspace:ws
      ~presets:(Filename.concat directory "presets")
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh ->
        let size = abs_float (Option.get (Mesh.vertex 0 mesh)).Vec3.x *. 2. in
        if size > 2.5 then Scene3.create [Scene3.group []]
        else Scene3.create [Scene3.mesh ~material:(Material.unlit (Color.rgb 200 30 20))
          (if size > 1.5 then Mesh.with_mode Mesh.Lines mesh else mesh)]) () |> Result.get_ok)
    ~update:(fun e frame -> E.update (E.set_renderer e Prismel_editor.Renderer.Path_traced) frame)
    ~view:E.scene
    ~after_present:(fun e frame ->
      if frame.Frame.count = 8 then check (Canvas.save_screen_png path = Ok ()) "failure capture failed";
      E.after_present e frame)
    ~on_stop:E.close ());
  let image = Image.load_exn path in
  Fun.protect ~finally:(fun () -> Image.destroy image) (fun () ->
    let pixels = Image.Private.pixels image |> Result.get_ok in
    let red = ref 0 in
    for offset = 0 to Bytes.length pixels / 4 - 1 do
      let r = Char.code (Bytes.get pixels (offset * 4))
      and g = Char.code (Bytes.get pixels (offset * 4 + 1)) in
      if r > 110 && r > g + 40 then incr red
    done;
    check (!red > 30) "a failed comparison renderer blanked the healthy viewport"))

let run () =
  let failures = List.filter_map (fun (name, run) ->
    try run (); None with exn -> Some (name ^ ": " ^ Printexc.to_string exn))
    ["settings opening and edits", settings_authority; "settings lowering", settings_rebuild;
     "preset defaults", settings_presets; "settings graph writeback", settings_graph_writeback;
     "scene picture", scene_picture; "empty preview", empty_preview;
     "preview lighting", preview_lights; "2D edit refusal", refuse_empty_2d;
     "document forms", document_forms; "Lisp applies before rendering", lisp_apply;
     "fullscreen preview", hidden_preview; "named graph inspector", named_inspector;
     "overlapping renderers", overlapping_renderers] in
  if failures <> [] then failwith (String.concat "\n" failures);
  print_endline "editor consistency: settings, saved defaults, scene pictures, isolated previews and atomic 2D refusals passed"
