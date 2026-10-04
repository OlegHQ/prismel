(* W3: the v4 document (text, layout by path, settings), presets as
   s-expressions, and the editor opened on a workspace: history labels, one
   entry per gesture, live `t` recooked and static nodes cached. *)
open Prismel
open Flow_sop
module E = Flow_edit
module S = Flow.Syntax
module Doc = Editor_document.Workspace_doc
module Layout = Editor_document.Layout_by_path
module Preset = Editor_document.Preset
module Document = Editor_document.Document

let fail message = failwith ("test_workspace_doc: " ^ message)
let check condition message = if not condition then fail message
let factories = Sop_catalog.Editor.factories
let catalog = Editor_document.Contexts.catalog ~version:1 factories |> Result.get_ok
let show ds = String.concat "; " (List.map Flow.Diagnostic.to_string ds)

let has text sub =
  let n = String.length sub in
  let rec at i = i + n <= String.length text && (String.sub text i n = sub || at (i + 1)) in
  at 0

let schema = Editor_core.Param.(schema ~name:"doc-settings" ~default:(0., "a")
  [ field ~name:"amount" ~label:"Amount" ~kind:(floating ~min:0. ~max:10. ()) ~default:0.
      ~get:fst ~set:(fun amount (_, mode) -> amount, mode) ();
    field ~name:"mode" ~label:"Mode" ~kind:Text ~default:"a"
      ~get:snd ~set:(fun mode (amount, _) -> amount, mode) () ])
let settings (amount, mode) = Editor_document.Settings.make schema (amount, mode)

let still = {|; a small study
(workspace study
  (graph g :context sop [(n : int 3)]
    (let* [a (sop/uv_sphere :radius 0.5)
           ; moved right
           b (sop/transform a :translate [1 0 0])]
      b)))
|}

let moving = {|(workspace moving
  (graph g :context sop
    (let* [a (sop/uv_sphere :radius 0.5)
           b (sop/transform a :translate [(sin t) 0 0])]
      b)))
|}

let of_text ?settings text = match Doc.of_text ?settings catalog text with
  | Ok doc -> doc
  | Error ds -> fail (show ds)

let part_text () =
  let text = still ^ {|
(layout
  (node ["g" "a"] :at [120 40] :pinned true :collapsed false :rows {:radius false})
  (node ["g" "b"] :at [300.5 40])
  (bend ["g" "b"] "in0" [12 24] [30 40])
  (wireless ["g" "b"] "in0")
  (frame ["g"] "Legs" :at [0 0] :size [200 100]))

(settings :amount 2.5 :mode "b")
|} in
  let doc = of_text ~settings:(settings (0., "a")) text in
  check (Doc.name doc = "study") "name";
  check (Layout.Path_map.find [ "g"; "a" ] doc.layout.at = (120., 40.)) "layout at";
  check (Layout.Path_map.find [ "g"; "b" ] doc.layout.at = (300.5, 40.)) "layout float";
  check (Layout.Port_map.find ([ "g"; "b" ], "in0") doc.layout.bends = [ (12., 24.); (30., 40.) ]) "bends";
  check (Layout.Port_set.mem ([ "g"; "b" ], "in0") doc.layout.wireless) "wireless";
  check ((List.hd (Layout.Path_map.find [ "g" ] doc.layout.frames)).title = "Legs") "frames";
  check (Editor_document.Settings.get schema doc.settings = (2.5, "b")) "settings read";
  let out = Doc.to_text doc in
  check (has out "; a small study" && has out "; moved right") "comments survive to_text";
  let again = of_text ~settings:(settings (0., "a")) out in
  check (Doc.to_text again = out) "to_text is a fixed point";
  check (again.layout = doc.layout) "layout round trip";
  (* a default setting is not written *)
  let plain = of_text ~settings:(settings (0., "a")) still in
  check (not (has (Doc.to_text plain) "settings") && not (has (Doc.to_text plain) "layout")) "empty layout and defaults are omitted";
  (* errors *)
  let bad text code = match Doc.of_text ~settings:(settings (0., "a")) catalog text with
    | Error ds -> check (List.exists (fun (d : Flow.Diagnostic.t) -> d.code = code) ds) (code ^ ": " ^ show ds)
    | Ok _ -> fail ("accepted: " ^ code) in
  bad (still ^ "(layout (nope))") "E_LAYOUT";
  bad (still ^ "(layout (node [\"g\"] :at [1]))") "E_LAYOUT";
  bad (still ^ "(settings :nope 1)") "E_SETTINGS";
  bad (still ^ "(settings :amount \"x\")") "E_SETTINGS";
  bad "(workspace w (graph g :context sop (sop/uv_sphere :nope 1)))" "E_UNKNOWN_PARAM";
  bad "(nothing)" "E_WORKSPACE"

