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
  }

  let validate (config : config) =
    let total = config.view_ratio +. config.graph_ratio
        +. config.inspector_ratio in
    if not (Float.is_finite total) || total <= 0. then
      invalid_arg "Prismel_editor layout ratios must have a positive finite sum";
    if config.splitter_width < 2 || config.collapsed_width < 18
        || config.header_height < 18 || config.status_height < 0 then
      invalid_arg "Prismel_editor layout dimensions are too small"

  let create (config : config) =
    validate config;
    let total = config.view_ratio +. config.graph_ratio
        +. config.inspector_ratio in
    { config; view_ratio = config.view_ratio /. total;
      graph_ratio = config.graph_ratio /. total;
      inspector_ratio = config.inspector_ratio /. total;
      view_collapsed = false; graph_collapsed = false;
      inspector_collapsed = false; timeline_collapsed = true }

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

  (* Collapsed Graph and Inspector vanish (the leader keymap reopens them);
     a collapsed View keeps a strip with its expand button. *)
  let splitters value =
    let s = value.config.splitter_width in
    (if value.graph_collapsed && value.inspector_collapsed then 0 else s),
    (if value.graph_collapsed || value.inspector_collapsed then 0 else s)

  let distribute value width =
    let config = value.config in
    let first, second = splitters value in
    let available = max 3 (width - first - second) in
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
        let strip = if index = 0 then config.collapsed_width else 0 in
        widths.(index) <- strip;
        fixed := !fixed + strip
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

  (* ponytail: the layout has three columns, so recompute instead of mutating
     a cache during Ui.frame; thread panes through the frame if this grows. *)
  let geometry value frame =
    let widths = distribute value frame.Frame.width in
    let first, second = splitters value in
    let x0 = 0 and x1 = widths.(0) + first
    and x2 = widths.(0) + first + widths.(1) + second in
    let header = min value.config.header_height (max 0 (frame.height - 1)) in
    let timeline = if value.timeline_collapsed then 0
      else min timeline_height (max 0 (frame.height - header - 1)) in
    let bottom = frame.height - timeline in
    let content_height = max 1 (bottom - header) in
    let status_height = min value.config.status_height
        (max 0 (content_height - 1)) in
    { view = x0, header, widths.(0), content_height - status_height;
      graph = x1, header, widths.(1), content_height;
      inspector = x2, header, widths.(2), content_height;
      status = x0, bottom - status_height, widths.(0), status_height;
      timeline = 0, bottom, frame.width, timeline;
      view_header = x0, 0, widths.(0), header;
      graph_header = x1, 0, widths.(1), header;
      inspector_header = x2, 0, widths.(2), header }

  let splitter_bounds value frame =
    let panes = geometry value frame in
    let vx, _, vw, _ = panes.view and gx, _, gw, _ = panes.graph in
    let first, second = splitters value in
    (vx + vw, 0, first, frame.height), (gx + gw, 0, second, frame.height)

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

  let pane_root ui (frame : Frame.t) ~bounds:(x, y, width, height) label =
    Pxui.Ui.box ui ~flags:Pxui.Ui.clickable
      ~w:(Pxui.Ui.Px (float_of_int frame.width))
      ~h:(Pxui.Ui.Px (float_of_int frame.height)) ~at:(0., 0.)
      ~hit:(fun _ -> float x, float y, float width, float height) label

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
      let button = floating ui ~flags:Ui.(clickable + tab_stop) (button_bounds value frame column)
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

  let focus ui ~bounds:(x, y, width, height) =
    if width > 2 && height > 2 then begin
      let theme = Pxui.Ui.theme ui in
      Pxui.Ui.draw ui (floating ui (x, y, width, height) "workspace-focus")
        (fun paint _ -> Pxui.Ui.Paint.stroke paint
          ~x:(float_of_int x +. 0.5) ~y:(float_of_int y +. 0.5)
          ~w:(float_of_int (width - 1)) ~h:(float_of_int (height - 1))
          ~width:1. theme.accent)
    end
