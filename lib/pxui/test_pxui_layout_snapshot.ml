open Prismel

let require condition message = if not condition then failwith message

let panel count =
  let value = ref (Pxui.create ()) in
  for index = 0 to count - 1 do
    value := Pxui.slider ~name:("slider-" ^ string_of_int index)
      ~label:("Slider " ^ string_of_int index)
      ~min:0. ~max:1. ~value:0.5 !value
  done;
  !value

let drag_last value count =
  let target = count - 1 in
  let y = 12 + 8 + (target * 32) + 16 in
  Pxui.update value
    [ Event.MousePressed (Input.LeftButton, (180, y));
      Event.MouseMoved (240, y);
      Event.MouseReleased (Input.LeftButton, (240, y)) ]

let allocated_drag count =
  let value = panel count in
  ignore (Pxui.scene value);
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let updated, changes = drag_last value count in
  let allocated = Gc.allocated_bytes () -. before in
  require (List.exists (function Pxui.Slid _ -> true | _ -> false) changes)
    "slider drag emitted no value change";
  require (Pxui.slider_value updated ("slider-" ^ string_of_int (count - 1))
      <> Some 0.5) "slider drag did not update the target";
  allocated

let () =
  let small = allocated_drag 100 in
  let large = allocated_drag 1_000 in
  require (large < 2_000_000.)
    (Printf.sprintf "1,000-widget drag allocated %.0f bytes" large);
  require (large < small *. 15.)
    (Printf.sprintf "slider drag allocation is superlinear: %.0f -> %.0f"
       small large);
  let stable = panel 1_000 in
  let first = Pxui.scene stable and second = Pxui.scene stable in
  require (first == second) "unchanged panel did not reuse its scene";
  let unchanged = Pxui.set_slider_value stable "slider-999" 0.5 in
  require (unchanged == stable) "unchanged slider setter rebuilt the panel";
  Printf.printf "PXUI layout snapshot: drag100=%.0f B drag1000=%.0f B\n"
    small large

let () =
  let module Store = Pxui.Private.Store in
  let store = Store.create ~capacity:1 () in
  let stale = ref None in
  for _cycle = 0 to 99_999 do
    let id = Store.add store (Bytes.make 32 'x') in
    require (Store.length store = 1 && Store.get store id <> None)
      "packed store lost a live slot";
    Option.iter (fun old ->
      require (Store.get store old = None
        && not (Store.set store old Bytes.empty)
        && not (Store.remove store old))
        "packed store accepted a stale generation") !stale;
    require (Store.remove store id && Store.get store id = None
      && Store.length store = 0)
      "packed store failed to clear a removed payload";
    stale := Some id
  done;
  require (Store.capacity store = 8)
    "packed store grew while repeatedly reusing one free slot";
  let bulk = Store.create ~capacity:1 () in
  let ids = Array.init 100_000 (fun index -> Store.add bulk index) in
  require (Store.length bulk = 100_000 && Store.capacity bulk = 131_072)
    "packed store geometric capacity drift";
  Array.iteri (fun index id ->
    require (Store.get bulk id = Some index) "packed store payload drift") ids;
  Array.iter (fun id ->
    require (Store.remove bulk id) "packed store bulk removal failed") ids;
  require (Store.length bulk = 0 && Store.capacity bulk = 131_072)
    "packed store capacity changed while releasing cold payloads"

