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
  (* settings graph *)
  let settings = fst (Result.get_ok (Editor_document.Settings.apply doc.settings [ "width", Parameter.Int_value 800 ])) in
  let edited = ok (reconcile doc { doc with settings }) in
  check (contains (source edited) ":width 800") "a settings edit did not reach the text";
  same_after_reload edited "settings";
  (* an object made by a loop, and a name two objects share, are refused whole *)
  let looped = open_text {|(workspace loop
    (graph scene :context scene
      (scene/merge (for [i (range 2)] (scene/light :name "lamp" :translate [i 0 0])))))|} in
  (match reconcile looped (set looped "lamp" [ float "intensity" 5. ]) with
   | Error _ -> ()
   | Ok _ -> failwith "an object made by a loop was edited");
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
