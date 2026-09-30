(* Edits of the derived scene and World are edits of the text (plan W10): each kind of change
   (an object's field, an inline object, a rename, a reparent, a delete, the render camera, the
   World node, its layers, a preset, settings, and objects only the host made) goes through
   [Scene_sync.reconcile], and the text it leaves lowers to the same document (by labels). *)
open Prismel
open Procedural

module Document = Editor_document.Document
module Contexts = Editor_document.Contexts
module Objects = Editor_document.Objects
module Layers = Editor_document.Layers
module Workspace_doc = Editor_document.Workspace_doc
module Sync = Editor_document.Scene_sync

let check condition message = if not condition then failwith message
let factories = Sop_catalog.Editor.factories

let contains text piece =
  let n = String.length piece in
  let rec at i = i + n <= String.length text && (String.sub text i n = piece || at (i + 1)) in
  at 0

let text = {|(workspace sync
  (graph g :context sop (sop/box))
  (graph scene :context scene
    (let* [body (scene/geometry (ref g) :name "body")
           arm (scene/geometry (ref g) :name "arm" :translate [1 0 0])
           cam (scene/camera :name "cam" :eye [0 2 6])
           side (scene/camera :name "side" :eye [6 2 0])
           all (scene/merge body arm cam side (scene/light :name "fill"))]
      all))
  (graph world :context world
    (world/world (world/sun (world/sky :name "sky") :name "sun") :name "studio" :exposure 0.5))
  (graph settings :context settings (settings/config :title "t" :width 640)))|}

let lower ?previous workspace =
  match Contexts.of_workspace ~factories ?previous workspace with
  | Ok doc -> doc | Error d -> failwith (Flow.Diagnostic.to_string d)

let open_text text = lower (Ws_fixture.of_text text)
let scene (doc : Document.t) = Document.scene_graph doc
let node_id doc label = (List.find (fun (i : Edit_graph.node_info) -> i.label = label)
  (Edit_graph.inspect (scene doc))).id

(* a document as labels say it: ids are allowed to differ *)
let snapshot (doc : Document.t) =
  let graph = scene doc in
  let fields node = List.map (fun (f : Parameter.field_view) -> f.name, f.current) (Node.parameter_fields node) in
  let label g id = Option.map Node.label (Edit_graph.find g ~node_id:id) in
  let objects = List.sort compare (List.map (fun (i : Edit_graph.node_info) ->
    i.label, i.operation, Option.bind (Objects.parent graph i.id) (label graph), fields i.node)
    (Edit_graph.inspect graph)) in
  let layers = List.concat_map (fun wid ->
    match Document.Int_map.find_opt wid doc.networks with
    | None -> []
    | Some n ->
        let g = n.graph.geometry in
        let rec down id = match Edit_graph.find g ~node_id:id with
          | None -> []
          | Some node -> (Node.label node, Node.operation node, fields node)
              :: (match Edit_graph.inputs g ~node_id:id with
                  | Some [| Some below |] -> down below | _ -> []) in
        Option.fold ~none:[] ~some:down n.displayed) (Objects.ids "world" graph) in
  objects, layers, Option.bind doc.active_camera (label graph),
  List.map (fun (f : Parameter.field_view) -> f.name, f.current) (Editor_document.Settings.fields doc.settings)
  |> List.sort compare

let source (doc : Document.t) = Workspace_doc.to_text (fst doc.workspace)

(* the text of [doc], opened again, says the same *)
let same_after_reload doc what =
  check (snapshot (open_text (source doc)) = snapshot doc) (what ^ ": the saved text is not the document")

let with_scene (doc : Document.t) graph =
  { doc with scene = { doc.scene with graph = Result.get_ok (Flow_sop.Network.with_geometry graph doc.scene.graph) } }

let set doc label values =
  with_scene doc (fst (Result.get_ok (Edit_graph.apply_parameters (scene doc) ~node_id:(node_id doc label) values)))

let reconcile ?adopt before after =
  Sync.reconcile ~factories ?adopt before after

let calls = ref 0
let ok = function Ok doc -> incr calls; doc | Error message -> failwith (Printf.sprintf "reconcile #%d: %s" !calls message)
let float name x = name, Parameter.Float_value x

let world_network (doc : Document.t) =
  let wid = List.hd (Objects.ids "world" (scene doc)) in
  wid, Document.Int_map.find wid doc.networks

let with_world_network (doc : Document.t) wid (network : Document.network) graph =
  Document.with_network doc (Document.Inside wid)
    { network with graph = Result.get_ok (Flow_sop.Network.with_geometry graph network.graph) }

let layer_id doc label =
  let _, n = world_network doc in
  (List.find (fun (i : Edit_graph.node_info) -> i.label = label) (Edit_graph.inspect n.graph.geometry)).id

