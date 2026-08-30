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
  view_ratio = 0.45;
  graph_ratio = 0.35;
  inspector_ratio = 0.20;
  splitter_width = 6;
  collapsed_width = 28;
  header_height = 30;
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

let predicted_ui_visible current frame =
  if key_pressed 'h' frame then not current
  else if key_pressed 'c' frame && not current then true
  else current

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

  type splitter = First | Second

  type t = {
    layout : layout;
    view_ratio : float;
    graph_ratio : float;
    inspector_ratio : float;
    view_collapsed : bool;
    graph_collapsed : bool;
    inspector_collapsed : bool;
    drag : (splitter * int) option;
    armed : column option;
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
      inspector_collapsed = false; drag = None; armed = None }

  let collapsed value = function
    | View -> value.view_collapsed
    | Graph -> value.graph_collapsed
    | Inspector -> value.inspector_collapsed

  let with_collapsed column state value = match column with
    | View -> { value with view_collapsed = state; drag = None; armed = None }
    | Graph -> { value with graph_collapsed = state; drag = None; armed = None }
    | Inspector ->
        { value with inspector_collapsed = state; drag = None; armed = None }

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
    let widths = distribute value frame.Frame.width in
    let splitter = value.layout.splitter_width in
    let x0 = 0 and x1 = widths.(0) + splitter
    and x2 = widths.(0) + splitter + widths.(1) + splitter in
    let header = min value.layout.header_height (max 0 (frame.height - 1)) in
    let content_height = max 1 (frame.height - header) in
    let status_height = min value.layout.status_height (max 0 (content_height - 1)) in
    { view = x0, header, widths.(0), content_height - status_height;
      graph = x1, header, widths.(1), content_height;
      inspector = x2, header, widths.(2), content_height;
      status = x0, frame.height - status_height, widths.(0), status_height;
      view_header = x0, 0, widths.(0), header;
      graph_header = x1, 0, widths.(1), header;
      inspector_header = x2, 0, widths.(2), header }

  let splitter_bounds value frame =
    let panes = geometry value frame in
    let vx, _, vw, _ = panes.view and gx, _, gw, _ = panes.graph in
    (vx + vw, 0, value.layout.splitter_width, frame.height),
    (gx + gw, 0, value.layout.splitter_width, frame.height)

  let contains (x, y, width, height) (px, py) =
    px >= x && py >= y && px < x + width && py < y + height

  let button_bounds value frame column =
    let panes = geometry value frame in
    let x, y, width, height = match column with
      | View -> panes.view_header
      | Graph -> panes.graph_header
      | Inspector -> panes.inspector_header in
    let size = min height 26 in
    x + max 0 (width - size), y + ((height - size) / 2), size, size

  let update value frame =
    let first, second = splitter_bounds value frame in
    let adjust value splitter delta =
      let available = max 1 (frame.Frame.width - (2 * value.layout.splitter_width)) in
      let amount = float_of_int delta /. float_of_int available in
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
      | _ -> value in
    let value =
      if key_pressed 'g' frame then toggle Graph value else value in
    let value =
      if key_pressed 'i' frame then toggle Inspector value else value in
    List.fold_left (fun value event -> match event with
      | Event.MousePressed (Input.LeftButton, (x, y))
          when contains first (x, y) -> { value with drag = Some (First, x) }
      | Event.MousePressed (Input.LeftButton, (x, y))
          when contains second (x, y) -> { value with drag = Some (Second, x) }
      | Event.MousePressed (Input.LeftButton, point) ->
          let armed = List.find_opt (fun column ->
            contains (button_bounds value frame column) point)
              [View; Graph; Inspector] in
          { value with armed }
      | Event.MouseMoved (x, _) ->
          (match value.drag with
           | None -> value
           | Some (splitter, last_x) ->
               { (adjust value splitter (x - last_x)) with
                 drag = Some (splitter, x) })
      | Event.MouseReleased (Input.LeftButton, point) ->
          let value = match value.armed with
            | Some column when contains (button_bounds value frame column) point ->
                toggle column value
            | _ -> value in
          { value with drag = None; armed = None }
      | Event.PointerCancelled Input.LeftButton | Event.WindowFocusLost ->
          { value with drag = None; armed = None }
      | _ -> value) value frame.Frame.events

  let scene value frame =
    let panes = geometry value frame in
    let theme = Pxui.default_theme in
    let header column title bounds =
      let x, y, width, height = bounds in
      let glyph = if collapsed value column then ">" else "<" in
      [Scene.rect ~at:(x, y) ~w:width ~h:height ~fill:theme.panel
         ~stroke:theme.control ();
       Scene.text ~at:(x + 10, y + 8) ~size:12 ~color:theme.foreground title;
       Scene.text ~at:(x + max 7 (width - 19), y + 8) ~size:12
         ~color:theme.accent glyph] in
    let first, second = splitter_bounds value frame in
    let splitter_scene (x, y, width, height) = Scene.rect ~at:(x, y)
        ~w:width ~h:height ~fill:(Color.hex_exn "#171b22") () in
    let panel (x, y, width, height) = Scene.rect ~at:(x, y) ~w:width ~h:height
        ~fill:theme.panel () in
    [panel panes.graph; panel panes.inspector; splitter_scene first;
      splitter_scene second]
    @ header View "VIEW" panes.view_header
    @ header Graph "GRAPH" panes.graph_header
    @ header Inspector "INSPECTOR" panes.inspector_header
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
    inspector_ui : Pxui.t option;
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
  }

  type 'prepared update = {
    core : 'prepared t;
    effects : Parameter.effects;
    prepared_changed : bool;
  }

  let pane_ui bounds =
    let x, y, width, height = bounds in
    x + 8, y + 8, max 1 (width - 16), max 40 (height - 16)

  let make_inspector_ui bounds inspector node =
    let x, y, width, height = pane_ui bounds in
    Pxui.create ~x ~y ~width ~max_height:height ()
    |> Sop_ui.Node_inspector.append_node inspector ~node
         ~expanded:(expanded_folders node)

  let position_ui bounds ui =
    let x, y, width, height = pane_ui bounds in
    ui |> Pxui.with_position ~x ~y |> Pxui.with_width width
       |> Pxui.with_max_height (Some height)

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
          displayed_id = Node.id graph;
          inspector = None; inspector_ui = None; workspace;
          timeline = Sketch_support.Timeline.create (); worker;
          schedule = Sketch_support.Reactive_sop.schedule_initial; prepare;
          prepared = None; edit_error = None; cook_error = None;
          cook_seconds = None; status_fps = None })
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

  let update value ~all_ui_visible frame =
    let timeline, timeline_changes = Sketch_support.Timeline.update
        value.timeline frame in
    let workspace = if all_ui_visible then Workspace.update value.workspace frame
      else value.workspace in
    let workspace = if key_pressed 'c' frame then
        Workspace.expand Workspace.Inspector workspace else workspace in
    let graph_view = if key_pressed 'c' frame
        then Pxui_graph.clear_selection value.graph_view else value.graph_view in
    let panes = Workspace.geometry workspace frame in
    let gx, gy, gw, gh = panes.graph in
    let graph_view = graph_view
      |> Pxui_graph.with_bounds ~x:gx ~y:gy ~width:(max 1 gw) ~height:(max 1 gh)
      |> Pxui_graph.with_visible
           (all_ui_visible && not (Workspace.collapsed workspace Workspace.Graph)) in
    let graph_view, graph_changes = if Pxui_graph.visible graph_view
      then Pxui_graph.update graph_view frame else graph_view, [] in
    let document, graph_view, edit_error, editor_effects = List.fold_left
        (apply_editor_change value.factories)
        (value.document, graph_view, value.edit_error, Parameter.no_effects)
        graph_changes in
    let selected = Pxui_graph.selected graph_view in
    let inspector, inspector_ui = match selected with
      | None -> None, None
      | Some node_id ->
          (match Edit_graph.find document ~node_id with
           | None -> None, None
           | Some node ->
               let retain = match value.inspector with
                 | Some inspector -> Sop_ui.Node_inspector.node_id inspector = node_id
                 | None -> false in
               if retain then value.inspector,
                   Option.map (position_ui panes.inspector) value.inspector_ui
               else
                 let inspector = Sop_ui.Node_inspector.create node in
                 Some inspector,
                 Some (make_inspector_ui panes.inspector inspector node)) in
    let inspector_ui, inspector_changes = match inspector, inspector_ui with
      | Some _, Some ui when all_ui_visible
          && not (Workspace.collapsed workspace Workspace.Inspector) ->
          let ui, changes = Pxui.update_frame ui frame in Some ui, changes
      | _ -> inspector_ui, [] in
    let document, inspector_ui, parameter_effects, edit_error =
      match inspector, inspector_ui with
      | Some _, Some ui when inspector_changes = [] ->
          document, Some ui, Parameter.no_effects, edit_error
      | Some inspector, Some ui ->
          let node_id = Sop_ui.Node_inspector.node_id inspector in
          (match Edit_graph.find document ~node_id with
           | None -> document, Some ui, Parameter.no_effects,
               Some "selected SOP is no longer in the editable graph"
           | Some node ->
               (match Sop_ui.Node_inspector.update_node inspector ~node
                   ~ui inspector_changes with
                | Error message -> document, Some ui, Parameter.no_effects,
                    Some message
                | Ok (node, ui, effects) ->
                    (match Edit_graph.replace_node node document with
                     | Error message -> document, Some ui, Parameter.no_effects,
                         Some message
                     | Ok document -> document, Some ui, effects, edit_error)))
      | _ -> document, inspector_ui, Parameter.no_effects, edit_error in
    let effects = Parameter.union_effects editor_effects parameter_effects in
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
    let status_fps =
      if frame.Frame.count mod 30 <> 0 then value.status_fps
      else if frame.fps > 0. && Float.is_finite frame.fps
      then Some (int_of_float (Float.round frame.fps)) else None in
    { core = { value with graph; displayed_graph; document; graph_view; displayed_id;
        inspector; inspector_ui;
        workspace; timeline; schedule; prepared; edit_error; cook_error; cook_seconds;
        status_fps };
      effects; prepared_changed }

  let truncate limit text = if String.length text <= limit then text
    else String.sub text 0 (limit - 3) ^ "..."

  let status_scene value frame ~render_status =
    let bounds = (Workspace.geometry value.workspace frame).status in
    let x, y, width, height = bounds in
    if height = 0 then [] else
    let cook = match Sketch_support.Reactive_sop.status value.worker with
      | Async_cook.Cooking { seconds; queued; _ } ->
          Printf.sprintf "Cooking… %.1fs%s" seconds
            (if queued then " · latest queued" else "")
      | Idle ->
          (match value.edit_error, value.cook_error, value.cook_seconds with
           | Some error, _, _ -> "Graph edit rejected: " ^ truncate 49 error
           | None, Some error, _ -> "Cook rejected: " ^ truncate 54 error
           | None, None, Some seconds ->
               Printf.sprintf "Cook complete · %.3fs" seconds
           | None, None, None -> "Waiting for first cook") in
    let render = match render_status with None -> "" | Some status -> " · " ^ status in
    let viewing = Node.label (displayed_node value) in
    let fps = match value.status_fps with
      | Some fps -> Printf.sprintf " · %d fps" fps
      | None -> "" in
    [Scene.rect ~at:(x, y) ~w:width ~h:height
       ~fill:(Color.hex_exn "#101318") ();
     Scene.text ~at:(x + 10, y + 8) ~size:11
       ~color:(Color.hex_exn "#cbd5e1")
       (cook ^ " · viewing " ^ viewing ^ render ^ fps)]

  let machinery value frame ~all_ui_visible ~camera_scene ~render_status =
    if not all_ui_visible then [] else
      Workspace.scene value.workspace frame
      @ (if Pxui_graph.visible value.graph_view
          then Pxui_graph.scene value.graph_view else [])
      @ (match value.inspector_ui with
         | Some ui when not (Workspace.collapsed value.workspace Workspace.Inspector) ->
             Pxui.scene ui
         | _ -> camera_scene)
      @ [Scene.Private.layer_break]
      @ status_scene value frame ~render_status

  let close value = Sketch_support.Reactive_sop.close value.worker