let part_edit () =
  let text = still ^ {|
(layout
  (node ["g" "a"] :at [120 40])
  (node ["g" "b"] :at [300 40]))
|} in
  let doc = of_text text in
  let renamed = match Doc.edit catalog doc (E.Rename { node = [ "g"; "a" ]; to_ = "ball" }) with
    | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
  check (Layout.Path_map.mem [ "g"; "ball" ] renamed.layout.at && not (Layout.Path_map.mem [ "g"; "a" ] renamed.layout.at))
    "rename rewrites layout keys in the same transaction";
  check (Layout.Path_map.mem [ "g"; "b" ] renamed.layout.at) "other layout keys stay";
  check (has (Doc.to_text renamed) "(sop/transform ball") "rename rewrites the source";
  check (renamed.checked.name = "study") "re-checked";
  (* atomic: a refused edit leaves the document as it was *)
  (match Doc.edit catalog doc (E.Rename { node = [ "g"; "a" ]; to_ = "b" }) with
   | Error _ -> ()
   | Ok _ -> fail "accepted a clashing rename");
  (match Doc.edit catalog doc (E.Set_arg { node = [ "g"; "a" ]; key = Kw "nope"; sub = []; value = S.make (S.Num "1") }) with
   | Error _ -> ()
   | Ok _ -> fail "accepted an unknown keyword");
  check (Doc.to_text doc = Doc.to_text (of_text text)) "the original document is untouched";
  let deleted = match Doc.edit catalog (of_text (still ^ "(layout (node [\"g\" \"a\"] :at [1 2]) (node [\"g\" \"b\"] :at [3 4]))"))
      (E.Add_node { scope = [ "g" ]; name = "spare"; expr = S.make (S.Num "1") }) with
    | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
  (match Doc.edit catalog deleted (E.Delete_nodes { nodes = [ [ "g"; "spare" ] ] }) with
   | Ok d -> check (Layout.Path_map.cardinal d.layout.at = 2) "delete keeps other keys"
   | Error d -> fail (Flow.Diagnostic.to_string d))

let frame ?(keys = []) events count = Test_editor_input.frame ~keys (450., 320.) events count
let key k = Event.KeyPressed k
let char c = key (Input.KeyChar c)

let editor ?presets text =
  let workspace = of_text text in
  Prismel_editor.Editor3.create ~await:true ~workspace ?presets
    ~prepare:(fun _ output -> Ok output.Procedural.Session.geometry)
    ~scene3:(fun _ _ -> Scene3.create []) () |> function
  | Ok e -> e | Error m -> fail m

let first_x geometry =
  let view = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  view.x.(0)

(* update frames until [ok] holds: the editor awaits each frame's cook, so a bounded number of
   frames, not a wait on the clock *)
let settle ?(from = 0) e ok =
  let rec go count e =
    let e = Prismel_editor.Editor3.update e (frame [] count) in
    if ok e then e, count
    else if count > from + 200 then fail "the editor did not settle"
    else go (count + 1) e in
  go from e

