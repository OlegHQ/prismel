open Prismel
open Procedural

type layout = {
  view_ratio : float;
  graph_ratio : float;
  inspector_ratio : float;
  splitter_width : int;
  collapsed_width : int;
  header_height : int;
  status_height : int;
  min_view_width : int;
  min_graph_width : int;
  min_inspector_width : int;
}

let default_layout = {
  view_ratio = 0.42;
  graph_ratio = 0.33;
  inspector_ratio = 0.25;
  splitter_width = 6;
  collapsed_width = 28;
  header_height = 22;
  status_height = 28;
  min_view_width = 220;
  min_graph_width = 180;
  min_inspector_width = 120;
}

let key_pressed character frame = Frame.has_event (function
  | Event.KeyPressed (Input.KeyChar key) ->
      Char.lowercase_ascii key = character
      && not (List.mem Input.Meta frame.Frame.keys)
      && not (List.mem Input.Ctrl frame.keys)
  | _ -> false) frame

let expanded_folders node =
  Node.parameter_fields node
  |> List.filter_map (fun field -> match field.Parameter.folder with
    | [] -> None
    | first :: _ -> Some first)
  |> List.sort_uniq String.compare

let initial_frame : Frame.t = {
  width = 1024; height = 720; size = 1024, 720;
  drawable_width = 1024; drawable_height = 720;
  drawable_size = 1024, 720; pixel_scale = 1., 1.;
  time = 0.; dt = 0.; fps = 0.; count = 0; mouse = 0, 0;
  mouse_delta = 0, 0; keys = []; mouse_buttons = []; events = [];
}

let viewport_frame (x, y, width, height) (frame : Frame.t) =
  let scale_x, scale_y = frame.pixel_scale in
  { frame with
    width; height; size = width, height;
    drawable_width = int_of_float (Float.round (float_of_int width *. scale_x));
    drawable_height = int_of_float (Float.round (float_of_int height *. scale_y));
    drawable_size =
      (int_of_float (Float.round (float_of_int width *. scale_x)),
       int_of_float (Float.round (float_of_int height *. scale_y)));
    mouse = (fst frame.mouse - x, snd frame.mouse - y) }

