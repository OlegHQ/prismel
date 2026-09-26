open Prismel
open Procedural

(* Effect- and dependency-aware cook scheduler. It fires initially, after a
   committed cook parameter change, after [force], and whenever the sketch
   clock changed and any reachable node declares [Time] or [Frame]. While a
   primary-pointer edit is held, only the latest desired cook is retained. *)
type t = {
  initialized : bool;
  dirty : bool;
  graph : Graph.t option;
  dependencies : Context.Dependencies.t;
}

let initial = { initialized = false; dirty = false;
  graph = None; dependencies = Context.Dependencies.static }

let step value ~graph ~effects ~context_changed ~force ~busy ~frame =
  let dirty = value.dirty || effects.Parameter.cook || force in
  let dependencies = match value.graph with
    | Some previous when previous == graph -> value.dependencies
    | None | Some _ -> Graph.dependencies graph in
  let dynamic = context_changed
      && (Context.Dependencies.mem Context.Dependencies.Time dependencies
          || Context.Dependencies.mem Context.Dependencies.Frame dependencies) in
  let held = Frame.mouse_down Input.LeftButton frame in
  let desired = not value.initialized || dirty || dynamic in
  let urgent = not value.initialized || effects.Parameter.cook || force in
  let fire = not held && desired && (not busy || urgent) in
  { initialized = value.initialized || fire;
    dirty = desired && not fire; graph = Some graph; dependencies }, fire