end

module Which_key = struct
  open Editor_core.Keymap
  open Editor_core.Command

  (* One page per typed prefix: a key that continues into longer sequences
     shows as a "+group" row named by the first word of its first command. *)
  let page keymap ~prefix scope =
    List.fold_left (fun rows command -> match command.trigger with
      | Some (Leader sequence) when command.scope = scope
          && String.length sequence > String.length prefix
          && String.starts_with ~prefix sequence ->
          let key = String.make 1 sequence.[String.length prefix] in
          if List.mem_assoc key rows then rows
          else rows @ [key, if String.length sequence = String.length prefix + 1
            then command.label
            else "+" ^ List.hd (String.split_on_char ' ' command.label)]
      | Some (Chord (key, modifiers)) when prefix = "" && command.scope = scope ->
          rows @ [(match key with
            | Prismel.Input.KeyChar key ->
                (if List.mem Prismel.Input.Meta modifiers then "⌘"
                 else if List.mem Prismel.Input.Ctrl modifiers then "Ctrl-" else "")
                ^ String.make 1 key
            | Prismel.Input.Delete -> "Del"
            | Prismel.Input.Backspace -> "⌫"
            | Prismel.Input.Home -> "Home"
            | _ -> "Key"), command.label]
      | _ -> rows) [] keymap

  let panel ui keymap ~prefix ~focus ~focus_name =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let row (key, label) =
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float_of_int (Ui.row_height ui)))
          ("leader-" ^ key ^ "-" ^ label) in
      Ui.draw ui box (fun paint (x, y, _, h) ->
        let y = y +. Float.max 5. ((h -. float_of_int (Ui.font_size ui) -. 3.) /. 2.) in
        Ui.Paint.text paint ~at:(x +. 8., y) ~color:theme.accent key;
        Ui.Paint.text paint ~at:(x +. 68., y) ~color:theme.foreground label) in
    let section title scope = match page keymap ~prefix scope with
      | [] -> ()
      | rows -> Ui.label ui title; List.iter row rows in
    let leader = if prefix = "" then "Leader" else "Leader " ^ prefix in
    ignore (Ui.modal ui ~width:300. "leader" (fun () ->
      section (leader ^ " · global") None;
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

module Timeline_bar = struct
  type intent = Pause_toggle | Stop_playback | Reset_playback
    | Seek_playback of int64

  let draw ui ~bounds:(x, y, width, height) ~playing ~frame ~time ~max_frame =
    let module Ui = Pxui.Ui in
    Ui.panel ui ~x:(float_of_int x) ~y:(float_of_int y)
      ~width:(float_of_int width) ~max_height:(float_of_int height)
      "workspace-timeline" (fun () ->
      Ui.row ui ~gap:6. "timeline-row" (fun () ->
        let pause = Ui.button ui (if playing then "Pause###timeline-play"
          else "Play###timeline-play") in
        let stop = Ui.button ui "Stop###timeline-stop" in
        let reset = Ui.button ui "Reset###timeline-reset" in
        Ui.label ui (Printf.sprintf "f %Ld  %.2fs###timeline-readout" frame time);
        let range = Float.max (Int64.to_float frame) (float_of_int max_frame) in
        let scrub = Ui.slider ui "Frame###timeline-scrub" ~range:(0., range)
          (Int64.to_float frame) in
        List.filter_map Fun.id [
          (if pause then Some Pause_toggle else None);
          (if stop then Some Stop_playback else None);
          (if reset then Some Reset_playback else None);
          (if scrub <> Int64.to_float frame
            then Some (Seek_playback (Int64.of_float (Float.round scrub)))
            else None)]))
end

module Prompt = struct
  let name ui ~key ~title ~label ~query =
    Pxui.Ui.modal ui ~width:360. key (fun () ->
      Pxui.Ui.label ui title;
      Pxui.Ui.picker ui label ~query (fun _ -> [||]))

  let search ui ~key ~title ~label ~query ~rows =
    Pxui.Ui.modal ui ~width:420. key (fun () ->
      Pxui.Ui.label ui title;
      Pxui.Ui.picker ui label ~query rows)
end

module Tree = struct
  module Ui = Pxui.Ui
  module Ids = Set.Make (Int)

  type row = { id : int; depth : int; label : string; detail : string;
               badge : string * Prismel.Color.t;
               link : bool; ghost : bool; flags : bool list }
  type drop = Before | Inside | After
  type intent =
    | Select of int list
    | Flag of { ids : int list; column : int; value : bool }
    | Move of { ids : int list; target : int; drop : drop }
    | Indent of int list
    | Outdent of int list
    | Reorder of { ids : int list; delta : int }
    | Rename of int * string
    | Activate of int
    | Delete of int list
  type command = Up | Down | Extend_up | Extend_down | Collapse | Expand
    | First | Last | Indent_rows | Outdent_rows | Move_up | Move_down
    | Rename_row | Filter | Hide | Activate_row

  type drag =
    | Rows of { ids : int list; moved : bool }
    | Paint of { column : int; value : bool; painted : int list }

  type t = { focus : int option; anchor : int option; folded : Ids.t;
             filter : string option; renaming : (int * string) option;
             scroll : float; drag : drag option; reveal : bool;
             context : (float * float * int * int list) option;
             shown : (row array * Ids.t * string option * int array) option }

  let create () = { focus = None; anchor = None; folded = Ids.empty; filter = None;
    renaming = None; scroll = 0.; drag = None; reveal = false; context = None;
    shown = None }
  let rename id label t = { t with renaming = Some (id, label); focus = Some id; reveal = true }
  let reveal t = { t with reveal = true }
  let focused t = t.focus
  let editing t = t.renaming <> None || t.filter <> None

  let bindings =
    let open Editor_core.Keymap in
    let key ?(modifiers = []) id label key action = Editor_core.Command.make
        ~id:("list." ^ id) ~label ~trigger:(Chord (key, modifiers)) action in
    let open Prismel.Input in
    [ key "up" "previous row" ArrowUp Up; key "down" "next row" ArrowDown Down;
      key "extend-up" "extend selection up" ArrowUp Extend_up ~modifiers:[Shift];
      key "extend-down" "extend selection down" ArrowDown Extend_down ~modifiers:[Shift];
      key "collapse" "fold / parent" ArrowLeft Collapse;
      key "expand" "unfold / first child" ArrowRight Expand;
      key "first" "first row" Home First; key "last" "last row" End Last;
      key "indent" "reparent under previous" Tab Indent_rows;
      key "outdent" "reparent up a level" Tab Outdent_rows ~modifiers:[Shift];
      key "move-up" "move up" ArrowUp Move_up ~modifiers:[Alt];
      key "move-down" "move down" ArrowDown Move_down ~modifiers:[Alt];
      key "rename" "rename" F2 Rename_row;
      key "filter" "filter" (KeyChar '/') Filter;
      key "hide" "hide / show" (KeyChar 'h') Hide ]

  let has_children rows index =
    index + 1 < Array.length rows && rows.(index + 1).depth > rows.(index).depth

  (* Indices of the shown rows: a filter keeps matches and their ancestors
     (and ignores folds); a folded row hides its descendants. *)
  let visible t rows =
    let count = Array.length rows in
    let filtering = match t.filter with None | Some "" -> false | Some _ -> true in
    let keep = if not filtering then Array.make count true else begin
      let query = Option.get t.filter in
      let keep = Array.make count false and stack = Array.make (count + 1) 0 in
      Array.iteri (fun index row ->
        let depth = min row.depth count in
        stack.(depth) <- index;
        if Ui.fuzzy_match ~query row.label then
          for level = 0 to depth do keep.(stack.(level)) <- true done) rows;
      keep end in
    let shown = ref [] and hidden_below = ref max_int in
    Array.iteri (fun index row ->
      if row.depth <= !hidden_below then hidden_below := max_int;
      if !hidden_below = max_int && keep.(index) then begin
        shown := index :: !shown;
        if not filtering && Ids.mem row.id t.folded && has_children rows index
        then hidden_below := row.depth
      end) rows;
    Array.of_list (List.rev !shown)

  (* The shown rows, recomputed only when the rows, folds, or filter change. *)
  let shown t rows = match t.shown with
    | Some (source, folded, filter, shown) when source == rows && folded == t.folded
        && filter = t.filter -> t, shown
    | _ -> let shown = visible t rows in
        { t with shown = Some (rows, t.folded, t.filter, shown) }, shown

  let position rows shown id =
    let found = ref None in
    Array.iteri (fun k index ->
      if !found = None && rows.(index).id = id then found := Some k) shown;
    !found

  let span rows shown a b =
    List.init (abs (b - a) + 1) (fun offset -> rows.(shown.(min a b + offset)).id)

  let run_command t rows ~selected command =
    let t, shown = shown t rows in
    let count = Array.length shown in
    let at k = rows.(shown.(k)) in
    let current = Option.bind t.focus (position rows shown) in
    let move k =
      let id = (at (max 0 (min (count - 1) k))).id in
      { t with focus = Some id; anchor = Some id; reveal = true }, [Select [id]] in
    let extend k =
      let k = max 0 (min (count - 1) k) in
      let anchor = Option.value ~default:k (Option.bind t.anchor (position rows shown)) in
      { t with focus = Some (at k).id; reveal = true },
      [Select ((at k).id :: List.filter (( <> ) (at k).id) (span rows shown anchor k))] in
    let targets = if selected = [] then Option.to_list t.focus else selected in
    if count = 0 then t, [] else
    match command, current with
    | Up, Some k -> move (k - 1)
    | Down, Some k -> move (k + 1)
    | (Up | Extend_up), None -> move (count - 1)
    | (Down | Extend_down), None -> move 0
    | First, _ -> move 0
    | Last, _ -> move (count - 1)
    | Extend_up, Some k -> extend (k - 1)
    | Extend_down, Some k -> extend (k + 1)
    | Collapse, Some k ->
        let index = shown.(k) in
        if has_children rows index && not (Ids.mem rows.(index).id t.folded)
        then { t with folded = Ids.add rows.(index).id t.folded }, []
        else
          let parent = ref None in
          for candidate = k - 1 downto 0 do
            if !parent = None && (at candidate).depth < (at k).depth then parent := Some candidate
          done;
          (match !parent with Some parent -> move parent | None -> t, [])
    | Expand, Some k ->
        let index = shown.(k) in
        if Ids.mem rows.(index).id t.folded
        then { t with folded = Ids.remove rows.(index).id t.folded }, []
        else if has_children rows index then move (k + 1) else t, []
    | Indent_rows, _ -> t, [Indent targets]
    | Outdent_rows, _ -> t, [Outdent targets]
    | Move_up, _ -> t, [Reorder { ids = targets; delta = -1 }]
    | Move_down, _ -> t, [Reorder { ids = targets; delta = 1 }]
    | Filter, _ -> { t with filter = Some (Option.value t.filter ~default:"") }, []
    | Rename_row, Some k when not (at k).ghost ->
        { t with renaming = Some ((at k).id, (at k).label) }, []
    | Hide, Some k ->
        let value = match (at k).flags with shown :: _ -> not shown | [] -> true in
        t, [Flag { ids = targets; column = 0; value }]
    | Activate_row, Some k -> t, [Activate (at k).id]
    | (Collapse | Expand | Rename_row | Hide | Activate_row), _ -> t, []

  let flag_width = 34.

  (* The row list, its toggle columns, and the filter and rename prompts,
     built inside [Ui.frame]. One box takes every pointer gesture; rows are
     found from the pointer, so only the visible slice is painted. *)
  let update t ui (_frame : Prismel.Frame.t) ~bounds:(x, y, w, h) ?(title = "") ~columns rows
      ~selected =
    let theme = Ui.theme ui in
    let height = float_of_int (Ui.row_height ui) in
    let x = float_of_int x and y = float_of_int y
    and w = float_of_int w and h = float_of_int h in
    let shown = visible t rows in
    let count = Array.length shown in
    let at k = rows.(shown.(k)) in
    let top = y +. height in
    let body = Float.max height (h -. height) in
    let box = Ui.box ui ~flags:Ui.(clickable + scroll + clip + blocking)
        ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(x, y) "tree" in
    let signal = Ui.signal ui box in
    let scroll = t.scroll -. snd signal.scroll *. height in
    let scroll = match t.reveal, Option.bind t.focus (position rows shown) with
      | true, Some k ->
          let row_top = float_of_int k *. height in
          if row_top < scroll then row_top
          else if row_top +. height > scroll +. body then row_top +. height -. body
          else scroll
      | _ -> scroll in
    let scroll = Float.max 0. (Float.min scroll
        (Float.max 0. (float_of_int count *. height -. body))) in
    let row_at (_, py) =
      let k = int_of_float (Float.floor ((py -. top +. scroll) /. height)) in
      if py < top || k < 0 || k >= count then None else Some k in
    let columns_x = x +. w -. flag_width *. float_of_int (List.length columns) in
    let column_at (px, _) =
      if px < columns_x then None
      else Some (int_of_float ((px -. columns_x) /. flag_width)) in
    let flag k column = match List.nth_opt (at k).flags column with
      | Some value -> value | None -> false in
    let is_selected id = List.mem id selected in
    let left = signal.button = Some Prismel.Input.LeftButton in
    let modifier key = List.mem key (Ui.press_keys ui box) in
    (* Presses: select, start a row drag or a toggle paint. *)
    let t, intents = if not (signal.pressed && left) then t, [] else
      match row_at signal.press_point with
      | None -> { t with drag = None }, [Select []]
      | Some k ->
          let row = at k in
          (match column_at signal.press_point with
           | Some column when column < List.length row.flags && not row.ghost ->
               let value = not (flag k column) in
               let ids = if is_selected row.id then selected else [row.id] in
               { t with drag = Some (Paint { column; value; painted = ids }) },
               [Flag { ids; column; value }]
           | _ ->
               let selection =
                 if modifier Prismel.Input.Shift then
                   let anchor = Option.value ~default:k
                       (Option.bind t.anchor (position rows shown)) in
                   row.id :: List.filter (( <> ) row.id) (span rows shown anchor k)
                 else if modifier Prismel.Input.Meta || modifier Prismel.Input.Ctrl then
                   if is_selected row.id then List.filter (( <> ) row.id) selected
                   else row.id :: selected
                 else if is_selected row.id then
                   row.id :: List.filter (( <> ) row.id) selected
                 else [row.id] in
               { t with focus = Some row.id;
                 anchor = (if modifier Prismel.Input.Shift then t.anchor else Some row.id);
                 drag = if row.ghost then None
                   else Some (Rows { ids = selection; moved = false }) },
               [Select selection]) in
    (* Right-click: a menu on the row, or on the selection when the row is
       in it; it never changes the selection. *)
    let t = if not (Ui.context_clicked signal) then t else
      match row_at signal.release_point with
      | Some k when not (at k).ghost ->
          let id = (at k).id in
          let x, y = signal.release_point in
          { t with context = Some (x, y, id,
              if is_selected id then selected else [id]) }
      | Some _ | None -> t in
    let t, intents = match t.context with
      | None -> t, intents
      | Some (x, y, id, ids) ->
          let shown = match List.find_opt (fun (row : row) -> row.id = id)
              (Array.to_list rows) with
            | Some row -> (match row.flags with value :: _ -> Some value | [] -> None)
            | None -> None in
          (match Ui.context_menu ui ~at:(x, y) "tree-context"
              ["Enter", true; "Rename", true;
               (if shown = Some false then "Show" else "Hide"), shown <> None;
               "Delete", true] with
           | `Open -> t, intents
           | `Dismiss -> { t with context = None }, intents
           | `Pick 0 -> { t with context = None }, intents @ [Activate id]
           | `Pick 1 -> { t with context = None; renaming = Some (id,
               Option.fold ~none:"" ~some:(fun (row : row) -> row.label)
                 (List.find_opt (fun (row : row) -> row.id = id) (Array.to_list rows))) },
               intents
           | `Pick 2 -> { t with context = None },
               intents @ [Flag { ids; column = 0; value = shown = Some false }]
           | `Pick _ -> { t with context = None }, intents @ [Delete ids]) in
    let intents = if signal.double_clicked && left then
        match row_at signal.pointer with
        | Some k -> intents @ [Activate (at k).id]
        | None -> intents
      else intents in
    (* Held gestures: a 4-point dead zone starts a row drag; paint applies
       the toggle value to each row the pointer passes. *)
    let t, intents = match t.drag with
      | Some (Rows { ids; moved }) when signal.held || signal.released ->
          let px, py = signal.pointer and sx, sy = signal.press_point in
          let moved = moved || Float.hypot (px -. sx) (py -. sy) >= 4. in
          if not signal.released then { t with drag = Some (Rows { ids; moved }) }, intents
          else
            let drop = match row_at signal.pointer with
              | Some k when moved && not (List.mem (at k).id ids) && not (at k).ghost ->
                  let offset = (py -. top +. scroll) /. height -. float_of_int k in
                  [Move { ids; target = (at k).id;
                    drop = if offset < 0.25 then Before
                      else if offset > 0.75 then After else Inside }]
              | _ -> [] in
            { t with drag = None }, intents @ drop
      | Some (Paint { column; value; painted }) when signal.held || signal.released ->
          let fresh = match row_at signal.pointer with
            | Some k when not (List.mem (at k).id painted) && not (at k).ghost
                && column < List.length (at k).flags && flag k column <> value ->
                [(at k).id]
            | _ -> [] in
          { t with drag = if signal.released then None
              else Some (Paint { column; value; painted = fresh @ painted }) },
          (if fresh = [] then intents else intents @ [Flag { ids = fresh; column; value }])
      | Some _ -> { t with drag = None }, intents
      | None -> t, intents in
    let first = int_of_float (scroll /. height) in
    let last = min (count - 1) (first + int_of_float (body /. height) + 1) in
    let ancestors k =
      let chain = ref [] and depth = ref (at k).depth in
      for candidate = k - 1 downto 0 do
        if (at candidate).depth < !depth then begin
          chain := candidate :: !chain; depth := (at candidate).depth end
      done;
      !chain in
    let sticky = if count = 0 || scroll <= 0. then []
      else List.filteri (fun index _ -> index < 3) (ancestors first) in
    let drop_hint = match t.drag with
      | Some (Rows { moved = true; ids }) ->
          (match row_at signal.pointer with
           | Some k when not (List.mem (at k).id ids) ->
               let offset = (snd signal.pointer -. top +. scroll) /. height
                            -. float_of_int k in
               Some (k, if offset < 0.25 then Before else if offset > 0.75 then After
                 else Inside)
           | _ -> None)
      | _ -> None in
    Ui.draw ui box (fun paint _ ->
      let text ?(color = theme.foreground) at label =
        Ui.Paint.text paint ~at ~color label in
      Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
      let draw_row k row_y =
        let row = at k in
        let index = shown.(k) in
        if is_selected row.id then
          Ui.Paint.fill paint ~x ~y:row_y ~w ~h:height (Pxui.Theme.pressed_fill theme)
        else Ui.Paint.fill paint ~x ~y:row_y ~w ~h:height theme.panel;
        if t.focus = Some row.id then
          Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(row_y +. 0.5) ~w:(w -. 1.)
            ~h:(height -. 1.) theme.accent;
        let indent level = x +. 8. +. float_of_int level *. 14. in
        for level = 1 to row.depth do
          Ui.Paint.line paint ~from_:(indent level -. 7., row_y)
            ~to_:(indent level -. 7., row_y +. height) (Pxui.Theme.faint_border theme)
        done;
        let text_y = row_y +. Float.max 4. ((height -. float_of_int (Ui.font_size ui)) /. 2.) in
        let muted = Pxui.Theme.muted theme in
        if has_children rows index then
          text ~color:muted (indent row.depth, text_y)
            (if Ids.mem row.id t.folded && t.filter = None then "►" else "▼");
        (* The kind badge: a letter on its colour, like the graph tiles. *)
        let badge_x = indent row.depth +. 14. in
        let letter, tint = if row.link then "↳", Pxui.Theme.muted theme else row.badge in
        Ui.Paint.fill paint ~x:badge_x ~y:(row_y +. 4.) ~w:18. ~h:(height -. 8.) tint;
        Ui.Paint.text paint ~color:Prismel.Color.white
          ~at:(badge_x +. 9. -. (Ui.Paint.text_width paint letter /. 2.), text_y) letter;
        let label_x = badge_x +. 24. in
        let hidden = match row.flags with shown :: _ -> not shown | [] -> false in
        let color = if row.ghost || row.link || hidden then muted else theme.foreground in
        text ~color (label_x, text_y) row.label;
        if hidden then
          Ui.Paint.line paint ~from_:(label_x, row_y +. (height /. 2.))
            ~to_:(label_x +. Ui.Paint.text_width paint row.label, row_y +. (height /. 2.)) muted;
        if row.detail <> "" then
          text ~color:muted (label_x +. Ui.Paint.text_width paint row.label +. 10., text_y)
            row.detail;
        (* Toggles: a square for the first column, a dot for the others. *)
        List.iteri (fun column value ->
          let cx = columns_x +. (float_of_int column +. 0.5) *. flag_width
          and cy = row_y +. (height /. 2.) in
          if column = 0 then begin
            Ui.Paint.fill paint ~x:(cx -. 6.) ~y:(cy -. 6.) ~w:12. ~h:12.
              (if value then theme.foreground else theme.input);
            Ui.Paint.stroke paint ~x:(cx -. 6.) ~y:(cy -. 6.) ~w:12. ~h:12. (Pxui.Theme.border theme)
          end else
            Ui.Paint.circle paint ~at:(cx, cy) ~radius:6.
              ~fill:(if value then theme.accent else theme.input)
              ~stroke:(if value then theme.accent else Pxui.Theme.border theme) ()) row.flags in
      for k = first to last do
        draw_row k (top +. float_of_int k *. height -. scroll)
      done;
      List.iteri (fun slot k -> draw_row k (top +. float_of_int slot *. height)) sticky;
      if sticky <> [] then
        Ui.Paint.line paint ~from_:(x, top +. float_of_int (List.length sticky) *. height)
          ~to_:(x +. w, top +. float_of_int (List.length sticky) *. height)
          (Pxui.Theme.border theme);
      (match drop_hint with
       | Some (k, drop) ->
           let row_y = top +. float_of_int k *. height -. scroll in
           (match drop with
            | Inside -> Ui.Paint.stroke paint ~x:(x +. 1.) ~y:row_y ~w:(w -. 2.)
                          ~h:height ~width:2. theme.accent
            | Before | After ->
                let line_y = if drop = Before then row_y else row_y +. height in
                Ui.Paint.line paint ~from_:(x, line_y) ~to_:(x +. w, line_y) ~width:2.
                  theme.accent)
       | None -> ());
      (* Header: column names, or the filter under a prompt. *)
      Ui.Paint.fill paint ~x ~y ~w ~h:height theme.foreground;
      if t.filter = None then begin
        text ~color:theme.input (x +. 8., y +. 5.) (title ^ "  · / filter");
        List.iteri (fun column name ->
          text ~color:theme.input (columns_x +. (float_of_int column +. 0.5) *. flag_width
            -. (Ui.Paint.text_width paint name /. 2.), y +. 5.) name) columns
      end);
    (* The filter field sits in the header; Escape clears it. *)
    let t = match t.filter with
      | None -> t
      | Some query ->
          (match Ui.panel ui ~x ~y ~width:w ~max_height:(height +. 16.) "tree-filter"
              (fun () -> Ui.picker ui "Filter rows" ~query (fun _ -> [||])) with
           | _, `Cancel -> Ui.unfocus ui; { t with filter = None }
           | query, (`Submit | `Pick _) -> Ui.unfocus ui; { t with filter = Some query }
           | query, _ -> { t with filter = Some query }) in
    let t, intents = match t.renaming with
      | None -> t, intents
      | Some (id, name) ->
          (match Prompt.name ui ~key:"tree-rename" ~title:"Rename" ~label:"Name"
              ~query:name with
           | None | Some (_, `Cancel) -> Ui.dismiss_popup ui; { t with renaming = None }, intents
           | Some (name, `Submit) ->
               Ui.dismiss_popup ui; { t with renaming = None },
               if String.trim name = "" then intents else intents @ [Rename (id, String.trim name)]
           | Some (name, _) -> { t with renaming = Some (id, name) }, intents) in
    { t with scroll; reveal = false }, intents
end

module Shell = struct
  let frame ui frame ~visible ~body ~overlay =
    Pxui.Ui.frame ui frame (fun ui ->
      Option.iter (fun draw -> draw ui) overlay;
      if visible then Some (body ui) else None)
end

module Inspector = struct
  module Param = Editor_core.Param
  module Ui = Pxui.Ui

  type item = Field of Param.field_view | Folder of string * item list

  let rec insert path field items = match path with
    | [] -> items @ [Field field]
    | name :: rest ->
        let rec loop reversed = function
          | [] -> List.rev_append reversed [Folder (name, insert rest field [])]
          | Folder (candidate, children) :: tail when candidate = name ->
              List.rev_append reversed
                (Folder (candidate, insert rest field children) :: tail)
          | item :: tail -> loop (item :: reversed) tail
        in
        loop [] items

  (* The field name is the widget key; the label is only displayed. *)
  let field_widget ui (field : Param.field_view) =
    let label = field.label ^ "##" ^ field.name in
    let edited value = if value = field.current then None
      else Some (field.name, value) in
    match field.kind, field.current with
    | Param.Toggle_view, Param.Bool_value value ->
        edited (Param.Bool_value (Ui.toggle ui label value))
    | Param.Integer_view range, Param.Int_value value ->
        edited (Param.Int_value
          (Ui.int_slider ui label ~range:(range.soft_min, range.soft_max) value))
    | Param.Floating_view range, Param.Float_value value ->
        edited (Param.Float_value
          (Ui.slider ui label ~range:(range.soft_min, range.soft_max) value))
    | Param.Text_view, Param.Text_value value ->
        edited (Param.Text_value (Ui.text_field ui label value))
    | Param.Choice_view options, Param.Choice_value value ->
        let selected = Option.value ~default:0
            (Array.find_index (String.equal value) options) in
        let chosen = Ui.choice ui label (Array.to_list options) selected in
        edited (Param.Choice_value options.(chosen))
    | _ -> invalid_arg "Pxui_shell.Inspector: inconsistent field metadata"

  let fields ui ?(expanded = []) views =
    if views = [] then (Ui.label ui "No exposed parameters"; [])
    else
      let rec build path items = List.concat_map (function
        | Field field -> Option.to_list (field_widget ui field)
        | Folder (label, children) ->
            let path = path @ [label] in
            let key = String.concat "/" path in
            Option.value ~default:[]
              (Ui.accordion ui ~expanded:(List.mem key expanded)
                 (label ^ "##folder." ^ key) (fun () -> build path children)))
          items in
      build [] (List.fold_left (fun items (field : Param.field_view) ->
        insert field.folder field items) [] views)

  let record ui ?expanded schema values =
    match fields ui ?expanded (Param.view schema values) with
    | [] -> Ok (values, Param.no_effects)
    | changes -> Param.apply_all schema values changes
end