end

module Environment3 = struct
  type nonrec layout = layout
  let default_layout = default_layout

  type 'prepared t = {
    core : 'prepared Core.t;
    camera : Easy_camera.t;
    camera_control : Pxui.Camera_control.t;
    camera_ui : Pxui.t;
    scene3 : Graph.t -> 'prepared -> Scene3.t;
    overlay : Graph.t -> 'prepared option -> Frame.t -> Scene.t;
    rendered : Scene3.t option;
    render_status : string option;
    background : Color.t;
  }

  let create ?(layout = default_layout) ?factories
      ?(camera = Easy_camera.create ~target:Vec3.zero ~distance:7. ())
      ?(background = Color.hex_exn "#09090b") ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      let camera_control = Pxui.Camera_control.create () in
      let bounds = (Core.panes core initial_frame).inspector in
      let x, y, width, height = Core.pane_ui bounds in
      let camera_ui = Pxui.create ~x ~y ~width ~max_height:height ()
        |> Pxui.Camera_control.append camera_control ~camera in
      { core; camera; camera_control; camera_ui; scene3; overlay;
        rendered = None; render_status = None; background })
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
    let predicted = predicted_ui_visible
        (Pxui.Camera_control.ui_visible value.camera_control) frame in
    let update = Core.update value.core ~all_ui_visible:predicted frame in
    let core = update.core and panes = Core.panes update.core frame in
    let camera_ui = Core.position_ui panes.inspector value.camera_ui in
    let camera_panel = Core.selected_node core = None
        && Core.column_visible core Workspace.Inspector in
    let control_area = if predicted then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let camera_control, camera_ui, camera, _, render_requests =
      Pxui.Camera_control.update ~control_area
        ~panel_visible:camera_panel value.camera_control
        ~ui:camera_ui ~camera:value.camera frame in
    let rendered = if update.prepared_changed || update.effects.view
        || update.effects.export then
        Option.map (value.scene3 (Core.displayed_node core)) (Core.prepared core)
      else value.rendered in
    let render_status = List.fold_left (fun _ request -> match rendered with
      | None -> Some "Render unavailable until the first cook completes"
      | Some rendered ->
          (match Pxui.Camera_control.save request ~frame ~camera
              ~background:value.background rendered with
           | Ok () -> Some (Printf.sprintf "Saved %s at %d×"
               request.Pxui.Camera_control.filename request.factor)
           | Error message -> Some ("Render failed: " ^ message)))
        value.render_status render_requests in
    { value with core; camera; camera_control; camera_ui; rendered; render_status }

  let scene value frame =
    let all_ui_visible = Pxui.Camera_control.ui_visible value.camera_control in
    let panes = Core.panes value.core frame in
    let viewport = if all_ui_visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let world = match value.rendered with
      | None -> []
      | Some rendered ->
          [Scene.view3d ~viewport ~camera:(Easy_camera.camera value.camera) rendered] in
    let overlay = if all_ui_visible then
        let x, y, width, height = viewport in
        let local_frame = viewport_frame viewport frame in
        [Scene.clip ~at:(x, y) ~w:width ~h:height
           [Scene.translate x y
              (value.overlay (Core.graph value.core) (Core.prepared value.core)
                local_frame)]]
      else [] in
    let world = if Core.column_visible value.core Workspace.View then world else [] in
    let camera_scene = if Core.selected_node value.core = None
        && Core.column_visible value.core Workspace.Inspector
      then Pxui.Camera_control.scene value.camera_control value.camera_ui else [] in
    Scene.clear value.background :: world @ overlay
    @ Core.machinery value.core frame ~all_ui_visible
        ~camera_scene
        ~render_status:value.render_status

  let close value = Core.close value.core

  let run ?layout ?factories ?camera ?background ?seed ?grain ?domains ?max_entries
      ?max_payload_bytes ~config ~graph ~prepare ~scene3
      ?overlay () =
    let init _frame = create ?layout ?factories ?camera ?background ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
        ?overlay () |> Result.get_ok in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene ~on_stop:close ())
