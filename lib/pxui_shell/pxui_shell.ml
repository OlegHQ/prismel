open Prismel

module Layout = struct
  type config = {
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

  let default = {
    view_ratio = 0.45;
    graph_ratio = 0.35;
    inspector_ratio = 0.20;
    splitter_width = 6;
    collapsed_width = 28;
    header_height = 22;
    status_height = 28;
    min_view_width = 220;
    min_graph_width = 180;
    min_inspector_width = 120;
  }

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
    config : config;
    view_ratio : float;
    graph_ratio : float;
    inspector_ratio : float;
    view_collapsed : bool;
    graph_collapsed : bool;
    inspector_collapsed : bool;
    timeline_collapsed : bool;
    mutable geometry_cache : geometry_cache option;
  }

  let validate (config : config) =
    let total = config.view_ratio +. config.graph_ratio
        +. config.inspector_ratio in
    if not (Float.is_finite total) || total <= 0. then
      invalid_arg "Sketch_ui layout ratios must have a positive finite sum";
    if config.splitter_width < 2 || config.collapsed_width < 18
        || config.header_height < 18 || config.status_height < 0 then
      invalid_arg "Sketch_ui layout dimensions are too small"

  let create (config : config) =
    validate config;
    let total = config.view_ratio +. config.graph_ratio
        +. config.inspector_ratio in
    { config; view_ratio = config.view_ratio /. total;
      graph_ratio = config.graph_ratio /. total;
      inspector_ratio = config.inspector_ratio /. total;
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
    let config = value.config in
    let available = max 3 (width - (2 * config.splitter_width)) in
    let collapsed = [|value.view_collapsed; value.graph_collapsed;
      value.inspector_collapsed|] in
    let ratios = [|value.view_ratio; value.graph_ratio;
      value.inspector_ratio|] in
    let minimums = [|config.min_view_width; config.min_graph_width;
      config.min_inspector_width|] in
    let widths = Array.make 3 0 in
    let fixed = ref 0 and weight = ref 0. in
    for index = 0 to 2 do
      if collapsed.(index) then begin
        widths.(index) <- config.collapsed_width;
        fixed := !fixed + config.collapsed_width
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
        let splitter = value.config.splitter_width in
        let x0 = 0 and x1 = widths.(0) + splitter
        and x2 = widths.(0) + splitter + widths.(1) + splitter in
        let header = min value.config.header_height (max 0 (frame.height - 1)) in
        let timeline = if value.timeline_collapsed then 0
          else min timeline_height (max 0 (frame.height - header - 1)) in
        let bottom = frame.height - timeline in
        let content_height = max 1 (bottom - header) in
        let status_height = min value.config.status_height
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
    (vx + vw, 0, value.config.splitter_width, frame.height),
    (gx + gw, 0, value.config.splitter_width, frame.height)

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
    let available = max 1 (frame.width - (2 * value.config.splitter_width)) in
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
end

module Chrome = struct
  open Layout
  let floating ui ?(flags = Pxui.Ui.none) (x, y, width, height) label =
    Pxui.Ui.box ui ~flags ~w:(Pxui.Ui.Px (float_of_int width))
      ~h:(Pxui.Ui.Px (float_of_int height)) ~at:(float_of_int x, float_of_int y) label

  (* Chrome of the retained workspace, painted and hit through PXUI boxes:
     pane backgrounds, splitters, and header bars with collapse buttons. *)
  let update value ui (frame : Frame.t) =
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
      let button = floating ui ~flags:Ui.clickable (button_bounds value frame column)
          ("workspace-collapse-" ^ title) in
      (if (Ui.signal ui button).clicked then toggle column value else value),
      (column, title, box) in
    let value, view_header = header View "VIEW" panes.view_header value in
    let value, graph_header = header Graph "GRAPH" panes.graph_header value in
    let value, inspector_header = header Inspector "INSPECTOR" panes.inspector_header value in
    List.iter (fun (column, title, box) ->
      Ui.draw ui box (fun paint (x, y, w, h) ->
        let glyph = if collapsed value column then ">" else "<" in
        Ui.Paint.rect paint ~x ~y ~w ~h ~fill:theme.foreground ~stroke:theme.foreground ();
        let x = int_of_float x and y = int_of_float y and w = int_of_float w in
        Ui.Paint.text paint ~at:(float_of_int (x + 10), float_of_int (y + 4)) ~size:11
          ~color:theme.input title;
        Ui.Paint.text paint ~at:(float_of_int (x + max 7 (w - 19)), float_of_int (y + 4))
          ~size:11 ~color:theme.accent glyph))
      [view_header; graph_header; inspector_header];
    value
end

module Which_key = struct
  open Editor.Keymap

  let panel ui keymap ~focus ~focus_name =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let row binding =
      let key = match binding.trigger with
        | Leader key -> String.make 1 key
        | Chord (Prismel.Input.KeyChar key, modifiers) ->
            (if List.mem Prismel.Input.Meta modifiers then "⌘"
             else if List.mem Prismel.Input.Ctrl modifiers then "Ctrl-" else "")
            ^ String.make 1 key
        | Chord (Prismel.Input.Delete, _) -> "Del"
        | Chord (Prismel.Input.Backspace, _) -> "⌫"
        | Chord (Prismel.Input.Home, _) -> "Home"
        | Chord _ -> "Key" in
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float_of_int (Ui.row_height ui)))
          ("leader-" ^ key) in
      Ui.draw ui box (fun paint (x, y, _, h) ->
        let y = y +. Float.max 5. ((h -. float_of_int (Ui.font_size ui) -. 3.) /. 2.) in
        Ui.Paint.text paint ~at:(x +. 8., y) ~color:theme.accent key;
        Ui.Paint.text paint ~at:(x +. 68., y) ~color:theme.foreground binding.label) in
    let section title scope =
      match List.filter (fun binding -> binding.scope = scope) keymap with
      | [] -> ()
      | bindings -> Ui.label ui title; List.iter row bindings in
    ignore (Ui.modal ui ~width:300. "leader" (fun () ->
      section "Leader · global" None;
      section focus_name (Some focus)))
end

module Status_bar = struct
  let draw ui ~bounds:(x, y, width, height) ~text ~fps =
    if height > 0 then begin
      let module Ui = Pxui.Ui in
      let box = Ui.box ui ~w:(Ui.Px (float_of_int width))
          ~h:(Ui.Px (float_of_int height))
          ~at:(float_of_int x, float_of_int y) "workspace-status" in
      let fps = match fps with
        | Some fps -> Printf.sprintf " · %d fps" fps | None -> "" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint _ ->
        Ui.Paint.fill paint ~x:(float_of_int x) ~y:(float_of_int y)
          ~w:(float_of_int width) ~h:(float_of_int height) theme.foreground;
        let at = float_of_int (x + 10), float_of_int (y + 8) in
        Ui.Paint.text paint ~at ~size:11 ~color:theme.input text;
        Ui.Paint.text paint
          ~at:(fst at +. Ui.Paint.text_width paint ~size:11 text, snd at)
          ~size:11 ~color:theme.input fps)
    end
end
