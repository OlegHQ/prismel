open Prismel
open Procedural

module Preset = Preset

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
  time = 0.; dt = 0.; fps = 0.; count = 0; mouse = 0., 0.;
  mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events = [];
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
    mouse = (fst frame.mouse -. float x, snd frame.mouse -. float y) }

module Workspace = struct
  type column = View | Graph | Inspector | Timeline
  type bounds = int * int * int * int

  (* One kit row plus panel padding. *)
  let timeline_height = 30

  type panes = {
    view : bounds;
    graph : bounds;
    inspector : bounds;
    status : bounds;
    timeline : bounds;
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
    cached_timeline_collapsed : bool;
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
    timeline_collapsed : bool;
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
      inspector_collapsed = false; timeline_collapsed = true;
      geometry_cache = None }

  let collapsed value = function
    | View -> value.view_collapsed
    | Graph -> value.graph_collapsed
    | Inspector -> value.inspector_collapsed
    | Timeline -> value.timeline_collapsed

  let with_collapsed column state value = match column with
    | View -> { value with view_collapsed = state }
    | Graph -> { value with graph_collapsed = state }
    | Inspector -> { value with inspector_collapsed = state }
    | Timeline -> { value with timeline_collapsed = state }

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
        && cached.cached_inspector_collapsed = value.inspector_collapsed
        && cached.cached_timeline_collapsed = value.timeline_collapsed ->
        cached.panes
    | _ ->
        let widths = distribute value frame.Frame.width in
        let splitter = value.layout.splitter_width in
        let x0 = 0 and x1 = widths.(0) + splitter
        and x2 = widths.(0) + splitter + widths.(1) + splitter in
        let header = min value.layout.header_height (max 0 (frame.height - 1)) in
        let timeline = if value.timeline_collapsed then 0
          else min timeline_height (max 0 (frame.height - header - 1)) in
        let bottom = frame.height - timeline in
        let content_height = max 1 (bottom - header) in
        let status_height = min value.layout.status_height
            (max 0 (content_height - 1)) in
        let panes =
          { view = x0, header, widths.(0), content_height - status_height;
            graph = x1, header, widths.(1), content_height;
            inspector = x2, header, widths.(2), content_height;
            status = x0, bottom - status_height, widths.(0), status_height;
            timeline = 0, bottom, frame.width, timeline;
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
            cached_timeline_collapsed = value.timeline_collapsed;
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
      | Inspector -> panes.inspector_header
      | Timeline -> panes.timeline in
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
      if signal.hovered || signal.held then
        Ui.request_cursor ui `Horizontal_resize;
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

module Leader = struct
  open Editor.Keymap
  type action =
    | Save_preset | Browse_presets
    | Toggle_timeline | Toggle_graph | Toggle_inspector | Hide_ui | Open_camera
    | Play_pause | Reset | Stop
    | Add_node | Layout | Frame_tile | Frame_camera
    | Look_through | Fly
    | Undo | Redo
    | Graph_command of Pxui_graph.command

  type binding = (Workspace.column, action) Editor.Keymap.binding

  type state = Editor.Router.state = Idle | Pending

  (* One table drives both dispatch and the which-key panel. *)
  let keymap = [
    { trigger = Leader 's'; label = "save preset"; scope = None; action = Save_preset };
    { trigger = Leader 'b'; label = "browse presets"; scope = None; action = Browse_presets };
    { trigger = Leader 't'; label = "toggle timeline"; scope = None; action = Toggle_timeline };
    { trigger = Leader 'g'; label = "toggle graph"; scope = None; action = Toggle_graph };
    { trigger = Leader 'i'; label = "toggle inspector"; scope = None; action = Toggle_inspector };
    { trigger = Leader 'h'; label = "hide all UI"; scope = None; action = Hide_ui };
    { trigger = Leader 'c'; label = "camera section"; scope = None; action = Open_camera };
    { trigger = Leader 'p'; label = "play / pause"; scope = None; action = Play_pause };
    { trigger = Leader 'r'; label = "reset"; scope = None; action = Reset };
    { trigger = Leader 'x'; label = "stop"; scope = None; action = Stop };
    { trigger = Leader 'a'; label = "add node"; scope = Some Workspace.Graph; action = Add_node };
    { trigger = Leader 'l'; label = "layout"; scope = Some Workspace.Graph; action = Layout };
    { trigger = Leader 'f'; label = "frame selected tile"; scope = Some Workspace.Graph;
      action = Frame_tile };
    { trigger = Chord (Input.KeyChar 'f', []);
      label = "frame camera on tile"; scope = Some Workspace.Graph;
      action = Frame_camera };
  ] @ List.concat_map (fun modifier -> [
    { trigger = Chord (Input.KeyChar 'z', [modifier]);
      label = "undo"; scope = None; action = Undo };
    { trigger = Chord (Input.KeyChar 'z', [modifier; Input.Shift]);
      label = "redo"; scope = None; action = Redo };
    { trigger = Chord (Input.KeyChar 'y', [modifier]);
      label = "redo"; scope = None; action = Redo }]) [Input.Meta; Input.Ctrl]
  @ List.map (fun (trigger, label, command) ->
    { trigger; label; scope = Some Workspace.Graph;
      action = Graph_command command }) Pxui_graph.bindings

  (* Bindings only the 3D environment has. *)
  let keymap3 = keymap @ [
    { trigger = Leader 'w'; label = "fly (WASD, Q/E, Esc)"; scope = Some Workspace.View; action = Fly };
    { trigger = Leader 'v'; label = "look through render camera"; scope = Some Workspace.View;
      action = Look_through };
  ]

  let pane_name = function
    | Workspace.View -> "View" | Graph -> "Graph" | Inspector -> "Inspector"
    | Timeline -> "Timeline"

  (* The which-key panel, built last so it is topmost. *)
  let panel ui keymap focus =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let row binding =
      let key = match binding.trigger with
        | Leader key -> String.make 1 key
        | Chord (Input.KeyChar key, modifiers) ->
            (if List.mem Input.Meta modifiers then "⌘"
             else if List.mem Input.Ctrl modifiers then "Ctrl-" else "")
            ^ String.make 1 key
        | Chord (Input.Delete, _) -> "Del"
        | Chord (Input.Backspace, _) -> "⌫"
        | Chord (Input.Home, _) -> "Home"
        | Chord _ -> "Key" in
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float_of_int (Ui.row_height ui)))
          ("leader-" ^ key) in
      Ui.draw ui box (fun paint (x, y, _, h) ->
        let y = y +. Float.max 5. ((h -. float_of_int (Ui.font_size ui) -. 3.) /. 2.) in
        Ui.Paint.text paint ~at:(x +. 8., y) ~color:theme.accent
          key;
        Ui.Paint.text paint ~at:(x +. 68., y) ~color:theme.foreground binding.label) in
    let section title scope =
      match List.filter (fun binding -> binding.scope = scope) keymap with
      | [] -> ()
      | bindings -> Ui.label ui title; List.iter row bindings in
    ignore (Ui.modal ui ~width:300. "leader" (fun () ->
      section "Leader · global" None;
      section (pane_name focus) (Some focus)))
end

module Doc = struct
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

  let apply factories (document, graph_view, error, effects) = function
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
    | Connection_selected _ | Flag_requested _ | Frame_camera_requested _ ->
        document, graph_view, error, effects
end

module Cook = struct
  type bounds = Vec3.t * Vec3.t

  type 'prepared cooked =
    | Displayed of 'prepared * bounds option
    | Framed of bounds option

  type 'prepared t = {
    worker : 'prepared cooked Sketch_support.Reactive_sop.t;
    schedule : Sketch_support.Reactive_sop.schedule;
    prepare : Session.output -> ('prepared, string) result;
    prepared : 'prepared option;
    error : string option;
    seconds : float option;
    displayed_bounds : bounds option;
    (* A framing job can supersede a display cook that must be resubmitted. *)
    framing : bool option;
    force : bool;
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
    Result.map (fun worker ->
      { worker; prepare; schedule = Sketch_support.Reactive_sop.schedule_initial;
        prepared = None; error = None; seconds = None; displayed_bounds = None;
        framing = None; force = false })
      (Sketch_support.Reactive_sop.create ~seed ~grain ?domains ~max_entries
        ~max_payload_bytes ())

  let status value = Sketch_support.Reactive_sop.status value.worker
  let busy value = match status value with
    | Async_cook.Idle -> false | Cooking _ -> true
  let force value = { value with force = true }

  let update value ~document ~displayed_id ~graph ~displayed_graph ~edit_error
      ~display_changed ~document_changed ~effects ~timeline_changes ~timeline
      ~frame ~frame_request =
    let graph, edit_error = if not document_changed then graph, edit_error
      else match Edit_graph.compile document with
      | Ok graph -> graph, edit_error
      | Error message -> graph, Some message in
    let displayed_graph, edit_error =
      if not document_changed && not display_changed
      then displayed_graph, edit_error
      else match Edit_graph.compile_node document ~node_id:displayed_id with
      | Ok graph -> graph, edit_error
      | Error message -> displayed_graph, Some message in
    let completion = Sketch_support.Reactive_sop.poll value.worker in
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
          Some (Sketch_support.Reactive_sop.error_to_string error),
          Some seconds, false, value.displayed_bounds, None, None, false in
    let schedule, submit = Sketch_support.Reactive_sop.schedule value.schedule
        ~graph:displayed_graph ~effects
        ~context_changed:(Sketch_support.Timeline.changed_context timeline_changes)
        ~force:(display_changed || value.force)
        ~busy:(busy value || framing <> None) ~frame in
    let prepare_display output = Result.map (fun prepared ->
      Displayed (prepared, geometry_bounds output.Session.geometry))
      (value.prepare output) in
    let error, framing = if submit then match
        Sketch_support.Reactive_sop.submit_timeline value.worker
          ~timeline ~node:displayed_graph ~prepare:prepare_display with
      | Ok _ -> None, None
      | Error message -> Some message, None
      else error, framing in
    let framed, framing = match frame_request with
      | None -> framed, framing
      | Some node_id when node_id = displayed_id && displayed_bounds <> None
          && not document_changed -> Some displayed_bounds, framing
      | Some node_id ->
          (match Edit_graph.compile_node document ~node_id with
           | Error _ -> Some None, framing
           | Ok node ->
               let was_busy = busy value && framing = None in
               match Sketch_support.Reactive_sop.submit_timeline value.worker
                   ~timeline ~node ~prepare:(fun output ->
                     Ok (Framed (geometry_bounds output.Session.geometry))) with
               | Ok _ -> framed, Some (was_busy || Option.value ~default:false framing)
               | Error _ -> Some None, framing) in
    { cook = { value with schedule; prepared; error; seconds; displayed_bounds;
        framing; force = force_next }; graph; displayed_graph; edit_error;
      prepared_changed; framed }

  let close value = Sketch_support.Reactive_sop.close value.worker
end

module Core = struct
  type bounds = Cook.bounds

  type prompt =
    | Saving of string
    | Browsing of { query : string; presets : (string * float) list }

  type prompt_intent = Save_preset_file of string | Load_preset_file of string
    | Delete_preset_file of { name : string; query : string }

  type timeline_intent = Pause_toggle | Stop_playback | Reset_playback
    | Seek_playback of int64

  type frame_result = {
    workspace : Workspace.t;
    graph_view : Pxui_graph.t;
    document : Edit_graph.t;
    edit_error : string option;
    inspector : Sop_ui.Node_inspector.t option;
    effects : Parameter.effects;
    timeline_intents : timeline_intent list;
    frame_request : int option;
    prompt : prompt option;
    prompt_intent : prompt_intent option;
  }

  type 'prepared t = {
    code_graph : Graph.t;
    presets : string;  (* preset directory *)
    name : string;  (* sketch name recorded in presets *)
    prompt : prompt option;
    notice : string option;
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
    cook : 'prepared Cook.t;
    edit_error : string option;
    status_fps : int option;
    status_fps_at : float;
    history : Edit_graph.t Editor.History.t;
    focus : Workspace.column;
    leader : Leader.state;
    keymap : Leader.binding list;
    timeline_frames : int;
  }

  type 'prepared update = {
    core : 'prepared t;
    effects : Parameter.effects;
    prepared_changed : bool;
    framed : bounds option option;
    (** A framing request finished: [Some None] had no geometry. *)
    loaded_view : Yojson.Safe.t option;
    (** A preset loaded this frame; its environment view settings. *)
    actions : Leader.action list;
    (* The frame without leader-consumed events, for the environment's own
       input handling. *)
    input : Frame.t;
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

  let create ?(keymap = Leader.keymap) ?(seed_document = fun _ document -> document)
      ?(name = "sketch") ?presets ?(timeline_frames = 240)
      ?(layout = default_layout) ?(factories = [])
      ?(seed = 0L) ?(grain = 16_384)
      ?domains ?(max_entries = 32)
      ?(max_payload_bytes = 256 * 1024 * 1024)
      ~graph ~prepare () =
    Result.map (fun cook ->
        let workspace = Workspace.create layout in
        let panes = Workspace.geometry workspace initial_frame in
        let gx, gy, gw, gh = panes.graph in
        let document = seed_document factories (Edit_graph.of_graph graph) in
        let graph_view = Pxui_graph.create_document ~x:gx ~y:gy
            ~width:(max 1 gw) ~height:(max 1 gh)
            ~catalog:(Pxui_graph.catalog_of_factories factories)
            ~flaggable:(fun info -> info.Edit_graph.operation = "camera") document in
        let presets = match presets with
          | Some directory -> directory
          | None -> Filename.concat (Filename.concat
              (Option.value ~default:"." (Sys.getenv_opt "HOME")) ".prismel")
              (Preset.sanitize name) in
        { code_graph = graph; presets; name; prompt = None; notice = None;
          graph; displayed_graph = graph; document; factories; graph_view;
          displayed_id = Node.id graph; inspector = None;
          ui = Pxui.Ui.create (); workspace;
          timeline = Sketch_support.Timeline.create (); cook;
          edit_error = None; status_fps = None;
          status_fps_at = Float.neg_infinity;
          history = Editor.History.create document;
          focus = Workspace.View; leader = Leader.Idle;
          keymap; timeline_frames = max 1 timeline_frames })
        (Cook.create ~prepare ~seed ~grain ?domains ~max_entries
          ~max_payload_bytes ())

  let graph value = value.graph
  let document value = value.document
  let prepared value = value.cook.Cook.prepared
  let timeline value = value.timeline
  let selected_node value = Option.bind (Pxui_graph.selected value.graph_view)
      (fun node_id -> Edit_graph.find value.document ~node_id)
  let displayed_node value = value.displayed_graph
  let panes value frame = Workspace.geometry value.workspace frame
  let column_visible value column = not (Workspace.collapsed value.workspace column)

  let truncate limit text = if String.length text <= limit then text
    else String.sub text 0 (limit - 3) ^ "..."

  let status_text value =
    let viewing = Node.label (displayed_node value) in
    let cook = match Cook.status value.cook with
      | Async_cook.Cooking { seconds; queued; _ } ->
          Printf.sprintf "Cooking… %.1fs%s" seconds
            (if queued then " · latest queued" else "")
      | Idle ->
          (match value.edit_error, value.cook.error, value.cook.seconds with
           | Some error, _, _ -> "Graph edit rejected: " ^ truncate 49 error
           | None, Some error, _ -> "Cook rejected: " ^ truncate 54 error
           | None, None, _ when value.notice <> None -> Option.get value.notice
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
  let pane_at (panes : Workspace.panes) point =
    let px, py = point in
    let inside (x, y, w, h) = px >= float x && py >= float y &&
      px < float (x + w) && py < float (y + h) in
    if inside panes.timeline then Some Workspace.Timeline
    else if inside panes.graph then Some Workspace.Graph
    else if inside panes.inspector then Some Workspace.Inspector
    else if inside panes.view || inside panes.status then Some Workspace.View
    else None

  (* Leader actions owned by the workspace; the environment handles the rest
     from [update.actions]. *)
  let apply_action (frame : Frame.t) (workspace, graph_view, timeline, changes) action =
    let module T = Sketch_support.Timeline in
    let timeline_step step = let timeline, more = step timeline in
      workspace, graph_view, timeline, changes @ more in
    match action with
    | Leader.Toggle_timeline ->
        Workspace.toggle Workspace.Timeline workspace, graph_view, timeline, changes
    | Toggle_graph ->
        Workspace.toggle Workspace.Graph workspace, graph_view, timeline, changes
    | Toggle_inspector ->
        Workspace.toggle Workspace.Inspector workspace, graph_view, timeline, changes
    | Open_camera ->
        Workspace.expand Workspace.Inspector workspace,
        Pxui_graph.clear_selection graph_view, timeline, changes
    | Play_pause -> timeline_step T.toggle_pause
    | Reset -> timeline_step T.reset
    | Stop -> timeline_step T.stop
    | Add_node ->
        let gx, gy, gw, gh = (Workspace.geometry workspace frame).graph in
        let mx, my = frame.mouse in
        let at = if mx >= float gx && my >= float gy &&
            mx < float (gx + gw) && my < float (gy + gh)
          then int_of_float mx, int_of_float my
          else gx + (gw / 3), gy + (gh / 3) in
        Workspace.expand Workspace.Graph workspace,
        Pxui_graph.open_menu_at at graph_view, timeline, changes
    | Layout -> workspace, Pxui_graph.optimize_layout graph_view, timeline, changes
    | Frame_tile -> workspace, Pxui_graph.frame_selected graph_view, timeline, changes
    | Hide_ui | Look_through | Fly | Save_preset | Browse_presets
    | Graph_command _ | Frame_camera | Undo | Redo ->
        workspace, graph_view, timeline, changes

  let update value ~all_ui_visible ~text_focus ~camera_panel ~render_status
      ~view_state (frame : Frame.t) =
    let panes = Workspace.geometry value.workspace frame in
    let focus = List.fold_left (fun focus -> function
      | Event.MousePressed (_, point) when all_ui_visible ->
          Option.value ~default:focus (pane_at panes point)
      | _ -> focus) value.focus frame.events in
    let keymap = if all_ui_visible
        && not (Workspace.collapsed value.workspace Workspace.Graph)
      then value.keymap else List.filter (fun binding ->
        match binding.Editor.Keymap.action with
        | Leader.Graph_command _ | Leader.Frame_camera -> false
        | _ -> true) value.keymap in
    let leader, actions, frame = Editor.Router.step keymap ~focus ~text_focus ~frame
        value.leader in
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
    let workspace, graph_view, timeline, timeline_changes = List.fold_left
        (apply_action frame)
        (value.workspace, value.graph_view, timeline, timeline_changes) actions in
    let graph_view, command_changes = List.fold_left (fun (graph_view, changes) ->
      function
      | Leader.Graph_command command when all_ui_visible
          && not (Workspace.collapsed workspace Workspace.Graph) ->
          let graph_view, emitted = Pxui_graph.run_command graph_view command in
          graph_view, changes @ emitted
      | _ -> graph_view, changes) (graph_view, []) actions in
    (* ponytail: seeking recooks the pure graph at the target frame; state a
       sketch threads through [run_state] outside the graph is not replayed. *)
    let timeline_bar ui (x, y, width, height) timeline =
      let module T = Sketch_support.Timeline in
      let module Ui = Pxui.Ui in
      Ui.panel ui ~x:(float_of_int x) ~y:(float_of_int y) ~width:(float_of_int width)
        ~max_height:(float_of_int height) "workspace-timeline" (fun () ->
        Ui.row ui ~gap:6. "timeline-row" (fun () ->
          let pause = Ui.button ui (if T.mode timeline = T.Playing then "Pause###timeline-play"
            else "Play###timeline-play") in
          let stop = Ui.button ui "Stop###timeline-stop" in
          let reset = Ui.button ui "Reset###timeline-reset" in
          let frame = T.frame timeline in
          Ui.label ui (Printf.sprintf "f %Ld  %.2fs###timeline-readout" frame
            (T.time timeline));
          let range = Float.max (Int64.to_float frame) (float_of_int value.timeline_frames) in
          let scrub = Ui.slider ui "Frame###timeline-scrub" ~range:(0., range)
            (Int64.to_float frame) in
          List.filter_map Fun.id [
            (if pause then Some Pause_toggle else None);
            (if stop then Some Stop_playback else None);
            (if reset then Some Reset_playback else None);
            (if scrub <> Int64.to_float frame
              then Some (Seek_playback (Int64.of_float (Float.round scrub)))
              else None)])) in
    let initial_frame_request = if List.mem Leader.Frame_camera actions
      then Pxui_graph.selected graph_view else None in
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
      let graph_changes = command_changes @ graph_changes in
      let frame_request = List.fold_left (fun request -> function
        | Pxui_graph.Frame_camera_requested id -> Some id
        | _ -> request) initial_frame_request graph_changes in
      let document, graph_view, edit_error, editor_effects = List.fold_left
          (Doc.apply value.factories)
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
      let timeline_intents = if Workspace.collapsed workspace Workspace.Timeline
        then [] else timeline_bar ui panes.timeline timeline in
      (* The focused pane's accent outline. *)
      let theme = Pxui.Ui.theme ui in
      let bounds = match focus with
        | Workspace.View -> panes.view | Graph -> panes.graph
        | Inspector -> panes.inspector | Timeline -> panes.timeline in
      let x, y, w, h = bounds in
      if w > 2 && h > 2 then
        Pxui.Ui.draw ui (Workspace.floating ui bounds "workspace-focus")
          (fun paint _ -> Pxui.Ui.Paint.stroke paint ~x:(float_of_int x +. 0.5)
            ~y:(float_of_int y +. 0.5) ~w:(float_of_int (w - 1))
            ~h:(float_of_int (h - 1)) ~width:1. theme.accent);
      { workspace; graph_view; document; edit_error; inspector;
        effects = Parameter.union_effects editor_effects parameter_effects;
        timeline_intents; frame_request; prompt = None; prompt_intent = None } in
    let leader_panel ui = if leader = Leader.Pending then
        Leader.panel ui keymap focus in
    (* Presets: Space s names and saves the document, Space b browses, loads
       (Enter), and deletes (Delete twice). A load replaces the document below
       as one undo entry. *)
    let initial_prompt = List.fold_left (fun prompt -> function
      | Leader.Save_preset -> Some (Saving (Preset.default_name ()))
      | Browse_presets ->
          Some (Browsing { query = ""; presets = Preset.list ~directory:value.presets })
      | _ -> prompt) value.prompt actions in
    let prompt_panel ui prompt =
      let module Ui = Pxui.Ui in
      let next = match prompt with
      | None -> None, None
      | Some (Saving name) ->
          (match Ui.modal ui ~width:360. "preset-save" (fun () ->
              Ui.label ui "Save preset";
              Ui.picker ui "Preset name" ~query:name (fun _ -> [||])) with
           | None | Some (_, `Cancel) -> None, None
           | Some (name, `Submit) -> None, Some (Save_preset_file name)
           | Some (name, _) -> Some (Saving name), None)
      | Some (Browsing { query; presets }) ->
          let rows query = List.filter (fun (name, _) -> Ui.fuzzy_match ~query name) presets
            |> List.map (fun (name, time) ->
              let tm = Unix.localtime time in
              name, Printf.sprintf "%02d-%02d %02d:%02d" (tm.tm_mon + 1) tm.tm_mday
                tm.tm_hour tm.tm_min) |> Array.of_list in
          (match Ui.modal ui ~width:420. "preset-browse" (fun () ->
              Ui.label ui (Printf.sprintf "Presets · %d" (List.length presets));
              Ui.picker ui "Search presets" ~query rows) with
           | None | Some (_, `Cancel) -> None, None
           | Some (query, `Pick index) ->
               let name = fst (rows query).(index) in
               None, Some (Load_preset_file name)
           | Some (query, `Delete index) ->
               let name = fst (rows query).(index) in
               Some (Browsing { query; presets }),
               Some (Delete_preset_file { name; query })
           | Some (query, _) -> Some (Browsing { query; presets }), None) in
      (* A closed prompt must not keep keyboard focus into the next frame. *)
      if fst next = None && value.prompt <> None then Ui.unfocus ui;
      next in
    let result =
      if all_ui_visible then
        Pxui.Ui.frame value.ui frame (fun ui ->
          let result = build ui in
          status_box { value with workspace = result.workspace;
              status_fps } ui frame
            ~render_status;
          let prompt, prompt_intent = prompt_panel ui initial_prompt in
          leader_panel ui;
          { result with prompt; prompt_intent })
      else begin
        if leader = Leader.Pending then Pxui.Ui.frame value.ui frame leader_panel;
        { workspace; graph_view; document = value.document;
          edit_error = value.edit_error; inspector = value.inspector;
          effects = Parameter.no_effects; timeline_intents = [];
          frame_request = initial_frame_request; prompt = initial_prompt;
          prompt_intent = None }
      end in
    let timeline, timeline_changes = List.fold_left (fun (timeline, changes) intent ->
      let next, emitted = match intent with
        | Pause_toggle -> Sketch_support.Timeline.toggle_pause timeline
        | Stop_playback -> Sketch_support.Timeline.stop timeline
        | Reset_playback -> Sketch_support.Timeline.reset timeline
        | Seek_playback frame -> Sketch_support.Timeline.seek timeline ~frame in
      next, changes @ emitted) (timeline, timeline_changes) result.timeline_intents in
    let prompt, notice, loaded = match result.prompt_intent with
      | None -> result.prompt, value.notice, None
      | Some (Save_preset_file name) ->
          let notice = match Preset.save ~directory:value.presets ~name
              ~sketch:value.name ~document:result.document
              ~positions:(Pxui_graph.node_positions result.graph_view)
              ~display:(Some (Pxui_graph.viewed result.graph_view))
              ~active_camera:(Pxui_graph.flagged result.graph_view)
              ~view:(view_state ()) with
            | Ok path -> "Saved preset " ^ Filename.basename path
            | Error message -> "Preset not saved: " ^ message in
          result.prompt, Some notice, None
      | Some (Load_preset_file name) ->
          (match Preset.load ~path:(Preset.path ~directory:value.presets ~name)
              ~code:value.code_graph ~factories:value.factories with
           | Ok preset -> result.prompt, Some ("Loaded preset " ^ name), Some preset
           | Error message -> result.prompt, Some ("Preset rejected: " ^ message), None)
      | Some (Delete_preset_file { name; query }) ->
          let notice = match Preset.delete ~directory:value.presets ~name with
            | Ok () -> "Deleted preset " ^ name
            | Error message -> "Preset not deleted: " ^ message in
          Some (Browsing { query; presets = Preset.list ~directory:value.presets }),
          Some notice, None in
    let document, graph_view, inspector, edit_error = match loaded with
      | None -> result.document, result.graph_view, result.inspector, result.edit_error
      | Some (preset : Preset.loaded) ->
          let graph_view = List.fold_left (fun view (node_id, x, y) ->
              Pxui_graph.place_node ~node_id ~x ~y view)
            (Pxui_graph.with_document preset.document graph_view |> Pxui_graph.clear_selection)
            preset.positions in
          let graph_view = match preset.display with
            | Some id -> Pxui_graph.view id graph_view | None -> graph_view in
          preset.document,
          Pxui_graph.with_flagged preset.active_camera graph_view, None, None in
    (* Shared undo stack: every document change (graph edits, node creation,
       paste, inspector commits) becomes one history entry; Command/Ctrl-Z
       undoes, Shift-Command/Ctrl-Z or Ctrl-Y redoes. *)
    let dragging = Frame.mouse_down Input.LeftButton frame in
    let history = if document == value.document then value.history
      else Editor.History.record
          ~merge:(if dragging then Gesture 0 else Step) document value.history in
    let ended_gesture = Frame.has_event (function
      | Event.MouseReleased (Input.LeftButton, _) | Event.WindowFocusLost -> true
      | _ -> false) frame in
    let history = if ended_gesture then Editor.History.seal history else history in
    let stepped = if List.mem Leader.Redo actions then Editor.History.redo history
      else if List.mem Leader.Undo actions then Editor.History.undo history else None in
    let history, document, undone = match stepped with
      | Some history -> history, Editor.History.present history, true
      | None -> history, document, false in
    let inspector = if undone then None else inspector in
    let effects = if undone then Parameter.union_effects result.effects Doc.cook_effects
      else result.effects in
    let graph_view = Pxui_graph.with_document document graph_view in
    let displayed_id = Pxui_graph.viewed graph_view in
    let display_changed = displayed_id <> value.displayed_id in
    let document_changed = document != value.document in
    let cooked = Cook.update value.cook ~document ~displayed_id ~graph:value.graph
        ~displayed_graph:value.displayed_graph ~edit_error ~display_changed
      ~document_changed ~effects ~timeline_changes ~timeline ~frame
      ~frame_request:result.frame_request in
    { core = { value with graph = cooked.graph;
        displayed_graph = cooked.displayed_graph; document; graph_view; displayed_id;
        inspector; workspace = result.workspace; timeline; cook = cooked.cook;
        edit_error = cooked.edit_error;
        status_fps; status_fps_at; history; focus; leader; prompt;
        notice = if document_changed && Option.is_none loaded then None else notice };
      effects; prepared_changed = cooked.prepared_changed;
      framed = cooked.framed;
      loaded_view = Option.map (fun (preset : Preset.loaded) -> preset.view) loaded;
      actions; input = frame }

  (* Environment-owned document edits (camera bookkeeping, follow viewport).
     They never affect the displayed cook: [`Reset] starts the history,
     [`Amend] folds into the present entry, and [`View time] coalesces a burst
     of view edits (a drag, a wheel gesture) into one undo entry. *)
  let environment_edit value mode document =
    let history = match mode with
      | `Reset -> Editor.History.create document
      | `Amend -> Editor.History.record ~merge:Repair document value.history
      | `View time -> Editor.History.record
          ~merge:(Burst { key = "view"; at = time; window = 0.25 })
          document value.history in
    { value with document; history;
      graph_view = Pxui_graph.with_document document value.graph_view }

  let machinery value ~all_ui_visible =
    if all_ui_visible || value.leader = Leader.Pending then Pxui.Ui.scene value.ui
    else []

  let close value =
    Pxui.Ui.destroy value.ui;
    Cook.close value.cook
end

module CC = Pxui.Camera_control
module CC2 = Pxui.Camera2_control

let set_ui_cursor ui visible =
  let shape = match if visible then Pxui.Ui.cursor ui else None with
    | Some shape -> (shape :> [`Default|`Horizontal_resize|`Vertical_resize])
    | None -> `Default in
  match Sketch.set_cursor shape with Ok () -> () | Error error -> failwith error

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
    look_through : bool;
    fly : float option;  (* flying at this speed, with relative pointer *)
    (* The active camera node's view, refreshed each update. *)
    render_camera : Camera.t;
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

  (* ---- camera nodes: SOPs with operation "camera" (Sop_catalog.Camera). *)

  let camera_ids document = Edit_graph.inspect document
    |> List.filter_map (fun (info : Edit_graph.node_info) ->
      if info.operation = "camera" then Some info.id else None)

  let follows node = match Sop_catalog.Camera.of_node node with
    | Some (_, follow_viewport) -> follow_viewport | None -> false

  let node_camera node = Option.map fst (Sop_catalog.Camera.of_node node)

  let view_parameters easy =
    let camera = Easy_camera.camera easy in
    let eye = Camera.position camera and target = Camera.target camera in
    Sop_catalog.Camera.to_values ~eye ~target ~fov_y:(Easy_camera.fov_y easy)

  let same_view a b =
    Vec3.nearly_equal (Camera.position a) (Camera.position b) ~eps:1e-6
    && Vec3.nearly_equal (Camera.target a) (Camera.target b) ~eps:1e-6
    && (match Camera.projection a, Camera.projection b with
      | Perspective a, Perspective b -> Float.abs (a.fov_y -. b.fov_y) < 1e-6
      | _ -> false)

  let active_node (core : _ Core.t) = Option.bind (Pxui_graph.flagged core.graph_view)
      (fun node_id -> Edit_graph.find core.document ~node_id)

  (* A default camera, following the viewport, when the catalog offers one. *)
  let add_default_camera ~factories document easy =
    let ( let* ) = Result.bind in
    match List.find_opt (fun factory -> Edit_graph.factory_key factory = "camera")
        factories with
    | None -> None
    | Some factory ->
        Result.to_option (
          let* node = Edit_graph.instantiate factory [] in
          let* document = Edit_graph.add_node ~factory node document in
          let* document, _ = Edit_graph.apply_parameters document ~node_id:(Node.id node)
              (("follow_viewport", Parameter.Bool_value true) :: view_parameters easy) in
          Ok document)

  (* One ACTIVE camera whenever any exists; losing the last one re-adds the
     default within the same undo entry. *)
  let sync_cameras ~mode (core : _ Core.t) easy =
    let core = if camera_ids core.document <> [] then core
      else match add_default_camera ~factories:core.factories core.document easy with
        | Some document -> Core.environment_edit core mode document
        | None -> core in
    let ids = camera_ids core.document in
    let active = match Pxui_graph.flagged core.graph_view with
      | Some id when List.mem id ids -> Some id
      | Some _ | None -> (match ids with id :: _ -> Some id | [] -> None) in
    if active = Pxui_graph.flagged core.graph_view then core
    else { core with graph_view = Pxui_graph.with_flagged active core.graph_view }

  let render_camera_of core easy = match active_node core with
    | Some node -> Option.value (node_camera node) ~default:(Easy_camera.camera easy)
    | None -> Easy_camera.camera easy

  let create ?(layout = default_layout) ?name ?presets ?timeline_frames ?factories
      ?(camera = Easy_camera.create ~target:Vec3.zero ~distance:7. ())
      ?(background = Color.hex_exn "#09090b") ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      let core = sync_cameras ~mode:`Reset core camera in
      { core; camera; camera_control = CC.create (); scene3; overlay;
        rendered = None; render_status = ref None; pending_render = None;
        background; look_through = false; fly = None;
        render_camera = render_camera_of core camera; hidden_scene_cache = None })
      (Core.create ~keymap:Leader.keymap3
        ~seed_document:(fun factories document ->
          if camera_ids document <> [] then document
          else Option.value ~default:document
              (add_default_camera ~factories document camera))
        ~layout ?name ?presets ?timeline_frames ?factories ?seed
        ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare ())

  let graph value = Core.graph value.core
  let document value = Core.document value.core
  let prepared value = Core.prepared value.core
  let camera value = value.camera
  let render_camera value = value.render_camera
  let flying value = value.fly <> None
  let look_through value = value.look_through
  let timeline value = Core.timeline value.core
  let selected_node value = Core.selected_node value.core
  let displayed_node value = Core.displayed_node value.core
  let panes value frame = Core.panes value.core frame
  let graph_nodes value = Pxui_graph.node_views value.core.graph_view
  let rerender value =
    { value with core = { value.core with Core.cook = Cook.force value.core.cook };
      rendered = Option.map (value.scene3 (Core.displayed_node value.core))
          (Core.prepared value.core) }
  let can_undo value = Editor.History.can_undo value.core.Core.history
  let can_redo value = Editor.History.can_redo value.core.Core.history

  (* Fly mode owns the keyboard: Escape or focus loss ends it; Space ends it
     and reaches the workspace, arming the leader in the same frame. *)
  let fly_input value (frame : Frame.t) =
    match value.fly with
    | None -> value.fly, frame
    | Some _ as fly ->
        let ends = List.exists (function
          | Event.KeyPressed (Input.Escape | Input.Space) | Event.WindowFocusLost -> true
          | _ -> false) frame.events in
        (if ends then None else fly),
        { frame with events = List.filter (function
            | Event.KeyPressed Input.Space | Event.WindowFocusLost -> true
            | Event.KeyPressed _ | Event.KeyReleased _ | Event.TextInput _
            | Event.TextEditing _ -> false
            | _ -> true) frame.events }

  let set_relative enabled = ignore (Sketch.set_relative_mouse enabled)

  (* Preset view settings: the viewport camera and look-through. *)
  let view_json easy look_through =
    let camera = Easy_camera.camera easy in
    let vector (v : Vec3.t) = `List [`Float v.x; `Float v.y; `Float v.z] in
    `Assoc [ "eye", vector (Camera.position camera); "target", vector (Camera.target camera);
             "fov", `Float (Easy_camera.fov_y easy); "look_through", `Bool look_through ]

  let load_view easy json =
    let number = function `Float v -> Some v | `Int v -> Some (float_of_int v) | _ -> None in
    let vector = function
      | Some (`List [x; y; z]) ->
          (match number x, number y, number z with
           | Some x, Some y, Some z -> Some (Vec3.create x y z) | _ -> None)
      | _ -> None in
    match json with
    | `Assoc fields ->
        let field name = List.assoc_opt name fields in
        let easy = match vector (field "eye"), vector (field "target") with
          | Some eye, Some target -> Easy_camera.of_view ~eye ~target easy
          | _ -> easy in
        let easy = match Option.bind (field "fov") number with
          | Some fov when fov > 0. && fov < Float.pi -> Easy_camera.with_fov_y fov easy
          | _ -> easy in
        easy, field "look_through" = Some (`Bool true)
    | _ -> easy, false

  let update_with value frame ~inspector =
    let ui = value.core.Core.ui in
    let raw_frame = frame in
    let fly, frame = fly_input value frame in
    if value.fly <> None && fly = None then set_relative false;
    let visible = CC.ui_visible value.camera_control in
    let control = ref value.camera_control and camera = ref value.camera
    and requests = ref [] and inspected = ref None
    and look_through = ref value.look_through in
    let camera_panel () =
      let next, edited, saves = CC.widgets !control ui ~camera:!camera in
      control := next; camera := edited; requests := saves;
      look_through := Pxui.Ui.toggle ui "Look through render camera" !look_through;
      inspected := Some (inspector ui) in
    let update = Core.update value.core ~all_ui_visible:visible
        ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel
        ~render_status:!(value.render_status)
        ~view_state:(fun () -> view_json !camera !look_through) frame in
    let core = update.core and panes = Core.panes update.core frame in
    let control = List.fold_left (fun control -> function
      | Leader.Hide_ui -> CC.toggle_ui control
      | Open_camera -> CC.open_camera control
      | _ -> control) !control update.actions in
    (match Option.map (load_view !camera) update.loaded_view with
     | Some (loaded, look) -> camera := loaded; look_through := look
     | None -> ());
    let look_through = List.fold_left (fun look -> function
      | Leader.Look_through -> not look | _ -> look) !look_through update.actions in
    let fly = if fly = None && List.mem Leader.Fly update.actions then begin
        set_relative true;
        value.render_status :=
          Some "Flying: WASD/QE move, Shift x4, wheel speed, Esc exits";
        Some (Float.max 0.5 (Easy_camera.distance !camera *. 0.5))
      end else fly in
    let core = if core.document == value.core.document
        && Pxui_graph.flagged core.graph_view
           = Pxui_graph.flagged value.core.graph_view
      then core else sync_cameras ~mode:`Amend core !camera in
    let active = active_node core in
    let following = Option.fold ~none:false ~some:follows active in
    (* Looking through a camera that does not follow the viewport freezes
       orbit input: the view shows exactly the render camera. *)
    let control_area = if visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let camera, fly = match fly with
      | _ when look_through && active <> None && not following -> !camera, fly
      | Some speed ->
          let camera, speed = Easy_camera.fly ~speed !camera raw_frame in camera, Some speed
      | None -> CC.navigate ~control_area control !camera update.input, None in
    let camera = match update.framed with
      | Some (Some (min, max)) -> Easy_camera.frame_bounds ~min ~max camera
      | Some None -> value.render_status := Some "Nothing to frame: no cooked points";
          camera
      | None -> camera in
    (* Follow viewport: viewport motion writes the node (one coalesced undo
       entry per gesture); otherwise node edits and undo move the viewport. *)
    let core, camera = match active with
      | Some node when following ->
          let moved = not (same_view (Easy_camera.camera value.camera)
              (Easy_camera.camera camera)) in
          (match node_camera node with
           | Some node_view when moved || not (same_view node_view (Easy_camera.camera camera)) ->
               if moved then
                 match Edit_graph.apply_parameters core.document ~node_id:(Node.id node)
                     (view_parameters camera) with
                 | Ok (document, _) ->
                     Core.environment_edit core (`View frame.Frame.time) document, camera
                 | Error _ -> core, camera
               else core,
                 (match Camera.projection node_view with
                  | Perspective { fov_y; _ } -> Easy_camera.with_fov_y fov_y camera
                  | _ -> camera)
                 |> Easy_camera.of_view ~eye:(Camera.position node_view)
                      ~target:(Camera.target node_view)
           | Some _ | None -> core, camera)
      | Some _ | None -> core, camera in
    let rendered = if update.prepared_changed || update.effects.view
        || update.effects.export then
        Option.map (value.scene3 (Core.displayed_node core)) (Core.prepared core)
      else value.rendered in
    let pending_render = match List.rev !requests with
      | request :: _ -> Some request | [] -> None in
    if pending_render <> None && rendered = None then
      value.render_status := Some "Render unavailable until the first cook completes";
    { value with core; camera; camera_control = control; rendered; pending_render;
      look_through; fly; render_camera = render_camera_of core camera },
    !inspected

  let update value frame = fst (update_with value frame ~inspector:ignore)

  let after_present value _frame =
    match value.pending_render, value.rendered with
    | Some request, Some _ ->
        value.render_status := Some (match CC.save request with
          | Ok () -> "Saved " ^ request.filename
          | Error message -> "Render failed: " ^ message)
    | _ -> ()

  (* The view shows the render camera while looking through it and on the
     frame whose framebuffer a PNG request captures. *)
  let view_camera value =
    if value.look_through || value.pending_render <> None then value.render_camera
    else Easy_camera.camera value.camera

  let scene value frame =
    let all_ui_visible = CC.ui_visible value.camera_control in
    if not all_ui_visible && value.core.Core.leader = Leader.Pending then
      Scene.clear value.background
      :: (match value.rendered with
        | Some rendered when Core.column_visible value.core Workspace.View ->
            [Scene.view3d ~viewport:(0, 0, frame.Frame.width, frame.height)
               ~camera:(view_camera value) rendered]
        | Some _ | None -> [])
      @ Core.machinery value.core ~all_ui_visible
    else if not all_ui_visible then begin
      let camera = view_camera value in
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
          [Scene.view3d ~viewport ~camera:(view_camera value) rendered]
      | Some _ | None -> [] in
    let x, y, width, height = viewport in
    let overlay = [Scene.clip ~at:(x, y) ~w:width ~h:height
        [Scene.translate x y
           (value.overlay (Core.graph value.core) (Core.prepared value.core)
              (viewport_frame viewport frame))]] in
    Scene.clear value.background :: world @ overlay
    @ Core.machinery value.core ~all_ui_visible

  let close value =
    if value.fly <> None then set_relative false;
    Core.close value.core

  let run ?layout ?name ?presets ?timeline_frames ?factories ?camera ?background ?seed ?grain ?domains ?max_entries
      ?max_payload_bytes ~config ~graph ~prepare ~scene3
      ?overlay () =
    let name = Option.value name ~default:(String.lowercase_ascii config.Sketch.title) in
    let init _frame = create ?layout ~name ?presets ?timeline_frames ?factories ?camera ?background ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ~scene3
        ?overlay () |> Result.get_ok in
    let update value frame =
      let value = update value frame in
      set_ui_cursor value.core.ui (CC.ui_visible value.camera_control);
      value in
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

  let create ?(layout = default_layout) ?name ?presets ?timeline_frames ?factories
      ?(camera = Easy_camera2.create ())
      ?(background = Color.hex_exn "#09090b") ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      { core; camera; camera_control = CC2.create (); scene2; overlay;
        rendered = None; render_status = ref None; pending_render = None; background;
        hidden_scene_cache = None })
      (Core.create ~layout ?name ?presets ?timeline_frames ?factories ?seed ?grain
        ?domains ?max_entries
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
    let visible = CC2.ui_visible value.camera_control in
    let control = ref value.camera_control and camera = ref value.camera
    and requests = ref [] in
    let camera_panel () =
      let next, edited, saves = CC2.widgets !control ui ~camera:!camera in
      control := next; camera := edited; requests := saves in
    let update = Core.update value.core ~all_ui_visible:visible
        ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel
        ~render_status:!(value.render_status)
        ~view_state:(fun () -> let center = Easy_camera2.center !camera in
          `Assoc [ "center", `List [`Float center.Vec2.x; `Float center.y];
                   "zoom", `Float (Easy_camera2.zoom !camera);
                   "rotation", `Float (Easy_camera2.rotation !camera) ]) frame in
    let core = update.core and panes = Core.panes update.core frame in
    (match update.loaded_view with
     | Some (`Assoc fields) ->
         let number = function Some (`Float v) -> Some v
           | Some (`Int v) -> Some (float_of_int v) | _ -> None in
         (match List.assoc_opt "center" fields with
          | Some (`List [x; y]) ->
              (match number (Some x), number (Some y) with
               | Some x, Some y -> camera := Easy_camera2.with_center (Vec2.create x y) !camera
               | _ -> ())
          | _ -> ());
         Option.iter (fun zoom -> if zoom > 0. then camera := Easy_camera2.with_zoom zoom !camera)
           (number (List.assoc_opt "zoom" fields));
         Option.iter (fun rotation -> camera := Easy_camera2.with_rotation rotation !camera)
           (number (List.assoc_opt "rotation" fields))
     | Some _ | None -> ());
    let control = List.fold_left (fun control -> function
      | Leader.Hide_ui -> CC2.toggle_ui control
      | Open_camera -> CC2.open_camera control
      | _ -> control) !control update.actions in
    let viewport = if visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    let camera = CC2.navigate ~control_area:viewport ~viewport control !camera
        update.input in
    let rendered = if update.prepared_changed || update.effects.view
        || update.effects.export then
        Option.map (value.scene2 (Core.displayed_node core)) (Core.prepared core)
      else value.rendered in
    let pending_render = match List.rev !requests with
      | request :: _ -> Some request | [] -> None in
    if pending_render <> None && rendered = None then
      value.render_status := Some "Render unavailable until the first cook completes";
    { value with core; camera; camera_control = control; rendered; pending_render }

  let after_present value _frame =
    match value.pending_render, value.rendered with
    | Some request, Some _ ->
        value.render_status := Some (match CC2.save request with
          | Ok () -> "Saved " ^ request.filename
          | Error message -> "Render failed: " ^ message)
    | _ -> ()

  let scene value frame =
    let all_ui_visible = CC2.ui_visible value.camera_control in
    if not all_ui_visible && value.core.Core.leader = Leader.Pending then
      Scene.clear value.background
      :: (match value.rendered with
        | Some rendered when Core.column_visible value.core Workspace.View ->
            Easy_camera2.scene ~viewport:(0, 0, frame.Frame.width, frame.height)
              value.camera rendered
        | Some _ | None -> [])
      @ Core.machinery value.core ~all_ui_visible
    else if not all_ui_visible then begin
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

  let run ?layout ?name ?presets ?timeline_frames ?factories ?camera ?background ?seed ?grain ?domains ?max_entries
      ?max_payload_bytes ~config ~graph ~prepare ~scene2
      ?overlay () =
    let name = Option.value name ~default:(String.lowercase_ascii config.Sketch.title) in
    let init _frame = create ?layout ~name ?presets ?timeline_frames ?factories ?camera ?background ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ~scene2
        ?overlay () |> Result.get_ok in
    let update value frame =
      let value = update value frame in
      set_ui_cursor value.core.ui (CC2.ui_visible value.camera_control);
      value in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene
      ~after_present ~on_stop:close ())
end

module Private = struct module Workspace = Workspace module Leader = Leader end
