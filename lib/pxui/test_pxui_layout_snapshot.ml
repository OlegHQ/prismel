open Prismel

let require condition message = if not condition then failwith message

let compose (a : Scene_command.Render_ir.transform)
    (b : Scene_command.Render_ir.transform) =
  { Scene_command.Render_ir.xx = a.xx *. b.xx +. a.yx *. b.xy;
    xy = a.xy *. b.xx +. a.yy *. b.xy;
    yx = a.xx *. b.yx +. a.yx *. b.yy;
    yy = a.xy *. b.yx +. a.yy *. b.yy;
    tx = a.xx *. b.tx +. a.yx *. b.ty +. a.tx;
    ty = a.xy *. b.tx +. a.yy *. b.ty +. a.ty }

let flattened_draws ir =
  let open Scene_command.Render_ir in
  let identity = { xx = 1.; xy = 0.; yx = 0.; yy = 1.; tx = 0.; ty = 0. } in
  let transforms = ref [identity] and reversed = ref [] in
  let point transform x y =
    transform.xx *. x +. transform.yx *. y +. transform.tx,
    transform.xy *. x +. transform.yy *. y +. transform.ty in
  Array.iter (function
    | Push_transform transform ->
        transforms := compose (List.hd !transforms) transform :: !transforms
    | Pop_transform -> transforms := List.tl !transforms
    | Geometry geometry ->
        let transform = List.hd !transforms in
        let vertices = Array.copy geometry.vertices in
        for index = 0 to (Array.length vertices / 2) - 1 do
          let x, y = point transform vertices.(index * 2)
              vertices.(index * 2 + 1) in
          vertices.(index * 2) <- x;
          vertices.(index * 2 + 1) <- y
        done;
        reversed := Geometry { geometry with vertices } :: !reversed
    | Image image ->
        let transform = List.hd !transforms in
        require (transform.xx = 1. && transform.xy = 0.
          && transform.yx = 0. && transform.yy = 1.)
          "label/button parity encountered a non-translation image transform";
        let x, y = point transform image.destination.x image.destination.y in
        reversed := Image { image with destination = { image.destination with x; y } }
          :: !reversed
    | Glyphs run ->
        let transform = List.hd !transforms in
        let glyph_array = Array.map (fun (glyph : glyph) ->
          let x, y = point transform glyph.x glyph.y in { glyph with x; y })
            run.glyphs in
        reversed := Glyphs { run with glyphs = glyph_array } :: !reversed
    | Debug_text debug ->
        let x, y = point (List.hd !transforms) debug.x debug.y in
        reversed := Debug_text { debug with x; y } :: !reversed
    | (Clear _ | Set_blend _ | Push_clip _ | Pop_clip) as command ->
        reversed := command :: !reversed)
    (Scene_command.Render_ir.Private.commands_readonly ir);
  List.rev !reversed

let command_kind = function
  | Scene_command.Render_ir.Clear _ -> "clear"
  | Set_blend _ -> "blend" | Push_clip _ -> "push-clip" | Pop_clip -> "pop-clip"
  | Push_transform _ -> "push-transform" | Pop_transform -> "pop-transform"
  | Geometry _ -> "geometry" | Image _ -> "image" | Glyphs _ -> "glyphs"
  | Debug_text _ -> "debug-text"

let require_draw_parity label retained compatibility =
  let retained = flattened_draws retained
  and compatibility = flattened_draws compatibility in
  if retained <> compatibility then begin
    let rec first index left right = match left, right with
      | l :: _, r :: _ when l <> r ->
          failwith (Printf.sprintf "%s first draw drift at %d (%s/%s)" label index
            (command_kind l) (command_kind r))
      | _ :: left, _ :: right -> first (index + 1) left right
      | [], [] -> assert false
      | _ -> failwith (Printf.sprintf "%s draw cardinality drift %d/%d" label
          (List.length retained) (List.length compatibility)) in
    first 0 retained compatibility
  end

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