let part_editor () =
  let module E3 = Prismel_editor.Editor3 in
  let e = editor still in
  let objects e = List.map (fun (i : Procedural.Edit_graph.node_info) -> i.label, i.operation)
    (Procedural.Edit_graph.inspect (E3.document e)) in
  check (List.mem ("g", "geometry") (objects e)) "one geometry object per sop graph";
  let e, count = settle e (fun e -> E3.prepared e <> None) in
  let before = Option.get (E3.prepared e) in
  (* static: idle frames keep the cooked value (no recook) *)
  let e, count = settle ~from:count e (fun _ -> true) in
  let e, count = List.fold_left (fun (e, c) _ -> E3.update e (frame [] c), c + 1) (e, count) (List.init 20 Fun.id) in
  check (E3.prepared e == Some before || Option.get (E3.prepared e) == before) "static nodes stay cached";
  check (E3.undo_label e = None) "no edit yet";
  (* one gesture is one history entry, named by the op *)
  let scrub v = E.Set_arg { node = [ "g"; "a" ]; key = Kw "radius"; sub = []; value = S.make (S.Num v) } in
  let e = E3.edit e (scrub "0.6") |> Result.get_ok in
  let e = E3.edit e (scrub "0.7") |> Result.get_ok in
  check (E3.undo_label e = Some "Edit value") "scrub label";
  check (has (Doc.to_text (E3.workspace e)) ":radius 0.7") "scrub rewrote the source";
  let e = E3.edit e (E.Rename { node = [ "g"; "b" ]; to_ = "moved" }) |> Result.get_ok in
  check (E3.undo_label e = Some "Rename") "rename label";
  let e = E3.edit e (E.Wrap { nodes = [ [ "g"; "a" ] ]; loop = For }) |> Result.get_ok in
  check (E3.undo_label e = Some "Repeat") "repeat label";
  check (match E3.edit e (E.Rename { node = [ "g"; "a" ]; to_ = "moved" }) with Error _ -> true | Ok _ -> false)
    "a refused edit is an error";
  check (E3.undo_label e = Some "Repeat") "a refused edit records nothing";
  let e, count = settle ~from:(count + 1) e (fun e ->
    match E3.prepared e with Some g -> Pdk.Geometry.point_count g > Pdk.Geometry.point_count before | None -> false) in
  (* undo steps back through the labelled entries *)
  let undo e c = E3.update e (frame ~keys:[ Input.Meta ] [ char 'z' ] c) in
  let e = undo e count in
  check (E3.undo_label e = Some "Rename" && E3.redo_label e = Some "Repeat")
    (Printf.sprintf "undo Repeat: undo=%s redo=%s" (Option.value ~default:"-" (E3.undo_label e))
       (Option.value ~default:"-" (E3.redo_label e)));
  let e = undo e (count + 1) in
  check (E3.undo_label e = Some "Edit value" && E3.redo_label e = Some "Rename") "undo Rename";
  let e = undo e (count + 2) in
  check (E3.undo_label e = None && E3.redo_label e = Some "Edit value") "one undo reverts the merged scrub";
  check (Doc.to_text (E3.workspace e) = Doc.to_text (of_text still)) "undo restored the source";
  let e = E3.update e (frame ~keys:[ Input.Meta; Input.Shift ] [ char 'z' ] (count + 3)) in
  check (E3.undo_label e = Some "Edit value") "redo";
  E3.close e

let part_live () =
  let module E3 = Prismel_editor.Editor3 in
  let e = editor moving in
  let e, count = settle e (fun e -> E3.prepared e <> None) in
  let xs = ref [] in
  let e = ref e and count = ref count in
  while List.length (List.sort_uniq compare !xs) < 4 && !count < 400 do
    e := E3.update !e (frame [] !count);
    incr count;
    Option.iter (fun g -> xs := first_x g :: !xs) (E3.prepared !e)
  done;
  check (List.length (List.sort_uniq compare !xs) >= 4) "a time-driven workspace animates in the editor";
  E3.close !e

let part_preset () =
  let module E3 = Prismel_editor.Editor3 in
  let directory = Filename.temp_dir "prismel-workspace-presets" "" in
  Fun.protect ~finally:(fun () ->
    let state = Filename.concat directory "state" in
    if Sys.file_exists state then begin
      Array.iter (fun name -> Sys.remove (Filename.concat state name)) (Sys.readdir state);
      Unix.rmdir state
    end;
    Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    let e = editor ~presets:directory still in
    let e, count = settle e (fun e -> E3.prepared e <> None) in
    let e = E3.edit e (E.Set_note { node = [ "g"; "a" ]; text = "kept" }) |> Result.get_ok in
    let e = E3.update e (frame [ key Input.Space; char 's' ] (count + 1)) in
    let e = E3.update e (frame [ key Input.Enter ] (count + 2)) in
    let name = match Preset.list ~directory with [ (name, _) ] -> name | _ -> fail "Space s did not save one preset" in
    let path = Preset.path ~directory ~name in
    check (Filename.check_suffix path ".plisp" && Sys.file_exists path) "Space s saved a .plisp";
    let text = In_channel.with_open_bin path In_channel.input_all in
    check (has text "(workspace study" && has text "; kept" && has text "(view") "the preset is s-expressions with its comments";
    check (not (has text "{\"") && not (has text "\"version\"")) "no JSON";
    (* it loads: same source, same comments *)
    let loaded = Preset.load ~path ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
    let ws = fst (loaded.doc.workspace) in
    check (Doc.to_text ws = Doc.to_text (E3.workspace e)) "save then load round trip";
    check (Preset.list ~directory |> List.map fst = [ name ]) "listed";
    (* load through Space b: one undo entry *)
    let e = E3.edit e (E.Rename { node = [ "g"; "a" ]; to_ = "ball" }) |> Result.get_ok in
    let e = E3.update e (frame [ key Input.Space; char 'b' ] (count + 3)) in
    let e = E3.update e (frame [ Event.TextInput name; key Input.Enter ] (count + 4)) in
    let e = E3.update e (frame [] (count + 5)) in
    check (has (Doc.to_text (E3.workspace e)) "(sop/transform a ") "Space b restored the saved source";
    check (E3.undo_label e = Some "Load preset") "load is one undo entry";
    (* errors never touch the document *)
    let corrupt = Preset.path ~directory ~name:"corrupt" in
    Out_channel.with_open_text corrupt (fun c -> output_string c "(workspace");
    check (Result.is_error (Preset.load ~path:corrupt ~factories ~settings:Editor_document.Settings.none)) "corrupt text is an error";
    check (Result.is_error (Preset.save ~directory ~name:"x" ~doc:loaded.doc ~view:Flow.Syntax.(make (Map [ make (Kw "zoom"); make (Num "inf") ]))))
      "a nonfinite view is refused";
    check (Result.is_error (Preset.save ~directory ~name:"" ~doc:loaded.doc ~view:(Flow.Syntax.make (Flow.Syntax.Map [])))) "an empty name is refused";
    E3.close e)

