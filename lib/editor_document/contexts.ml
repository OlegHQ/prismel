(* The scene, world and settings contexts of a workspace (plan W10, part A).

   Their Lisp spellings are generated from the schemas that exist: one kind
   per object factory ([scene/geometry], [scene/light], [scene/camera]), per
   World node and layer factory ([world/world], [world/gradient], ...) and
   the workspace settings record ([settings/config]).  A kind's keywords are
   its schema's fields, three consecutive [_x _y _z] or [_r _g _b] floats
   grouped as one vec3 or colour ([:translate [0 1 0]], [:color "#3b7d4e"]),
   plus [:name], the node's label.  Nothing here is written per kind: a new
   field in a schema is a new keyword.

   The evaluator returns these calls as [Struct] values; [of_workspace] walks
   the scene, world and settings results into the editor document:
   objects become nodes of the scene network, the World a node with its layer
   stack as a network, settings a [Settings.t]. *)
open Procedural
module E = Flow.Eval
module W = Flow.Workspace
module Edit = Edit_graph
module Param = Editor_core.Param

let ( let* ) = Result.bind
let diag code message = Flow.Diagnostic.error ~code message
let flow r = Result.map_error (diag "E_DOCUMENT") r

(* ---- the kinds ---- *)

let name_field : Param.field_view = {
  name = "name"; label = "Name"; description = None; folder = []; impact = Param.Cook;
  primary = false; vec3 = None; kind = Param.Text_view; default = Param.Text_value "";
  current = Param.Text_value "" }

(* [:parent "label"] places an object under another by name (a camera has none); [:active true]
   makes a camera the render camera.  Neither is a field of the node: the lowering reads them. *)
let parent_field = { name_field with name = "parent"; label = "Parent" }
let active_field = { name_field with name = "active"; label = "Active camera";
  kind = Param.Toggle_view; default = Param.Bool_value false; current = Param.Bool_value false }

(* Three consecutive floats [p_x p_y p_z] (or [_r _g _b]) of one folder become the
   vec3 [p]; a stem that is already a field name becomes [p_color]. *)
let group_triples (fields : Param.field_view list) =
  let names = List.map (fun (f : Param.field_view) -> f.name) fields in
  let floating (f : Param.field_view) = match f.kind with
    | Param.Floating_view _ -> true | _ -> false in
  let stem (f : Param.field_view) = List.find_map (fun suffixes ->
    if floating f && f.vec3 = None
       && String.ends_with ~suffix:(List.hd suffixes) f.name
    then Some (String.sub f.name 0 (String.length f.name - 2), suffixes) else None)
    [ [ "_x"; "_y"; "_z" ]; [ "_r"; "_g"; "_b" ] ] in
  let rec go = function
    | (x : Param.field_view) :: (y : Param.field_view) :: (z : Param.field_view) :: rest
      when (match stem x with
          | Some (p, [ _; sy; sz ]) -> y.name = p ^ sy && z.name = p ^ sz && floating y
              && floating z && y.folder = x.folder && z.folder = x.folder
          | _ -> false) ->
        let p = fst (Option.get (stem x)) in
        let group = if List.mem p names then p ^ "_color" else p in
        { x with vec3 = Some (group, 0) } :: { y with vec3 = Some (group, 1) }
        :: { z with vec3 = Some (group, 2) } :: go rest
    | x :: rest -> x :: go rest
    | [] -> [] in
  go fields

(* The World and the root are scene kinds too: [scene/world] is a merge member that references a
   world graph, [scene/root] ends the scene graph.  The old [world/world] stays a (legacy) kind of
   the world context, so old files still check and load. *)
let scene_kinds = List.map (fun f -> "scene/" ^ Edit.factory_key f, f)
    (Objects.catalog @ [ Layers.Settings.factory; Objects.Root.factory ])
let world_kinds = List.map (fun f -> "world/" ^ Edit.factory_key f, f)
    (Layers.Settings.factory :: Layers.catalog)

(* Workspace settings: what the host needs to open the window. *)
type window = { title : string; width : int; height : int; fps : int; seed : int }

let window_schema =
  let integer min max hard_min = Param.integer ~hard_min ~min ~max () in
  let int_field name label kind default get set =
    Param.field ~name ~label:(label ^ " (on restart)") ~kind ~default ~get ~set () in
  Param.schema ~name:"workspace" ~default:{ title = "Prismel"; width = 1280; height = 800;
                                            fps = 60; seed = 1 } [
    Param.field ~name:"title" ~label:"Title (on restart)" ~kind:Param.Text ~default:"Prismel"
      ~get:(fun w -> w.title) ~set:(fun title w -> { w with title }) ();
    int_field "width" "Width" (integer 320 3840 64) 1280 (fun w -> w.width)
      (fun width w -> { w with width });
    int_field "height" "Height" (integer 240 2160 64) 800 (fun w -> w.height)
      (fun height w -> { w with height });
    int_field "fps" "Frames per second" (Param.integer ~hard_min:1 ~hard_max:240 ~min:1 ~max:120 ())
      60 (fun w -> w.fps) (fun fps w -> { w with fps });
    int_field "seed" "Seed" (Param.integer ~hard_min:0 ~min:0 ~max:9999 ()) 1
      (fun w -> w.seed) (fun seed w -> { w with seed }) ]

let window_fields = Param.view window_schema (Param.default window_schema)

(* slot of each kind: a geometry object takes its geometry, a World layer the layer below *)
let kind_slots qualified = match qualified with
  | "scene/geometry" -> [ "geometry", Edit.Required ]
  | "scene/world" -> [ "world", Edit.Required ]
  | "scene/root" -> [ "scene", Edit.Required; "camera", Edit.Optional ]
  | "world/world" -> [ "layers", Edit.Optional ]
  | q when String.starts_with ~prefix:"world/" q -> [ "below", Edit.Optional ]
  | _ -> []