let () =
  let module Runtime = Pxui.Runtime in
  let spec = Pxui.create ~max_height:160 ()
    |> Pxui.label ~text:"Retained label"
    |> Pxui.button ~name:"apply" ~label:"Apply" in
  let runtime = Runtime.create spec in
  Runtime.run_passes runtime;
  let _, _, references_before = Font.Private.automatic_counts () in
  let first = Runtime.scene runtime spec in
  let _, _, references_painted = Font.Private.automatic_counts () in
  require (references_painted = references_before + 2)
    "retained label/button did not own two automatic text leases";
  let compatibility_scene = Pxui.scene spec in
  let retained_ir, _ = Result.get_ok
      (Scene.Private.stage ~density:1 ~width:320 ~height:200 first)
  and compatibility_ir, _ = Result.get_ok
      (Scene.Private.stage ~density:1 ~width:320 ~height:200
         compatibility_scene) in
  let retained_draws = flattened_draws retained_ir
  and compatibility_draws = flattened_draws compatibility_ir in
  if retained_draws <> compatibility_draws then begin
    Printf.eprintf "retained kinds: %s\ncompatibility kinds: %s\n"
      (String.concat "," (List.map command_kind retained_draws))
      (String.concat "," (List.map command_kind compatibility_draws))
    ; let rec first index left right = match left, right with
        | l :: _, r :: _ when l <> r ->
            (match l, r with
             | Scene_command.Render_ir.Geometry l,
               Scene_command.Render_ir.Geometry r ->
                 Printf.eprintf
                   "first drift %d geometry colors=%lx/%lx vertices=%b indices=%b\n"
                   index l.color r.color (l.vertices = r.vertices)
                   (l.indices = r.indices)
             | Scene_command.Render_ir.Image l,
               Scene_command.Render_ir.Image r ->
                 Printf.eprintf
                   "first drift %d image ids=%d/%d source=%b destination=%b\n"
                   index l.resource_id r.resource_id (l.source = r.source)
                   (l.destination = r.destination)
             | _ -> Printf.eprintf "first drift %d kinds=%s/%s\n" index
                 (command_kind l) (command_kind r))
        | _ :: left, _ :: right -> first (index + 1) left right
        | _ -> () in
      first 0 retained_draws compatibility_draws
  end;
  require (retained_draws = compatibility_draws)
    "retained label/button command stream drifted from compatibility paint";
  Scene.Private.release compatibility_scene;
  ignore (Result.get_ok
    (Scene.Private.stage_native ~density:1 ~width:320 ~height:200 first));
  let second = Runtime.scene runtime spec in
  require (first == second)
    "unchanged retained label/button panel recomposed its Scene";
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10_000 do ignore (Runtime.scene runtime spec) done;
  let unchanged_allocated = Gc.allocated_bytes () -. before in
  require (unchanged_allocated <= 512.)
    (Printf.sprintf "unchanged retained Scene allocated %.0f bytes"
      unchanged_allocated);
  let button = Option.get (Runtime.find runtime "apply") in
  let _, y, _, height, _, _, _, _ = Option.get (Runtime.bounds runtime button) in
  let before_hover = Runtime.stats runtime in
  ignore (Runtime.update runtime [Event.MouseMoved (30, y + (height / 2))]);
  Runtime.run_passes runtime;
  let hovered = Runtime.scene runtime spec in
  let after_hover = Runtime.stats runtime in
  require (hovered != first
    && after_hover.paint_visits = before_hover.paint_visits + 1
    && after_hover.paint_generation = Int64.succ before_hover.paint_generation)
    "button hover did not rebuild exactly one retained paint segment";
  Runtime.destroy runtime;
  let _, _, references_after = Font.Private.automatic_counts () in
  require (references_after = references_before)
    "retained label/button teardown leaked automatic text references";
  Printf.printf "PXUI retained label/button unchanged=%.0f B/10k calls\n"
    unchanged_allocated