let () =
  let module Runtime = Pxui.Private.Runtime in
  let original = Pxui.create ()
    |> Pxui.accordion ~name:"section" ~label:"Section" ~expanded:true
         (fun ui -> ui
           |> Pxui.slider ~name:"a" ~label:"A" ~min:0. ~max:1. ~value:0.25
           |> Pxui.slider ~name:"b" ~label:"B" ~min:0. ~max:1. ~value:0.75) in
  let runtime = Runtime.create original in
  let initial = Runtime.stats runtime in
  require (initial.live = 4 && initial.capacity = 8)
    "retained runtime initial packed cardinality drift";
  require (Runtime.reconcile runtime original = 0)
    "identical retained spec mutated nodes";
  require (Runtime.stats runtime = initial)
    "identical retained spec changed counters or generations";
  let section = Option.get (Runtime.find runtime "section")
  and a = Option.get (Runtime.find runtime "a")
  and b = Option.get (Runtime.find runtime "b") in
  require (Runtime.parent runtime a = Some section
    && Runtime.parent runtime b = Some section)
    "retained accordion hierarchy drift";
  require (Runtime.set_focus runtime (Some a)
    && Runtime.set_active runtime (Some a))
    "retained runtime rejected live focus/capture";
  Runtime.clear_dirty runtime;
  let changed = Pxui.set_slider_value original "a" 0.5 in
  require (Runtime.reconcile runtime changed = 1)
    "one changed value did not touch exactly one retained node";
  require (Runtime.find runtime "a" = Some a
    && Runtime.dirty runtime a = 88)
    "one changed value replaced its ID or emitted wrong dirty effects";
  let changed_stats = Runtime.stats runtime in
  require (changed_stats.structure_generation = initial.structure_generation
    && changed_stats.layout_generation = initial.layout_generation
    && changed_stats.paint_generation = Int64.succ initial.paint_generation)
    "value-only reconcile dirtied structure or layout";
  let reordered = Pxui.create ()
    |> Pxui.slider ~name:"b" ~label:"B" ~min:0. ~max:1. ~value:0.75
    |> Pxui.slider ~name:"a" ~label:"A" ~min:0. ~max:1. ~value:0.5 in
  ignore (Runtime.reconcile runtime reordered);
  require (Runtime.find runtime "a" = Some a
    && Runtime.find runtime "b" = Some b)
    "keyed reorder did not preserve stable IDs";
  let only_b = Pxui.create ()
    |> Pxui.slider ~name:"b" ~label:"B" ~min:0. ~max:1. ~value:0.75 in
  ignore (Runtime.reconcile runtime only_b);
  require (not (Runtime.valid runtime a) && Runtime.focus runtime = None
    && Runtime.active runtime = None && not (Runtime.set_focus runtime (Some a)))
    "removed retained node left live stale focus/capture";
  let churn = Runtime.create (Pxui.create ()) in
  for cycle = 0 to 99_999 do
    let spec = Pxui.create ()
      |> Pxui.slider ~name:("cycle-" ^ string_of_int cycle) ~label:"Cycle"
           ~min:0. ~max:100_000. ~value:(float_of_int cycle) in
    ignore (Runtime.reconcile churn spec)
    ; Runtime.run_passes churn
  done;
  ignore (Runtime.reconcile churn (Pxui.create ()));
  let churn_stats = Runtime.stats churn in
  require (churn_stats.live = 0 && churn_stats.capacity = 8
    && churn_stats.created = 100_000 && churn_stats.removed = 100_000)
    "retained runtime 100k reconciliation storage drift"