end

module Environment2 = struct
  type nonrec layout = layout
  let default_layout = default_layout

  type 'prepared t = {
    core : 'prepared Core.t;
    camera : Easy_camera2.t;
    camera_control : Pxui.Camera2_control.t;
    camera_ui : Pxui.t;
    scene2 : Graph.t -> 'prepared -> Scene.t;
    overlay : Graph.t -> 'prepared option -> Frame.t -> Scene.t;
    rendered : Scene.t option;
    render_status : string option;
    background : Color.t;
  }

  let create ?(layout = default_layout) ?factories
      ?(camera = Easy_camera2.create ())
      ?(background = Color.hex_exn "#09090b") ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      let camera_control = Pxui.Camera2_control.create () in
      let bounds = (Core.panes core initial_frame).inspector in
      let x, y, width, height = Core.pane_ui bounds in
      let camera_ui = Pxui.create ~x ~y ~width ~max_height:height ()
        |> Pxui.Camera2_control.append camera_control ~camera in
      { core; camera; camera_control; camera_ui; scene2; overlay;
        rendered = None; render_status = None; background })
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
    let predicted = predicted_ui_visible
        (Pxui.Camera2_control.ui_visible value.camera_control) frame in
    let update = Core.update value.core ~all_ui_visible:predicted frame in
    let core = update.core and panes = Core.panes update.core frame in
    let camera_ui = Core.position_ui panes.inspector value.camera_ui in
    let camera_panel = Core.selected_node core = None
        && Core.column_visible core Workspace.Inspector in
    let viewport = if predicted then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let camera_control, camera_ui, camera, _, render_requests =
      Pxui.Camera2_control.update ~control_area:viewport ~viewport
        ~panel_visible:camera_panel value.camera_control
        ~ui:camera_ui ~camera:value.camera frame in
    let rendered = if update.prepared_changed || update.effects.view
        || update.effects.export then
        Option.map (value.scene2 (Core.displayed_node core)) (Core.prepared core)
      else value.rendered in
    let render_status = List.fold_left (fun _ request -> match rendered with
      | None -> Some "Render unavailable until the first cook completes"
      | Some rendered ->
          (match Pxui.Camera2_control.save request ~frame ~camera
              ~background:value.background rendered with
           | Ok () -> Some (Printf.sprintf "Saved %s at %d×"
               request.Pxui.Camera2_control.filename request.factor)
           | Error message -> Some ("Render failed: " ^ message)))
        value.render_status render_requests in
    { value with core; camera; camera_control; camera_ui; rendered; render_status }

  let scene value frame =
    let all_ui_visible = Pxui.Camera2_control.ui_visible value.camera_control in
    let panes = Core.panes value.core frame in
    let viewport = if all_ui_visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let world = match value.rendered with
      | None -> []
      | Some rendered -> Easy_camera2.scene ~viewport value.camera rendered in
    let overlay = if all_ui_visible then
        let x, y, width, height = viewport in
        let local_frame = viewport_frame viewport frame in
        [Scene.clip ~at:(x, y) ~w:width ~h:height
           [Scene.translate x y
              (value.overlay (Core.graph value.core) (Core.prepared value.core)
                local_frame)]]
      else [] in
    let world = if Core.column_visible value.core Workspace.View then world else [] in
    let camera_scene = if Core.selected_node value.core = None
        && Core.column_visible value.core Workspace.Inspector
      then Pxui.Camera2_control.scene value.camera_control value.camera_ui else [] in
    Scene.clear value.background :: world @ overlay
    @ Core.machinery value.core frame ~all_ui_visible
        ~camera_scene
        ~render_status:value.render_status

  let close value = Core.close value.core

  let run ?layout ?factories ?camera ?background ?seed ?grain ?domains ?max_entries
      ?max_payload_bytes ~config ~graph ~prepare ~scene2
      ?overlay () =
    let init _frame = create ?layout ?factories ?camera ?background ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
        ?overlay () |> Result.get_ok in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene ~on_stop:close ())
end