let () =
  let module Runtime = Pxui.Runtime in
  let panel = ref (Pxui.create ~max_height:320 ()) in
  for index = 0 to 9_999 do
    panel := Pxui.label ~text:("Label " ^ string_of_int index) !panel
  done;
  let runtime = Runtime.create !panel in
  Runtime.run_passes runtime;
  let _, _, references_before = Font.Private.automatic_counts () in
  ignore (Runtime.scene runtime !panel);
  for _ = 1 to 80 do
    let updated, _ = Pxui.update !panel
        [Event.MouseMoved (20, 100); Event.MouseScrolled (0, -8)] in
    panel := updated;
    ignore (Runtime.reconcile runtime updated);
    Runtime.run_passes runtime;
    ignore (Runtime.scene runtime updated)
  done;
  let stats = Runtime.stats runtime in
  require (stats.display_list_entries <= 256
    && stats.display_list_bytes <= 64 * 1024 * 1024
    && stats.display_list_evictions > 0)
    (Printf.sprintf
      "retained display-list cache bounds drift entries=%d bytes=%d evictions=%d"
      stats.display_list_entries stats.display_list_bytes
      stats.display_list_evictions);
  Runtime.destroy runtime;
  let _, _, references_after = Font.Private.automatic_counts () in
  require (references_after = references_before)
    "10k retained display-list churn leaked automatic text references"

let () =
  let module Runtime = Pxui.Runtime in
  let spec = Pxui.create ~width:360 ~max_height:640 ()
    |> Pxui.accordion ~name:"section" ~label:"Section" ~expanded:true
         (fun ui -> ui |> Pxui.label ~text:"Inside")
    |> Pxui.button ~name:"button" ~label:"Button"
    |> Pxui.toggle ~name:"toggle" ~label:"Toggle" ~value:true
    |> Pxui.slider ~name:"slider" ~label:"Slider" ~min:(-1.) ~max:2.
         ~value:0.625
    |> Pxui.int_slider ~name:"integer" ~label:"Integer" ~min:(-5) ~max:12
         ~value:3
    |> Pxui.text_field ~name:"text" ~label:"Text" ~value:"value"
    |> Pxui.choice ~name:"choice" ~label:"Choice"
         ~options:["first"; "second"; "third"] ~selected:1
    |> Pxui.range ~name:"range" ~label:"Range" ~min:0. ~max:1.
         ~low:0.2 ~high:0.8
    |> Pxui.xy ~name:"xy" ~label:"XY" ~x_range:(-1., 1.)
         ~y_range:(-2., 2.) ~value:(0.25, -0.5) in
  let runtime = Runtime.create spec in
  Runtime.run_passes runtime;
  let retained_scene = Runtime.scene runtime spec
  and compatibility_scene = Pxui.scene spec in
  let retained_ir, _ = Result.get_ok
      (Scene.Private.stage ~density:1 ~width:480 ~height:720 retained_scene)
  and compatibility_ir, _ = Result.get_ok
      (Scene.Private.stage ~density:1 ~width:480 ~height:720 compatibility_scene) in
  require_draw_parity "all-widget retained paint" retained_ir compatibility_ir;
  Scene.Private.release compatibility_scene;
  let staged = Result.get_ok
      (Scene.Private.stage_native ~density:1 ~width:480 ~height:720
         retained_scene) in
  let staged_again = Result.get_ok
      (Scene.Private.stage_native ~density:1 ~width:480 ~height:720
         retained_scene) in
  require (staged == staged_again)
    "unchanged retained workspace missed native-stage identity cache";
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10_000 do
    ignore (Scene.Private.stage_native ~density:1 ~width:480 ~height:720
      retained_scene)
  done;
  let stage_allocated = Gc.allocated_bytes () -. before in
  require (stage_allocated <= 960_000.)
    (Printf.sprintf "retained native staging allocated %.0f B/10k calls"
      stage_allocated);
  Printf.printf "PXUI retained native-stage=%.1f B/call\n"
    (stage_allocated /. 10_000.);
  Runtime.destroy runtime
