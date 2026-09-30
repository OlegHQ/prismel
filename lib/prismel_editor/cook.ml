open Prismel
open Procedural
open Editor_document

type bounds = Vec3.t * Vec3.t

(* One geometry object's latest cook: its displayed SOP graph, the sketch's
   prepared value, and bounds in the object's own space. *)
type 'prepared piece = {
  id : int;
  graph : Graph.t;
  prepared : 'prepared;
  bounds : bounds option;
  settings : Settings.t;
  context : string;  (* projection of the graph's declared context dependencies *)
  output : Session.output;  (* what [prepared] was made from, before the tint *)
  lit : Pick.Set.t;  (* the provenance tags [prepared] highlights, see {!Pick} *)
  surface : Pdk.Surface_index.t option Lazy.t;  (* built by the first click *)
}

(* What a footer shows of a geometry value: its object and compiled node. *)
type summary = (int * int) * Flow_sop.Probe.geometry

type 'prepared cooked =
  | Displayed of 'prepared piece list * summary list
  | Framed of bounds option

type flattened = {
  source : Flow_sop.Network.t;
  displayed : int;
  definitions : Document.definition Document.String_map.t;
  compiled_ids : int Flow_sop.Instance_path.Map.t;
  result : (Flow_sop.Network.t * int, Flow.Diagnostic.t) result;
}

type 'prepared t = {
  worker : 'prepared cooked Async_cook.t;
  seed : int64;
  grain : int;
  domains : int;
  await : bool;  (* block on each cook: fixed-step runs, see [create] *)
  schedule : Schedule.t;
  prepare : Settings.t -> Session.output -> ('prepared, string) result;
  pieces : 'prepared piece list;
  settings : Settings.t option;  (* the latest desired submission settings *)
  error : string option;
  seconds : float option;
  (* A framing job can supersede a display cook that must be resubmitted. *)
  framing : bool option;
  force : bool;
  (* Each object's last compiled network, reused node-by-node on the next
     edit, and this frame's displayed graphs. *)
  compiled : (Edit_graph.t * Edit_graph.compiled) Document.Layout.t;
  flattened : flattened Document.Layout.t;
  value_lanes : Flow_sop.Value_lane.t Document.Layout.t;
  applied : Flow_sop.Value_lane.resolved Document.Layout.t;
  graphs : (int * Graph.t) list;
  displayed : (int * int) list;  (* the display node each graph compiles *)
  probing : (int * int) list;  (* the (object, node) pairs the last submission asked to summarise *)
  summaries : summary list;
}

type 'prepared update = {
  cook : 'prepared t;
  edit_error : string option;
  prepared_changed : bool;
  framed : bounds option option;
}

let geometry_bounds geometry =
  let points = Pdk.Geometry.positions geometry in
  let count = Pdk.Packed.Float3.length points in
  if count = 0 then None else begin
    let x, y, z = Pdk.Packed.Float3.get points 0 in
    let lo = [| x; y; z |] and hi = [| x; y; z |] in
    for index = 1 to count - 1 do
      let x, y, z = Pdk.Packed.Float3.get points index in
      lo.(0) <- Float.min lo.(0) x; lo.(1) <- Float.min lo.(1) y;
      lo.(2) <- Float.min lo.(2) z; hi.(0) <- Float.max hi.(0) x;
      hi.(1) <- Float.max hi.(1) y; hi.(2) <- Float.max hi.(2) z
    done;
    Some (Vec3.create lo.(0) lo.(1) lo.(2), Vec3.create hi.(0) hi.(1) hi.(2))
  end

(* A packed output's bounds: the prototype's box at every instance. *)
let output_bounds (output : Session.output) =
  match geometry_bounds output.geometry, output.instances with
  | None, _ | _, (None | Some [||]) as bounds -> fst bounds
  | Some (lo, hi), Some transforms ->
      let lower = ref (Vec3.create infinity infinity infinity)
      and upper = ref (Vec3.create neg_infinity neg_infinity neg_infinity) in
      Array.iter (fun matrix ->
        for corner = 0 to 7 do
          let p = Mat4.transform_point matrix (Vec3.create
              (if corner land 1 = 0 then lo.Vec3.x else hi.Vec3.x)
              (if corner land 2 = 0 then lo.y else hi.y)
              (if corner land 4 = 0 then lo.z else hi.z)) in
          lower := Vec3.create (Float.min !lower.x p.x) (Float.min !lower.y p.y)
              (Float.min !lower.z p.z);
          upper := Vec3.create (Float.max !upper.x p.x) (Float.max !upper.y p.y)
              (Float.max !upper.z p.z)
        done) transforms;
      Some (!lower, !upper)

(* [await]: a fixed-step run (export, PRISMEL_MAX_FRAMES, tests) must show the
   geometry of exactly frame n, so [update] waits for the cook it submitted;
   interactive play never blocks (latest request wins). ponytail: the default
   reads PRISMEL_MAX_FRAMES because [Frame.t] does not say the clock is fixed;
   an export host passes [~await:true]. *)
let create ~prepare ~seed ~grain ?domains ?await ~max_entries ~max_payload_bytes () =
  let await = match await with Some flag -> flag
    | None -> Sys.getenv_opt "PRISMEL_MAX_FRAMES" <> None in
  if grain <= 0 then invalid_arg "Prismel_editor: grain must be positive";
  let domains = Option.value ~default:
      (max 1 (Parallel.recommended_domains () - 1)) domains in
  if domains <= 0 then invalid_arg "Prismel_editor: domains must be positive";
  Result.map (fun worker ->
    { worker; seed; grain; domains; await; prepare; schedule = Schedule.initial;
      pieces = []; settings = None; error = None; seconds = None;
      framing = None; force = false; compiled = Document.Layout.empty;
      flattened = Document.Layout.empty; graphs = [];
      value_lanes = Document.Layout.empty; applied = Document.Layout.empty;
      displayed = []; probing = []; summaries = [] })
    (Async_cook.create ~max_entries ~max_payload_bytes)

let status value = Async_cook.status value.worker

(* [Lower.is_volatile] of the current lowering: the nodes that recook per frame. *)
let set_volatile value predicate = Async_cook.set_volatile value.worker predicate
let stats value = Async_cook.stats value.worker
let seconds value = value.seconds
let pieces value = value.pieces
(* the counts of a compiled node of an object, once a cook has reported them *)
let geometry value ~object_id ~node_id = List.assoc_opt (object_id, node_id) value.summaries
let applied value id = Document.Layout.find_opt id value.applied

let context value timeline = Sketch_support.Timeline.context ~seed:value.seed
    ~grain:value.grain ~domains:value.domains timeline

let busy value = match status value with
  | Async_cook.Idle -> false | Cooking _ -> true
let force value = { value with force = true }

(* [objects] are the visible geometry objects as (id, network graph,
   display node); [frame_request] is (object, node) to frame. *)
let flatten ~definitions ~compiled_ids network displayed =
  let geometry = Result.map_error (Flow.Diagnostic.error ~code:"E_GEOMETRY")
    (Edit_graph.set_root displayed network.Flow_sop.Network.geometry) in
  Result.bind geometry (fun geometry ->
    Result.bind (Flow_sop.Network.with_geometry geometry network) (fun network ->
      let definitions = Document.String_map.fold (fun name definition values ->
        Flow_sop.Network.String_map.add name definition.Document.spec values)
        definitions Flow_sop.Network.String_map.empty in
      Result.bind (Flow_sop.Compile.flatten ~allocate:false ~definitions
        ~compiled_ids network) (fun (network, _) ->
          match Edit_graph.root network.geometry with
          | Some displayed -> Ok (network, displayed)
          | None -> Error (Flow.Diagnostic.error ~code:"E_INTERFACE"
              "Compound display has no geometry output"))))

let update ?live ?(probes = []) ?(lit = Pick.Set.empty) ~definitions ~compiled_ids value ~settings ~objects
    ~edit_error ~effects ~timeline_changes
    ~timeline ~frame ~frame_request =
  let objects, value_lanes, applied, flattened, resolve_error =
    List.fold_left (fun (objects, lanes, applied, flattened, error)
        (id, (network : Flow_sop.Network.t), displayed) ->
      let lane = match Document.Layout.find_opt id value.value_lanes with
        | Some lane -> lane | None -> Flow_sop.Value_lane.create () in
      let lanes = Document.Layout.add id lane lanes in
      let flat, flattened =
        if Flow_sop.Network.Int_map.is_empty network.instances then
          Ok (network, displayed), flattened
        else match Document.Layout.find_opt id value.flattened with
          | Some previous when previous.source == network
              && previous.displayed = displayed
              && previous.definitions == definitions
              && previous.compiled_ids == compiled_ids ->
              previous.result, Document.Layout.add id previous flattened
          | _ ->
              let result = flatten ~definitions ~compiled_ids network displayed in
              let entry = {source = network; displayed; definitions;
                compiled_ids; result} in
              result, Document.Layout.add id entry flattened in
      match Result.bind flat (fun (network, displayed) ->
        Result.map (fun resolved -> resolved, displayed)
          (Flow_sop.Value_lane.resolve lane
            ~time:(Sketch_support.Timeline.time timeline) network)) with
      | Ok (resolved, displayed) -> (id, resolved.geometry, displayed) :: objects,
          lanes, Document.Layout.add id resolved applied, flattened, error
      | Error diagnostic ->
          let previous = Document.Layout.find_opt id value.applied in
          let objects = match previous with
            | Some previous -> (id, previous.geometry, displayed) :: objects
            | None -> objects in
          let applied = match previous with
            | Some previous -> Document.Layout.add id previous applied
            | None -> applied in
          objects, lanes, applied, flattened,
          Some (Flow.Diagnostic.to_string diagnostic))
      ([], Document.Layout.empty, Document.Layout.empty,
        Document.Layout.empty, None) objects in
  let objects = List.rev objects in
  let edit_error = match edit_error with Some _ -> edit_error
    | None -> resolve_error in
  let compiled = List.fold_left (fun compiled (id, document, _) ->
      match Document.Layout.find_opt id value.compiled with
      | Some (source, _) when source == document -> compiled
      | previous -> Document.Layout.add id (document,
          Edit_graph.compile_all ?previous:(Option.map (fun (_, c) -> c) previous) document)
          compiled) value.compiled objects in
  let compiled = Document.Layout.filter (fun id _ ->
      List.exists (fun (object_id, _, _) -> object_id = id) objects) compiled in
  (* An unchanged network and display node keep their graph physically, so
     an idle frame never looks like an edit and never resubmits a cook. *)
  let graphs, edit_error = List.fold_left (fun (graphs, error) (id, document, displayed) ->
      let unchanged = match Document.Layout.find_opt id value.compiled with
        | Some (source, _) -> source == document | None -> false in
      match List.assoc_opt id value.graphs, List.assoc_opt id value.displayed with
      | Some graph, Some previous when unchanged && previous = displayed ->
          (id, graph) :: graphs, error
      | previous, _ ->
          match Edit_graph.compiled_node (snd (Document.Layout.find id compiled))
              ~node_id:displayed with
          | Ok graph -> (id, graph) :: graphs, error
          | Error message ->
              (match previous with
               | Some graph -> (id, graph) :: graphs | None -> graphs),
              Some message) ([], edit_error) objects in
  let displayed = List.map (fun (id, _, displayed) -> id, displayed) objects in
  let graphs = List.rev graphs in
  let changed = not (List.equal (fun (a, g) (b, h) -> a = b && g == h) graphs value.graphs) in
  let completion = Async_cook.poll value.worker in
  let resume = value.framing = Some true in
  let summaries = ref value.summaries in
  let pieces, error, seconds, prepared_changed, framed, framing,
      force_next = match completion with
    | None -> value.pieces, value.error, value.seconds, false,
        None, value.framing, false
    | Some { Async_cook.result = Ok (Displayed (pieces, found)); seconds; _ } ->
        summaries := found;
        pieces, None, Some seconds, true, None, None, false
    | Some { result = Ok (Framed bounds); _ } ->
        value.pieces, value.error, value.seconds, false,
        Some bounds, None, resume
    | Some { result = Error _; _ } when value.framing <> None ->
        value.pieces, value.error, value.seconds, false,
        Some None, None, resume
    | Some { result = Error error; seconds; _ } ->
        value.pieces, Some (Async_cook.error_to_string error),
        Some seconds, false, None, None, false in
  (* Empty/removed objects have no current preview, including when a job
     from before the deletion completes. Invalid nonempty SOPs keep their
     last successful graph and preview through the compilation fallback. *)
  let pieces, prepared_changed =
    if (changed || Option.is_some completion)
        && List.exists (fun piece -> not (Document.Layout.mem piece.id compiled)) pieces
    then List.filter (fun piece -> Document.Layout.mem piece.id compiled) pieces, true
    else pieces, prepared_changed in
  let schedule, submit = Schedule.step ?live value.schedule
      ~graphs:(List.map snd graphs) ~effects
      ~context_changed:(Sketch_support.Timeline.changed_context timeline_changes)
      ~force:(changed || value.force || probes <> value.probing
        || not (Option.fold ~none:false ~some:(( == ) settings) value.settings))
      ~busy:(busy value || framing <> None) ~frame in
  (* Unchanged objects keep their prepared value: the worker only cooks
     (a session cache hit) and re-prepares what changed. *)
  let previous = pieces in
  (* the probed nodes are cooked after the displayed ones, so they are cache
     hits (or the volatile slots) of the display cook; only nodes upstream of
     the display are asked for, so a footer never fails the display *)
  let probed = if not submit then [] else List.filter_map (fun ((object_id, node_id) as key) ->
    Option.bind (List.assoc_opt object_id graphs) (fun graph ->
      Option.map (fun node -> key, node) (Graph.find graph ~node_id)))
    (List.filteri (fun i _ -> i < 64) probes) in
  let summary (key, _) (output : Session.output) =
    let g = output.geometry in
    key, { Flow_sop.Probe.prims = Pdk.Geometry.primitive_count g; data_id = Pdk.Geometry.data_id g;
           groups = List.sort_uniq compare (List.map Pdk.Group.name (Pdk.Geometry.groups g)) } in
  let prepare context outputs =
    let rec loop reversed graphs outputs = match graphs, outputs with
      | [], rest when List.length rest = List.length probed ->
          let found = List.map2 summary probed rest in
          Ok (Displayed (List.rev reversed, found))
      | (id, graph) :: graphs, (output : Session.output) :: outputs ->
          let projection = Context.cache_projection (Graph.dependencies graph) context in
          let reused = List.find_opt (fun piece -> piece.id = id && piece.graph == graph
              && piece.settings == settings && piece.context = projection
              && Pick.same_set piece.lit lit) previous in
          (match reused with
           | Some piece -> loop (piece :: reversed) graphs outputs
           | None ->
               Result.bind (value.prepare settings (Pick.tint output lit)) (fun prepared ->
                 loop ({ id; graph; prepared; output; lit;
                         surface = lazy (Pick.surface output.geometry);
                         bounds = output_bounds output; settings; context = projection } :: reversed)
                   graphs outputs))
      | _ -> Error "cook returned a different number of outputs" in
    loop [] graphs outputs in
  let error, framing = if submit then match
      Result.bind (context value timeline) (fun context ->
        Async_cook.submit_all value.worker ~context
          ~nodes:(List.map snd graphs @ List.map snd probed) ~prepare:(prepare context)) with
    | Ok _ -> None, None
    | Error message -> Some message, None
    else error, framing in
  (* A fixed-step run waits for the cook it just submitted. *)
  let pieces, error, seconds, prepared_changed =
    if submit && Option.is_none error && value.await then
      let awaited = Async_cook.await value.worker in
      match awaited.result with
      | Ok (Displayed (pieces, found)) ->
          summaries := found;
          List.filter (fun piece -> Document.Layout.mem piece.id compiled) pieces,
          None, Some awaited.seconds, true
      | Ok (Framed _) -> pieces, error, seconds, prepared_changed
      | Error failure -> pieces, Some (Async_cook.error_to_string failure),
          Some awaited.seconds, prepared_changed
    else pieces, error, seconds, prepared_changed in
  (* a piece prepared under another highlight is prepared again from its kept
     output: no recook, no lowering, and nothing when no tag is involved *)
  let retinted = ref false in
  let pieces = List.map (fun piece ->
    if Pick.same_set piece.lit lit then piece
    else if Pick.tags piece.output.geometry = None then { piece with lit }
    else match value.prepare piece.settings (Pick.tint piece.output lit) with
      | Ok prepared -> retinted := true; { piece with prepared; lit }
      | Error _ -> piece) pieces in
  let prepared_changed = prepared_changed || !retinted in
  let framed, framing = match frame_request with
    | None -> framed, framing
    | Some (object_id, node_id) ->
        match List.find_opt (fun piece -> piece.id = object_id) pieces,
            List.assoc_opt object_id graphs with
        | Some piece, Some graph when Node.id graph = node_id && piece.graph == graph
            && Result.fold ~ok:(fun context -> piece.context =
                Context.cache_projection (Graph.dependencies graph) context)
              ~error:(fun _ -> false) (context value timeline) ->
            Some piece.bounds, framing
        | _ ->
            (match Option.map (fun (_, compiled) ->
                Edit_graph.compiled_node compiled ~node_id)
                (Document.Layout.find_opt object_id compiled) with
             | None | Some (Error _) -> Some None, framing
             | Some (Ok node) ->
                 let was_busy = busy value && framing = None in
                 match Result.bind (context value timeline) (fun context ->
                     Async_cook.submit value.worker ~context ~node
                       ~prepare:(fun output ->
                         Ok (Framed (output_bounds output)))) with
                 | Ok _ -> framed, Some (was_busy || Option.value ~default:false framing)
                 | Error _ -> Some None, framing) in
  { cook = { value with schedule; pieces; settings = Some settings; error; seconds;
      framing; force = force_next; compiled; flattened;
      value_lanes; applied; graphs; displayed;
      probing = (if submit then probes else value.probing); summaries = !summaries };
    edit_error; prepared_changed; framed }

let close value = Async_cook.close value.worker

(* The nearest displayed primitive under a ray in the piece's own space, as (t, provenance tag)
   where the hit is [origin + t * direction]: the parameter, not the local distance, so hits of
   pieces and instances with any scale compare in the world's units.  A piece drawn as instances
   casts the ray into each instance's own frame (about 2 us each; per click, never per frame). *)
let pick piece ~origin ~direction =
  let cast ~origin ~direction =
    Option.map (fun (distance, tag) -> distance /. Vec3.length direction, tag)
      (Pick.cast (Lazy.force piece.surface) piece.output.geometry ~origin ~direction) in
  match piece.output.instances with
  | None | Some [||] -> cast ~origin ~direction
  | Some transforms ->
      Array.fold_left (fun best matrix -> match Mat4.inverse matrix with
        | None -> best
        | Some inverse ->
            match cast ~origin:(Mat4.transform_point inverse origin)
                ~direction:(Mat4.transform_direction inverse direction), best with
            | Some (t, _), Some (nearer, _) when t >= nearer -> best
            | (Some _ as hit), _ -> hit
            | None, _ -> best) None transforms
