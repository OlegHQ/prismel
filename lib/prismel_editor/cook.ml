open Prismel
open Procedural

type bounds = Vec3.t * Vec3.t

(* One geometry object's latest cook: its displayed SOP graph, the sketch's
   prepared value, and bounds in the object's own space. *)
type 'prepared piece = {
  id : int;
  graph : Graph.t;
  prepared : 'prepared;
  bounds : bounds option;
}

type 'prepared cooked =
  | Displayed of 'prepared piece list
  | Framed of bounds option

type 'prepared t = {
  worker : 'prepared cooked Async_cook.t;
  seed : int64;
  grain : int;
  domains : int;
  schedule : Schedule.t;
  prepare : Settings.t -> Session.output -> ('prepared, string) result;
  pieces : 'prepared piece list;
  prepared_with : Settings.t option;  (* the settings [pieces] saw *)
  error : string option;
  seconds : float option;
  (* A framing job can supersede a display cook that must be resubmitted. *)
  framing : bool option;
  force : bool;
  (* Each object's last compiled network, reused node-by-node on the next
     edit, and this frame's displayed graphs. *)
  compiled : (Edit_graph.t * Edit_graph.compiled) Document.Layout.t;
  graphs : (int * Graph.t) list;
  displayed : (int * int) list;  (* the display node each graph compiles *)
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

let create ~prepare ~seed ~grain ?domains ~max_entries ~max_payload_bytes () =
  if grain <= 0 then invalid_arg "Prismel_editor: grain must be positive";
  let domains = Option.value ~default:
      (max 1 (Parallel.recommended_domains () - 1)) domains in
  if domains <= 0 then invalid_arg "Prismel_editor: domains must be positive";
  Result.map (fun worker ->
    { worker; seed; grain; domains; prepare; schedule = Schedule.initial;
      pieces = []; prepared_with = None; error = None; seconds = None;
      framing = None; force = false; compiled = Document.Layout.empty; graphs = [];
      displayed = [] })
    (Async_cook.create ~max_entries ~max_payload_bytes)

let status value = Async_cook.status value.worker

let context value timeline = Sketch_support.Timeline.context ~seed:value.seed
    ~grain:value.grain ~domains:value.domains timeline

let busy value = match status value with
  | Async_cook.Idle -> false | Cooking _ -> true
let force value = { value with force = true }

(* [objects] are the visible geometry objects as (id, network graph,
   display node); [frame_request] is (object, node) to frame. *)
let update ?live value ~settings ~objects ~edit_error ~effects ~timeline_changes
    ~timeline ~frame ~frame_request =
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
  let pieces, prepared_with, error, seconds, prepared_changed, framed, framing,
      force_next = match completion with
    | None -> value.pieces, value.prepared_with, value.error, value.seconds, false,
        None, value.framing, false
    | Some { Async_cook.result = Ok (Displayed pieces); seconds; _ } ->
        pieces, Some settings, None, Some seconds, true, None, None, false
    | Some { result = Ok (Framed bounds); _ } ->
        value.pieces, value.prepared_with, value.error, value.seconds, false,
        Some bounds, None, resume
    | Some { result = Error _; _ } when value.framing <> None ->
        value.pieces, value.prepared_with, value.error, value.seconds, false,
        Some None, None, resume
    | Some { result = Error error; seconds; _ } ->
        value.pieces, value.prepared_with, Some (Async_cook.error_to_string error),
        Some seconds, false, None, None, false in
  (* Nothing visible to cook: the scene is simply empty. *)
  let pieces, prepared_changed = if graphs = [] && pieces <> []
    then [], true else pieces, prepared_changed in
  let schedule, submit = Schedule.step ?live value.schedule
      ~graphs:(List.map snd graphs) ~effects
      ~context_changed:(Sketch_support.Timeline.changed_context timeline_changes)
      ~force:(changed || value.force)
      ~busy:(busy value || framing <> None) ~frame in
  (* Unchanged objects keep their prepared value: the worker only cooks
     (a session cache hit) and re-prepares what changed. *)
  let previous = pieces and previous_settings = prepared_with in
  let prepare outputs =
    let rec loop reversed graphs outputs = match graphs, outputs with
      | [], [] -> Ok (Displayed (List.rev reversed))
      | (id, graph) :: graphs, (output : Session.output) :: outputs ->
          let reused = if previous_settings != Some settings then None
            else List.find_opt (fun piece -> piece.id = id && piece.graph == graph)
                previous in
          (match reused with
           | Some piece -> loop (piece :: reversed) graphs outputs
           | None ->
               Result.bind (value.prepare settings output) (fun prepared ->
                 loop ({ id; graph; prepared;
                         bounds = output_bounds output } :: reversed)
                   graphs outputs))
      | _ -> Error "cook returned a different number of outputs" in
    loop [] graphs outputs in
  let error, framing = if submit && graphs <> [] then match
      Result.bind (context value timeline) (fun context ->
        Async_cook.submit_all value.worker ~context
          ~nodes:(List.map snd graphs) ~prepare) with
    | Ok _ -> None, None
    | Error message -> Some message, None
    else error, framing in
  let framed, framing = match frame_request with
    | None -> framed, framing
    | Some (object_id, node_id) ->
        match List.find_opt (fun piece -> piece.id = object_id) pieces,
            List.assoc_opt object_id graphs with
        | Some piece, Some graph when Node.id graph = node_id && piece.graph == graph ->
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
  { cook = { value with schedule; pieces; prepared_with; error; seconds;
      framing; force = force_next; compiled; graphs; displayed };
    edit_error; prepared_changed; framed }

let close value = Async_cook.close value.worker