module Workspace = struct
  type column = View | Graph | Inspector
  type bounds = int * int * int * int

  type panes = {
    view : bounds;
    graph : bounds;
    inspector : bounds;
    status : bounds;
    view_header : bounds;
    graph_header : bounds;
    inspector_header : bounds;
  }

  type geometry_cache = {
    frame_width : int;
    frame_height : int;
    cached_view_ratio : float;
    cached_graph_ratio : float;
    cached_inspector_ratio : float;
    cached_view_collapsed : bool;
    cached_graph_collapsed : bool;
    cached_inspector_collapsed : bool;
    panes : panes;
  }

  type splitter = First | Second

  (* Ratios and collapsed columns are model state; pointer capture for the
     splitters and header buttons belongs to the UI. *)
  type t = {
    layout : layout;
    view_ratio : float;
    graph_ratio : float;
    inspector_ratio : float;
    view_collapsed : bool;
    graph_collapsed : bool;
    inspector_collapsed : bool;
    mutable geometry_cache : geometry_cache option;
  }

  let validate (layout : layout) =
    let total = layout.view_ratio +. layout.graph_ratio
        +. layout.inspector_ratio in
    if not (Float.is_finite total) || total <= 0. then
      invalid_arg "Sketch_ui layout ratios must have a positive finite sum";
    if layout.splitter_width < 2 || layout.collapsed_width < 18
        || layout.header_height < 18 || layout.status_height < 0 then
      invalid_arg "Sketch_ui layout dimensions are too small"

  let create (layout : layout) =
    validate layout;
    let total = layout.view_ratio +. layout.graph_ratio
        +. layout.inspector_ratio in
    { layout; view_ratio = layout.view_ratio /. total;
      graph_ratio = layout.graph_ratio /. total;
      inspector_ratio = layout.inspector_ratio /. total;
      view_collapsed = false; graph_collapsed = false;
      inspector_collapsed = false; geometry_cache = None }

  let collapsed value = function
    | View -> value.view_collapsed
    | Graph -> value.graph_collapsed
    | Inspector -> value.inspector_collapsed

  let with_collapsed column state value = match column with
    | View -> { value with view_collapsed = state }
    | Graph -> { value with graph_collapsed = state }
    | Inspector -> { value with inspector_collapsed = state }

  let toggle column value = with_collapsed column (not (collapsed value column)) value
  let expand column value = with_collapsed column false value

  let distribute value width =
    let layout = value.layout in
    let available = max 3 (width - (2 * layout.splitter_width)) in
    let collapsed = [|value.view_collapsed; value.graph_collapsed;
      value.inspector_collapsed|] in
    let ratios = [|value.view_ratio; value.graph_ratio;
      value.inspector_ratio|] in
    let minimums = [|layout.min_view_width; layout.min_graph_width;
      layout.min_inspector_width|] in
    let widths = Array.make 3 0 in
    let fixed = ref 0 and weight = ref 0. in
    for index = 0 to 2 do
      if collapsed.(index) then begin
        widths.(index) <- layout.collapsed_width;
        fixed := !fixed + layout.collapsed_width
      end else weight := !weight +. ratios.(index)
    done;
    let flexible = max 3 (available - !fixed) in
    for index = 0 to 2 do
      if not collapsed.(index) then widths.(index) <- max 1
          (int_of_float (float_of_int flexible *. ratios.(index) /. !weight))
    done;
    let used = Array.fold_left ( + ) 0 widths in
    let last_visible = ref 2 in
    while !last_visible > 0 && collapsed.(!last_visible) do decr last_visible done;
    widths.(!last_visible) <- max 1 (widths.(!last_visible) + available - used);
    let required = ref 0 in
    for index = 0 to 2 do
      if not collapsed.(index) then required := !required + minimums.(index)
    done;
    let needs_minimum = ref false in
    for index = 0 to 2 do
      if not collapsed.(index) && widths.(index) < minimums.(index)
      then needs_minimum := true
    done;
    if !required <= flexible && !needs_minimum then begin
      let extra = flexible - !required and assigned = ref 0
      and last = ref 0 in
      for index = 0 to 2 do
        if not collapsed.(index) then begin
          last := index;
          let addition = int_of_float
              (float_of_int extra *. ratios.(index) /. !weight) in
          widths.(index) <- minimums.(index) + addition;
          assigned := !assigned + widths.(index)
        end
      done;
      widths.(!last) <- widths.(!last) + flexible - !assigned
    end;
    widths

  let geometry value frame =
    match value.geometry_cache with
    | Some cached when cached.frame_width = frame.Frame.width
        && cached.frame_height = frame.height
        && cached.cached_view_ratio = value.view_ratio
        && cached.cached_graph_ratio = value.graph_ratio
        && cached.cached_inspector_ratio = value.inspector_ratio
        && cached.cached_view_collapsed = value.view_collapsed
        && cached.cached_graph_collapsed = value.graph_collapsed
        && cached.cached_inspector_collapsed = value.inspector_collapsed ->
        cached.panes
    | _ ->
        let widths = distribute value frame.Frame.width in
        let splitter = value.layout.splitter_width in
        let x0 = 0 and x1 = widths.(0) + splitter
        and x2 = widths.(0) + splitter + widths.(1) + splitter in
        let header = min value.layout.header_height (max 0 (frame.height - 1)) in
        let content_height = max 1 (frame.height - header) in
        let status_height = min value.layout.status_height
            (max 0 (content_height - 1)) in
        let panes =
          { view = x0, header, widths.(0), content_height - status_height;
            graph = x1, header, widths.(1), content_height;
            inspector = x2, header, widths.(2), content_height;
            status = x0, frame.height - status_height, widths.(0), status_height;
            view_header = x0, 0, widths.(0), header;
            graph_header = x1, 0, widths.(1), header;
            inspector_header = x2, 0, widths.(2), header } in
        value.geometry_cache <- Some
          { frame_width = frame.width; frame_height = frame.height;
            cached_view_ratio = value.view_ratio;
            cached_graph_ratio = value.graph_ratio;
            cached_inspector_ratio = value.inspector_ratio;
            cached_view_collapsed = value.view_collapsed;
            cached_graph_collapsed = value.graph_collapsed;
            cached_inspector_collapsed = value.inspector_collapsed;
            panes };
        panes

  let splitter_bounds value frame =
    let panes = geometry value frame in
    let vx, _, vw, _ = panes.view and gx, _, gw, _ = panes.graph in
    (vx + vw, 0, value.layout.splitter_width, frame.height),
    (gx + gw, 0, value.layout.splitter_width, frame.height)

  let button_bounds value frame column =
    let panes = geometry value frame in
    let x, y, width, height = match column with
      | View -> panes.view_header
      | Graph -> panes.graph_header
      | Inspector -> panes.inspector_header in
    let size = min height 26 in
    x + max 0 (width - size), y + ((height - size) / 2), size, size

  let adjust value (frame : Frame.t) splitter delta =
    let available = max 1 (frame.width - (2 * value.layout.splitter_width)) in
    let amount = delta /. float_of_int available in
    let floor = 0.03 in
    match splitter with
    | First when not value.view_collapsed && not value.graph_collapsed ->
        let amount = max (floor -. value.view_ratio)
            (min (value.graph_ratio -. floor) amount) in
        { value with view_ratio = value.view_ratio +. amount;
          graph_ratio = value.graph_ratio -. amount }
    | Second when not value.graph_collapsed && not value.inspector_collapsed ->
        let amount = max (floor -. value.graph_ratio)
            (min (value.inspector_ratio -. floor) amount) in
        { value with graph_ratio = value.graph_ratio +. amount;
          inspector_ratio = value.inspector_ratio -. amount }
    | _ -> value

  let floating ui ?(flags = Pxui.Ui.none) (x, y, width, height) label =
    Pxui.Ui.box ui ~flags ~w:(Pxui.Ui.Px (float_of_int width))
      ~h:(Pxui.Ui.Px (float_of_int height)) ~at:(float_of_int x, float_of_int y) label

  (* Chrome of the retained workspace, painted and hit through PXUI boxes:
     pane backgrounds, splitters, and header bars with collapse buttons. *)
  let update value ui (frame : Frame.t) =
    let final = ref value in
    let value = if key_pressed 'g' frame then toggle Graph value else value in
    let value = if key_pressed 'i' frame then toggle Inspector value else value in
    let module Ui = Pxui.Ui in
    let panes = geometry value frame in
    let theme = Ui.theme ui in
    let panel label bounds =
      let box = floating ui bounds label in
      Ui.draw ui box (fun paint (x, y, w, h) -> Ui.Paint.fill paint ~x ~y ~w ~h theme.panel) in
    panel "workspace-graph" panes.graph;
    panel "workspace-inspector" panes.inspector;
    let first, second = splitter_bounds value frame in
    let splitter bounds label which value =
      let box = floating ui ~flags:Ui.(clickable + blocking) bounds label in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h theme.foreground);
      let signal = Ui.signal ui box in
      let dx, _ = signal.drag in
      if (signal.held || signal.released) && dx <> 0. then adjust value frame which dx
      else value in
    let value = splitter first "workspace-splitter-a" First value in
    let value = splitter second "workspace-splitter-b" Second value in
    let header column title bounds value =
      let box = floating ui bounds ("workspace-header-" ^ title) in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        let glyph = if collapsed !final column then ">" else "<" in
        Ui.Paint.rect paint ~x ~y ~w ~h ~fill:theme.foreground ~stroke:theme.foreground ();
        let x = int_of_float x and y = int_of_float y and w = int_of_float w in
        Ui.Paint.text paint ~at:(float_of_int (x + 10), float_of_int (y + 4)) ~size:11
          ~color:theme.input title;
        Ui.Paint.text paint ~at:(float_of_int (x + max 7 (w - 19)), float_of_int (y + 4))
          ~size:11 ~color:theme.accent glyph);
      let button = floating ui ~flags:Ui.clickable (button_bounds value frame column)
          ("workspace-collapse-" ^ title) in
      if (Ui.signal ui button).clicked then toggle column value else value in
    let value = value
      |> header View "VIEW" panes.view_header
      |> header Graph "GRAPH" panes.graph_header
      |> header Inspector "INSPECTOR" panes.inspector_header in
    final := value;
    value