let run () =
  let doc = open_text text in
  let arm = node_id doc "arm" and fill = node_id doc "fill" in
  (* a field of a bound object *)
  let edited = ok (reconcile doc (set doc "arm" [ float "translate_x" 4.; float "translate_y" 2. ])) in
  check (contains (source edited) ":translate [4.0 2.0 0.0]") "a transform edit did not reach the text";
  check (node_id edited "arm" = arm) "an edit changed an object's id";
  check (snd edited.workspace != snd doc.workspace) "the edited text was not lowered again";
  same_after_reload edited "transform";
  (* an inline object is unfolded into a binding first *)
  let edited = ok (reconcile doc (set doc "fill" [ float "intensity" 99. ])) in
  check (contains (source edited) ":intensity 99.0") "an inline object's edit did not reach the text";
  check (node_id edited "fill" = fill) "an inline object lost its id when unfolded";
  check (List.exists (fun (_, h) -> match h with Document.Bound_at _ -> true | _ -> false)
           (List.filter (fun (id, _) -> id = fill) edited.homes.objects)) "the unfolded object has no binding";
  same_after_reload edited "inline object";
  (* rename keeps the id, and the children's parent names follow *)
  let renamed = with_scene doc (Edit_graph.replace_node
    (Node.relabel "forearm" (Option.get (Edit_graph.find (scene doc) ~node_id:arm))) (scene doc) |> Result.get_ok) in
  let edited = ok (reconcile doc renamed) in
  check (contains (source edited) ":name \"forearm\"" && node_id edited "forearm" = arm) "a rename did not keep the id";
  same_after_reload edited "rename";
  (* reparent keeping the world placement, rename the parent, then unparent *)
  let body = node_id doc "body" in
  let under = with_scene doc (Edit_graph.connect ~source:body ~consumer:arm ~input_index:0 (scene doc) |> Result.get_ok) in
  let edited = ok (reconcile doc under) in
  check (contains (source edited) ":parent \"body\"") "a reparent did not reach the text";
  same_after_reload edited "reparent";
  let torso = with_scene edited (Edit_graph.replace_node
    (Node.relabel "torso" (Option.get (Edit_graph.find (scene edited) ~node_id:body))) (scene edited) |> Result.get_ok) in
  let edited' = ok (reconcile edited torso) in
  check (contains (source edited') ":parent \"torso\"" && not (contains (source edited') ":parent \"body\""))
    "renaming a parent left its child pointing at the old name";
  same_after_reload edited' "parent rename";
  let free = with_scene edited (Edit_graph.disconnect ~consumer:arm ~input_index:0 (scene edited) |> Result.get_ok) in
  let edited' = ok (reconcile edited free) in
  check (not (contains (source edited') ":parent")) "unparenting left the parent keyword";
  same_after_reload edited' "unparent";
  (* delete: a bound object leaves its binding and the merge; an inline one leaves the merge *)
  let gone = with_scene doc (Edit_graph.remove_nodes [ arm; fill ] (scene doc)) in
  let edited = ok (reconcile doc gone) in
  check (not (contains (source edited) "\"arm\"") && not (contains (source edited) "\"fill\""))
    "a deleted object stayed in the text";
  check (contains (source edited) "scene/merge body cam side") "a deleted object stayed in the merge";
  same_after_reload edited "delete";
  (* the render camera *)
  let side = node_id doc "side" in
  let edited = ok (reconcile doc { doc with active_camera = Some side }) in
  check (contains (source edited) ":active true" && edited.active_camera = Some side) "the render camera did not reach the text";
  let reopened = open_text (source edited) in
  check (reopened.active_camera = Some (node_id reopened "side")) "the render camera did not survive a reload";
  (* the World node, a layer of an inline stack, a layer rename *)
  let wid, network = world_network doc in
  let sun = layer_id doc "sun" in
  let world_node graph values = fst (Result.get_ok (Edit_graph.apply_parameters graph ~node_id:wid values)) in
  let edited = ok (reconcile doc (with_scene doc (world_node (scene doc) [ float "exposure" (-1.) ]))) in
  check (contains (source edited) ":exposure -1.0") "a World node edit did not reach the text";
  same_after_reload edited "world node";
  let layer_edit doc id values =
    let wid, n = world_network doc in
    with_world_network doc wid n (fst (Result.get_ok (Edit_graph.apply_parameters n.graph.geometry ~node_id:id values))) in
  let edited = ok (reconcile doc (layer_edit doc sun [ float "intensity" 321. ])) in
  check (contains (source edited) ":intensity 321.0") "a World layer edit did not reach the text";
  check (layer_id edited "sun" = sun) "a World layer edit changed its id";
  same_after_reload edited "world layer";
  (* drag a layer (azimuth, elevation) then undo-like: the document before is untouched *)
  check (snapshot doc = snapshot (open_text text)) "reconcile changed its input";
  (* delete a layer: the stack closes over it *)
  let removed = with_world_network doc wid network (Edit_graph.remove_nodes [ sun ] network.graph.geometry) in
  let edited = ok (reconcile doc removed) in
  check (not (contains (source edited) "world/sun")) "a deleted World layer stayed in the text";
  same_after_reload edited "world layer delete";
  (* reorder the stack: sky above sun *)
  let sky = layer_id doc "sky" in
  let g = network.graph.geometry in
  let swapped = Edit_graph.disconnect ~consumer:sun ~input_index:0 g |> Result.get_ok
    |> Edit_graph.connect ~source:sun ~consumer:sky ~input_index:0 |> Result.get_ok in
  let swapped = Document.with_network doc (Document.Inside wid)
    { network with graph = Result.get_ok (Flow_sop.Network.with_geometry swapped network.graph);
                   displayed = Some sky } in
  let edited = ok (reconcile doc swapped) in
  same_after_reload edited "world restack";
  check (List.map (fun (l, _, _) -> l) (let _, layers, _, _ = snapshot edited in layers) = [ "sky"; "sun" ])
    "the World stack was not rewritten";
  (* a preset replaces the layers: the World graph is written whole *)
  let world = List.assoc "white room" World.presets in
  let preset_network = Result.get_ok (Layers.network_of_world world) in
  let values = snd (Layers.of_world world) in
  let preset = with_scene (Document.with_network doc (Document.Inside wid) preset_network)
      (world_node (scene doc) values) in
  let edited = ok (reconcile doc preset) in
  check (contains (source edited) "world/room") "a World preset did not reach the text";
  same_after_reload edited "world preset";
  (* deleting the World: its graph stays and says none (a removed graph would be seeded again) *)
  let worldless = Document.prune (with_scene doc (Edit_graph.remove_nodes [ wid ] (scene doc))) in
  let edited = ok (reconcile doc worldless) in
  check (contains (source edited) "world/none" && Objects.ids "world" (scene edited) = [])
    "a deleted World was not written as none";
  same_after_reload edited "world delete";
  check (Objects.ids "world" (scene (open_text (source edited))) = []) "a deleted World came back on reload";
  (* settings graph *)
  let settings = fst (Result.get_ok (Editor_document.Settings.apply doc.settings [ "width", Parameter.Int_value 800 ])) in
  let edited = ok (reconcile doc { doc with settings }) in
  check (contains (source edited) ":width 800") "a settings edit did not reach the text";
  same_after_reload edited "settings";
  (* a name two objects share is refused whole *)
  let twins = open_text {|(workspace twins
    (graph scene :context scene
      (scene/merge (scene/light :name "a") (scene/light :name "a") (scene/light :name "b"))))|} in
  let b = node_id twins "b" in
  let first = (List.hd (List.filter (fun (i : Edit_graph.node_info) -> i.label = "a") (Edit_graph.inspect (scene twins)))).id in
  (match reconcile twins (with_scene twins (Edit_graph.connect ~source:first ~consumer:b ~input_index:0 (scene twins) |> Result.get_ok)) with
   | Error _ -> ()
   | Ok _ -> failwith "a parent named like another object was written");
  (* objects only the host made: the first explicit edit writes them *)
  let bare = open_text "(workspace bare (graph g :context sop (sop/box)))" in
  let with_light (doc : Document.t) =
    let node = Result.get_ok (Edit_graph.instantiate_optional Objects.Light.factory [ None ]) in
    let node = Node.relabel "light1" node in
    let graph = Result.get_ok (Edit_graph.add_node ~factory:Objects.Light.factory ~inputs:[| None |] node (scene doc)) in
    let camera = Result.get_ok (Edit_graph.instantiate_optional Objects.Camera.factory []) in
    let camera = Node.relabel "camera1" camera in
    with_scene doc (Result.get_ok (Edit_graph.add_node ~factory:Objects.Camera.factory camera graph)) in
  let bare = with_light bare in
  check (not (contains (source bare) "scene/")) "the host's objects were written before any edit";
  let edited = ok (reconcile bare (set bare "light1" [ float "intensity" 12. ])) in
  check (contains (source edited) "graph scene" && contains (source edited) "scene/light"
         && contains (source edited) ":intensity 12.0" && contains (source edited) "scene/geometry (ref g)"
         && contains (source edited) "scene/camera") "an edited host object was not written to a scene graph";
  same_after_reload edited "adoption";
  (* a camera that follows the viewport is not such an edit *)
  let followed = ok (reconcile ~adopt:false bare (set bare "camera1" [ float "eye_x" 3. ])) in
  check (not (contains (source followed) "scene/") && snapshot followed = snapshot (set bare "camera1" [ float "eye_x" 3. ]))
    "a follow-the-viewport move was written or lost";
  (* the host's World, edited, is written as a world graph *)
  let worlded = match Objects.ids "world" (scene bare) with
    | [] ->
        let node = Result.get_ok (Edit_graph.instantiate Layers.Settings.factory []) in
        let graph = Result.get_ok (Edit_graph.add_node ~factory:Layers.Settings.factory node (scene bare)) in
        let daylight = List.assoc "daylight" World.presets in
        let network = Result.get_ok (Layers.network_of_world daylight) in
        let doc = with_scene bare graph in
        { doc with networks = Document.Int_map.add (Node.id node) network doc.networks }
    | _ -> bare in
  let edited = ok (reconcile bare worlded) in
  check (contains (source edited) "graph world" && contains (source edited) "world/sky")
    "a World added by the host did not reach the text";
  (* the host's own camera and light are not in the text, only the World is *)
  let layers (doc : Document.t) = let _, layers, _, _ = snapshot doc in layers in
  check (layers (open_text (source edited)) = layers edited) "added world: the saved text is not the document";
  (* a scene graph is authoritative for cameras and lights (and a world graph for the World): what
     it does not say is not there, and the host seeds nothing *)
  let names doc = List.sort compare (List.map (fun (i : Edit_graph.node_info) -> i.label) (Edit_graph.inspect (scene doc))) in
  let with_graphs extra = Ws_fixture.of_text ("(workspace bare (graph g :context sop (sop/box))" ^ extra ^ ")") in
  check (names (lower ~previous:bare (with_graphs "")) = [ "camera1"; "g"; "light1" ])
    "a workspace with no scene graph lost the host's camera and light";
  check (names (lower ~previous:bare (with_graphs " (graph scene :context scene (scene/merge (scene/geometry (ref g))))")) = [ "g" ])
    "a scene graph kept the host's camera or light";
  check (names (lower ~previous:bare (with_graphs " (graph scene :context scene (scene/merge))")) = [])
    "an empty scene graph kept an object";
  let with_world = match Objects.ids "world" (scene worlded) with _ :: _ -> worlded | [] -> failwith "no host World" in
  check (Objects.ids "world" (scene (lower ~previous:with_world (with_graphs ""))) <> [])
    "a workspace with no world graph lost the host's World";
  check (Objects.ids "world" (scene (lower ~previous:with_world (with_graphs " (graph world :context world (world/none))"))) = [])
    "(world/none) kept the host's World";
  (* deleting a host-made camera or light adopts the other host objects into a scene graph and
     removes the one; the saved text has no seed to bring it back *)
  let without (doc : Document.t) label =
    Document.prune (with_scene doc (Edit_graph.remove_nodes [ node_id doc label ] (scene doc))) in
  let no_camera = ok (reconcile bare (without bare "camera1")) in
  check (contains (source no_camera) "graph scene" && contains (source no_camera) "scene/light"
         && not (contains (source no_camera) "scene/camera")) "a deleted host camera was not written as absent";
  check (names no_camera = [ "g"; "light1" ] && names (open_text (source no_camera)) = [ "g"; "light1" ])
    "a deleted host camera came back on reload";
  same_after_reload no_camera "host camera delete";
  let no_light = ok (reconcile bare (without bare "light1")) in
  check (not (contains (source no_light) "scene/light") && contains (source no_light) "scene/camera"
         && names (open_text (source no_light)) = [ "camera1"; "g" ]) "a deleted host light came back on reload";
  let nothing = ok (reconcile no_camera (without no_camera "light1")) in
  check (names (open_text (source nothing)) = [ "g" ]) "deleting the last host objects was not written";
  (* the host's World, deleted: the world graph says none *)
  let no_world = ok (reconcile with_world (Document.prune (with_scene with_world
    (Edit_graph.remove_nodes (Objects.ids "world" (scene with_world)) (scene with_world))))) in
  check (contains (source no_world) "world/none" && Objects.ids "world" (scene (open_text (source no_world))) = [])
    "a deleted host World came back on reload";
  (* adding by key: an object joins the scene's merge, a layer goes on top of the stack; a document
     with no scene graph (or World graph) gets one, its host objects written first *)
  let add doc name expr = Result.get_ok (Flow_sop.Flow_edit.apply_checked
    (Result.get_ok (Contexts.catalog ~version:Flow_sop.Manifest.version factories)) (fst (doc : Workspace_doc.t * _)).source
    (Flow_sop.Flow_edit.Add_node { scope = [ "scene" ]; name; expr })) in
  ignore add;
  let call head args = Flow.Syntax.make (Flow.Syntax.List (Flow.Syntax.make (Flow.Syntax.Sym head) :: args)) in
  let catalog = Result.get_ok (Contexts.catalog ~version:Flow_sop.Manifest.version factories) in
  let edit (doc : Document.t) op = lower ~previous:doc
    (Result.get_ok (Workspace_doc.edit catalog (fst doc.workspace) op)) in
  let added = edit doc (Flow_sop.Flow_edit.Add_node { scope = [ "scene" ]; name = "lamp";
    expr = call "scene/light" [ Flow.Syntax.make (Flow.Syntax.Kw "name"); Flow.Syntax.make (Flow.Syntax.Str "lamp") ] }) in
  check (contains (source added) "scene/merge body arm cam side (scene/light :name \"fill\") lamp"
         || contains (source added) "lamp)") "a new object did not join the scene's merge";
  check (List.exists (fun (i : Edit_graph.node_info) -> i.label = "lamp") (Edit_graph.inspect (scene added)))
    "a new object is not in the scene";
  let layered = edit doc (Flow_sop.Flow_edit.Add_node { scope = [ "world" ]; name = "haze";
    expr = call "world/gradient" [] }) in
  check (List.map (fun (l, _, _) -> l) (let _, layers, _, _ = snapshot layered in layers) = [ "Gradient"; "sun"; "sky" ])
    "a new World layer is not on top of the stack";
  same_after_reload layered "added layer";
  let twice = edit added (Flow_sop.Flow_edit.Delete_nodes { nodes = [ [ "scene"; "lamp" ] ] }) in
  check (snapshot twice = snapshot doc) "deleting what was added did not give the scene back";
  check (Result.is_ok (Workspace_doc.edit catalog (fst layered.workspace) (Flow_sop.Flow_edit.Delete_nodes { nodes = [ [ "world"; "haze" ] ] })))
    "a World layer could not be deleted by its binding";
  (* through the editor: a workspace with no scene graph gets one when an object is added *)
  let env = Prismel_editor.Editor3.create ~workspace:(Ws_fixture.of_text "(workspace bare (graph g :context sop (sop/box)))")
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok in
  let env = match Prismel_editor.Editor3.edit env (Flow_sop.Flow_edit.Add_node { scope = [ "scene" ]; name = "lamp";
    expr = call "scene/light" [] }) with Ok env -> env | Error m -> failwith m in
  let saved = Workspace_doc.to_text (Prismel_editor.Editor3.workspace env) in
  check (contains saved "graph scene" && contains saved "scene/geometry (ref g)" && contains saved "scene/camera"
         && contains saved "lamp") "adding to a missing scene graph did not write it";
  check (Prismel_editor.Editor3.undo_label env = Some "Add node") "adding an object is not one entry";
  Prismel_editor.Editor3.close env;
  print_endline "scene sync: fields, inline, rename, reparent, delete, camera, World, settings, host objects, add by key ok"

(* Command: dune exec test/test_main.exe -- bench_scene_sync (from _build/default/test).  One handle-drag frame on an
   object of a workspace: the derived edit, its text rewrite and the new lowering, median of 50. *)
let bench () =
  let case name =
    In_channel.with_open_bin (Filename.concat "../specification/workspace/cases" (name ^ ".lisp")) In_channel.input_all in
  List.iter (fun (name, label) ->
    let doc = open_text (case name) in
    let id = node_id doc label in
    let runs = 50 in
    let times = List.init runs (fun i ->
      let after = set doc label [ float "translate_x" (Stdlib.float_of_int i *. 0.01) ] in
      let start = Unix.gettimeofday () in
      ignore (ok (reconcile doc after));
      (Unix.gettimeofday () -. start) *. 1000.) in
    ignore id;
    let sorted = List.sort compare times in
    Printf.printf "reconcile of one transform edit, %s: %.2f ms (median of %d)\n%!" name (List.nth sorted (runs / 2)) runs)
    [ "bloom", "flower"; "variations", "garden" ]

(* ---- the copies of a loop are one template (register V4) ---- *)

let lamps (doc : Document.t) =
  List.filter_map (fun (i : Edit_graph.node_info) -> if i.operation = "light" then Some i else None)
    (Edit_graph.inspect (scene doc))

let field (i : Edit_graph.node_info) name =
  List.find_map (fun (f : Parameter.field_view) -> if f.name = name then Some f.current else None)
    (Node.parameter_fields i.node)

let set_id (doc : Document.t) id values =
  with_scene doc (fst (Result.get_ok (Edit_graph.apply_parameters (scene doc) ~node_id:id values)))

let without_ids (doc : Document.t) ids =
  Document.prune (with_scene doc (Edit_graph.remove_nodes ids (scene doc)))

let refused = function Error message -> message | Ok _ -> failwith "an edit the loop cannot take was written"

let run_loops () =
  let body_loop = {|(workspace lamps
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (let* [body (scene/geometry (ref g) :name "body")
             row (for [i (range 4)] (scene/light :name "lamp" :intensity 30 :translate [i 2 0]))]
        (scene/merge body row))))|} in
  (* both spellings: the loop bound to a name, and written in the merge *)
  List.iter (fun (what, text) ->
    let doc = open_text text in
    check (List.length (lamps doc) = 4) (what ^ ": the loop did not make four lamps");
    check (List.length (List.filter (fun (_, h) -> Document.loop_of h <> None) doc.homes.objects) = 4)
      (what ^ ": the copies have no home in the loop");
    let third = (List.nth (lamps doc) 2).id in
    (* a literal field: the template is edited, every copy changes, the text says it once *)
    let edited = ok (reconcile doc (set_id doc third [ float "intensity" 77. ])) in
    check (List.for_all (fun i -> field i "intensity" = Some (Parameter.Float_value 77.)) (lamps edited))
      (what ^ ": an edit of one copy did not change them all");
    check (List.length (lamps edited) = 4 && contains (source edited) ":intensity 77.0"
           && not (contains (source edited) ":intensity 30"))
      (what ^ ": the template was not edited");
    check (snapshot (open_text (source edited)) = snapshot edited) (what ^ ": the saved text is not the document");
    check (match Sync.note doc edited with Some n -> contains n "loop template" && contains n "4 copies" | None -> false)
      (what ^ ": the status does not say the loop template and the copies: "
       ^ Option.value ~default:"none" (Sync.note doc edited));
    (* a field the loop computes from its variable has no value of its own *)
    let message = refused (reconcile doc (set_id doc third [ float "translate_x" 9. ])) in
    check (contains message "translate is computed by the loop" && contains message "(now i)")
      (what ^ ": a computed component was not refused with its expression: " ^ message);
    (* a component the loop does not compute is the template's: every copy follows *)
    let lifted = ok (reconcile doc (set_id doc third [ float "translate_y" 5. ])) in
    check (contains (source lifted) ":translate [i 5.0 0]"
           && List.for_all (fun i -> field i "translate_y" = Some (Parameter.Float_value 5.)) (lamps lifted)
           && List.map (fun i -> field i "translate_x") (lamps lifted) = List.map (fun i -> field i "translate_x") (lamps doc))
      (what ^ ": a literal component of a computed vector was not edited in the template: " ^ source lifted);
    (* rename: the template's :name *)
    let renamed = with_scene doc (Result.get_ok (Edit_graph.replace_node
      (Node.relabel "spot" (Option.get (Edit_graph.find (scene doc) ~node_id:third))) (scene doc))) in
    let renamed = ok (reconcile doc renamed) in
    check (List.for_all (fun (i : Edit_graph.node_info) -> i.label = "spot") (lamps renamed)
           && contains (source renamed) ":name \"spot\"" && not (contains (source renamed) ":name \"lamp\""))
      (what ^ ": a rename did not reach the template :name: " ^ source renamed ^ String.concat "," (List.map (fun (i : Edit_graph.node_info) -> i.label) (lamps renamed)));
    (* delete one copy: the loop skips that iteration, the others keep their iteration, id and place *)
    let x doc = List.map (fun i -> field i "translate_x") (lamps doc) in
    let xs = List.map (fun v -> Some (Parameter.Float_value v)) in
    let ids doc = List.sort compare (List.map (fun (i : Edit_graph.node_info) -> i.id) (lamps doc)) in
    let gone = ok (reconcile doc (without_ids doc [ third ])) in
    check (contains (source gone) ":skip [2]" && not (contains (source gone) "take") && not (contains (source gone) "drop"))
      (what ^ ": copy 3 was not skipped: " ^ source gone);
    check (x (open_text (source gone)) = xs [ 0.; 1.; 3. ]) (what ^ ": the copies after a deleted one moved");
    check (ids gone = List.filter (( <> ) third) (ids doc)) (what ^ ": the other copies changed id");
    same_after_reload gone (what ^ " delete a copy");
    (* repeated deletes accumulate in one list; a literal edit still reaches every remaining copy *)
    let again = ok (reconcile gone (without_ids gone [ (List.nth (lamps gone) 1).id ])) in
    check (contains (source again) ":skip [1 2]" && x (open_text (source again)) = xs [ 0.; 3. ])
      (what ^ ": a second delete did not accumulate: " ^ source again);
    let edited_after = ok (reconcile again (set_id again (List.hd (lamps again)).id [ float "intensity" 5. ])) in
    check (List.length (lamps edited_after) = 2 && contains (source edited_after) ":skip [1 2]"
           && List.for_all (fun i -> field i "intensity" = Some (Parameter.Float_value 5.)) (lamps edited_after))
      (what ^ ": an edit after a delete lost the skip or a copy");
    same_after_reload again (what ^ " delete twice");
    let first = (List.hd (lamps doc)).id in
    let gone = ok (reconcile doc (without_ids doc [ first ])) in
    check (contains (source gone) ":skip [0]" && not (contains (source gone) "concat")) (what ^ ": deleting the first copy");
    let gone2 = ok (reconcile doc (without_ids doc [ (List.nth (lamps doc) 1).id; (List.nth (lamps doc) 3).id ])) in
    check (x (open_text (source gone2)) = xs [ 0.; 2. ]) (what ^ ": two copies deleted together")) [
    "bound", body_loop;
    "inline", {|(workspace lamps
      (graph g :context sop (sop/box))
      (graph scene :context scene
        (scene/merge (scene/geometry (ref g) :name "body")
                     (for [i (range 4)] (scene/light :name "lamp" :intensity 30 :translate [i 2 0])))))|} ];
  (* several clauses: one iteration of the product goes, the flat iteration index is what is listed *)
  let grid = open_text {|(workspace grid
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g) :name "body")
                   (for [i (range 2) j (range 3)] (scene/light :name "lamp" :translate [i j 0])))))|} in
  check (List.length (lamps grid) = 6) "the two-clause loop did not make six lamps";
  let ids doc = List.sort compare (List.map (fun (i : Edit_graph.node_info) -> i.id) (lamps doc)) in
  let xy doc = List.map (fun i -> field i "translate_x", field i "translate_y") (lamps doc) in
  let cell i j = Some (Parameter.Float_value i), Some (Parameter.Float_value j) in
  let victim = (List.nth (lamps grid) 4).id in
  let gone = ok (reconcile grid (without_ids grid [ victim ])) in
  check (contains (source gone) ":skip [4]") ("a product iteration was not skipped: " ^ source gone);
  check (xy (open_text (source gone)) = [ cell 0. 0.; cell 0. 1.; cell 0. 2.; cell 1. 0.; cell 1. 2. ])
    "a two-clause delete removed the wrong copy";
  check (ids gone = List.filter (( <> ) victim) (ids grid)) "a two-clause delete changed the other ids";
  same_after_reload gone "two-clause delete";
  (* a bound loop too *)
  let bound_grid = open_text {|(workspace grid
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (let* [body (scene/geometry (ref g) :name "body")
             lamps (for [i (range 2) j (range 3)] (scene/light :name "lamp" :translate [i j 0]))]
        (scene/merge body lamps))))|} in
  let gone = ok (reconcile bound_grid (without_ids bound_grid [ (List.nth (lamps bound_grid) 4).id ])) in
  check (List.length (lamps gone) = 5 && contains (source gone) "lamps (for [i (range 2)"
         && contains (source gone) ":skip [4]") ("a bound two-clause delete: " ^ source gone);
  same_after_reload gone "bound two-clause delete";
  (* a copy that makes two objects: deleting one keeps its sibling, at any iteration *)
  let pairs = open_text {|(workspace pairs
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g) :name "body")
                   (for [i (range 3)]
                     (scene/merge (scene/light :name "a" :translate [i 0 0]) (scene/light :name "b" :translate [i 1 0]))))))|} in
  check (List.length (lamps pairs) = 6) "the loop of pairs did not make six lamps";
  let at doc label i = List.find_opt (fun (l : Edit_graph.node_info) -> l.label = label
    && field l "translate_x" = Some (Parameter.Float_value i)) (lamps doc) in
  let id_at doc label i = (Option.get (at doc label i)).id in
  let half = ok (reconcile pairs (without_ids pairs [ id_at pairs "a" 0. ])) in
  check (contains (source half) ":skip [[0 0]]" && not (contains (source half) "for [i (range 3)] :skip"))
    ("half a copy: the merge did not skip its argument: " ^ source half);
  check (List.length (lamps half) = 5 && at half "a" 0. = None && at half "b" 0. <> None && at half "a" 1. <> None)
    "deleting one object of a copy took its sibling or another copy";
  check (snapshot (open_text (source half)) = snapshot half) "half a copy: the saved text is not the document";
  let ids_before = List.filter (( <> ) (id_at pairs "a" 0.)) (ids pairs) in
  check (ids half = ids_before) "half a copy: the other objects changed id";
  (* then the other half: its iteration has nothing left, so the loop skips it *)
  let other = ok (reconcile half (without_ids half [ id_at half "b" 0. ])) in
  check (List.length (lamps other) = 4
         && contains (source other) ":skip [0]") ("the second half of a copy: " ^ source other);
  same_after_reload other "both halves";
  (* both at once, in another iteration *)
  let both = ok (reconcile pairs (without_ids pairs [ id_at pairs "a" 1.; id_at pairs "b" 1. ])) in
  check (List.length (lamps both) = 4 && contains (source both) ":skip [1]" && not (contains (source both) "[[1 0]]"))
    ("both objects of a copy: " ^ source both);
  (* the siblings bound by name in a let* body *)
  let named = open_text {|(workspace pairs
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g) :name "body")
                   (for [i (range 3)]
                     (let* [a (scene/light :name "a" :translate [i 0 0])
                            b (scene/light :name "b" :translate [i 1 0])]
                       (scene/merge a b))))))|} in
  let half = ok (reconcile named (without_ids named [ id_at named "b" 2. ])) in
  check (List.length (lamps half) = 5 && at half "b" 2. = None && at half "a" 2. <> None
         && contains (source half) ":skip [[2 1]]") ("a bound pair, one deleted: " ^ source half);
  same_after_reload half "bound pair half";
  (* a merge that loses an argument renumbers its skip (here b, which it skipped, and d, which it skips, move up) *)
  let catalog = Result.get_ok (Contexts.catalog ~version:Flow_sop.Manifest.version factories) in
  let renum = open_text {|(workspace r (graph scene :context scene
    (let* [a (scene/light :name "a") b (scene/light :name "b") c (scene/light :name "c") d (scene/light :name "d")]
      (scene/merge a b c d :skip [1 3]))))|} in
  check (List.length (lamps renum) = 2) "a merge :skip did not leave two lamps";
  let edit_text doc op = Workspace_doc.to_text (Result.get_ok (Workspace_doc.edit catalog (fst doc.Document.workspace) op)) in
  let after = edit_text renum (Flow_sop.Flow_edit.Delete_nodes { nodes = [ [ "scene"; "b" ] ] }) in
  check (contains after ":skip [2]") ("deleting an argument did not renumber the skip: " ^ after);
  let after = edit_text renum (Flow_sop.Flow_edit.Delete_nodes { nodes = [ [ "scene"; "a" ] ] }) in
  check (contains after ":skip [0 2]") ("deleting an earlier argument did not shift the skip: " ^ after);
  print_endline "scene sync: loop copies are one template: edit, computed refusal, rename, exact delete, pairs ok"

