open Prismel
open Procedural

type bounds = Vec3.t * Vec3.t

type 'prepared cooked =
  | Displayed of 'prepared * bounds option
  | Framed of bounds option

type 'prepared t = {
  worker : 'prepared cooked Async_cook.t;
  seed : int64;
  grain : int;
  domains : int;
  schedule : Schedule.t;
  prepare : Settings.t -> Session.output -> ('prepared, string) result;
  prepared : 'prepared option;
  error : string option;
  seconds : float option;
  displayed_bounds : bounds option;
  (* A framing job can supersede a display cook that must be resubmitted. *)
  framing : bool option;
  force : bool;
  (* The last compiled document, reused node-by-node on the next edit. *)
  compiled : (Edit_graph.t * Edit_graph.compiled) option;
}

type 'prepared update = {
  cook : 'prepared t;
  graph : Graph.t;
  displayed_graph : Graph.t;
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

let create ~prepare ~seed ~grain ?domains ~max_entries ~max_payload_bytes () =
  if grain <= 0 then invalid_arg "Prismel_editor: grain must be positive";
  let domains = Option.value ~default:
      (max 1 (Parallel.recommended_domains () - 1)) domains in
  if domains <= 0 then invalid_arg "Prismel_editor: domains must be positive";
  Result.map (fun worker ->
    { worker; seed; grain; domains; prepare; schedule = Schedule.initial;
      prepared = None; error = None; seconds = None; displayed_bounds = None;
      framing = None; force = false; compiled = None })
    (Async_cook.create ~max_entries ~max_payload_bytes)

let status value = Async_cook.status value.worker

let submit_cook value ~timeline ~node ~prepare =
  Result.bind (Sketch_support.Timeline.context ~seed:value.seed ~grain:value.grain
      ~domains:value.domains timeline) (fun context ->
    Async_cook.submit value.worker ~context ~node ~prepare)
let busy value = match status value with
  | Async_cook.Idle -> false | Cooking _ -> true
let force value = { value with force = true }

let update value ~settings ~document ~displayed_id ~graph ~displayed_graph ~edit_error
    ~display_changed ~document_changed ~effects ~timeline_changes ~timeline
    ~frame ~frame_request =
  let compiled = match value.compiled with
    | Some (source, compiled) when source == document -> compiled
    | previous -> Edit_graph.compile_all ?previous:(Option.map snd previous) document in
  let graph, edit_error = if not document_changed then graph, edit_error
    else match Option.map (fun node_id -> Edit_graph.compiled_node compiled ~node_id)
        (Edit_graph.root document) with
    | Some (Ok graph) -> graph, edit_error
    | Some (Error message) -> graph, Some message
    | None -> graph, Some "editable graph has no output node" in
  let displayed_graph, edit_error =
    if not document_changed && not display_changed
    then displayed_graph, edit_error
    else match Edit_graph.compiled_node compiled ~node_id:displayed_id with
    | Ok graph -> graph, edit_error
    | Error message -> displayed_graph, Some message in
  let completion = Async_cook.poll value.worker in
  let resume = value.framing = Some true in
  let prepared, error, seconds, prepared_changed, displayed_bounds,
      framed, framing, force_next = match completion with
    | None -> value.prepared, value.error, value.seconds, false,
        value.displayed_bounds, None, value.framing, false
    | Some { Async_cook.result = Ok (Displayed (prepared, bounds)); seconds; _ } ->
        Some prepared, None, Some seconds, true, bounds, None, None, false
    | Some { result = Ok (Framed bounds); _ } ->
        value.prepared, value.error, value.seconds, false,
        value.displayed_bounds, Some bounds, None, resume
    | Some { result = Error _; _ } when value.framing <> None ->
        value.prepared, value.error, value.seconds, false,
        value.displayed_bounds, Some None, None, resume
    | Some { result = Error error; seconds; _ } ->
        value.prepared,
        Some (Async_cook.error_to_string error),
        Some seconds, false, value.displayed_bounds, None, None, false in
  let schedule, submit = Schedule.step value.schedule
      ~graph:displayed_graph ~effects
      ~context_changed:(Sketch_support.Timeline.changed_context timeline_changes)
      ~force:(display_changed || value.force)
      ~busy:(busy value || framing <> None) ~frame in
  let prepare_display output = Result.map (fun prepared ->
    Displayed (prepared, geometry_bounds output.Session.geometry))
    (value.prepare settings output) in
  let error, framing = if submit then match
      submit_cook value
        ~timeline ~node:displayed_graph ~prepare:prepare_display with
    | Ok _ -> None, None
    | Error message -> Some message, None
    else error, framing in
  let framed, framing = match frame_request with
    | None -> framed, framing
    | Some node_id when node_id = displayed_id && displayed_bounds <> None
        && not document_changed -> Some displayed_bounds, framing
    | Some node_id ->
        (match Edit_graph.compiled_node compiled ~node_id with
         | Error _ -> Some None, framing
         | Ok node ->
             let was_busy = busy value && framing = None in
             match submit_cook value
                 ~timeline ~node ~prepare:(fun output ->
                   Ok (Framed (geometry_bounds output.Session.geometry))) with
             | Ok _ -> framed, Some (was_busy || Option.value ~default:false framing)
             | Error _ -> Some None, framing) in
  { cook = { value with schedule; prepared; error; seconds; displayed_bounds;
      framing; force = force_next; compiled = Some (document, compiled) }; graph;
    displayed_graph; edit_error;
    prepared_changed; framed }

let close value = Async_cook.close value.worker