let () =
  let module Runtime = Pxui.Private.Runtime in
  let spec value = Pxui.create ()
    |> Pxui.slider ~name:"value" ~label:"Value" ~min:0. ~max:10. ~value in
  let runtime = Runtime.create (spec 0.) in
  Runtime.run_passes runtime;
  Runtime.clear_dirty runtime;
  let warmed = Runtime.stats runtime in
  ignore (Runtime.reconcile runtime (spec 1.));
  ignore (Runtime.reconcile runtime (spec 2.));
  ignore (Runtime.reconcile runtime (spec 3.));
  require (Runtime.pending runtime = (0, 0, 0, 1, 1, 0))
    "three writes did not coalesce into one text/paint pass";
  Runtime.run_passes runtime;
  let after = Runtime.stats runtime in
  require (after.layout_visits = warmed.layout_visits
    && after.prepaint_visits = warmed.prepaint_visits
    && after.text_visits = warmed.text_visits + 1
    && after.paint_visits = warmed.paint_visits + 1)
    "value writes scheduled structure/layout or repeated paint";
  Runtime.set_visible runtime false;
  ignore (Runtime.reconcile runtime (spec 4.));
  Runtime.run_passes runtime;
  let hidden = Runtime.stats runtime in
  require (hidden.text_visits = after.text_visits
    && hidden.paint_visits = after.paint_visits
    && Runtime.pending runtime = (0, 0, 0, 1, 1, 0))
    "hidden retained runtime executed visual passes";
  Runtime.set_visible runtime true;
  Runtime.run_passes runtime;
  let shown = Runtime.stats runtime in
  require (shown.text_visits = after.text_visits + 1
    && shown.paint_visits = after.paint_visits + 1
    && Runtime.pending runtime = (0, 0, 0, 0, 0, 0))
    "shown retained runtime did not reconcile pending visual work once"

let () =
  let module Runtime = Pxui.Private.Runtime in
  let large = ref (Pxui.create ~max_height:320 ()) in
  for index = 0 to 9_999 do
    large := Pxui.slider ~name:("large-" ^ string_of_int index) ~label:"Large"
      ~min:0. ~max:1. ~value:0.5 !large
  done;
  let runtime = Runtime.create !large in
  Runtime.run_passes runtime;
  let content, panel_height, max_scroll, visible = Runtime.layout_metrics runtime in
  require (content = 320_016 && panel_height = 320 && max_scroll = 319_696
    && visible <= 12)
    "10k retained panel layout cardinality drift";
  let first = Option.get (Runtime.find runtime "large-0") in
  require (Runtime.hit_test runtime (180, 24) = Some first)
    "retained hit testing did not use committed layout";
  let before = Runtime.stats runtime in
  let scrolled, _ = Pxui.update !large
    [Event.MouseMoved (180, 100); Event.MouseScrolled (0, -10_000)] in
  ignore (Runtime.reconcile runtime scrolled);
  Runtime.run_passes runtime;
  let after = Runtime.stats runtime in
  let last = Option.get (Runtime.find runtime "large-9991") in
  let hit = Runtime.hit_test runtime (180, 45) in
  require (after.layout_visits - before.layout_visits <= 12
    && after.paint_visits - before.paint_visits <= 12 && hit = Some last)
    (Printf.sprintf
      "10k retained scroll drift layout=%d paint=%d hit=%b"
      (after.layout_visits - before.layout_visits)
      (after.paint_visits - before.paint_visits) (hit = Some last))

let () =
  let module Runtime = Pxui.Runtime in
  let spec = panel 1_000 in
  let runtime = Runtime.create (Pxui.Spec.of_canvas spec) in
  Runtime.run_passes runtime;
  Runtime.clear_dirty runtime;
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let y = 12 + 8 + (999 * 32) + 16 in
  let changes = Runtime.update runtime
    [ Event.MousePressed (Input.LeftButton, (180, y));
      Event.MouseMoved (240, y);
      Event.MouseReleased (Input.LeftButton, (240, y)) ] in
  let allocated = Gc.allocated_bytes () -. before in
  require (allocated < 64_000.)
    (Printf.sprintf "retained 1,000-widget drag allocated %.0f bytes" allocated);
  require (List.exists (function Pxui.Slid ("slider-999", _) -> true
    | _ -> false) changes)
    "retained captured drag emitted no target change";
  require (Runtime.pending runtime = (0, 0, 0, 1, 1, 0))
    "retained captured drag dirtied structure/layout or multiple nodes";
  Runtime.run_passes runtime;
  Runtime.destroy runtime;
  require (Runtime.destroyed runtime)
    "owned retained runtime did not enter destroyed state";
  Printf.printf "PXUI retained drag1000=%.0f B\n" allocated