end

module Core = struct
  type 'prepared t = {
    graph : Graph.t;
    displayed_graph : Graph.t;
    document : Edit_graph.t;
    factories : Edit_graph.factory list;
    graph_view : Pxui_graph.t;
    displayed_id : int;
    inspector : Sop_ui.Node_inspector.t option;
    ui : Pxui.Ui.t;
    workspace : Workspace.t;
    timeline : Sketch_support.Timeline.t;
    worker : 'prepared Sketch_support.Reactive_sop.t;
    schedule : Sketch_support.Reactive_sop.schedule;
    prepare : Session.output -> ('prepared, string) result;
    prepared : 'prepared option;
    edit_error : string option;
    cook_error : string option;
    cook_seconds : float option;
    status_fps : int option;
    status_fps_at : float;
    history : Edit_graph.t Pxui.Undo.t;
    (* An inspector edit made while the primary button is held amends the
       open undo entry instead of adding one per frame. *)
    drag_edit : bool;
  }

  type 'prepared update = {
    core : 'prepared t;
    effects : Parameter.effects;
    prepared_changed : bool;
  }

  let pane_ui bounds =
    let x, y, width, height = bounds in
    x + 8, y + 8, max 1 (width - 16), max 40 (height - 16)

  (* The inspector column's kit panel. *)
  let inspector_panel ui bounds build =
    let x, y, width, height = pane_ui bounds in
    Pxui.Ui.panel ui ~x:(float_of_int x) ~y:(float_of_int y)
      ~width:(float_of_int width) ~max_height:(float_of_int height)
      "workspace-inspector-panel" build

  let create ?(layout = default_layout) ?(factories = [])
      ?(seed = 0L) ?(grain = 16_384)
      ?domains ?(max_entries = 32)
      ?(max_payload_bytes = 256 * 1024 * 1024)
      ~graph ~prepare () =
    Result.map (fun worker ->
        let workspace = Workspace.create layout in
        let panes = Workspace.geometry workspace initial_frame in
        let gx, gy, gw, gh = panes.graph in
        let document = Edit_graph.of_graph graph in
        let graph_view = Pxui_graph.create_document ~x:gx ~y:gy
            ~width:(max 1 gw) ~height:(max 1 gh)
            ~catalog:(Pxui_graph.catalog_of_factories factories) document in
        { graph; displayed_graph = graph; document; factories; graph_view;
          displayed_id = Node.id graph; inspector = None;
          ui = Pxui.Ui.create (); workspace;
          timeline = Sketch_support.Timeline.create (); worker;
          schedule = Sketch_support.Reactive_sop.schedule_initial; prepare;
          prepared = None; edit_error = None; cook_error = None;
          cook_seconds = None; status_fps = None;
          status_fps_at = Float.neg_infinity;
          history = Pxui.Undo.create document; drag_edit = false })
        (Sketch_support.Reactive_sop.create ~seed ~grain ?domains ~max_entries
          ~max_payload_bytes ())

  let graph value = value.graph
  let document value = value.document
  let prepared value = value.prepared
  let timeline value = value.timeline
  let selected_node value = Option.bind (Pxui_graph.selected value.graph_view)
      (fun node_id -> Edit_graph.find value.document ~node_id)
  let displayed_node value = value.displayed_graph
  let panes value frame = Workspace.geometry value.workspace frame
  let column_visible value column = not (Workspace.collapsed value.workspace column)

  let busy worker = match Sketch_support.Reactive_sop.status worker with
    | Async_cook.Idle -> false | Cooking _ -> true

  let cook_effects = Parameter.add_impact Parameter.Cook Parameter.no_effects

  let find_factory factories key = List.find_opt (fun factory ->
    String.equal key (Edit_graph.factory_key factory)) factories

  let input_nodes document input_slots =
    let rec loop reversed = function
      | [] -> Ok (List.rev reversed)
      | None :: rest -> loop (None :: reversed) rest
      | Some id :: rest ->
          (match Edit_graph.find document ~node_id:id with
           | None -> Error (Printf.sprintf "selected input node #%d no longer exists" id)
           | Some node -> loop (Some node :: reversed) rest)
    in
    loop [] input_slots

  let instantiate factories document key input_ids =
    match find_factory factories key with
    | None -> Error (Printf.sprintf "unknown SOP type %S" key)
    | Some factory when List.length input_ids > Edit_graph.factory_arity factory ->
        Error (Printf.sprintf "%s accepts at most %d selected input%s"
          (Edit_graph.factory_label factory) (Edit_graph.factory_arity factory)
          (if Edit_graph.factory_arity factory = 1 then "" else "s"))
    | Some factory ->
        let supplied = Array.of_list input_ids in
        let slots = Array.init (Edit_graph.factory_arity factory) (fun index ->
          if index < Array.length supplied then Some supplied.(index) else None) in
        Result.bind (input_nodes document (Array.to_list slots)) (fun nodes ->
          Result.map (fun node -> node, slots, factory)
            (Edit_graph.instantiate_optional factory nodes))

  let apply_editor_change factories (document, graph_view, error, effects) = function
    | Pxui_graph.Connect_requested connection ->
        (match Edit_graph.connect ~source:connection.source
            ~consumer:connection.consumer ~input_index:connection.input_index document with
         | Error message -> document, graph_view, Some message, effects
         | Ok document -> document, Pxui_graph.with_document document graph_view,
             None, Parameter.union_effects effects cook_effects)
    | Disconnect_requested connection ->
        (match Edit_graph.disconnect ~consumer:connection.consumer
            ~input_index:connection.input_index document with
         | Error message -> document, graph_view, Some message, effects
         | Ok document -> document, Pxui_graph.with_document document graph_view,
             None, Parameter.union_effects effects cook_effects)
    | Delete_nodes_requested ids ->
        let document = Edit_graph.remove_nodes ids document in
        document, Pxui_graph.with_document document graph_view, None,
        Parameter.union_effects effects cook_effects
    | Add_requested request ->
        (match instantiate factories document request.factory_key request.inputs with
         | Error message -> document, graph_view, Some message, effects
         | Ok (node, slots, factory) ->
             (match Edit_graph.add_node ~inputs:slots ~factory node document with
              | Error message -> document, graph_view, Some message, effects
              | Ok document ->
                  let connected = Edit_graph.factory_ready factory
                      (Array.to_list slots |> List.map (function
                        | None -> None
                        | Some node_id ->
                            Edit_graph.find document ~node_id)) in
                  let document = if connected then
                      match Edit_graph.set_root (Node.id node) document with
                      | Ok document -> document | Error _ -> document
                    else document in
                  let x, y = request.at in
                  let graph_view = graph_view
                    |> Pxui_graph.with_document document
                    |> Pxui_graph.place_node ~node_id:(Node.id node) ~x ~y
                    |> Pxui_graph.select (Node.id node) in
                  let graph_view = if connected
                    then Pxui_graph.view (Node.id node) graph_view else graph_view in
                  document, graph_view, None,
                  Parameter.union_effects effects cook_effects))
    | Insert_requested request ->
        (match instantiate factories document request.factory_key
            [request.connection.source] with
         | Error message -> document, graph_view, Some message, effects
         | Ok (node, _, factory) ->
             (match Edit_graph.insert_on_connection ~factory
                 request.connection node document with
              | Error message -> document, graph_view, Some message, effects
              | Ok document ->
                  let x, y = request.at in
                  let graph_view = graph_view
                    |> Pxui_graph.with_document document
                    |> Pxui_graph.place_node ~node_id:(Node.id node) ~x ~y
                    |> Pxui_graph.select (Node.id node)
                    |> Pxui_graph.view (Node.id node) in
                  document, graph_view, None,
                  Parameter.union_effects effects cook_effects))
    | Paste_requested request ->
        (match Edit_graph.paste request.fragment document with
         | Error message -> document, graph_view, Some message, effects
         | Ok (document, mapping) ->
             let graph_view = Pxui_graph.with_document document graph_view in
             let graph_view = List.fold_left (fun graph_view (old_id, new_id) ->
               match List.find_opt (fun (id, _, _) -> id = old_id)
                   request.positions with
               | None -> graph_view
               | Some (_, x, y) ->
                   Pxui_graph.place_node ~node_id:new_id ~x ~y graph_view)
                 graph_view mapping in
             let graph_view = Pxui_graph.select_nodes
                 (List.map snd mapping) graph_view in
             document, graph_view, None,
             Parameter.union_effects effects cook_effects)
    | Selected _ | Viewed _ | View_changed | Node_moved _ | Nodes_moved _
    | Connection_selected _ | Layout_optimized ->
        document, graph_view, error, effects

  let truncate limit text = if String.length text <= limit then text
    else String.sub text 0 (limit - 3) ^ "..."

  let status_text value =
    let viewing = Node.label (displayed_node value) in
    let cook = match Sketch_support.Reactive_sop.status value.worker with
      | Async_cook.Cooking { seconds; queued; _ } ->
          Printf.sprintf "Cooking… %.1fs%s" seconds
            (if queued then " · latest queued" else "")
      | Idle ->
          (match value.edit_error, value.cook_error, value.cook_seconds with
           | Some error, _, _ -> "Graph edit rejected: " ^ truncate 49 error
           | None, Some error, _ -> "Cook rejected: " ^ truncate 54 error
           | None, None, Some seconds -> Printf.sprintf "Cook complete · %.3fs" seconds
           | None, None, None -> "Waiting for first cook") in
    cook ^ " · viewing " ^ viewing

  (* The status strip under the view: kit text on a dark bar. *)
  let status_box value ui (frame : Frame.t) ~render_status =
    let x, y, width, height = (Workspace.geometry value.workspace frame).status in
    if height > 0 then begin
      let module Ui = Pxui.Ui in
      let box = Workspace.floating ui (x, y, width, height) "workspace-status" in
      let base = truncate (max 1 ((width - 80) / 7))
          (status_text value ^ match render_status with
            | None -> "" | Some status -> " · " ^ status)
      and fps = match value.status_fps with
        | Some fps -> Printf.sprintf " · %d fps" fps | None -> "" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint _ ->
        Ui.Paint.fill paint ~x:(float_of_int x) ~y:(float_of_int y)
          ~w:(float_of_int width) ~h:(float_of_int height) theme.foreground;
        let at = float_of_int (x + 10), float_of_int (y + 8) in
        Ui.Paint.text paint ~at ~size:11 ~color:theme.input base;
        Ui.Paint.text paint ~at:(fst at +. Ui.Paint.text_width paint ~size:11 base, snd at)
          ~size:11 ~color:theme.input fps)
    end

  (* Build the workspace in [ui] and apply its edits. [camera_panel] fills
     the inspector while no node is selected. *)
  let update value ~all_ui_visible ~text_focus ~camera_panel ~render_status
      (frame : Frame.t) =
    let sample_fps = frame.time < value.status_fps_at
      || frame.time -. value.status_fps_at >= 1. in
    let status_fps, status_fps_at = if not sample_fps then
        value.status_fps, value.status_fps_at
      else (if frame.fps > 0. && Float.is_finite frame.fps
        then Some (int_of_float (Float.round frame.fps)) else None), frame.time in
    let shortcut_frame = if text_focus then
        { frame with Frame.events = List.filter (function
          | Event.KeyPressed _ | Event.KeyReleased _ | Event.TextInput _
          | Event.TextEditing _ -> false | _ -> true) frame.events }
      else frame in
    let timeline, timeline_changes = Sketch_support.Timeline.update
        value.timeline shortcut_frame in
    let workspace = if key_pressed 'c' shortcut_frame then
        Workspace.expand Workspace.Inspector value.workspace else value.workspace in
    let graph_view = if key_pressed 'c' shortcut_frame
        then Pxui_graph.clear_selection value.graph_view else value.graph_view in
    let build ui =
      let workspace = Workspace.update workspace ui shortcut_frame in
      let panes = Workspace.geometry workspace frame in
      let gx, gy, gw, gh = panes.graph in
      let graph_view = graph_view
        |> Pxui_graph.with_bounds ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
        |> Pxui_graph.with_visible
             (not (Workspace.collapsed workspace Workspace.Graph)) in
      let graph_view, graph_changes = if Pxui_graph.visible graph_view
        then Pxui_graph.update graph_view ui shortcut_frame else graph_view, [] in
      let document, graph_view, edit_error, editor_effects = List.fold_left
          (apply_editor_change value.factories)
          (value.document, graph_view, value.edit_error, Parameter.no_effects)
          graph_changes in
      let inspector_visible = not (Workspace.collapsed workspace Workspace.Inspector) in
      let selected = Option.bind (Pxui_graph.selected graph_view)
          (fun node_id -> Edit_graph.find document ~node_id) in
      let inspector, document, parameter_effects, edit_error = match selected with
        | None ->
            if inspector_visible then inspector_panel ui panes.inspector camera_panel;
            None, document, Parameter.no_effects, edit_error
        | Some node ->
            let inspector = match value.inspector with
              | Some inspector when Sop_ui.Node_inspector.node_id inspector = Node.id node ->
                  inspector
              | Some _ | None -> Sop_ui.Node_inspector.create node in
            if not inspector_visible then
              Some inspector, document, Parameter.no_effects, edit_error
            else match inspector_panel ui panes.inspector (fun () ->
                Sop_ui.Node_inspector.widgets ~expanded:(expanded_folders node)
                  inspector ui ~node) with
            | Error message -> Some inspector, document, Parameter.no_effects, Some message
            | Ok (edited, _) when edited == node ->
                Some inspector, document, Parameter.no_effects, edit_error
            | Ok (edited, effects) ->
                (match Edit_graph.replace_node edited document with
                 | Error message -> Some inspector, document, Parameter.no_effects,
                     Some message
                 | Ok document -> Some inspector, document, effects, edit_error) in
      workspace, graph_view, document, edit_error, inspector,
      Parameter.union_effects editor_effects parameter_effects in
    let workspace, graph_view, document, edit_error, inspector, effects =
      if all_ui_visible then
        Pxui.Ui.frame value.ui frame (fun ui ->
          let result = build ui in
          let (workspace, _, _, _, _, _) = result in
          status_box { value with workspace; status_fps } ui frame ~render_status;
          result)
      else workspace, graph_view, value.document, value.edit_error,
        value.inspector, Parameter.no_effects in
    (* Shared undo stack: every document change (graph edits, node creation,
       paste, inspector commits) becomes one history entry; Command/Ctrl-Z
       undoes, Shift-Command/Ctrl-Z or Ctrl-Y redoes. *)
    let dragging = Frame.mouse_down Input.LeftButton frame in
    let history, drag_edit =
      if document == value.document then value.history, value.drag_edit && dragging
      else if dragging && value.drag_edit then Pxui.Undo.amend document value.history, true
      else Pxui.Undo.commit document value.history, dragging in
    let shortcut character = Frame.has_event (function
      | Event.KeyPressed (Input.KeyChar key) ->
          Char.lowercase_ascii key = character
          && (List.mem Input.Meta frame.Frame.keys || List.mem Input.Ctrl frame.keys)
      | _ -> false) shortcut_frame in
    let shift = List.mem Input.Shift frame.Frame.keys in
    let stepped = if (shortcut 'z' && shift) || shortcut 'y' then Pxui.Undo.redo history
      else if shortcut 'z' then Pxui.Undo.undo history else None in
    let history, document, undone = match stepped with
      | Some history -> history, Pxui.Undo.present history, true
      | None -> history, document, false in
    let drag_edit = drag_edit && not undone in
    let inspector = if undone then None else inspector in
    let effects = if undone then Parameter.union_effects effects cook_effects
      else effects in
    let graph_view = Pxui_graph.with_document document graph_view in
    let displayed_id = Pxui_graph.viewed graph_view in
    let display_changed = displayed_id <> value.displayed_id in
    let document_changed = document != value.document in
    let graph, edit_error = if not document_changed then value.graph, edit_error
      else match Edit_graph.compile document with
      | Ok graph -> graph, edit_error
      | Error message -> value.graph, Some message in
    let displayed_graph, edit_error =
      if not document_changed && not display_changed
      then value.displayed_graph, edit_error
      else match Edit_graph.compile_node document ~node_id:displayed_id with
      | Ok graph -> graph, edit_error
      | Error message -> value.displayed_graph, Some message in
    let completion = Sketch_support.Reactive_sop.poll value.worker in
    let prepared, cook_error, cook_seconds, prepared_changed = match completion with
      | None -> value.prepared, value.cook_error, value.cook_seconds, false
      | Some { Async_cook.result = Ok prepared; seconds; _ } ->
          Some prepared, None, Some seconds, true
      | Some { result = Error error; seconds; _ } ->
          value.prepared,
          Some (Sketch_support.Reactive_sop.error_to_string error),
          Some seconds, false in
    let schedule, submit = Sketch_support.Reactive_sop.schedule value.schedule
        ~graph:displayed_graph ~effects
        ~context_changed:(Sketch_support.Timeline.changed_context timeline_changes)
        ~force:display_changed ~busy:(busy value.worker) ~frame in
    let cook_error = if submit then match
        Sketch_support.Reactive_sop.submit_timeline value.worker
          ~timeline ~node:displayed_graph ~prepare:value.prepare with
      | Ok _ -> None
      | Error message -> Some message
      else cook_error in
    { core = { value with graph; displayed_graph; document; graph_view; displayed_id;
        inspector; workspace; timeline; schedule; prepared; edit_error; cook_error;
        cook_seconds; status_fps; status_fps_at; history; drag_edit };
      effects; prepared_changed }

  let machinery value ~all_ui_visible =
    if all_ui_visible then Pxui.Ui.scene value.ui else []

  let close value =
    Pxui.Ui.destroy value.ui;
    Sketch_support.Reactive_sop.close value.worker