(* a loop inside a loop: the copies nest, the rules are the same, and a delete is exact at any depth *)
let run_nested_loops () =
  let text = {|(workspace nest
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g) :name "body")
                   (for [i (range 3)]
                     (scene/merge (for [j (range 2)] (scene/light :name "lamp" :intensity 30 :translate [i j 0])))))))|} in
  let doc = open_text text in
  check (List.length (lamps doc) = 6) "the nested loop did not make six lamps";
  let pick n = (List.nth (lamps doc) n).id in
  let edited = ok (reconcile doc (set_id doc (pick 3) [ float "intensity" 77. ])) in
  check (List.for_all (fun i -> field i "intensity" = Some (Parameter.Float_value 77.)) (lamps edited)
         && contains (source edited) ":intensity 77.0" && not (contains (source edited) ":intensity 30"))
    "a literal edit did not reach the inner template";
  same_after_reload edited "nested edit";
  let message = refused (reconcile doc (set_id doc (pick 3) [ float "translate_x" 9. ])) in
  check (contains message "computed by the loop" && contains message "(now i)")
    ("a computed field of a nested copy was not refused with its expression: " ^ message);
  let renamed = ok (reconcile doc (with_scene doc (Result.get_ok (Edit_graph.replace_node
    (Node.relabel "spot" (Option.get (Edit_graph.find (scene doc) ~node_id:(pick 3)))) (scene doc))))) in
  check (List.for_all (fun (i : Edit_graph.node_info) -> i.label = "spot") (lamps renamed)
         && contains (source renamed) ":name \"spot\"" && not (contains (source renamed) ":name \"lamp\""))
    ("a nested rename did not reach the template: " ^ source renamed);
  same_after_reload renamed "nested rename";
  let ids doc = List.sort compare (List.map (fun (i : Edit_graph.node_info) -> i.id) (lamps doc)) in
  let ij doc = List.map (fun i -> field i "translate_x", field i "translate_y") (lamps doc) in
  let cell i j = Some (Parameter.Float_value i), Some (Parameter.Float_value j) in
  let all = [ 0, 0; 0, 1; 1, 0; 1, 1; 2, 0; 2, 1 ] in
  let cells without = List.filter_map (fun (i, j) -> if List.mem (i, j) without then None
    else Some (cell (float_of_int i) (float_of_int j))) all in
  (* one inner copy goes alone: only that object, every other outer copy untouched *)
  List.iter (fun n ->
    let i, j = List.nth all n in
    let gone = ok (reconcile doc (without_ids doc [ pick n ])) in
    check (contains (source gone) (Printf.sprintf ":skip [[%d %d]]" i j)) ("nested delete " ^ string_of_int n ^ ": " ^ source gone);
    check (ij gone = cells [ i, j ] && ij (open_text (source gone)) = cells [ i, j ])
      (Printf.sprintf "deleting inner copy (%d,%d) took another object" i j);
    check (ids gone = List.filter (( <> ) (pick n)) (ids doc)) "a nested delete changed the other ids";
    same_after_reload gone "nested delete") [ 0; 3; 5 ];
  (* repeated deletes accumulate in the inner loop's list *)
  let first = ok (reconcile doc (without_ids doc [ pick 3 ])) in
  let second = ok (reconcile first (without_ids first [ (List.nth (lamps first) 0).id ])) in
  check (contains (source second) ":skip [[0 0] [1 1]]" && List.length (lamps second) = 4)
    ("nested deletes did not accumulate: " ^ source second);
  same_after_reload second "nested twice";
  (* every object of one outer copy: the outer iteration goes *)
  let outer = ok (reconcile doc (without_ids doc [ pick 2; pick 3 ])) in
  check (ij outer = cells [ 1, 0; 1, 1 ] && contains (source outer) ":skip [1]" && not (contains (source outer) "[[1"))
    ("an outer copy was not skipped: " ^ source outer);
  same_after_reload outer "outer copy";
  (* three levels, several clauses in the innermost: the innermost loop that makes the object is the one that skips *)
  let deep = open_text {|(workspace deep
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g) :name "body")
        (for [i (range 2)]
          (scene/merge
            (for [j (range 2)]
              (scene/merge
                (for [a (range 2) b (range 2)]
                  (scene/light :name "lamp" :translate [i j (+ (* 2 a) b)])))))))))|} in
  check (List.length (lamps deep) = 16) "the three-level loop did not make sixteen lamps";
  let z doc = List.map (fun i -> field i "translate_x", field i "translate_y", field i "translate_z") (lamps doc) in
  let pick3 n = (List.nth (lamps deep) n).id in
  (* lamp number 11 is i=1 j=0 a=1 b=1, the innermost iteration (1 0 3) *)
  let gone = ok (reconcile deep (without_ids deep [ pick3 11 ])) in
  check (contains (source gone) ":skip [[1 0 3]]" && List.length (lamps gone) = 15
         && z (open_text (source gone)) = z gone
         && not (List.mem (List.nth (z deep) 11) (z gone)))
    ("a three-level delete: " ^ source gone);
  check (ids gone = List.filter (( <> ) (pick3 11)) (ids deep)) "a three-level delete changed the other ids";
  same_after_reload gone "three-level delete";
  (* all of (1 0): the middle iteration goes, not four inner ones *)
  let middle = ok (reconcile deep (without_ids deep (List.map pick3 [ 8; 9; 10; 11 ]))) in
  check (List.length (lamps middle) = 12 && contains (source middle) ":skip [[1 0]]" && not (contains (source middle) "[[1 0 "))
    ("a middle iteration was not skipped as one: " ^ source middle);
  same_after_reload middle "three-level middle";
  (* an empty loop stays a loop: every object deleted *)
  let none = ok (reconcile doc (without_ids doc (List.map pick [ 0; 1; 2; 3; 4; 5 ]))) in
  check (lamps none = [] && lamps (open_text (source none)) = []) "deleting every copy left objects";
  same_after_reload none "all copies";
  print_endline "scene sync: nested loops: edit, computed refusal, rename, exact delete at 2 and 3 levels, accumulate ok"