(* the render settings an old camera carried: read as the root's until the first save *)
let legacy_render = [ "width"; "height"; "max_spp" ]
let legacy_field name label default =
  { name_field with name; label; kind = Param.Integer_view
      { Param.soft_min = 1; soft_max = 16384; hard_min = Some 1; hard_max = Some 16384 };
    default = Param.Int_value default; current = Param.Int_value default }

let extra_fields = function
  | "scene/camera" -> [ active_field; legacy_field "width" "Width (old files)" 1920;
                        legacy_field "height" "Height (old files)" 1080;
                        legacy_field "max_spp" "Max samples (old files)" 256 ]
  | "scene/geometry" | "scene/light" -> [ parent_field ]
  | _ -> []

let descriptors : Flow_sop.Catalog.descriptor list =
  List.map (fun (qualified, factory) ->
    { Flow_sop.Catalog.qualified; key = Edit.factory_key factory;
      operation = Edit.factory_operation factory; label = Edit.factory_label factory;
      category = Edit.factory_category factory; slots = kind_slots qualified;
      fields = name_field :: extra_fields qualified @ group_triples (Edit.factory_fields factory) })
    (scene_kinds @ world_kinds)
  @ [ { Flow_sop.Catalog.qualified = "settings/config"; key = "config"; operation = "config";
        label = "Settings"; category = [ "Workspace" ]; slots = [];
        fields = window_fields } ]

let catalog ~version factories = Flow_sop.Catalog.of_factories ~version ~extra:descriptors factories

let ports qualified =
  match List.find_opt (fun (d : Flow_sop.Catalog.descriptor) -> d.qualified = qualified) descriptors with
  | Some d -> Result.get_ok (Flow_sop.Port.parameters d.fields)  (* valid by construction *)
  | None -> []

(* ---- lowering a struct ---- *)

let slot_names = [ "geometry"; "layers"; "below"; "name"; "parent"; "active"; "world"; "scene"; "camera" ]

(* The field changes a struct's keywords make, checked against the schema's bounds. *)
let changes qualified args =
  let ports = ports qualified in
  List.fold_left (fun acc (key, value) ->
    let* acc = acc in
    if List.mem key slot_names || (qualified = "scene/camera" && List.mem key legacy_render) then Ok acc
    else
      let* port = Flow_sop.Port.find_parameter ports key in
      let* changes = Flow_sop.Lower.changes port value in
      Ok (acc @ changes)) (Ok []) args

let label_arg args = match List.assoc_opt "name" args with
  | Some (E.Text s) when s <> "" -> Some s | _ -> None

let live_light_field kind key = kind = "scene/light" && List.mem key ["intensity"; "color"]

(* Geometry references are static [Geo] identities even when their SOP
   parameters are live. Residuals in the surrounding structs would otherwise
   be silently frozen when we materialize these contexts at startup. *)
let check_context_time (workspace : Workspace_doc.t) (plan : E.plan) =
  let rec live_field path = function
    | E.Residual _ -> Some path
    | E.Struct (kind, args) -> List.find_map (fun (key, value) ->
        if live_light_field kind key then None else live_field (kind ^ "." ^ key) value) args
    | E.Record args -> List.find_map (fun (key, value) -> live_field (path ^ "." ^ key) value) args
    | E.List values -> Array.to_list values |> List.find_map (live_field path)
    | _ -> None in
  match Array.to_list plan.instances |> List.find_map (fun (instance : E.instance) ->
    Option.bind (List.find_opt (fun (g : W.graph) -> g.name = instance.graph
      && g.context <> W.Sop && g.context <> W.Value) workspace.checked.graphs) (fun graph ->
      Option.map (fun field -> Flow.Diagnostic.error ~code:"E_CONTEXT_TIME" ~span:graph.body.form.span
        (Printf.sprintf "Graph %s: %s depends on t, but %s fields are static. Use a literal or a SOP/value drive."
          graph.name field (W.context_name graph.context))) (live_field "result" instance.result))) with
  | None -> Ok () | Some diagnostic -> Error diagnostic

(* Non-SOP fields are checked before their static context is materialized. *)
let result ?(force = true) (workspace : Workspace_doc.t) (plan : E.plan) context =
  match (if context = Flow.Workspace.Editor then Workspace_doc.editor_graph workspace
    else List.find_opt (fun (g : Flow.Workspace.graph) -> g.context = context) workspace.checked.graphs) with
  | None -> Ok None
  | Some graph ->
      (match List.find_opt (fun (i : E.instance) -> i.default && i.graph = graph.name)
               (Array.to_list plan.instances) with
       | None -> Ok None
       | Some instance ->
           if force then Result.map Option.some (E.force instance.result ~live:{ E.t = 0. })
           else Ok (Some instance.result))

let has_settings (workspace : Workspace_doc.t) =
  List.exists (fun (g : Flow.Workspace.graph) -> g.context = Flow.Workspace.Settings)
    workspace.checked.graphs

let settings_of = function
  | E.Struct ("settings/config", args) ->
      let* changes = changes "settings/config" args in
      let* settings, _ = Result.map_error (diag "E_RANGE")
          (Settings.apply (Settings.make window_schema (Param.default window_schema)) changes) in
      Ok settings
  | _ -> Error (diag "E_LOWER" "A settings graph returns a (settings/config ...) call.")

(* The window the settings graph asks for; defaults without one. *)
let window (workspace : Workspace_doc.t) =
  let* evaluated = E.static workspace.checked in
  let* () = check_context_time workspace evaluated.plan in
  let* value = result workspace evaluated.plan Flow.Workspace.Settings in
  match value with
  | None -> Ok (Param.default window_schema)
  | Some value -> Result.map (Settings.get window_schema) (settings_of value)

(* ---- where things are written ---- *)

module F = Flow_sop.Flow_edit

(* A call of interest in an evaluated result, with where its text is. *)
type call = { kind : string; args : (string * E.value) list; home : Document.home;
              via : string option  (* the graph a [(ref g)] argument names, for [scene/world] *) }

let slot_args = [ "geometry"; "layers"; "below"; "scene"; "world" ]

(* Argument [i] of a call as an edit addresses it: positional for a slot, else its keyword. *)
let arg_key args i =
  let name = fst (List.nth args i) in
  if List.mem name slot_args then
    F.Pos (List.length (List.filter (fun (n, _) -> List.mem n slot_args)
                          (List.filteri (fun j _ -> j < i) args)))
  else F.Kw name

(* Calls with no term to read (graph inputs, loops, macro expansions): reachable but unwritable. *)
let rec loose ~want ~below = function
  | E.Struct ("scene/merge", args) -> List.concat_map (fun (_, v) -> loose ~want ~below v) args
  | E.Struct (kind, args) when want kind ->
      (match Option.bind (below kind) (fun slot -> List.assoc_opt slot args) with
       | Some under -> loose ~want ~below under | None -> [])
      @ [ { kind; args; home = Document.Looped; via = None } ]
  | E.List xs -> List.concat_map (loose ~want ~below) (Array.to_list xs)
  | _ -> []

(* The home of a call in a loop body, as a copy: the template's path goes relative to the loop,
   a call written inside another call of the body keeps that nesting, a loop in a loop nests. *)
let rec copy ~zone ~loop index : Document.home -> Document.home = function
  | Bound_at p when List.length p > List.length zone
                    && List.filteri (fun i _ -> i < List.length zone) p = zone ->
      Copy { loop; rel = List.filteri (fun i _ -> i >= List.length zone) p; index }
  | Inline_in (h, k) -> Inline_in (copy ~zone ~loop index h, k)
  | Copy c -> Copy { c with loop = copy ~zone ~loop index c.loop }
  | h -> h

(* Walk the terms of a graph beside its evaluated result: each wanted call, bottom layer
   first, with its binding, or the argument of another call that holds it. [below kind] names
   the slot a call stacks its predecessor in. *)
let is_loop env (t : W.term) = match t.node with
  | W.Loop { kind = `For; _ } -> true
  | W.Ref_binding (n, []) ->
      (match List.assoc_opt n env with
       | Some { W.node = W.Loop { kind = `For; _ }; _ } -> true | _ -> false)
  | _ -> false