(* the view round trips through s-expressions *)
let part_view () =
  let directory = Filename.temp_dir "prismel-workspace-view" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    let doc = match Editor_document.Contexts.of_workspace ~factories (of_text still) with
      | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
    let view = match Flow.Syntax.parse "{:eye [1.5 -2.0 3] :look_through true :name \"a \\\"b\\\"\"}" with
      | Ok [ v ] -> v | _ -> fail "view text" in
    let path = Preset.save ~directory ~name:"v" ~doc ~view |> Result.get_ok in
    let loaded = Preset.load ~path ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
    let print v = fst (Flow.Lisp.print [ v ]) in
    check (print loaded.view = print view) "view round trip")


(* W4: the editor's layout gestures edit the layout keys only. *)
let part_pane_layout () =
  let module M = Layout.Path_map in
  let doc = of_text still in
  let opened = Editor_document.Contexts.of_workspace ~factories doc |> function Ok d -> d | Error m -> fail (Flow.Diagnostic.to_string m) in
  let ws = fst (opened.workspace) in
  let ws = { ws with layout = { ws.layout with at = M.add [ "g"; "a" ] (40., 60.) ws.layout.at;
                                               collapsed = M.add [ "g"; "z" ] true ws.layout.collapsed } } in
  let again = of_text (Doc.to_text ws) in
  check (M.find [ "g"; "a" ] again.layout.at = (40., 60.) && M.mem [ "g"; "z" ] again.layout.collapsed)
    "moved items and collapsed zones round-trip through the s-expression"

(* W10: scene, world and settings graphs become the document's objects, World and settings *)
let case name = In_channel.with_open_bin
  (Filename.concat "../specification/workspace/cases" (name ^ ".lisp")) In_channel.input_all

let part_contexts () =
  let module Objects = Editor_document.Objects in
  let module Layers = Editor_document.Layers in
  let module Contexts = Editor_document.Contexts in
  let module Edit = Procedural.Edit_graph in
  let build ?previous ws = match Contexts.of_workspace ~factories ?previous ws with
    | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
  let bloom = of_text (case "bloom") in
  let doc = build bloom in
  let scene = Document.scene_graph doc in
  let infos = Edit.inspect scene in
  let ops op = List.filter (fun (i : Edit.node_info) -> i.operation = op) infos in
  let label (i : Edit.node_info) = i.label in
  check (List.map label (ops "geometry") = [ "flower"; "accent" ]) "the scene graph's geometry objects, by :name";
  check (List.length (ops "camera") = 1 && List.length (ops "light") = 1 && List.length (ops "world") = 1)
    "camera, light and World come from the workspace";
  check (Document.validate doc = Ok ()) "the document validates";
  let accent = (List.nth (ops "geometry") 1).node in
  (match Objects.geometry accent with
   | Some p -> check (p.translate_x = 2.2 && p.translate_z = -1.2 && p.scale_x = 0.55 && p.scale_y = 0.55
                      && p.rotate_y = 0.) "a vec3 keyword sets its three fields"
   | None -> fail "accent is not a geometry object");
  (match Objects.Camera.of_node (List.hd (ops "camera")).node with
   | Some (camera, _) -> check (Prismel.Camera.position camera = Prismel.Vec3.create 0.5 1.8 6.) "camera eye"
   | None -> fail "no camera");
  (match Objects.light (List.hd (ops "light")).node with
   | Some p -> check (p.intensity = 60. && p.translate_x = 4.) "light fields"
   | None -> fail "no light");
  check (doc.active_camera = Some (List.hd (ops "camera")).id) "the workspace's camera is the active one";
  (* each geometry object owns the lowered network of the sop graph it refers to *)
  let flower = (List.hd (ops "geometry")).id and accent_id = (List.nth (ops "geometry") 1).id in
  let network id = Option.get (Document.Int_map.find_opt id doc.networks) in
  check ((network flower).displayed <> None && (network accent_id).displayed <> None
         && (network flower).graph != (network accent_id).graph)
    "two refs of one graph with different inputs are two networks";
  (* the World: a node and its layer stack, bottom first *)
  let world_id = (List.hd (ops "world")).id in
  let world_node = (List.hd (ops "world")).node in
  check (Procedural.Node.label world_node = "Bloom study") "the World's name";
  (match Layers.to_world world_node (network world_id) with
   | Some w ->
       check (w.exposure = -0.5) "World exposure";
       check (match w.layers with
         | [ { layer = Prismel.World.Sky s; _ }; { layer = Prismel.World.Sun u; _ } ] ->
             s.turbidity = 3. && u.intensity = 1500.
         | _ -> false) "World layers, bottom first"
   | None -> fail "the World does not read");
  (* settings: the window the host opens *)
  let window = match Contexts.window bloom with Ok w -> w | Error d -> fail (Flow.Diagnostic.to_string d) in
  check (window = { Contexts.title = "Bloom study"; width = 1400; height = 800; fps = 60; seed = 42 })
    "settings graph: window title, size, fps (a macro call) and seed";
  (match Contexts.window (of_text (case "tree")) with
   | Ok w -> check (w.title = "Prismel" && w.fps = 60) "no settings graph: defaults"
   | Error d -> fail (Flow.Diagnostic.to_string d));
  check (List.exists (fun (f : Editor_core.Param.field_view) -> f.name = "title" && f.current = Text_value "Bloom study")
    (Editor_document.Settings.fields doc.settings)) "the settings graph is the document's settings";
  (* determinism, print/parse and preset round trips *)
  (* ids are fresh per build; everything else is a function of the source *)
  let shape (d : Document.t) =
    List.map (fun (i : Edit.node_info) -> i.operation, i.label, i.parameters) (Edit.inspect (Document.scene_graph d)),
    List.filter_map (fun (i : Edit.node_info) -> if i.operation <> "world" then None else
      Option.bind (Document.Int_map.find_opt i.id d.networks) (fun n -> Layers.to_world i.node n))
      (Edit.inspect (Document.scene_graph d)),
    Editor_document.Settings.fields d.settings in
  check (shape (build bloom) = shape doc) "the same source builds the same document twice";
  check (Document.dump (build ~previous:doc bloom) = Document.dump doc) "rebuilding over the previous document changes nothing";
  let again = of_text (Doc.to_text bloom) in
  check (Doc.to_text again = Doc.to_text bloom) "print and parse are a fixed point";
  check (shape (build again) = shape doc) "the printed text builds the same document";
  let directory = Filename.temp_dir "prismel-contexts" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    let path = Preset.save ~directory ~name:"bloom" ~doc ~view:(Flow.Syntax.make (Flow.Syntax.Map [])) |> Result.get_ok in
    let text = In_channel.with_open_bin path In_channel.input_all in
    check (not (has text "(settings :")) "settings owned by a graph are not written a second time";
    let loaded = Preset.load ~path ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
    check (shape loaded.doc = shape doc) "the preset round trips scene, World and settings");
  (* a Flow_edit on the scene graph rebuilds it; ids, and viewport edits of unmentioned fields, stay *)
  let edited = match Doc.edit catalog bloom (E.Set_arg { node = [ "scene"; "accent" ]; key = Kw "translate";
      sub = []; value = Flow.Syntax.make (S.Vec (List.map (fun n -> S.make (S.Num n)) [ "4"; "0"; "1" ])) }) with
    | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
  let doc2 = build ~previous:doc edited in
  let accent2 = List.nth (List.filter (fun (i : Edit.node_info) -> i.operation = "geometry")
    (Edit.inspect (Document.scene_graph doc2))) 1 in
  check (accent2.id = accent_id) "an edit keeps the object's id";
  check ((Option.get (Objects.geometry accent2.node)).translate_x = 4.) "the edit reaches the object";
  check (has (Doc.to_text edited) ":translate [4 0 1]") "the source carries the edit";
  (* negative lowering: computed arguments outside a schema bound, and a wrong result *)
  let settings_of body = of_text ("(workspace w (graph c :context settings [(f : int 60)] " ^ body ^ "))") in
  check (Result.is_ok (Contexts.window (settings_of "(settings/config :fps f)"))) "a settings graph with an input";
  (* a literal past a hard bound is a check error; a computed one is clamped like any write *)
  check ((Result.get_ok (Contexts.window (settings_of "(settings/config :fps (* f 100))"))).fps = 240)
    "a computed fps above the hard bound is clamped when lowered";
  check (match Contexts.of_workspace ~factories (of_text "(workspace w (graph x :context world (world/sky)))") with
    | Ok doc -> Objects.ids "world" (Document.scene_graph doc) = [] | Error _ -> false)
    "a world graph no scene/world references is no World";
  (* the implicit scene: without a scene graph, one geometry object per sop graph *)
  let plain = build (of_text still) in
  check (List.map label (List.filter (fun (i : Edit.node_info) -> i.operation = "geometry")
    (Edit.inspect (Document.scene_graph plain))) = [ "g" ]) "no scene graph: one object per sop graph";
  (* Variations: one garden object, the graph opened for a viewport *)
  let variations = build (of_text (case "variations")) in
  check (List.map label (Edit.inspect (Document.scene_graph variations))
         = [ "garden"; "garden (v1.1.1)"; "garden (v1.1.2)"; "garden (v1.1.3)" ]) "variations scene";
  (* the manifest kinds equal the runtime kinds *)
  let manifest, _ = Flow_sop.Manifest.generate ~extra:Contexts.descriptors factories |> Result.get_ok in
  let from_manifest, _ = Flow.Check.catalog_of_manifest manifest |> Result.get_ok in
  check (from_manifest.kinds = (Result.get_ok (Contexts.catalog ~version:from_manifest.version factories)).kinds)
    "the generated scene, world and settings kinds survive the manifest"

(* W10: the scene's objects and the World come from the workspace *)
let part_editor_contexts () =
  let module E3 = Prismel_editor.Editor3 in
  let e = ref (editor (case "bloom")) in
  let count = ref 0 in
  let step events = incr count; e := E3.update !e (frame events !count) in
  for _ = 1 to 10 do step [] done;
  let dump () =
    let directory = Filename.temp_dir "prismel-contexts-dump" "" in
    Fun.protect ~finally:(fun () ->
      Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
      Unix.rmdir directory) (fun () ->
      E3.crash_dump !e directory;
      In_channel.with_open_bin (Filename.concat directory "editor.txt") In_channel.input_all) in
  let objects () = List.map (fun (i : Procedural.Edit_graph.node_info) -> i.label, i.operation)
    (Procedural.Edit_graph.inspect (E3.document !e)) in
  check (List.mem ("accent", "geometry") (objects ()) && List.mem ("Bloom study", "world") (objects ()))
    "the editor opens the workspace's objects and World";
  check (List.length (List.filter (fun (_, op) -> op = "camera") (objects ())) = 1
         && List.length (List.filter (fun (_, op) -> op = "light") (objects ())) = 1)
    "a scene that declares a camera and a light gets no seeded ones";
  check (has (dump ()) "pane graph: scene\n") "the pane shows the scene graph at the scene level until an outline row or a named panel picks another";
  (* an edit on the scene graph reaches the objects, in one history entry *)
  let e' = E3.edit !e (E.Set_arg { node = [ "scene"; "accent" ]; key = Kw "scale"; sub = [];
    value = S.make (S.Vec (List.map (fun n -> S.make (S.Num n)) [ "1"; "1"; "1" ])) }) |> Result.get_ok in
  check (E3.undo_label e' = Some "Edit value") "one history entry";
  check (List.exists (fun (i : Procedural.Edit_graph.node_info) -> i.label = "accent"
    && (Option.get (Editor_document.Objects.geometry i.node)).scale_x = 1.) (Procedural.Edit_graph.inspect (E3.document e')))
    "the scene edit reached the object"

let run () = List.iter (fun f -> f ()) [ part_text; part_edit; part_view; part_editor; part_live; part_preset; part_pane_layout; part_contexts; part_editor_contexts ]