end

module CC = Pxui.Camera_control
module CC2 = Pxui.Camera2_control

module Environment3 = struct
  type nonrec layout = layout
  let default_layout = default_layout

  type 'prepared t = {
    core : 'prepared Core.t;
    camera : Easy_camera.t;
    camera_control : CC.t;
    scene3 : Graph.t -> 'prepared -> Scene3.t;
    overlay : Graph.t -> 'prepared option -> Frame.t -> Scene.t;
    rendered : Scene3.t option;
    render_status : string option ref;
    pending_render : CC.render_request option;
    background : Color.t;
    mutable hidden_scene_cache : hidden_scene_cache option;
  }

  and hidden_scene_cache = {
    hidden_width : int;
    hidden_height : int;
    hidden_rendered : Scene3.t option;
    hidden_camera : Camera.t;
    hidden_background : Color.t;
    hidden_view_visible : bool;
    hidden_scene : Scene.t;
  }

  let create ?(layout = default_layout) ?factories
      ?(camera = Easy_camera.create ~target:Vec3.zero ~distance:7. ())
      ?(background = Color.hex_exn "#09090b") ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      { core; camera; camera_control = CC.create (); scene3; overlay;
        rendered = None; render_status = ref None; pending_render = None;
        background; hidden_scene_cache = None })
      (Core.create ~layout ?factories ?seed ?grain ?domains ?max_entries
        ?max_payload_bytes ~graph ~prepare ())

  let graph value = Core.graph value.core
  let document value = Core.document value.core
  let prepared value = Core.prepared value.core
  let camera value = value.camera
  let timeline value = Core.timeline value.core
  let selected_node value = Core.selected_node value.core
  let displayed_node value = Core.displayed_node value.core
  let panes value frame = Core.panes value.core frame
  let graph_nodes value = Pxui_graph.node_views value.core.graph_view
  let rerender value =
    { value with rendered = Option.map (value.scene3 (Core.displayed_node value.core))
          (Core.prepared value.core) }
  let can_undo value = Pxui.Undo.can_undo value.core.Core.history
  let can_redo value = Pxui.Undo.can_redo value.core.Core.history

  let update_with value frame ~inspector =
    let ui = value.core.Core.ui in
    let control = CC.shortcuts ~text_focus:(Pxui.Ui.text_input_focused ui)
        value.camera_control frame in
    let visible = CC.ui_visible control in
    let control = ref control and camera = ref value.camera
    and requests = ref [] and inspected = ref None in
    let camera_panel () =
      let next, edited, saves = CC.widgets !control ui ~camera:!camera in
      control := next; camera := edited; requests := saves;
      inspected := Some (inspector ui) in
    let update = Core.update value.core ~all_ui_visible:visible
        ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel
        ~render_status:!(value.render_status) frame in
    let core = update.core and panes = Core.panes update.core frame in
    let control_area = if visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let camera = CC.navigate ~control_area !control !camera frame in
    let rendered = if update.prepared_changed || update.effects.view
        || update.effects.export then
        Option.map (value.scene3 (Core.displayed_node core)) (Core.prepared core)
      else value.rendered in
    let pending_render = match List.rev !requests with
      | request :: _ -> Some request | [] -> None in
    if pending_render <> None && rendered = None then
      value.render_status := Some "Render unavailable until the first cook completes";
    { value with core; camera; camera_control = !control; rendered; pending_render },
    !inspected

  let update value frame = fst (update_with value frame ~inspector:ignore)

  let after_present value frame =
    match value.pending_render, value.rendered with
    | Some request, Some rendered ->
        value.render_status := Some (match CC.save request
            ~frame ~camera:value.camera ~background:value.background rendered with
          | Ok () -> Printf.sprintf "Saved %s at %d×" request.filename request.factor
          | Error message -> "Render failed: " ^ message)
    | _ -> ()

  let scene value frame =
    let all_ui_visible = CC.ui_visible value.camera_control in
    if not all_ui_visible then begin
      let camera = Easy_camera.camera value.camera in
      let view_visible = Core.column_visible value.core Workspace.View in
      match value.hidden_scene_cache with
      | Some cached when cached.hidden_width = frame.Frame.width
          && cached.hidden_height = frame.height
          && cached.hidden_rendered == value.rendered
          && cached.hidden_camera == camera
          && cached.hidden_background = value.background
          && cached.hidden_view_visible = view_visible ->
          cached.hidden_scene
      | _ ->
          let world = match value.rendered with
            | Some rendered when view_visible ->
                [Scene.view3d ~viewport:(0, 0, frame.width, frame.height)
                   ~camera rendered]
            | Some _ | None -> [] in
          let scene = Scene.clear value.background :: world in
          value.hidden_scene_cache <- Some
            { hidden_width = frame.width; hidden_height = frame.height;
              hidden_rendered = value.rendered; hidden_camera = camera;
              hidden_background = value.background;
              hidden_view_visible = view_visible; hidden_scene = scene };
          scene
    end else
    let panes = Core.panes value.core frame in
    let viewport = panes.view in
    let world = match value.rendered with
      | Some rendered when Core.column_visible value.core Workspace.View ->
          [Scene.view3d ~viewport ~camera:(Easy_camera.camera value.camera) rendered]
      | Some _ | None -> [] in
    let x, y, width, height = viewport in
    let overlay = [Scene.clip ~at:(x, y) ~w:width ~h:height
        [Scene.translate x y
           (value.overlay (Core.graph value.core) (Core.prepared value.core)
              (viewport_frame viewport frame))]] in
    Scene.clear value.background :: world @ overlay
    @ Core.machinery value.core ~all_ui_visible

  let close value = Core.close value.core

  let run ?layout ?factories ?camera ?background ?seed ?grain ?domains ?max_entries
      ?max_payload_bytes ~config ~graph ~prepare ~scene3
      ?overlay () =
    let init _frame = create ?layout ?factories ?camera ?background ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
        ?overlay () |> Result.get_ok in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene
      ~after_present ~on_stop:close ())