(* a merge's values line up with its arguments: one each, and at most one loop takes the rest *)
let merge_fits env targs vargs =
  let loops = List.length (List.filter (fun (_, t) -> is_loop env t) targs) in
  let extra = List.length vargs - List.length targs in
  if loops = 0 then extra = 0 else loops = 1 && extra >= -1

(* the running index of each copy of a loop at the iteration tuple [iter] (its enclosing loops'
   indices): the copies are the iterations not in [skip] (register L16), so a copy keeps its index
   when others are deleted *)
let real_indices skip iter n =
  let k = ref 0 in
  Array.init n (fun _ ->
    while List.mem (iter @ [ !k ]) skip do incr k done;
    let r = !k in incr k; r)

(* the arguments of a merge that stay, with their written positions *)
let kept ~iter skip args =
  List.filter (fun (i, _) -> not (List.mem (iter @ [ i ]) skip)) (List.mapi (fun i a -> i, a) args)

(* the graph a [scene/world]'s World argument references: written in place or by a binding *)
let rec referenced env (t : W.term) = match t.node with
  | W.Graph_ref { graph; _ } -> Some graph
  | W.Ref_binding (n, []) -> Option.bind (List.assoc_opt n env) (referenced env)
  | _ -> None

let rec walk ~want ~below ~iter env place (t : W.term) (v : E.value) =
  let home () = match t.path, place with
    | Some p, _ -> Document.Bound_at p
    | None, Some (parent, key) -> Document.Inline_in (parent, key)
    | None, None -> Document.Looped in
  match t.node, v with
  | W.Let (bindings, body), _ ->
      let env = List.filter_map (function W.Name n, x -> Some (n, x) | _ -> None) bindings @ env in
      walk ~want ~below ~iter env place body v
  | W.Ref_binding (n, []), _ ->
      (match List.assoc_opt n env with
       | Some bound -> walk ~want ~below ~iter env None bound v
       | None -> loose ~want ~below v)
  | W.Call { kind; args = targs }, E.Struct (k, vargs) when k = kind && want kind ->
      let here = home () in
      let under = match Option.bind (below kind) (fun slot ->
          Option.map (fun i -> i, List.assoc slot vargs) (List.find_index (fun (n, _) -> n = slot) targs)) with
        | Some (i, under_value) ->
            walk ~want ~below ~iter env (Some (here, arg_key targs i)) (snd (List.nth targs i)) under_value
        | None | exception Not_found -> [] in
      let via = if kind <> "scene/world" then None
        else Option.bind (List.assoc_opt "world" targs) (referenced env) in
      under @ [ { kind; args = vargs; home = here; via } ]
  | W.Op { op = "scene/merge"; args = all; skip }, E.Struct ("scene/merge", vargs)
    when merge_fits env (List.map snd (kept ~iter skip all)) vargs ->
      let targs = List.map snd (kept ~iter skip all) in
      let here = home () in
      (* an argument gives one value, a loop the rest: its copies *)
      let extra = List.length vargs - List.length targs in
      let _, found = List.fold_left (fun (at, found) (i, (_, (term : W.term))) ->
        let n = if is_loop env term then extra + 1 else 1 in
        let value = if is_loop env term then E.List (Array.of_list (List.map snd (List.filteri
            (fun j _ -> j >= at && j < at + n) vargs))) else snd (List.nth vargs at) in
        at + n, found @ walk ~want ~below ~iter env (Some (here, F.Pos (fst (List.nth (kept ~iter skip all) i)))) term value)
        (0, []) (List.mapi (fun i a -> i, a) targs) in
      found
  | W.Loop { kind = `For; body; zone; skip; _ }, E.List xs ->
      (* the body is one template, walked beside each copy's value *)
      let loop = home () in
      let real = real_indices skip iter (Array.length xs) in
      List.concat (List.mapi (fun pos x ->
        let i = real.(pos) in
        List.map (fun c -> { c with home = copy ~zone ~loop i c.home })
          (walk ~want ~below ~iter:(iter @ [ i ]) env None body x)) (Array.to_list xs))
  | _ -> loose ~want ~below v

let graph_of (workspace : Workspace_doc.t) context =
  List.find_opt (fun (g : W.graph) -> g.context = context) workspace.checked.graphs

let graph_of_name (workspace : Workspace_doc.t) name =
  List.find_opt (fun (g : W.graph) -> g.name = name && g.context = W.World) workspace.checked.graphs

(* Scene calls retain their light residuals beside their homes; other contexts
   are materialized at zero after unsupported live fields have been refused. *)
let graph_calls ~want ~below (plan : E.plan) context (graph : W.graph) =
  match List.find_opt (fun (i : E.instance) -> i.default && i.graph = graph.name)
          (Array.to_list plan.instances) with
  | None -> Ok []
  | Some instance ->
      let* value = if context = W.Scene then Ok instance.result
        else E.force instance.result ~live:{ E.t = 0. } in
      Ok (walk ~want ~below ~iter:[] [] None graph.body value)

let calls ~want ~below (workspace : Workspace_doc.t) (plan : E.plan) context =
  match graph_of workspace context with
  | None -> Ok []
  | Some graph -> graph_calls ~want ~below plan context graph

let no_below _ = None

(* a [scene/root] holds the rest of the scene in its [scene] slot *)
let scene_below = function "scene/root" -> Some "scene" | _ -> None

(* ---- the scene ---- *)

type item = { factory : Edit.factory; label : string; values : (string * Param.value) list;
              geometry : Flow_sop.Lower.graph option; home : Document.home;
              parent : string option; active : bool; group : string option;
              drives : (string * (Flow_sop.Port.parameter * E.value) list) option;
              via : string option;  (* the world graph a [scene/world] references *)
              legacy : (string * Param.value) list  (* render settings an old camera carries *) }

let item_of (lowered : Flow_sop.Lower.t) { kind; args; home; via } =
  let dynamic = List.filter (fun (key, value) -> live_light_field kind key && E.is_live value) args in
  let* dynamic = List.fold_right (fun (key, value) result ->
    let* rest = result in
    let* parameter = Flow_sop.Port.find_parameter (ports kind) key in
    Ok ((parameter, value) :: rest)) dynamic (Ok []) in
  let drives = if dynamic = [] then None else Some (kind, dynamic) in
  let* forced = E.force (E.Struct (kind, args)) ~live:{E.t = 0.} in
  let args = match forced with E.Struct (_, args) -> args | _ -> assert false in
  let factory = List.assoc kind scene_kinds in
  let* values = changes kind args in
  let* geometry = match List.assoc_opt "geometry" args with
    | Some (E.Geo id) ->
        let inst = lowered.plan.nodes.(id).inst in
        (match List.find_opt (fun (g : Flow_sop.Lower.graph) -> g.instance = inst) lowered.graphs with
         | Some g -> Ok (Some g)
         | None -> Error (diag "E_LOWER" "A scene object's geometry comes from a sop graph."))
    | _ -> Ok None in
  let label = match label_arg args, geometry with
    | Some label, _ -> label
    | None, Some g -> g.name
    | None, None -> if kind = "scene/world" then "World" else String.lowercase_ascii (Edit.factory_label factory) in
  let legacy = if kind <> "scene/camera" then [] else List.filter_map (function
    | key, E.Int n when List.mem key legacy_render -> Some (key, Param.Int_value n)
    | _ -> None) args in
  let parent = match List.assoc_opt "parent" args with Some (E.Text s) when s <> "" -> Some s | _ -> None in
  let active = List.assoc_opt "active" args = Some (E.Bool true) in
  Ok { factory; label; values; geometry; home; parent; active; group = None; drives; via; legacy }

let is_scene_kind kind = List.mem_assoc kind scene_kinds

(* How a scene renders: the settings of the scene graph's [scene/root] over the old camera's, where
   the root's text is, and the object its [:camera] slot names (an index among the objects). *)
type root = { params : Objects.Root.parameters; root_home : Document.home option;
              camera : int option }

let root_params values =
  Result.map fst (Result.map_error (diag "E_RANGE")
    (Param.apply_all Objects.Root.parameters_schema Objects.Root.default values))

(* the item a camera value is: the call whose arguments it carries *)
let find_call calls = function
  | E.Struct (_, cargs) ->
      List.find_index (fun (c : call) ->
        c.args == cargs || (try c.args = cargs with Invalid_argument _ -> false)) calls
  | _ -> None

let root_of calls (objects : item list) =
  let legacy = let cameras = List.filter (fun (i : item) -> Edit.factory_operation i.factory = "camera") objects in
    match List.find_opt (fun (i : item) -> i.active) cameras, cameras with
    | Some c, _ | None, c :: _ -> c.legacy
    | None, [] -> [] in
  match List.find_opt (fun (c : call) -> c.kind = "scene/root") calls with
  | None -> let* params = root_params legacy in Ok { params; root_home = None; camera = None }
  | Some call ->
      let own = List.filter (fun (key, _) -> not (List.mem key slot_names)) call.args in
      let* forced = E.force (E.Struct ("scene/root", own)) ~live:{ E.t = 0. } in
      let* values = changes "scene/root" (match forced with E.Struct (_, args) -> args | _ -> []) in
      let* params = root_params (legacy @ values) in
      let others = List.filter (fun (c : call) -> c.kind <> "scene/root") calls in
      Ok { params; root_home = Some call.home;
           camera = Option.bind (List.assoc_opt "camera" call.args) (find_call others) }

(* How a viewport's own scene instance renders: its [scene/root]'s settings, none for a part *)
let instance_root = function
  | E.Struct ("scene/root", args) ->
      let own = List.filter (fun (key, _) -> not (List.mem key slot_names)) args in
      (match E.force (E.Struct ("scene/root", own)) ~live:{ E.t = 0. } with
       | Ok (E.Struct (_, forced)) ->
           (match changes "scene/root" forced with
            | Ok values -> Result.to_option (root_params values)
            | Error _ -> None)
       | Ok _ | Error _ -> None)
  | _ -> None

(* The objects of a workspace: its scene graph's calls, else one geometry object
   per sop graph; and its root. *)
let items workspace (lowered : Flow_sop.Lower.t) =
  match graph_of workspace Flow.Workspace.Scene with
  | Some _ ->
      let* scene = calls ~want:is_scene_kind ~below:scene_below workspace lowered.plan Flow.Workspace.Scene in
      let* objects = List.fold_right (fun call rest ->
        let* rest = rest in
        if call.kind = "scene/root" then Ok rest
        else let* item = item_of lowered call in Ok (item :: rest)) scene (Ok []) in
      let* root = root_of scene objects in
      let objects = List.mapi (fun i (item : item) ->
        if Some i = root.camera then { item with active = true } else item) objects in
      Ok (objects, root)
  | None ->
      let* params = root_params [] in
      Ok (List.filter_map (fun (g : Flow_sop.Lower.graph) ->
        if g.default then Some { factory = Objects.Geometry.factory; label = g.name; values = [];
                                 geometry = Some g; home = Document.Looped; parent = None;
                                 active = false; group = None; drives = None; via = None; legacy = [] }
        else None) lowered.graphs, { params; root_home = None; camera = None })

(* The scene value of a graph, at t = 0, as loose calls (a viewport's own scene instance). *)
let scene_calls value = loose ~want:is_scene_kind ~below:scene_below value

(* ---- what a scene graph refuses ---- *)

(* everything a scene value holds, through merges, roots and parts *)
let rec members = function
  | E.Struct ("scene/merge", args) -> List.concat_map (fun (_, v) -> members v) args
  | E.Struct ("scene/root", args) ->
      (match List.assoc_opt "scene" args with Some v -> members v | None -> [])
  | E.List xs -> List.concat_map members (Array.to_list xs)
  | E.Struct _ as v -> [ v ]
  | _ -> []

(* a root wired into a merge or another root: it renders, so it is always last *)
let rec nested_root ~under = function
  | E.Struct ("scene/root", args) ->
      under || (match List.assoc_opt "scene" args with Some v -> nested_root ~under:true v | None -> false)
  | E.Struct ("scene/merge", args) -> List.exists (fun (_, v) -> nested_root ~under:true v) args
  | E.List xs -> Array.exists (nested_root ~under) xs
  | _ -> false

(* E_SCENE_ROOT, E_SCENE_WORLD, E_SCENE_CAMERA over every scene graph of the workspace *)
let check_scene (workspace : Workspace_doc.t) (plan : E.plan) =
  List.fold_left (fun checked (g : W.graph) ->
    let* () = checked in
    match List.find_opt (fun (i : E.instance) -> i.default && i.graph = g.name) (Array.to_list plan.instances) with
    | Some instance when g.context = W.Scene ->
        let refuse code message = Error (Flow.Diagnostic.error ~code ~span:g.body.form.span message) in
        let value = instance.result in
        if nested_root ~under:false value then
          refuse "E_SCENE_ROOT" (Printf.sprintf
            "Graph %s: a scene/root is wired into a merge or another root. A root renders the scene, so it is always last." g.name)
        else
          let* worlds = graph_calls ~want:(fun k -> k = "scene/world" || k = "scene/root") ~below:scene_below plan W.Scene g in
          let worlds = List.filter (fun (c : call) -> c.kind = "scene/world") worlds in
          let name (c : call) = Document.describe workspace.source c.home in
          (match worlds with
           | first :: second :: _ ->
               refuse "E_SCENE_WORLD" (Printf.sprintf
                 "Graph %s: two Worlds reach one root, %s and %s. A scene has one World; take one out of the merge." g.name
                 (name first) (name second))
           | _ ->
               (match value with
                | E.Struct ("scene/root", args) ->
                    (match List.assoc_opt "camera" args with
                     | Some (E.Struct ("scene/camera", _) as camera)
                       when List.exists (fun m -> m == camera || (try m = camera with Invalid_argument _ -> false))
                              (members value) -> Ok ()
                     | Some _ -> refuse "E_SCENE_CAMERA" (Printf.sprintf
                         "Graph %s: the root's :camera is not a camera in its scene." g.name)
                     | None -> Ok ())
                | _ -> Ok ()))
    | _ -> Ok ()) (Ok ()) workspace.checked.graphs

let find_node graph used operation label =
  List.find_opt (fun (info : Edit.node_info) ->
    info.operation = operation && info.label = label && not (List.mem info.id used))
    (Edit.inspect graph)

(* The node of a previous document that stands for this text: the one at the same home (so a
   rename keeps the id), else the one of the same kind and label. *)
let find_claim graph used operation ~home ~label homes =
  let by_home = if home = Document.Looped then None else
    List.find_map (fun (id, h) ->
      if h = home && not (List.mem id used) then
        (match Edit.find graph ~node_id:id with
         | Some node when Node.operation node = operation -> Some id
         | _ -> None)
      else None) homes in
  match by_home with
  | Some _ -> by_home
  | None -> Option.map (fun (info : Edit.node_info) -> info.id) (find_node graph used operation label)

(* What the text says is the whole truth of a declared node: fields it does not name are
   the schema's defaults. *)
let apply factory graph id values =
  let defaults = List.filter_map (fun (f : Param.field_view) ->
    if List.mem_assoc f.name values then None else Some (f.name, f.default))
    (Edit.factory_fields factory) in
  match defaults @ values with
  | [] -> Ok graph
  | values -> Result.map fst (flow (Edit.apply_parameters graph ~node_id:id values))

(* a claimed node takes the label the text gives it *)
let relabel graph id label = match Edit.find graph ~node_id:id with
  | Some node when Node.label node <> label -> flow (Edit.replace_node (Node.relabel label node) graph)
  | _ -> Ok graph

let empty_inputs factory = List.map (fun _ -> None) (Edit.factory_inputs factory)

let add_node graph factory label =
  let* node = flow (Edit.instantiate_optional factory (empty_inputs factory)) in
  let node = Node.relabel label node in
  let* graph = flow (Edit.add_node ~factory
    ~inputs:(Array.of_list (empty_inputs factory)) node graph) in
  Ok (graph, Node.id node)

(* Parents by name: [:parent "label"] links an object under the object of that label (of its
   own scene instance). *)
let link_parents graph objects =
  List.fold_left (fun graph (id, item) ->
    let* graph = graph in
    let want = match item.parent with
      | None -> Ok None
      | Some name ->
          let label = match item.group with Some key -> Printf.sprintf "%s (%s)" name key | None -> name in
          (match List.find_map (fun (pid, (p : item)) ->
             if pid <> id && p.label = label then Some pid else None) objects with
           | Some pid -> Ok (Some pid)
           | None -> Error (diag "E_LOWER" (Printf.sprintf "%s: there is no object named %S to be its parent."
                                               item.label name))) in
    let* want = want in
    if Objects.parent graph id = want then Ok graph
    else
      let* graph = match Objects.parent graph id with
        | Some _ -> flow (Edit.disconnect ~consumer:id ~input_index:0 graph)
        | None -> Ok graph in
      match want with
      | Some parent -> flow (Edit.connect ~source:parent ~consumer:id ~input_index:0 graph)
      | None -> Ok graph) (Ok graph) objects

(* ---- the World ---- *)

let is_world_kind kind = List.mem_assoc kind world_kinds

(* the slot a world call stacks its predecessor in *)
let world_below = function
  | "world/world" -> Some "layers" | kind when is_world_kind kind -> Some "below" | _ -> None

(* The layer network of the layers (bottom first); ids come from [previous] by home, else by label. *)
let layer_network ?previous ~homes layers =
  let old = match previous with Some (n : Document.network) -> n.graph.geometry | None -> Edit.empty in
  let* graph, _, below, made = List.fold_left (fun state call ->
    let* graph, used, below, made = state in
    let factory = List.assoc call.kind world_kinds in
    let label = Option.value (label_arg call.args) ~default:(Edit.factory_label factory) in
    let operation = Edit.factory_operation factory in
    let* node = flow (Edit.instantiate_optional factory [ None ]) in
    let* node = match find_claim old used operation ~home:call.home ~label homes with
      | Some id -> flow (Node.Private.restore_id id node)
      | None -> Ok node in
    let node = Node.relabel label node in
    let* graph = flow (Edit.add_node ~factory ~inputs:[| None |] node graph) in
    let* graph = match below with
      | Some below -> flow (Edit.connect ~source:below ~consumer:(Node.id node) ~input_index:0 graph)
      | None -> Ok graph in
    let* values = changes call.kind call.args in
    let* graph = apply factory graph (Node.id node) values in
    Ok (graph, Node.id node :: used, Some (Node.id node), (Node.id node, call.home) :: made))
    (Ok (Edit.empty, [], None, [])) layers in
  Ok (Document.of_geometry ~context:Flow.Context.World graph below, List.rev made)

(* ---- the editor ---- *)

module Panels = Editor_core.Panels

type editor = { tree : Panels.t; origins : (Panels.path * Document.origin) list;
                named : string option; wires : string option; viewports : (string * E.value) list;
                preview_sources : (string * Document.preview_source) list;
                switch : Document.switch option }

let viewport_key path = "v" ^ String.concat "." (List.map string_of_int path)

(* The tree of a [ui/workspace] value, with the graph a [ui/graph] names and the scene
   of each viewport; the origins come from walking the terms beside the values. *)
let panel_tree root =
  let graph = ref None and wires = ref None and viewports = ref [] and switch = ref None in
  let arg name args = match List.assoc_opt name args with
    | Some v -> Ok v | None -> Error (diag "E_LOWER" ("A panel is missing its " ^ name ^ ".")) in
  let axis = function E.Text "vertical" -> `V | _ -> `H in
  let rec go path = function
    | E.Struct ("ui/viewport", args) ->
        let key = viewport_key (List.rev path) in
        let* scene = arg "scene" args in
        viewports := (key, scene) :: !viewports; Ok (Panels.Leaf (Panels.View key))
    | E.Struct ("ui/graph", args) ->
        (match List.assoc_opt "graph" args with
         | Some (E.Text name) when !graph = None -> graph := Some name | _ -> ());
        (match List.assoc_opt "wires" args with
         | Some (E.Text w) when !wires = None -> wires := Some w | _ -> ());
        Ok (Leaf Graph)
    | E.Struct ("ui/inspector", _) -> Ok (Leaf Inspector)
    | E.Struct ("ui/outline", _) -> Ok (Leaf Outline)
    | E.Struct ("ui/list", _) -> Ok (Leaf List)
    | E.Struct ("ui/lisp", _) -> Ok (Leaf Lisp)
    | E.Struct ("ui/timeline", _) -> Ok (Leaf Timeline)
    | E.Struct (("ui/split" | "ui/split-at") as kind, args) ->
        let* first = arg "first" args in
        let* second = arg "second" args in
        let* a = go (0 :: path) first in
        let* b = go (1 :: path) second in
        let ratio = match List.assoc_opt "ratio" args with
          | Some (E.Float r) -> r | Some (E.Int n) -> float_of_int n | _ -> 0.5 in
        ignore kind;
        Ok (Panels.Split { axis = axis (Option.value (List.assoc_opt "axis" args) ~default:(E.Text "horizontal"));
                           ratio; a; b })
    | E.Struct ("ui/tile", args) ->
        let* cells = List.fold_left (fun acc (i, (_, v)) ->
          let* acc = acc in let* c = go (i :: path) v in Ok (c :: acc)) (Ok [])
          (List.mapi (fun i a -> i, a) args) in
        Ok (Panels.Tile (List.rev cells))
    | E.Struct ("ui/floating", args) ->
        let* p = arg "panel" args in
        let* t = go (0 :: path) p in Ok (Panels.Float t)
    (* a switch is transparent: its active layout sits at the switch's own place in the tree, and
       a layout that is not showing registers nothing but its shape *)
    | E.Struct ("ui/switch", args) ->
        let active = match List.assoc_opt "active" args with Some (E.Int n) -> n | _ -> 0 in
        let first = !switch = None in
        if first then switch := Some { Document.layouts = []; active };
        let kids = List.filter_map (fun (n, v) -> if n = "active" then None else Some v) args in
        let* trees = List.fold_left (fun acc (i, kid) ->
          let* acc = acc in
          let saved = !graph, !wires, !viewports in
          let* tree = go path kid in
          if i <> active then (let g, w, v = saved in graph := g; wires := w; viewports := v);
          Ok (tree :: acc)) (Ok []) (List.mapi (fun i k -> i, k) kids) in
        let trees = List.rev trees in
        if first then switch := Some { Document.layouts = trees; active };
        Ok (List.nth trees active)
    | _ -> Error (diag "E_LOWER" "The editor graph returns a (ui/workspace ...) of panels.") in
  let* tree = go [] root in
  let* () = Result.map_error (diag "E_RANGE") (Panels.valid tree) in
  Ok (tree, !graph, !wires, List.rev !viewports, !switch)

(* Which panels are named: the terms of the graph beside its value. *)
let origins (graph : W.graph) value =
  let bindings, result = match graph.body.node with
    | W.Let (bs, r) -> bs, r | _ -> [], graph.body in
  let env = List.filter_map (fun (p, t) -> match p with W.Name n -> Some (n, t) | _ -> None) bindings in
  let found = ref [] in
  let add path o = found := (List.rev path, o) :: !found in
  (* a panel that is not a name is written in place: the argument [key] of the call around it *)
  let inline home path key (t : W.term) = match t.node with
    | W.Ref_binding (_, []) | W.Loop _ -> ()
    | _ -> add path (Document.Inline (home, key)) in
  let rec walk place path (t : W.term) (v : E.value) =
    let here () = match t.path, place with
      | Some p, _ -> Document.Bound_at p
      | None, Some (parent, key) -> Document.Inline_in (parent, key)
      | None, None -> Document.Looped in
    let pos i = Flow_sop.Flow_edit.Pos i in
    match t.node, v with
    | W.Ref_binding (n, []), _ ->
        add path (Document.Bound n);
        Option.iter (fun t' -> walk None path t' v) (List.assoc_opt n env)
    | W.Op { op = "ui/workspace"; args = [ _, r ]; _ }, E.Struct (_, [ _, rv ]) ->
        let h = here () in
        inline h path (pos 0) r;
        walk (Some (h, pos 0)) path r rv
    | W.Op { op = "ui/split" | "ui/split-at"; args; _ }, E.Struct (_, vargs) ->
        let h = here () in
        List.iteri (fun i key -> match List.assoc_opt key args, List.assoc_opt key vargs with
          | Some a, Some va ->
              let k = pos (Option.get (List.find_index (fun (n, _) -> n = key) args)) in
              inline h (i :: path) k a;
              walk (Some (h, k)) (i :: path) a va
          | _ -> ()) [ "first"; "second" ]
    | W.Op { op = "ui/switch"; args; _ }, E.Struct (_, vargs) ->
        (* transparent: the active layout is found at the switch's own path *)
        let h = here () in
        let layouts l = List.filter (fun (n, _) -> n <> "active") l in
        let active = match List.assoc_opt "active" vargs with Some (E.Int n) -> n | _ -> 0 in
        (match List.nth_opt (layouts args) active, List.nth_opt (layouts vargs) active with
         | Some (_, a), Some (_, va) ->
             inline h path (pos active) a;
             walk (Some (h, pos active)) path a va
         | _ -> ())
    | W.Op { op = "ui/floating"; args = [ _, a ]; _ }, E.Struct (_, [ _, va ]) ->
        let h = here () in
        inline h (0 :: path) (pos 0) a;
        walk (Some (h, pos 0)) (0 :: path) a va
    | W.Op { op = "ui/tile"; args; _ }, E.Struct (_, vargs) ->
        let h = here () in
        if List.exists (fun (_, (a : W.term)) -> match a.node with W.Loop _ -> true | _ -> false) args
        then begin
          let key = pos (Option.get (List.find_index (fun (_, (a : W.term)) ->
            match a.node with W.Loop _ -> true | _ -> false) args)) in
          List.iteri (fun i _ -> add (i :: path) (Document.Loop (h, key))) vargs
        end
        else List.iteri (fun i (_, a) ->
          inline h (i :: path) (pos i) a;
          Option.iter (walk (Some (h, pos i)) (i :: path) a) (List.nth_opt (List.map snd vargs) i)) args
    | _ -> () in
  walk None [] result value;
  !found

let editor (workspace : Workspace_doc.t) (plan : E.plan) =
  let* value = result ~force:false workspace plan Flow.Workspace.Editor in
  match value with
  | None -> Ok None
  | Some (E.Struct ("ui/workspace", [ _, root ]) as whole) ->
      let* tree, graph, wires, viewports, switch = panel_tree root in
      let g = Option.get (Workspace_doc.editor_graph workspace) in
      let origins = origins g whole in
      let leaves = Panels.leaves tree |> List.filter_map (function
        | path, Panels.View key -> Some (path, key, List.assoc_opt path origins) | _ -> None) in
      (* ponytail: quadratic uniqueness scan over viewport leaves; use name
         counts if large layouts beyond the 16-renderer limit need it. *)
      let keys = List.map (fun (_, old, origin) ->
        let key = match origin with
          | Some (Document.Bound name) when List.length (List.filter (fun (_, _, o) -> o = origin) leaves) = 1 ->
              Printf.sprintf "v:%S/%S" g.name name
          | _ -> old in
        old, key) leaves in
      let key old = List.assoc old keys in
      let rec remap = function
        | Panels.Leaf (View old) -> Panels.Leaf (View (key old))
        | Leaf p -> Leaf p
        | Split s -> Split {s with a = remap s.a; b = remap s.b}
        | Tile cells -> Tile (List.map remap cells)
        | Float panel -> Float (remap panel) in
      let rec authored = function
        | Document.Bound_at path -> F.arg_text workspace.source path F.Whole
        | Inline_in (home, arg) -> Option.bind (authored home) (fun form -> F.arg_of form arg)
        | Copy _ | Looped -> None in
      let preview_sources = List.map (fun (_, old, origin) ->
        let panel_form = match origin with
          | Some (Document.Bound name) -> F.arg_text workspace.source [g.name; name] F.Whole
          | Some (Inline (home, arg)) -> Option.bind (authored home) (fun form -> F.arg_of form arg)
          | Some (Loop _) | None -> None in
        key old, {Document.editor_graph = g.name; panel = origin;
          scene_ref = Option.bind panel_form (fun form -> F.arg_of form (F.Pos 0));
          instance = List.assoc old viewports}) leaves in
      Ok (Some { tree = remap tree; origins; named = graph; wires;
        viewports = List.map (fun (old, scene) -> key old, scene) viewports; preview_sources; switch })
  | Some _ -> Error (diag "E_LOWER" "The editor graph returns a (ui/workspace ...).")

(* ---- the document of a workspace ---- *)

(* A network the previous document already has, field for field, is kept physically: a
   gesture that moves a scene object does not look like an edit of its geometry, so nothing
   re-prepares or recooks. *)
let same_network (a : Document.network) (b : Document.network) =
  let summary (n : Document.network) = List.map (fun (i : Edit.node_info) ->
    i.id, i.operation, i.label, i.bypass, i.inputs,
    List.map (fun (f : Param.field_view) -> f.name, f.current) (Node.parameter_fields i.node))
    (Edit.inspect n.graph.geometry) in
  a.context = b.context && a.displayed = b.displayed
  && (a.graph.drives == b.graph.drives || Flow_sop.Port.Map.is_empty a.graph.drives && Flow_sop.Port.Map.is_empty b.graph.drives)
  && Edit.root a.graph.geometry = Edit.root b.graph.geometry
  && summary a = summary b

(* One geometry object per geometry item beside the sketch's own objects, the World
   of a world graph, the settings of a settings graph.  [previous] keeps object ids
   (matched by home, then by operation and label), tile layouts and the objects the
   workspace does not declare (the host's camera and lights): the workspace owns geometry
   always, every object when it has a scene graph (an empty one means none), and the World
   when it has a world graph ([world/none] means none).  Whatever a declared object's text
   does not say is the schema's default, so the text is the whole truth of it. *)
let of_workspace ~factories ?previous (workspace : Workspace_doc.t) =
  let compiled_ids, sites = match previous with
    | Some (doc : Document.t) ->
        let _, (lowered : Flow_sop.Lower.t) = doc.workspace in
        Some lowered.compiled_ids, Some lowered.sites
    | None -> None, None in
  let old_homes = match previous with Some doc -> doc.Document.homes | None -> Document.no_homes in
  let* lowered = Flow_sop.Lower.workspace ~factories ~extra:descriptors ?compiled_ids ?sites
      workspace.source in
  let* () = check_context_time workspace lowered.plan in
  let* () = check_scene workspace lowered.plan in
  let* items, root = items workspace lowered in
  (* a viewport over another instance of the scene draws objects of its own *)
  let* editor = editor workspace lowered.plan in
  let* default_scene = result ~force:false workspace lowered.plan Flow.Workspace.Scene in
  (* a viewport's own scene draws its objects; its root and World are not the document's *)
  let objects_only calls = List.filter (fun (c : call) -> c.kind <> "scene/root" && c.kind <> "scene/world") calls in
  let default_calls = objects_only (Option.fold ~none:[] ~some:scene_calls default_scene) in
  let* aux = List.fold_right (fun (key, scene) rest ->
    let* rest = rest in
    let calls = objects_only (scene_calls scene) in
    if Option.fold ~none:false ~some:(( == ) scene) default_scene
       || (try List.map (fun c -> c.kind, c.args) calls
                          = List.map (fun c -> c.kind, c.args) default_calls
                      with Invalid_argument _ -> false) then Ok rest
    else
      let* extra = List.fold_right (fun call rest ->
        let* rest = rest in let* item = item_of lowered call in
        Ok ({ item with label = Printf.sprintf "%s (%s)" item.label key; group = Some key } :: rest))
        calls (Ok []) in
      Ok ((key, extra) :: rest))
    (Option.fold ~none:[] ~some:(fun e -> e.viewports) editor) (Ok []) in
  (* a viewport over an instance that names another World shows that one (or none) *)
  let world_calls scene = List.filter (fun (c : call) -> c.kind = "scene/world") (scene_calls scene) in
  let same_calls a b = try List.map (fun (c : call) -> c.kind, c.args) a = List.map (fun (c : call) -> c.kind, c.args) b
    with Invalid_argument _ -> false in
  let default_worlds = Option.fold ~none:[] ~some:world_calls default_scene in
  let* view_worlds = List.fold_right (fun (key, scene) rest ->
    let* rest = rest in
    let own = world_calls scene in
    if default_scene = None || Option.fold ~none:false ~some:(( == ) scene) default_scene
       || same_calls own default_worlds then Ok rest
    else match own with
      | [] -> Ok ((key, None) :: rest)
      | call :: _ ->
          let* item = item_of lowered call in
          (* the instance is a value: the world graph it references is the call's [world] argument *)
          let stack = match List.assoc_opt "world" call.args with
            | Some layers -> loose ~want:is_world_kind ~below:world_below layers
            | None -> [] in
          let* graph, id = add_node Edit.empty item.factory item.label in
          let* graph = apply item.factory graph id item.values in
          let* layers, _ = layer_network ~homes:[] stack in
          (match Edit.find graph ~node_id:id with
           | Some node -> Ok ((key, Some { Document.node; layers }) :: rest)
           | None -> Error (diag "E_LOWER" "The World of a viewport could not be built.")))
    (Option.fold ~none:[] ~some:(fun e -> e.viewports) editor) (Ok []) in
  let primary = List.length items in
  let items = items @ List.concat_map snd aux in
  let scene = match previous with
    | Some (doc : Document.t) -> doc.scene
    | None -> Document.of_geometry ~context:Flow.Context.Scene Edit.empty None in
  (* a scene graph is authoritative for every object kind: what it does not say is not there
     (no camera, no lights), and the host seeds nothing *)
  let has_scene = graph_of workspace Flow.Workspace.Scene <> None in
  let has_world = graph_of workspace Flow.Workspace.World <> None in
  (* the World is a merge member ([scene/world]); an old file's world graph returning a
     [world/world] call is read as the scene's World, written where it is *)
  let scene_world = List.find_opt (fun item -> item.group = None && Edit.factory_operation item.factory = "world") items in
  let owned operation = operation = "geometry"
    || (has_scene && (operation <> "world" || scene_world <> None)) in
  let* world, layers, orphan = if scene_world <> None then Ok (None, [], false) else
    let* stack = calls ~want:is_world_kind ~below:world_below workspace lowered.plan Flow.Workspace.World in
    match List.rev stack with
    | [] -> Ok (None, [], false)
    | { kind = "world/world"; _ } as world :: layers -> Ok (Some world, List.rev layers, false)
    | _ -> Ok (None, [], true)  (* layers no [scene/world] references: the scene has no World of it *) in
  (* claim or create a node per item, then drop the owned nodes nothing claimed *)
  let* graph, used, objects = List.fold_left (fun state item ->
    let* graph, used, objects = state in
    let operation = Edit.factory_operation item.factory in
    let home = if item.group = None then item.home else Document.Looped in
    match find_claim graph used operation ~home ~label:item.label old_homes.objects with
    | Some id ->
        let* graph = relabel graph id item.label in
        let* graph = apply item.factory graph id item.values in
        Ok (graph, id :: used, (id, item) :: objects)
    | None ->
        let* graph, id = add_node graph item.factory item.label in
        let* graph = apply item.factory graph id item.values in
        Ok (graph, id :: used, (id, item) :: objects))
    (Ok (scene.graph.geometry, [], [])) items in
  let objects = List.rev objects in
  let views = List.rev (fst (List.fold_left (fun (views, from) (key, extra) ->
    let n = List.length extra in
    (key, List.filteri (fun i _ -> i >= from && i < from + n) (List.map fst objects)) :: views, from + n)
    ([], primary) aux)) in
  let stale = List.filter_map (fun (info : Edit.node_info) ->
    if owned info.operation && not (List.mem info.id used)
    then Some info.id else None) (Edit.inspect graph) in
  let graph = Edit.remove_nodes stale graph in
  let* graph = link_parents graph objects in
  (* the World node *)
  let* graph, world_id, world_network, layer_homes = match world with
    | None when scene_world <> None ->
        (* the node the objects made; its layers are the referenced world graph's *)
        let id, item = List.find (fun (_, (item : item)) ->
          item.group = None && Edit.factory_operation item.factory = "world") objects in
        let* named = match item.via with
          | Some name -> Ok name
          | None -> Error (diag "E_LOWER" "A scene/world references a world graph: (scene/world (ref sky)).") in
        let* stack = match graph_of_name workspace named with
          | Some g -> graph_calls ~want:is_world_kind ~below:world_below lowered.plan W.World g
          | None -> Error (diag "E_LOWER" (Printf.sprintf "scene/world references %s, which is not a world graph." named)) in
        let previous_network = Option.bind previous (fun (doc : Document.t) ->
          Document.Int_map.find_opt id doc.networks) in
        let* network, made = layer_network ?previous:previous_network ~homes:old_homes.layers stack in
        Ok (graph, Some id, Some network, made)
    | None ->
        (* a world graph that returns no World removes the host's *)
        let gone = if has_world && not orphan then Objects.ids "world" graph else [] in
        Ok (Edit.remove_nodes gone graph, None, None, [])
    | Some { args; home; _ } ->
        let factory = Layers.Settings.factory in
        let label = Option.value (label_arg args) ~default:"World" in
        let existing = List.find_map (fun (i : Edit.node_info) ->
          if i.operation = "world" then Some i.id else None) (Edit.inspect graph) in
        let claimed = match existing with
          | Some id when old_homes.world = Some home || find_node graph [] "world" label <> None -> Some id
          | _ -> None in
        let* graph, id = match claimed with
          | Some id -> Ok (graph, id)
          | None ->
              let old = List.filter (fun (info : Edit.node_info) -> info.operation = "world")
                  (Edit.inspect graph) in
              let graph = Edit.remove_nodes (List.map (fun (info : Edit.node_info) -> info.id) old) graph in
              add_node graph factory label in
        let* values = changes "world/world" args in
        let* graph = apply factory graph id values in
        let previous_network = Option.bind previous (fun (doc : Document.t) ->
          Document.Int_map.find_opt id doc.networks) in
        let* network, made = layer_network ?previous:previous_network ~homes:old_homes.layers layers in
        Ok (graph, Some id, Some network, made) in
  let* scene_network = Flow_sop.Network.with_geometry graph scene.graph in
  let first = match objects with (id, _) :: _ -> Some id | [] -> None in
  let scene = { scene with graph = scene_network;
    displayed = (match scene.displayed with
      | Some id when Edit.find graph ~node_id:id <> None -> Some id | _ -> first) } in
  (* networks: geometry objects' lowered graphs, the World's layers, and the previous
     networks of objects that survive *)
  let carried = match previous with
    | None -> Document.Int_map.empty
    | Some (doc : Document.t) -> Document.Int_map.filter (fun id _ ->
        Edit.find graph ~node_id:id <> None && not (List.mem_assoc id objects)
        && Some id <> world_id) doc.networks in
  let networks = List.fold_left (fun networks (id, item) ->
    if Edit.factory_operation item.factory <> "geometry" then networks
    else
      let network = match item.geometry with
        | Some g -> { Document.context = Flow.Context.Sop; graph = g.network; displayed = g.root }
        | None -> { Document.context = Flow.Context.Sop;
                    graph = Flow_sop.Network.of_geometry Edit.empty; displayed = None } in
      Document.Int_map.add id network networks) carried objects in
  let networks = match world_id, world_network with
    | Some id, Some network -> Document.Int_map.add id network networks
    | _ -> networks in
  let networks = match previous with
    | None -> networks
    | Some (doc : Document.t) -> Document.Int_map.mapi (fun id network ->
        match Document.Int_map.find_opt id doc.networks with
        | Some old when same_network old network -> old
        | _ -> network) networks in
  let* settings_calls = calls ~want:(fun k -> k = "settings/config") ~below:no_below workspace
      lowered.plan Flow.Workspace.Settings in
  let* settings = match settings_calls with
    | { kind; args; _ } :: _ -> settings_of (E.Struct (kind, args))
    | [] -> Ok workspace.settings in
  let cameras = List.filter (fun id -> not (List.exists (fun (_, ids) -> List.mem id ids) views))
    (Objects.ids "camera" graph) in
  let active_camera =
    match List.find_opt (fun (id, item) -> item.active && item.group = None && List.mem id cameras) objects with
    | Some (id, _) -> Some id
    | None when has_scene -> List.nth_opt cameras 0
    | None ->
        (match Option.bind previous (fun (doc : Document.t) -> doc.active_camera) with
         | Some id when List.mem id cameras -> Some id
         | _ -> None) in
  let workspace = if has_settings workspace then workspace
    else { workspace with Workspace_doc.settings } in
  let homes = { Document.objects = List.filter_map (fun (id, item) ->
      Some (id, if item.group = None then item.home else Document.Looped)) objects;
    world = (match scene_world with
      | Some item -> Some item.home | None -> Option.map (fun (c : call) -> c.home) world);
    layers = layer_homes; root = root.root_home;
    world_graph = Option.bind scene_world (fun item -> item.via);
    settings = (match settings_calls with (c : call) :: _ -> Some c.home | [] -> None) } in
  let scene_drives = List.fold_left (fun drives (id, item) -> match item.drives with
    | None -> drives | Some drive -> Document.Int_map.add id drive drives)
    Document.Int_map.empty objects in
  Ok { Document.scene; networks; active_camera; root = root.params; settings; scene_drives;
       shell = Option.map (fun e -> { Document.tree = e.tree; origins = e.origins;
                                      named = e.named; wires = e.wires; views; preview_sources = e.preview_sources;
                                      switch = e.switch }) editor;
       view_worlds; homes; workspace = (workspace, lowered) }

(* Only the recorded live fields run; SOP networks, source and panel identities
   stay untouched. Errors leave the caller's last successful picture available. *)
let resolve_scene ?previous (document : Document.t) ~time =
  let graph, errors = Document.Int_map.fold (fun id (kind, args) (graph, errors) ->
    let resolve () =
      let* values = List.fold_left (fun result (parameter, value) ->
        let* values = result in
        let* value = E.force value ~live:{E.t = time} in
        let* next = Flow_sop.Lower.changes parameter value in
        Ok (values @ next)) (Ok []) args in
      flow (Edit.apply_parameters graph ~node_id:id values) |> Result.map fst in
    match resolve () with
    | Ok graph -> graph, errors
    | Error error ->
        let graph = match Option.bind previous (fun graph -> Edit.find graph ~node_id:id) with
          | Some node -> Result.value ~default:graph (Edit.replace_node node graph)
          | None -> graph in
        let views = Option.fold ~none:[] ~some:(fun shell ->
          List.filter_map (fun (key, ids) -> if List.mem id ids then Some key else None)
            shell.Document.views) document.shell in
        let view = if views = [] then "primary" else String.concat ", " views in
        let error = diag "E_CONTEXT_LIVE"
          (Printf.sprintf "%s #%d [%s] (%s): %s (last successful light retained)" kind id view
            (String.concat ", " (List.map (fun (parameter, _) -> parameter.Flow_sop.Port.path) args))
            (Flow.Diagnostic.to_string error)) in
        graph, error :: errors)
    document.scene_drives (document.scene.graph.geometry, []) in
  graph, List.rev errors

let sha256 s = Digestif.SHA256.(to_hex (digest_string s))

let catalog_digest factories =
  sha256 (match Flow_sop.Manifest.generate ~extra:descriptors factories with
    | Ok (text, _) -> text
    | Error d -> Flow.Diagnostic.to_string d)
