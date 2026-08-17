open Prismel
open Procedural

type 'prepared t = {
  worker : 'prepared Async_cook.t;
  seed : int64;
  grain : int;
  domains : int;
}

let create ?(seed = 0L) ?(grain = 16_384) ?domains
    ~max_entries ~max_payload_bytes () =
  if grain <= 0 then invalid_arg "Reactive_sop.create: grain must be positive";
  let domains = Option.value ~default:
      (max 1 (Parallel.recommended_domains () - 1)) domains in
  if domains <= 0 then
    invalid_arg "Reactive_sop.create: domains must be positive";
  Result.map (fun worker -> { worker; seed; grain; domains })
    (Async_cook.create ~max_entries ~max_payload_bytes)

let submit value ~frame ~node ~prepare =
  let context = Context.of_frame ~seed:value.seed ~grain:value.grain
      ~domains:value.domains frame |> Result.get_ok in
  Async_cook.submit value.worker ~context ~node ~prepare

let submit_context value ~context ~node ~prepare =
  Async_cook.submit value.worker ~context ~node ~prepare

let submit_timeline value ~timeline ~node ~prepare =
  let context = Timeline.context ~seed:value.seed ~grain:value.grain
      ~domains:value.domains timeline |> Result.get_ok in
  Async_cook.submit value.worker ~context ~node ~prepare

let poll value = Async_cook.poll value.worker
let status value = Async_cook.status value.worker
let cancel value = Async_cook.cancel value.worker
let close value = Async_cook.close value.worker
let error_to_string = Async_cook.error_to_string

type gate = Clean | Dirty
let clean = Clean

let gate state ~effects ~frame =
  let state = if effects.Parameter.cook then Dirty else state in
  match state with
  | Dirty when not (Frame.mouse_down Input.LeftButton frame) -> Clean, true
  | Clean | Dirty -> state, false

type schedule = {
  initialized : bool;
  dirty : bool;
}

let schedule_initial = { initialized = false; dirty = false }

let schedule value ~graph ~effects ~context_changed ~force ~busy ~frame =
  let dirty = value.dirty || effects.Parameter.cook || force in
  let dependencies = Graph.dependencies graph in
  let dynamic = context_changed
      && (Context.Dependencies.mem Context.Dependencies.Time dependencies
          || Context.Dependencies.mem Context.Dependencies.Frame dependencies) in
  let held = Frame.mouse_down Input.LeftButton frame in
  let desired = not value.initialized || dirty || dynamic in
  let urgent = not value.initialized || effects.Parameter.cook || force in
  let fire = not held && desired && (not busy || urgent) in
  { initialized = value.initialized || fire;
    dirty = desired && not fire }, fire