end

module Environment2 = struct
  type nonrec layout = layout
  let default_layout = default_layout

  type 'prepared t = {
    core : 'prepared Core.t;
    camera : Easy_camera2.t;
    camera_control : CC2.t;
    scene2 : Graph.t -> 'prepared -> Scene.t;
    overlay : Graph.t -> 'prepared option -> Frame.t -> Scene.t;
    rendered : Scene.t option;
    render_status : string option ref;
    pending_render : CC2.render_request option;
    background : Color.t;
    mutable hidden_scene_cache : hidden_scene2_cache option;
  }

  and hidden_scene2_cache = {
    hidden_width : int;
    hidden_height : int;
    hidden_rendered : Scene.t option;
    hidden_camera : Easy_camera2.t;
    hidden_background : Color.t;
    hidden_view_visible : bool;
    hidden_scene : Scene.t;
  }

  let create ?(layout = default_layout) ?factories
      ?(camera = Easy_camera2.create ())
      ?(background = Color.hex_exn "#09090b") ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      { core; camera; camera_control = CC2.create (); scene2; overlay;
        rendered = None; render_status = ref None; pending_render = None; background;
        hidden_scene_cache = None })
      (Core.create ~layout ?factories ?seed ?grain ?domains ?max_entries
        ?max_payload_bytes ~graph ~prepare ())

  let graph value = Core.graph value.core
  let document value = Core.document value.core
  let prepared value = Core.prepared value.core
  let camera value = value.camera
  let timeline value = Core.timeline value.core
  let selected_node value = Core.selected_node value.core
  let displayed_node value = Core.displayed_node value.core
  let panes value frame = Core.panes value.core frame
  let graph_nodes value = Pxui_graph.node_views value.core.graph_view

  let update value frame =
    let ui = value.core.Core.ui in
    let control = CC2.shortcuts ~text_focus:(Pxui.Ui.text_input_focused ui)
        value.camera_control frame in
    let visible = CC2.ui_visible control in
    let control = ref control and camera = ref value.camera and requests = ref [] in
    let camera_panel () =
      let next, edited, saves = CC2.widgets !control ui ~camera:!camera in
      control := next; camera := edited; requests := saves in
    let update = Core.update value.core ~all_ui_visible:visible
        ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel
        ~render_status:!(value.render_status) frame in
    let core = update.core and panes = Core.panes update.core frame in
    let viewport = if visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let camera = CC2.navigate ~control_area:viewport ~viewport !control !camera frame in
    let rendered = if update.prepared_changed || update.effects.view
        || update.effects.export then
        Option.map (value.scene2 (Core.displayed_node core)) (Core.prepared core)
      else value.rendered in
    let pending_render = match List.rev !requests with
      | request :: _ -> Some request | [] -> None in
    if pending_render <> None && rendered = None then
      value.render_status := Some "Render unavailable until the first cook completes";
    { value with core; camera; camera_control = !control; rendered; pending_render }

  let after_present value frame =
    match value.pending_render, value.rendered with
    | Some request, Some rendered ->
        value.render_status := Some (match CC2.save request
            ~frame ~camera:value.camera ~background:value.background rendered with
          | Ok () -> Printf.sprintf "Saved %s at %d×" request.filename request.factor
          | Error message -> "Render failed: " ^ message)
    | _ -> ()

  let scene value frame =
    let all_ui_visible = CC2.ui_visible value.camera_control in
    if not all_ui_visible then begin
      let view_visible = Core.column_visible value.core Workspace.View in
      match value.hidden_scene_cache with
      | Some cached when cached.hidden_width = frame.Frame.width
          && cached.hidden_height = frame.height
          && cached.hidden_rendered == value.rendered
          && cached.hidden_camera == value.camera
          && cached.hidden_background = value.background
          && cached.hidden_view_visible = view_visible ->
          cached.hidden_scene
      | _ ->
          let world = match value.rendered with
            | Some rendered when view_visible ->
                Easy_camera2.scene
                  ~viewport:(0, 0, frame.width, frame.height)
                  value.camera rendered
            | Some _ | None -> [] in
          let scene = Scene.clear value.background :: world in
          value.hidden_scene_cache <- Some
            { hidden_width = frame.width; hidden_height = frame.height;
              hidden_rendered = value.rendered; hidden_camera = value.camera;
              hidden_background = value.background;
              hidden_view_visible = view_visible; hidden_scene = scene };
          scene
    end else
    let panes = Core.panes value.core frame in
    let viewport = panes.view in
    let world = match value.rendered with
      | Some rendered when Core.column_visible value.core Workspace.View ->
          Easy_camera2.scene ~viewport value.camera rendered
      | Some _ | None -> [] in
    let x, y, width, height = viewport in
    let overlay = [Scene.clip ~at:(x, y) ~w:width ~h:height
        [Scene.translate x y
           (value.overlay (Core.graph value.core) (Core.prepared value.core)
              (viewport_frame viewport frame))]] in
    Scene.clear value.background :: world @ overlay
    @ Core.machinery value.core ~all_ui_visible

  let close value = Core.close value.core

  let run ?layout ?factories ?camera ?background ?seed ?grain ?domains ?max_entries
      ?max_payload_bytes ~config ~graph ~prepare ~scene2
      ?overlay () =
    let init _frame = create ?layout ?factories ?camera ?background ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
        ?overlay () |> Result.get_ok in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene
      ~after_present ~on_stop:close ())
end
