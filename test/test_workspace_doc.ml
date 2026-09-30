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
let catalog = Catalog.of_factories ~version:1 factories |> Result.get_ok
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
  Prismel_editor.Editor3.create ~workspace ?presets
    ~prepare:(fun _ output -> Ok output.Procedural.Session.geometry)
    ~scene3:(fun _ _ -> Scene3.create []) () |> function
  | Ok e -> e | Error m -> fail m

let first_x geometry =
  let view = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  view.x.(0)

(* update frames until [ok] holds *)
let settle ?(from = 0) e ok =
  let deadline = Unix.gettimeofday () +. 10. in
  let rec go count e =
    let e = Prismel_editor.Editor3.update e (frame [] count) in
    if ok e then e, count
    else if Unix.gettimeofday () > deadline then fail "the editor did not settle"
    else (Unix.sleepf 0.001; go (count + 1) e) in
  go from e

let part_editor () =
  let module E3 = Prismel_editor.Editor3 in
  let e = editor still in
  check (E3.workspace e <> None) "the editor opens a workspace";
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
  check (has (Doc.to_text (Option.get (E3.workspace e))) ":radius 0.7") "scrub rewrote the source";
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
  check (Doc.to_text (Option.get (E3.workspace e)) = Doc.to_text (of_text still)) "undo restored the source";
  let e = E3.update e (frame ~keys:[ Input.Meta; Input.Shift ] [ char 'z' ] (count + 3)) in
  check (E3.undo_label e = Some "Edit value") "redo";
  E3.close e

let part_live () =
  let module E3 = Prismel_editor.Editor3 in
  let e = editor moving in
  let e, count = settle e (fun e -> E3.prepared e <> None) in
  let xs = ref [] in
  let e = ref e and count = ref count in
  let deadline = Unix.gettimeofday () +. 10. in
  while List.length (List.sort_uniq compare !xs) < 4 && Unix.gettimeofday () < deadline do
    e := E3.update !e (frame [] !count);
    incr count;
    Option.iter (fun g -> xs := first_x g :: !xs) (E3.prepared !e);
    Unix.sleepf 0.002
  done;
  check (List.length (List.sort_uniq compare !xs) >= 4) "a time-driven workspace animates in the editor";
  E3.close !e

let part_preset () =
  let module E3 = Prismel_editor.Editor3 in
  let directory = Filename.temp_dir "prismel-workspace-presets" "" in
  Fun.protect ~finally:(fun () ->
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
    let ws = fst (Option.get loaded.doc.workspace) in
    check (Doc.to_text ws = Doc.to_text (Option.get (E3.workspace e))) "save then load round trip";
    check (Preset.list ~directory |> List.map fst = [ name ]) "listed";
    (* load through Space b: one undo entry *)
    let e = E3.edit e (E.Rename { node = [ "g"; "a" ]; to_ = "ball" }) |> Result.get_ok in
    let e = E3.update e (frame [ key Input.Space; char 'b' ] (count + 3)) in
    let e = E3.update e (frame [ Event.TextInput name; key Input.Enter ] (count + 4)) in
    let e = E3.update e (frame [] (count + 5)) in
    check (has (Doc.to_text (Option.get (E3.workspace e))) "(sop/transform a ") "Space b restored the saved source";
    check (E3.undo_label e = Some "Load preset") "load is one undo entry";
    (* errors never touch the document *)
    let corrupt = Preset.path ~directory ~name:"corrupt" in
    Out_channel.with_open_text corrupt (fun c -> output_string c "(workspace");
    check (Result.is_error (Preset.load ~path:corrupt ~factories ~settings:Editor_document.Settings.none)) "corrupt text is an error";
    check (Result.is_error (Preset.save ~directory ~name:"x" ~doc:loaded.doc ~view:(`Assoc [ "zoom", `Float infinity ])))
      "a nonfinite view is refused";
    check (Result.is_error (Preset.save ~directory ~name:"" ~doc:loaded.doc ~view:`Null)) "an empty name is refused";
    E3.close e)

(* the view round trips through s-expressions *)
let part_view () =
  let directory = Filename.temp_dir "prismel-workspace-view" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    let doc = match Document.of_workspace ~factories (of_text still) with
      | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
    let view = `Assoc [ "eye", `List [ `Float 1.5; `Float (-2.); `Int 3 ]; "look_through", `Bool true;
      "name", `String "a \"b\""; "none", `Null ] in
    let path = Preset.save ~directory ~name:"v" ~doc ~view |> Result.get_ok in
    let loaded = Preset.load ~path ~factories ~settings:Editor_document.Settings.none |> Result.get_ok in
    check (loaded.view = view) "view round trip")


(* W4: the editor's layout gestures edit the layout keys only. *)
let part_pane_layout () =
  let module M = Layout.Path_map in
  let doc = of_text still in
  let opened = Document.of_workspace ~factories doc |> function Ok d -> d | Error m -> fail (Flow.Diagnostic.to_string m) in
  let ws = fst (Option.get opened.workspace) in
  let ws = { ws with layout = { ws.layout with at = M.add [ "g"; "a" ] (40., 60.) ws.layout.at;
                                               collapsed = M.add [ "g"; "z" ] true ws.layout.collapsed } } in
  let again = of_text (Doc.to_text ws) in
  check (M.find [ "g"; "a" ] again.layout.at = (40., 60.) && M.mem [ "g"; "z" ] again.layout.collapsed)
    "moved items and collapsed zones round-trip through the s-expression"
let run () = List.iter (fun f -> f ()) [ part_text; part_edit; part_view; part_editor; part_live; part_preset; part_pane_layout ]
