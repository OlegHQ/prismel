open Rays

module Layout = struct
  type panel = Editor_core.Panels.panel =
    | View of string | Graph | List | Lisp | Inspector | Outline | Timeline
  type axis = Editor_core.Panels.axis
  type t = Editor_core.Panels.t =
    | Leaf of panel
    | Split of { axis : axis; size : Editor_core.Panels.size; a : t; b : t }
    | Tile of t list
    | Float of t
  type path = int list
  type bounds = int * int * int * int

  let default = Editor_core.Panels.default

  let splitter_width = 1
  let collapsed_width = 24
  let header_height = 24
  let status_height = 24
  let timeline_height = 24

  (* a collapsed panel is its header: as tall in a stack, a 28-point column in a row *)
  let strip axis = if axis = `V then header_height else collapsed_width

  type leaf = { path : path; panel : panel; header : bounds; body : bounds; floating : bool }
  type splitter = { node : path option; axis : axis; size : Editor_core.Panels.size; bounds : bounds;
                    start : int; span : int }
  let sides (s : splitter) =
    let x, y, _, _ = s.bounds in
    let first = (if s.axis = `H then x else y) - s.start in
    first, s.span - first - splitter_width
  let resized s how : Editor_core.Panels.size =
    let first, second = sides s in
    Editor_core.Panels.clamp_size (match how with
      (* the middle of the point the first side ends on, so the ratio places it there again *)
      | `Ratio -> `Ratio ((float first +. 0.5) /. float (max 1 (s.span - splitter_width)))
      | `First -> `First first | `Second -> `Second second)

  (* the rows of a size menu: the three ways, the one in use greyed *)
  let size_rows (s : splitter) =
    let a, b = if s.axis = `H then "left", "right" else "top", "bottom" in
    let now = match s.size with `Ratio _ -> 0 | `First _ -> 1 | `Second _ -> 2 in
    List.mapi (fun i label -> label, i <> now) [ "By ratio"; "Fix " ^ a ^ " side"; "Fix " ^ b ^ " side" ]
  let size_ways = [ `Ratio; `First; `Second ]

  type geometry = { leaves : leaf list; splitters : splitter list; status_at : bounds;
                    timeline_at : bounds }
  type panes = { view : bounds; graph : bounds; inspector : bounds; status : bounds;
                 timeline : bounds }

  let toggle panel hidden =
    if List.mem panel hidden then List.filter (( <> ) panel) hidden else panel :: hidden
  let expand panel hidden = List.filter (( <> ) panel) hidden

  (* A hidden panel vanishes; a hidden viewport keeps a strip with its expand button. *)
  type presence = Live | Strip | Gone
  let join x y = match x, y with
    | Live, _ | _, Live -> Live | Strip, _ | _, Strip -> Strip | Gone, Gone -> Gone
  let rec presence ~state hidden path = function
    | Leaf _ when (state path).Editor_core.Panels.window <> None -> Gone
    | Leaf Timeline when (state path).Editor_core.Panels.collapsed -> Gone  (* it has no header to keep *)
    | Leaf _ when (state path).Editor_core.Panels.collapsed -> Strip
    | Leaf p -> if not (List.mem p hidden) then Live
        else (match p with View _ -> Strip | _ -> Gone)
    | Float _ -> Gone
    | Split { a; b; _ } -> join (presence ~state hidden (path @ [0]) a) (presence ~state hidden (path @ [1]) b)
    | Tile cells -> List.mapi (fun i c -> presence ~state hidden (path @ [i]) c) cells
        |> List.fold_left join Gone

  let is_float = function Float _ -> true | _ -> false

  (* A run of splits by ratio along one axis is one row of columns whose weights are the
     products of the ratios, so [0.45 | 0.55 * 0.6364 | ...] divides the width once.  A split
     with a fixed side is one column of the run and is placed on its own. *)
  let rec columns axis weight path = function
    | Split ({ size = `Ratio ratio; _ } as s) when s.axis = axis && not (is_float s.a || is_float s.b) ->
        columns axis (weight *. ratio) (path @ [ 0 ]) s.a
        @ columns axis (weight *. (1. -. ratio)) (path @ [ 1 ]) s.b
    | tree -> [ weight, path, tree ]

  let rec split_size path tree : Editor_core.Panels.size = match path, tree with
    | [], Split s -> s.size
    | 0 :: rest, Split s -> split_size rest s.a
    | 1 :: rest, Split s -> split_size rest s.b
    | _ -> `Ratio 0.5

  let rec minimum axis = function
    | Leaf p when axis = `H ->
        (match p with View _ -> 220 | Graph | List | Lisp -> 180 | _ -> 120)
    | Split { a; b; _ } -> max (minimum axis a) (minimum axis b)
    | Tile cells -> List.fold_left (fun m c -> max m (minimum axis c)) 0 cells
    | Leaf _ | Float _ -> 0

  (* Sizes of the columns of one row.  A column is (presence, weight, minimum, fixed): a
     fixed extent (a strip, the timeline's own height) is kept, the rest share what is
     left by weight, each at least its minimum when the minimums fit, the last
     weighted one taking the rounding remainder. *)
  let distribute total cols =
    let n = Array.length cols in
    let present = Array.fold_left (fun k (p, _, _, _) -> if p = Gone then k else k + 1) 0 cols in
    let available = max 3 (total - (max 0 (present - 1) * splitter_width)) in
    let sizes = Array.make n 0 in
    let fixed = ref 0 and weight = ref 0. and required = ref 0 and live = ref (-1)
    and last = ref (-1) in
    let weighted (p, _, _, f) = p <> Gone && f = 0 in
    Array.iteri (fun i ((p, w, m, f) as col) ->
      if p <> Gone then last := i;
      if weighted col then (weight := !weight +. w; required := !required + m; live := i)
      else if p <> Gone then (sizes.(i) <- f; fixed := !fixed + f)) cols;
    let flexible = max 3 (available - !fixed) in
    Array.iteri (fun i ((_, w, _, _) as col) -> if weighted col then
      sizes.(i) <- max 1 (int_of_float (float_of_int flexible *. w /. !weight))) cols;
    let rest = if !live >= 0 then !live else !last in
    if rest >= 0 then begin
      let used = Array.fold_left ( + ) 0 sizes in
      sizes.(rest) <- max 1 (sizes.(rest) + available - used)
    end;
    let short = ref false in
    Array.iteri (fun i ((_, _, m, _) as col) -> if weighted col && sizes.(i) < m then short := true) cols;
    if !live >= 0 && !required <= flexible && !short then begin
      let extra = flexible - !required and assigned = ref 0 in
      Array.iteri (fun i ((_, w, m, _) as col) -> if weighted col then begin
        sizes.(i) <- m + int_of_float (float_of_int extra *. w /. !weight);
        assigned := !assigned + sizes.(i) end) cols;
      sizes.(!live) <- sizes.(!live) + flexible - !assigned
    end;
    sizes

  let rec common a b = match a, b with
    | x :: a, y :: b when x = y -> x :: common a b
    | _ -> []

  let rec prefix under path = match under, path with
    | [], _ -> true
    | x :: under, y :: path -> x = y && prefix under path
    | _ -> false

  let geometry ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) tree (frame : Frame.t) =
    let all = Editor_core.Panels.leaves tree in
    let header = min header_height (max 0 (frame.height - 1)) in
    let timeline = if List.mem Timeline hidden || List.exists (fun (_, p) -> p = Timeline) all
      then 0 else min timeline_height (max 0 (frame.height - header - 1)) in
    (* the status strip spans the window below the tree and the timeline strip *)
    let status = min status_height (max 0 (frame.height - header - timeline - 1)) in
    let bottom = frame.height - status - timeline in
    let leaves = ref [] and splitters = ref [] and floats = ref [] in
    let leaf ?(floating = false) path panel (x, y, w, h) =
      (* a docked timeline is its strip alone *)
      let collapsed = (state path).Editor_core.Panels.collapsed in
      let hh = if panel = Timeline && not floating then 0
        else min header_height (max 0 (if collapsed then h else h - 1)) in
      let body = if collapsed then 0 else max 1 (h - hh) in
      leaves := { path; panel; floating; header = (x, y, w, hh);
                  body = (x, y + hh, w, body) } :: !leaves in
    let cut total n = (* n cells and n-1 gutters over [total] *)
      let cell = max 1 ((total - ((n - 1) * splitter_width)) / n) in
      Array.init n (fun i -> if i = n - 1 then max 1 (total - (i * (cell + splitter_width))) else cell) in
    let rec place ?(floating = false) ((x, y, w, h) as rect) path = function
      | Leaf p -> if presence ~state hidden path (Leaf p) <> Gone then leaf ~floating path p rect
      | Float t -> floats := ((x + (w / 8), y + (h / 8), w - (w / 4), h - (h / 4)), path @ [ 0 ], t)
                             :: !floats
      | Split { a; b; _ } when is_float a || is_float b ->
          place ~floating rect (path @ [ 0 ]) a; place ~floating rect (path @ [ 1 ]) b
      | Split { axis; size = (`First points | `Second points) as size; a; b } ->
          (* one side keeps its points, the other takes the rest: the other keeps its minimum
             first, then the fixed side shrinks, never below one point *)
          let pa = presence ~state hidden (path @ [ 0 ]) a and pb = presence ~state hidden (path @ [ 1 ]) b in
          if pb = Gone then (if pa <> Gone then place ~floating rect (path @ [ 0 ]) a)
          else if pa = Gone then place ~floating rect (path @ [ 1 ]) b
          else begin
            let horizontal = axis = `H in
            let total = if horizontal then w else h in
            let available = max 2 (total - splitter_width) in
            let first = match size with `First _ -> true | _ -> false in
            let fixed_presence, other, other_presence = if first then pa, b, pb else pb, a, pa in
            let fixed =
              if other_presence = Strip then available - min (strip axis) (available - 1)
              else max 1 (min (if fixed_presence = Strip then strip axis else points)
                     (available - min (max 1 (minimum axis other)) (available - 1))) in
            let size_a = if first then fixed else available - fixed in
            let origin = if horizontal then x else y in
            let rect_at from extent = if horizontal then (from, y, extent, h) else (x, from, w, extent) in
            place ~floating (rect_at origin size_a) (path @ [ 0 ]) a;
            splitters := { node = Some path; axis; size; bounds = rect_at (origin + size_a) splitter_width;
                           start = origin; span = total } :: !splitters;
            place ~floating (rect_at (origin + size_a + splitter_width) (available - size_a)) (path @ [ 1 ]) b
          end
      | Split { axis; _ } as tree ->
          let cols = Array.of_list (columns axis 1. [] tree) in
          let info = Array.map (fun (weight, col_path, sub) ->
            let p = presence ~state hidden (path @ col_path) sub in
            p, weight, minimum axis sub,
            (match p, sub with
             | Strip, _ -> strip axis
             | Live, Leaf Timeline when axis = `V -> timeline_height
             | _ -> 0)) cols in
          let horizontal = axis = `H in
          let sizes = distribute (if horizontal then w else h) info in
          let cursor = ref (if horizontal then x else y) in
          let prior = ref None and placed = ref [] and gutters = ref [] in
          Array.iteri (fun i (_, col_path, sub) ->
            let p, _, _, _ = info.(i) in
            if p <> Gone then begin
              Option.iter (fun before ->
                gutters := (common before col_path, if horizontal then (!cursor, y, splitter_width, h)
                            else (x, !cursor, w, splitter_width)) :: !gutters;
                cursor := !cursor + splitter_width) !prior;
              let rect = if horizontal then (!cursor, y, sizes.(i), h) else (x, !cursor, w, sizes.(i)) in
              place ~floating rect (path @ col_path) sub;
              placed := (col_path, if horizontal then !cursor, sizes.(i) else !cursor, sizes.(i)) :: !placed;
              cursor := !cursor + sizes.(i);
              prior := Some col_path
            end) cols;
          let extent node =
            match List.filter (fun (cp, _) -> prefix node cp) (List.rev !placed) with
            | [] -> 0, 1
            | (_, (start, _)) :: _ as under ->
                let _, (s, len) = List.nth under (List.length under - 1) in start, s + len - start in
          List.iter (fun (node, bounds) ->
            let start, span = extent node in
            splitters := { node = Some (path @ node); axis; size = split_size node tree; bounds; start; span }
                         :: !splitters)
            (List.rev !gutters)
      | Tile cells ->
          let cells = List.mapi (fun i cell -> i, cell) cells
            |> List.filter (fun (i, cell) -> is_float cell || presence ~state hidden (path @ [i]) cell <> Gone) in
          let n = List.length cells in
          if n > 0 then begin
          let columns = int_of_float (Float.ceil (sqrt (float_of_int n))) in
          let rows = (n + columns - 1) / columns in
          let heights = cut h rows in
          let offset sizes k = let s = ref 0 in
            for j = 0 to k - 1 do s := !s + sizes.(j) + splitter_width done; !s in
          (* a short last row stretches its cells over the whole width *)
          let widths = Array.init rows (fun r -> cut w (min columns (n - (r * columns)))) in
          List.iteri (fun i (original, cell) ->
            let c = i mod columns and r = i / columns in
            let cx = x + offset widths.(r) c and cy = y + offset heights r in
            if c > 0 then splitters := { node = None; axis = `H; size = `Ratio 0.5;
              bounds = (cx - splitter_width, cy, splitter_width, heights.(r)); start = 0; span = 1 }
              :: !splitters;
            if r > 0 && c = 0 then splitters := { node = None; axis = `V; size = `Ratio 0.5;
              bounds = (x, cy - splitter_width, w, splitter_width); start = 0; span = 1 } :: !splitters;
            place ~floating (cx, cy, widths.(r).(c), heights.(r)) (path @ [ original ]) cell) cells
          end in
    place (0, 0, frame.width, max 1 bottom) [] tree;
    let rec drain () = match List.rev !floats with
      | [] -> ()
      | queue -> floats := [];
          List.iter (fun (rect, path, t) -> place ~floating:true rect path t) queue; drain () in
    drain ();
    List.iter (fun (path, panel) -> match (state path).Editor_core.Panels.window with
      | None -> ()
      | Some (x, y, w, h) ->
          let w = min frame.width w and h = min frame.height h in
          let x = max 0 (min x (frame.width - w)) and y = max 0 (min y (frame.height - header_height)) in
          (* a collapsed window is a short tab: its title and the expand button *)
          let w = if (state path).collapsed
            then min w (max 90 (60 + (7 * String.length (Editor_core.Panels.name panel)))) else w in
          leaf ~floating:true path panel (x, y, w, if (state path).collapsed then header_height else min h (frame.height - y))) all;
    { leaves = List.rev !leaves; splitters = List.rev !splitters;
      status_at = (0, frame.height - status, frame.width, status);
      timeline_at = (0, bottom, frame.width, timeline) }

  let find geometry panel = List.find_opt (fun l -> l.panel = panel && (let _, _, _, h = l.body in h > 0)) geometry.leaves
  let first_view geometry = List.find_opt (fun l -> (let _, _, _, h = l.body in h > 0)
      && match l.panel with View _ -> true | _ -> false)
      geometry.leaves

  let zero = (0, 0, 0, 0)
  let panes g =
    let body panel = match find g panel with Some l -> l.body | None -> zero in
    { view = (match first_view g with Some l -> l.body | None -> zero);
      graph = body Graph; inspector = body Inspector; status = g.status_at; timeline = g.timeline_at }
end

(* Kit rev 3 pieces the chrome shares: where text sits in a 24-point bar, and the text button. *)
module Kit = struct
  module Ui = Pxui.Ui
  let text_y ui y h = y +. Float.max 4. (Float.floor ((h -. float (Ui.font_size ui) -. 3.) /. 2.))
  let cap_y ui y h = y +. Float.floor ((h -. float (max 8 (Ui.font_size ui - 2)) -. 3.) /. 2.)
  let cap_size ui = max 8 (Ui.font_size ui - 2)

  (* the width of a text button: 6, the label, 6 and the key, 6 *)
  let button_width ui ?hint ?(icon = false) label =
    12. +. Ui.text_width ui label +. (if icon then 13. else 0.)
    +. (match hint with Some hint -> 6. +. Ui.text_width ui ~size:(cap_size ui) hint | None -> 0.)

  (* A button is its text and, in ink-3, its key: a fill on hover and press, the control fill
     while [active]; [primary] is the one outlined button of a panel.  [icon] draws a play
     triangle or a stop square before the label. *)
  let button ui ~key ~at:(bx, by) ~w ?(h = 20.) ?(enabled = true) ?(active = false) ?(primary = false)
      ?hint ?icon label =
    let theme = Ui.theme ui in
    let box = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(bx, by) key in
    let signal = Ui.signal ui box in
    Ui.draw ui box (fun paint (x, y, w, h) ->
      if enabled && signal.held then Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.pressed_fill theme)
      else if enabled && signal.hovered then Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.hover_fill theme)
      else if active then Ui.Paint.fill paint ~x ~y ~w ~h theme.control;
      if primary then Ui.Paint.stroke paint ~x ~y ~w ~h (Pxui.Theme.border theme);
      let color = if enabled then theme.foreground else Pxui.Theme.ink_3 theme in
      let tx = match icon with
        | None -> x +. 6.
        | Some shape ->
            let cy = y +. (h /. 2.) in
            (match shape with
             | `Play -> for i = 0 to 3 do
                 Ui.Paint.fill paint ~x:(x +. 6. +. (2. *. float i)) ~y:(cy -. 4. +. float i) ~w:2. ~h:(8. -. (2. *. float i)) color done
             | `Stop -> Ui.Paint.fill paint ~x:(x +. 6.) ~y:(cy -. 4.) ~w:8. ~h:8. color);
            x +. 19. in
      Ui.Paint.text paint ~at:(tx, text_y ui y h) ~color label;
      Option.iter (fun hint ->
        Ui.Paint.text paint ~size:(cap_size ui) ~color:(Pxui.Theme.ink_3 theme)
          ~at:(tx +. Ui.Paint.text_width paint label +. 6., cap_y ui y h) hint) hint);
    signal.clicked && enabled

  (* Text tabs: the one in use is ink with a 1-point underline, the others ink-3.  Laid out
     leftwards from [right]; the index clicked. *)
  let segments ui ~key ~right ~y ?(h = 20.) labels active =
    let theme = Ui.theme ui in
    let widths = List.map (fun label -> Ui.text_width ui label) labels in
    let total = List.fold_left ( +. ) (12. *. float (max 0 (List.length labels - 1))) widths in
    let x = ref (right -. total) and clicked = ref None in
    List.iteri (fun index label ->
      let w = List.nth widths index in
      let box = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px (w +. 8.)) ~h:(Ui.Px h)
          ~at:(!x -. 4., y) (Printf.sprintf "%s-%d" key index) in
      let signal = Ui.signal ui box in
      if signal.clicked then clicked := Some index;
      Ui.draw ui box (fun paint (x, y, w, h) ->
        let on = index = active in
        Ui.Paint.text paint ~at:(x +. 4., text_y ui y h)
          ~color:(if on || signal.hovered then theme.foreground else Pxui.Theme.ink_3 theme) label;
        if on then Ui.Paint.fill paint ~x:(x +. 4.) ~y:(y +. h -. 1.) ~w:(w -. 8.) ~h:1. theme.foreground);
      x := !x +. w +. 12.) labels;
    !clicked, right -. total
end

module Chrome = struct
  open Layout
  type intent =
    | Resize of { node : path; size : Editor_core.Panels.size }
    | Settled
    | Toggle of path
    | Window of path * bounds option
    | Window_drag of path * bounds * bool
    | Dragging of path * bool
    | Dock_panel of path * path * [ `Left | `Right | `Top | `Bottom ]
    | Split_panel of path * axis
    | Close_panel of path
    | Retype_panel of path * panel

  let floating ui ?(flags = Pxui.Ui.none) (x, y, width, height) label =
    Pxui.Ui.box ui ~flags ~w:(Pxui.Ui.Px (float_of_int width))
      ~h:(Pxui.Ui.Px (float_of_int height)) ~at:(float_of_int x, float_of_int y) label

  let pane_root ui (frame : Frame.t) ~bounds:(x, y, width, height) label =
    Pxui.Ui.box ui ~flags:Pxui.Ui.clickable
      ~w:(Pxui.Ui.Px (float_of_int frame.width))
      ~h:(Pxui.Ui.Px (float_of_int frame.height)) ~at:(0., 0.)
      ~hit:(fun _ -> float x, float y, float width, float height) label

  let key path = String.concat "." (List.map string_of_int path)
  let retypes = [ "Graph", Graph; "List", List; "Lisp", Lisp; "Inspector", Inspector;
                  "Outline", Outline; "Timeline", Timeline; "Viewport", View "" ]

  let drag_origin ui box bounds signal =
    if signal.Pxui.Ui.pressed then begin
      let x, y, w, h = bounds in
      Pxui.Ui.set_text_state ui box (Some (Printf.sprintf "%d %d %d %d" x y w h))
    end;
    match Option.map (String.split_on_char ' ') (Pxui.Ui.text_state ui box) with
    | Some parts -> (match List.filter_map int_of_string_opt parts with
        | [x; y; w; h] -> x, y, w, h | _ -> bounds)
    | None -> bounds

  (* Chrome of the retained workspace, painted and hit through PXUI boxes:
     panel backgrounds, splitters, and header bars with a collapse button and a
     right-click menu (split, close, retype). *)
  let update ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) ?(title = fun (l : leaf) -> Editor_core.Panels.name l.panel)
      ?focus tree ui (frame : Frame.t) =
    let module Ui = Pxui.Ui in
    let geometry = geometry ~state ~hidden tree frame in
    let theme = Ui.theme ui in
    List.iteri (fun order l -> match l.panel with
      | View _ | Timeline -> ()
      | p ->
          let box = floating ui l.body ("workspace-" ^ String.lowercase_ascii (Editor_core.Panels.name p)
                                        ^ key l.path) in
          if l.floating then Ui.to_front ui ~order box;
          Ui.draw ui box (fun paint (x, y, w, h) ->
            (* a window is a sheet with one line-3 edge; a docked panel is the ground *)
            if l.floating then begin
              Ui.Paint.fill paint ~x ~y ~w ~h theme.input;
              let line = Pxui.Theme.border theme in
              Ui.Paint.fill paint ~x ~y ~w:1. ~h line; Ui.Paint.fill paint ~x:(x +. w -. 1.) ~y ~w:1. ~h line;
              Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. line
            end else Ui.Paint.fill paint ~x ~y ~w ~h theme.panel))
      geometry.leaves;
    let intents = ref [] in
    let emit i = intents := i :: !intents in
    List.iteri (fun n (s : splitter) ->
      let box = floating ui s.bounds ("workspace-gutter-" ^ string_of_int n) in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.edge theme))) geometry.splitters;
    let headed = List.filter (fun (_, (l : leaf)) -> let _, _, _, h = l.header in h > 0)
      (List.mapi (fun order l -> order, l) geometry.leaves) in
    let headers = List.map (fun (order, (l : leaf)) ->
      let x, y, w, h = l.header in
      let label = String.lowercase_ascii (Editor_core.Panels.name l.panel) ^ key l.path in
      let box = floating ui ~flags:Ui.(clickable + clip) l.header ("workspace-header-" ^ label) in
      if l.floating then Ui.to_front ui ~order box;
      let size = min h 24 in
      (* docked: the collapse chevron.  A window: dock, then close. *)
      let windowed = (state l.path).window <> None && not (state l.path).collapsed in
      let button = floating ui ~flags:Ui.(clickable + tab_stop)
          (x + max 0 (w - size), y + ((h - size) / 2), size, size) ("workspace-collapse-" ^ label) in
      if l.floating then Ui.to_front ui ~order button;
      if (Ui.signal ui button).clicked then emit (if windowed then Close_panel l.path else Toggle l.path);
      let tools = if windowed then 2 * size else size in
      if windowed then begin
        let dock = floating ui ~flags:Ui.(clickable + tab_stop)
            (x + max 0 (w - tools), y + ((h - size) / 2), size, size) ("workspace-dock-" ^ label) in
        Ui.to_front ui ~order dock;
        let signal = Ui.signal ui dock in
        if signal.clicked then emit (Window (l.path, None));
        Ui.draw ui dock (fun paint (x, y, w, h) ->
          if signal.hovered then Ui.Paint.fill paint ~x:(x +. 2.) ~y:(y +. 2.) ~w:(w -. 4.) ~h:(h -. 4.)
            (Pxui.Theme.hover_fill theme);
          Ui.Paint.chevron paint ~at:(x +. (w /. 2.), y +. (h /. 2.)) `Down (Pxui.Theme.ink_2 theme))
      end;
      let grip = floating ui ~flags:Ui.(clickable + blocking)
          (x, y, max 0 (w - tools), h) ("workspace-drag-" ^ label) in
      if l.floating then Ui.to_front ui ~order grip;
      let drag = Ui.signal ui grip in
      let original = Option.value (state l.path).window
        ~default:(x, y, max 120 w, max 80 (let _, _, _, bh = l.body in h + bh)) in
      let ox, oy, ow, oh = drag_origin ui grip original drag in
      if drag.held || drag.released then begin
        let px, py = if drag.released then drag.release_point else drag.pointer in
        let sx, sy = drag.press_point in
        if Float.hypot (px -. sx) (py -. sy) >= 4. then begin
          emit (Dragging (l.path, drag.released));
          emit (Window_drag (l.path, (max 0 (min (frame.width - 18) (ox + int_of_float (Float.round (px -. sx)))),
            max 0 (min (frame.height - header_height) (oy + int_of_float (Float.round (py -. sy)))), ow, oh), drag.released))
        end
      end;
      let opened = Ui.state ui box ~default:0 = 1 in
      (* the whole empty header drags; a click that did not move opens the menu *)
      let still = Float.hypot (fst drag.release_point -. fst drag.press_point)
          (snd drag.release_point -. snd drag.press_point) < 4. in
      let opened = opened || Ui.context_clicked drag || (drag.clicked && still) in
      Ui.set_state ui box (if opened then 1 else 0);
      if opened then begin
        let holder = match List.rev l.path with
          | _ :: up -> List.find_opt (fun (s : splitter) -> s.node = Some (List.rev up)) geometry.splitters
          | [] -> None in
        let rows = [ "Split side by side", true; "Split top and bottom", true; "Close", true;
                     (if (state l.path).window = None then "Undock" else "Dock"), true;
                     "", false; "Show as", false ]
          @ List.map (fun (name, panel) -> name, panel <> l.panel) retypes
          (* the split that holds the panel, sized another way *)
          @ (match holder with
             | Some s -> ("", false) :: ("Size of its split", false) :: size_rows s
             | None -> []) in
        match Ui.context_menu ui ~at:(float x, float (y + h)) ("workspace-menu-" ^ label) rows with
        | `Open -> ()
        | `Dismiss -> Ui.set_state ui box 0
        | `Pick i -> Ui.set_state ui box 0;
            emit (match i with
              | 0 -> Split_panel (l.path, `H) | 1 -> Split_panel (l.path, `V)
              | 2 -> Close_panel l.path
              | 3 -> Window (l.path, if (state l.path).window <> None then None else
                    Some (x, y, max 120 w, max 80 (let _, _, _, bh = l.body in h + bh)))
              | i when i < 6 + List.length retypes -> Retype_panel (l.path, snd (List.nth retypes (i - 6)))
              | i ->
                  let s = Option.get holder in
                  emit (Resize { node = Option.get s.node;
                                 size = resized s (List.nth size_ways (i - 8 - List.length retypes)) });
                  Settled)
      end;
      l, title l, box, button, grip) headed in
    List.iter (fun ((l : leaf), text, box, button, _grip) ->
      let collapse_hovered = (Ui.signal ui button).hovered in
      let panel_state = state l.path in
      let collapsed = panel_state.collapsed || List.mem l.panel hidden in
      let windowed = panel_state.window <> None && not panel_state.collapsed in
      let focused = focus = Some l.path in
      let text_box = Ui.within ui box (fun () -> Ui.box ui ~w:Ui.Grow ~h:Ui.Grow "header-text") in
      Ui.draw ui text_box (fun paint (x, y, w, h) ->
        if l.floating then begin
          Ui.Paint.fill paint ~x ~y ~w ~h theme.input;
          let line = Pxui.Theme.border theme in
          Ui.Paint.fill paint ~x ~y ~w ~h:1. line;
          Ui.Paint.fill paint ~x ~y ~w:1. ~h line; Ui.Paint.fill paint ~x:(x +. w -. 1.) ~y ~w:1. ~h line;
          if collapsed then Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. line
        end else Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
        let ink_2 = Pxui.Theme.ink_2 theme and ink_3 = Pxui.Theme.ink_3 theme in
        (* "Title<TAB>a / b": the kind as a label, then the breadcrumb, its last part in ink *)
        let main, sub = match String.index_opt text '\t' with
          | Some i -> String.sub text 0 i, String.sub text (i + 1) (String.length text - i - 1)
          | None -> text, "" in
        if w >= 60. then begin
          let tx = ref (x +. 12.) in
          (* the accent square marks the focused pane, docked or floating *)
          if focused then begin
            Ui.Paint.fill paint ~x:!tx ~y:(y +. (h /. 2.) -. 3.) ~w:6. ~h:6. theme.accent; tx := !tx +. 12.
          end;
          Ui.Paint.cap paint ~at:(!tx, Kit.cap_y ui y h) ~color:(if focused then theme.foreground else ink_2) main;
          tx := !tx +. Ui.Paint.cap_width paint main +. 8.;
          let ty = Kit.text_y ui y h in
          let put color part = Ui.Paint.text paint ~at:(!tx, ty) ~color part;
            tx := !tx +. Ui.Paint.text_width paint part +. 8. in
          let rec crumbs = function
            | [] -> ()
            | [ last ] -> put (if String.contains sub '/' then theme.foreground else ink_2) last
            | part :: rest -> put ink_2 part; put ink_3 "/"; crumbs rest in
          if sub <> "" then crumbs (List.map String.trim (String.split_on_char '/' sub));
          if collapsed then put ink_3 "collapsed"
        end;
        let cx = x +. w -. 12. and cy = y +. (h /. 2.) in
        if collapse_hovered then Ui.Paint.fill paint ~x:(cx -. 10.) ~y:(y +. 2.)
          ~w:20. ~h:(h -. 4.) (Pxui.Theme.hover_fill theme);
        if windowed then begin
          Ui.Paint.line paint ~from_:(cx -. 3.5, cy -. 3.5) ~to_:(cx +. 3.5, cy +. 3.5) ink_2;
          Ui.Paint.line paint ~from_:(cx -. 3.5, cy +. 3.5) ~to_:(cx +. 3.5, cy -. 3.5) ink_2
        end else Ui.Paint.chevron paint ~at:(cx, cy) (if collapsed then `Down else `Left) ink_2)) headers;
    List.rev !intents

  (* Empty: a crossed box with the reason as a label on the ground. *)
  let note ui ~bounds:(x, y, width, height) text =
    let theme = Pxui.Ui.theme ui in
    Pxui.Ui.draw ui (floating ui (x, y, width, height) (Printf.sprintf "workspace-note-%d-%d" x y))
      (fun paint (x, y, w, h) ->
        let module P = Pxui.Ui.Paint in
        if w > 48. && h > 48. then P.cross paint ~x:(x +. 12.) ~y:(y +. 12.) ~w:(w -. 24.) ~h:(h -. 24.)
          (Pxui.Theme.edge theme);
        let tw = P.cap_width paint text in
        let tx = x +. Float.max 12. (Float.floor ((w -. tw) /. 2.)) and ty = y +. Float.floor (h /. 2.) -. 8. in
        P.fill paint ~x:(tx -. 8.) ~y:ty ~w:(tw +. 16.) ~h:16. theme.panel;
        P.cap paint ~at:(tx, ty +. 2.) text)

  let drop_targets ui ~dragging ~(geometry : geometry) ~state =
    match dragging with
    | None -> []
    | Some (source, released) ->
        List.concat_map (fun (leaf : leaf) ->
          if leaf.path = source || leaf.floating
              || (state leaf.path).Editor_core.Panels.collapsed then [] else
          let x, y, w, hh = leaf.header and _, _, _, bh = leaf.body in
          let h = hh + bh in
          let ex = min 36 (w / 3) and ey = min 36 (h / 3) in
          List.filter_map (fun (side, rect) ->
            let suffix = match side with `Left -> "left" | `Right -> "right" | `Top -> "top" | `Bottom -> "bottom" in
            let box = floating ui ~flags:Pxui.Ui.(clickable + blocking) rect
              ("workspace-drop-" ^ key leaf.path ^ suffix) in
            Pxui.Ui.to_front ui ~order:max_int box;
            let hovered = (Pxui.Ui.signal ui box).hovered in
            (* four edge bars; the nearest turns accent and the half it would take is tinted *)
            let theme = Pxui.Ui.theme ui in
            let fx = float x and fy = float y and fw = float w and fh = float h in
            Pxui.Ui.draw ui box (fun paint _ ->
              let module P = Pxui.Ui.Paint in
              let color = if hovered then theme.accent else Pxui.Theme.border theme in
              (match side with
               | `Top -> P.fill paint ~x:(fx +. (fw /. 2.) -. 24.) ~y:(fy +. 6.) ~w:48. ~h:4. color
               | `Bottom -> P.fill paint ~x:(fx +. (fw /. 2.) -. 24.) ~y:(fy +. fh -. 10.) ~w:48. ~h:4. color
               | `Left -> P.fill paint ~x:(fx +. 6.) ~y:(fy +. (fh /. 2.) -. 24.) ~w:4. ~h:48. color
               | `Right -> P.fill paint ~x:(fx +. fw -. 10.) ~y:(fy +. (fh /. 2.) -. 24.) ~w:4. ~h:48. color);
              if hovered then begin
                let hx, hy, hw, hh = match side with
                  | `Top -> fx, fy, fw, fh /. 2. | `Bottom -> fx, fy +. (fh /. 2.), fw, fh /. 2.
                  | `Left -> fx, fy, fw /. 2., fh | `Right -> fx +. (fw /. 2.), fy, fw /. 2., fh in
                P.fill paint ~x:hx ~y:hy ~w:hw ~h:hh (Pxui.Theme.tint theme);
                P.dashed_rect paint ~x:(hx +. 0.5) ~y:(hy +. 0.5) ~w:(hw -. 1.) ~h:(hh -. 1.) theme.accent;
                let label = "split " ^ suffix in
                P.cap paint ~color:theme.accent
                  ~at:(hx +. ((hw -. P.cap_width paint label) /. 2.), hy +. (hh /. 2.) -. 6.) label
              end);
            if released && hovered then Some (Dock_panel (source, leaf.path, side)) else None)
            [ `Left, (x, y + ey, ex, max 0 (h - 2 * ey));
              `Right, (x + w - ex, y + ey, ex, max 0 (h - 2 * ey));
              `Top, (x, y, w, ey); `Bottom, (x, y + h - ey, w, ey)]) geometry.leaves

  (* The draggable gutters, wider than they are drawn.  Build them after the panes so
     they sit on top of the neighbours' hit rectangles. *)
  let splitters ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) tree ui (frame : Frame.t) =
    let module Ui = Pxui.Ui in
    let intents = ref [] in
    List.iteri (fun n (s : splitter) -> match s.node with
      | None -> ()
      | Some node ->
          let x, y, width, height = s.bounds in
          let gx, gy = if s.axis = `H then 3, 0 else 0, 3 in
          let box = Ui.box ui ~flags:Ui.(clickable + blocking)
              ~at:(float x, float y) ~w:(Ui.Px (float width)) ~h:(Ui.Px (float height))
              ~hit:(fun _ -> float (x - gx), float (y - gy),
                float (width + (2 * gx)), float (height + (2 * gy)))
              ("workspace-grip-" ^ string_of_int n) in
          let signal = Ui.signal ui box in
          if signal.hovered || signal.held then Ui.request_cursor ui
            (if s.axis = `H then `Horizontal_resize else `Vertical_resize);
          if signal.held then Ui.draw ui box (fun paint (x, y, w, h) ->
            Ui.Paint.fill paint ~x ~y ~w ~h (Ui.theme ui).accent);
          let dx, dy = signal.drag in
          if (signal.held || signal.released) && (if s.axis = `H then dx else dy) <> 0. then begin
            let px, py = signal.pointer in
            let along = if s.axis = `H then px else py in
            (* a fixed split is dragged in whole points of its fixed side, any other by ratio *)
            let size : Editor_core.Panels.size = match s.size with
              | `Ratio _ -> `Ratio ((along -. float s.start) /. float (max 1 s.span))
              | `First _ -> `First (int_of_float (Float.round along) - s.start)
              | `Second _ -> `Second (s.start + s.span - splitter_width - int_of_float (Float.round along)) in
            intents := Resize { node; size = Editor_core.Panels.clamp_size size } :: !intents
          end;
          if signal.released then intents := Settled :: !intents;
          (* a right-click sizes the split another way, keeping what it shows *)
          let clicked = Ui.context_clicked signal in
          (* the menu opens where the gutter was clicked *)
          if clicked then (let px, py = signal.release_point in
            Ui.set_text_state ui box (Some (Printf.sprintf "%g %g" px py)));
          let opened = Ui.state ui box ~default:0 = 1 || clicked in
          Ui.set_state ui box (if opened then 1 else 0);
          if opened then begin
            let at = match Option.map (String.split_on_char ' ') (Ui.text_state ui box) with
              | Some [ px; py ] -> float_of_string px, float_of_string py
              | _ -> float x, float y in
            match Ui.context_menu ui ~at ("workspace-size-menu-" ^ string_of_int n) (size_rows s) with
            | `Open -> ()
            | `Dismiss -> Ui.set_state ui box 0
            | `Pick i -> Ui.set_state ui box 0;
                intents := Settled :: Resize { node; size = resized s (List.nth size_ways i) } :: !intents
          end)
      (geometry ~state ~hidden tree frame).splitters;
    List.iteri (fun order (leaf : leaf) -> match (state leaf.path).window with
      | None -> ()
      | Some _ when not (state leaf.path).collapsed ->
          let x, y, w, hh = leaf.header in
          let _, _, _, bh = leaf.body in
          let bounds = x, y, w, hh + bh in
          let x, y, w, h = bounds in
          let box = floating ui ~flags:Ui.(clickable + blocking)
            (x + w - 12, y + h - 12, 12, 12) ("workspace-window-size-" ^ key leaf.path) in
          Ui.to_front ui ~order box;
          let signal = Ui.signal ui box in
          let x, y, w, h = drag_origin ui box bounds signal in
          if signal.held || signal.released then begin
            let px, py = if signal.released then signal.release_point else signal.pointer in
            let sx, sy = signal.press_point in
            if px <> sx || py <> sy then intents := Window_drag (leaf.path, (x, y,
              max 120 (w + int_of_float (Float.round (px -. sx))),
              max 80 (h + int_of_float (Float.round (py -. sy)))), signal.released) :: !intents
          end;
          Ui.draw ui box (fun paint (x, y, w, h) ->
            let ink = Pxui.Theme.ink_3 (Ui.theme ui) in
            Ui.Paint.fill paint ~x:(x +. w -. 4.) ~y:(y +. h -. 11.) ~w:1. ~h:8. ink;
            Ui.Paint.fill paint ~x:(x +. w -. 11.) ~y:(y +. h -. 4.) ~w:8. ~h:1. ink)
      | Some _ -> ()) (geometry ~state ~hidden tree frame).leaves;
    List.rev !intents

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
          rows @ [Editor_core.Keymap.label (Chord (key, modifiers)), command.label]
      | _ -> rows) [] keymap

  (* Sections of key rows flowed into columns and painted by one box. *)
  let columns ui paint (x, y, w) ~per_column sections =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let row = float (Ui.row_height ui) in
    let count = List.fold_left (fun n (_, rows) -> n + 1 + List.length rows) 0 sections in
    let cols = max 1 ((count + per_column - 1) / per_column) in
    let col_w = Float.floor (w /. float cols) in
    let slot = ref 0 in
    let place () = let c = !slot / per_column and r = !slot mod per_column in
      incr slot; x +. (float c *. col_w), y +. (float r *. row) in
    List.iter (fun (title, rows) ->
      (* a header never ends a column *)
      if !slot mod per_column = per_column - 1 then incr slot;
      let hx, hy = place () in
      Ui.Paint.cap paint ~at:(hx +. 12., Kit.cap_y ui hy row) ~color:(Pxui.Theme.ink_3 theme) title;
      List.iter (fun (key, label) ->
        let rx, ry = place () in
        let group = String.starts_with ~prefix:"+" label in
        let label = if group then String.sub label 1 (String.length label - 1) else label in
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~at:(rx +. 12., Kit.cap_y ui ry row)
          ~color:(Pxui.Theme.ink_3 theme) key;
        let lx = rx +. 12. +. Float.max 28. (Ui.Paint.text_width paint ~size:(Kit.cap_size ui) key +. 8.) in
        Ui.Paint.text paint ~at:(lx, Kit.text_y ui ry row) ~color:theme.foreground label;
        (* a key that continues into more keys *)
        if group then Ui.Paint.chevron paint ~at:(rx +. col_w -. 16., ry +. (row /. 2.)) `Right
          (Pxui.Theme.ink_3 theme)) rows) sections

  let slots sections = List.fold_left (fun n (_, rows) -> n + 1 + List.length rows) 0 sections

  let panel ui keymap ~prefix ~focus ~focus_name =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let sections = List.filter (fun (_, rows) -> rows <> [])
        [ "Global", page keymap ~prefix None; focus_name, page keymap ~prefix (Some focus) ] in
    let view_w, view_h = Ui.view_size ui in
    let row = float (Ui.row_height ui) in
    let cols = max 1 (int_of_float ((view_w -. 32.) /. 220.)) in
    let per_column = max 3 ((slots sections + List.length sections + cols - 1) / cols) in
    let height = row +. 8. +. (float per_column *. row) +. 8. in
    let y = Float.max 0. (view_h -. float Layout.status_height -. height) in
    let leader = if prefix = "" then "Space" else "Space " ^ prefix in
    (* build before the body it shields; the host closes it on any key *)
    ignore (Ui.popup ui ~dismiss_initial:false ~at:(0., y) ~width:view_w ~height "leader" (fun () ->
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px height) "leader-sheet" in
      Ui.draw ui box (fun paint (x, y, w, _) ->
        Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.border theme);
        let y = y +. 8. in
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~at:(x +. 12., Kit.cap_y ui y row)
          ~color:(Pxui.Theme.ink_3 theme) leader;
        Ui.Paint.cap paint ~at:(x +. 20. +. Ui.Paint.text_width paint ~size:(Kit.cap_size ui) leader, Kit.cap_y ui y row)
          "Leader";
        let hint = "a key continues \xc2\xb7 esc closes" in
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~color:(Pxui.Theme.ink_2 theme)
          ~at:(x +. w -. 12. -. Ui.Paint.text_width paint ~size:(Kit.cap_size ui) hint, Kit.cap_y ui y row) hint;
        columns ui paint (x +. 4., y +. row, w -. 8.) ~per_column sections)))

  let sheet ui keymap =
    let module Ui = Pxui.Ui in
    let groups = ["Move", ["graph.walk."; "graph.frame-"; "scene.enter"; "scene.up"];
      "Build", ["graph.add"; "graph.repeat"; "graph.connect-hint"];
      "Shape", ["graph.open"; "graph.point"; "graph.group"; "graph.ungroup"];
      "Rows", ["row."];
      "Change", ["graph.display"; "graph.mute"; "graph.delete"; "graph.dissolve";
        "graph.copy"; "graph.cut"; "graph.paste"; "graph.duplicate"; "edit."];
      "Guide", ["guide."; "graph.find"; "graph.projection"]] in
    let sections = List.filter_map (fun (title, prefixes) ->
      let commands = List.filter (fun command -> command.trigger <> None
        && List.exists (fun prefix -> String.starts_with ~prefix command.id) prefixes) keymap in
      let commands = List.fold_left (fun seen command ->
        if List.exists (fun previous -> previous.id = command.id) seen then seen
        else command :: seen) [] commands |> List.rev in
      if commands = [] then None else Some (title, List.map (fun command ->
        let keys = List.filter_map (fun alias -> if alias.id <> command.id then None
          else match alias.trigger with
            | Some (Chord (_, modifiers)) when List.mem Input.Ctrl modifiers -> None
            | Some trigger -> Some (Editor_core.Keymap.label trigger) | None -> None) keymap
          |> List.sort_uniq String.compare |> String.concat " / " in
        keys, command.label) commands)) groups in
    let per_column = max 3 ((slots sections + List.length sections + 2) / 3) in
    match Ui.modal ui ~width:660. "guide-keys" (fun () ->
      Ui.label ui "Keys";
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float (per_column * Ui.row_height ui) +. 8.)) "keys-sheet" in
      Ui.draw ui box (fun paint (x, y, w, _) -> columns ui paint (x, y, w) ~per_column sections);
      not (Ui.button ui "Close###guide-close")) with
    | Some open_ -> open_ | None -> false
end

module Status_bar = struct
  let draw ui ~bounds:(x, y, width, height) ~text ~fps =
    if height > 0 then begin
      let module Ui = Pxui.Ui in
      let box = Ui.box ui ~w:(Ui.Px (float_of_int width))
          ~h:(Ui.Px (float_of_int height))
          ~at:(float_of_int x, float_of_int y) "workspace-status" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
        Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.edge theme);
        Ui.Paint.text paint ~at:(x +. 12., Kit.text_y ui y h) ~color:theme.foreground text;
        Option.iter (fun fps ->
          let fps = Printf.sprintf "%d fps" fps in
          Ui.Paint.cap paint ~color:theme.foreground
            ~at:(x +. w -. 12. -. Ui.Paint.cap_width paint fps, Kit.cap_y ui y h) fps) fps)
    end

  let guide ui ~bounds:(x, y, width, height) ~context commands =
    let module Ui = Pxui.Ui in
    if height <= 0 then false else
    let bar = Ui.box ui ~flags:Ui.(clickable + clip)
        ~w:(Ui.Px (float width)) ~h:(Ui.Px (float height))
        ~at:(float x, float y) "workspace-guide" in
    let keys = List.filter_map (fun (command : _ Editor_core.Command.t) ->
        Option.map (fun trigger -> Editor_core.Keymap.label trigger, command.label) command.trigger) commands in
    let title = Editor_core.Guide_context.name context in
    let theme = Ui.theme ui in
    Ui.draw ui bar (fun paint (x, y, w, h) ->
      Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
      Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.edge theme);
      (* the context as a label, then each key in ink-3 before what it does *)
      Ui.Paint.cap paint ~at:(x +. 12., Kit.cap_y ui y h) ~color:theme.foreground title;
      let tx = ref (x +. 24. +. Ui.Paint.cap_width paint title) and limit = x +. w -. 64. in
      let small = Kit.cap_size ui in
      (try List.iter (fun (key, label) ->
        let kw = Ui.Paint.text_width paint ~size:small key and lw = Ui.Paint.text_width paint label in
        if !tx +. kw +. 6. +. lw > limit then raise Exit;
        Ui.Paint.text paint ~size:small ~at:(!tx, Kit.cap_y ui y h) ~color:(Pxui.Theme.ink_3 theme) key;
        Ui.Paint.text paint ~at:(!tx +. kw +. 6., Kit.text_y ui y h) ~color:(Pxui.Theme.ink_2 theme) label;
        tx := !tx +. kw +. 6. +. lw +. 12.) keys
      with Exit -> Ui.Paint.text paint ~at:(!tx, Kit.text_y ui y h) ~color:(Pxui.Theme.ink_3 theme) "\xe2\x80\xa6"));
    let hide = Ui.within ui bar (fun () ->
      Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px 48.) ~h:(Ui.Px (float height))
        ~at:(float (max 0 (width - 48)), 0.) "guide-hide") in
    let hide_hovered = (Ui.signal ui hide).hovered in
    Ui.draw ui hide (fun paint (x, y, _, h) ->
      Ui.Paint.text paint ~at:(x +. 8., Kit.text_y ui y h)
        ~color:(if hide_hovered then theme.foreground else Pxui.Theme.ink_2 theme) "hide");
    if (Ui.signal ui bar).hovered then
      Ui.tooltip ui ~key:"guide-strip" ~text:(title ^ " \xc2\xb7 "
        ^ String.concat "  " (List.map fst keys) ^ " \xc2\xb7 Space k: all keys");
    (Ui.signal ui hide).clicked

  (* Key feedback in the pane's corner: a tip (sheet fill, hairline, ink text). *)
  let hud ui ~bounds:(x, y, width, height) ~text =
    let module Ui = Pxui.Ui in
    if width > 0 && height > 0 then begin
      let box = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px (float (max 0 (width - 24))))
        ~h:(Ui.Px 20.) ~at:(float (x + 12), float (y + max 0 (height - 32))) "key-hud" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint (x, y, _, h) ->
        let w = Ui.Paint.text_width paint text +. 12. in
        Ui.Paint.rect paint ~x ~y ~w ~h ~fill:theme.input ~stroke:(Pxui.Theme.edge theme) ();
        Ui.Paint.text paint ~at:(x +. 6., Kit.text_y ui y h -. 1.) ~color:theme.foreground text)
    end
end

module Timeline_bar = struct
  type intent = Pause_toggle | Stop_playback | Reset_playback
    | Seek_playback of int64

  let draw ui ~bounds:(x, y, width, height) ~playing ~frame ~time ~max_frame =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let fx = float x and fy = float y and fw = float width and fh = float height in
    let bar = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px fw) ~h:(Ui.Px fh) ~at:(fx, fy) "workspace-timeline" in
    Ui.draw ui bar (fun paint (x, y, w, h) ->
      Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
      Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.edge theme));
    Ui.within ui bar (fun () ->
      let cx = ref 6. and cy = Float.max 0. (Float.floor ((fh -. 20.) /. 2.)) in
      let button key ?icon label =
        let w = Kit.button_width ui ~icon:(icon <> None) label in
        let clicked = Kit.button ui ~key ~at:(!cx, cy) ~w ?icon label in
        cx := !cx +. w +. 2.; clicked in
      let pause = button "timeline-play" ~icon:`Play (if playing then "Pause" else "Play") in
      let stop = button "timeline-stop" ~icon:`Stop "Stop" in
      let reset = button "timeline-reset" "Reset" in
      (* the frame, typed: a click opens the field *)
      let label_x = !cx +. 8. in
      let field_x = label_x +. 16. in
      let current = Int64.to_string frame in
      let typed = fst (Ui.value_field ui ~at:(field_x, cy) ~w:48. ~h:20.
          ~valid:(fun text -> Int64.of_string_opt (String.trim text) <> None)
          "timeline-frame-field" current) in
      let readout = Printf.sprintf "%.2f s" time in
      let ruler_x = field_x +. 56. +. Ui.text_width ui readout +. 12. in
      let ruler_w = Float.max 0. (fw -. ruler_x) in
      let range = Float.max (Int64.to_float frame) (float_of_int max_frame) in
      let ruler = Ui.box ui ~flags:Ui.(clickable + blocking) ~at:(ruler_x, 0.)
          ~w:(Ui.Px ruler_w) ~h:(Ui.Px fh) "timeline-scrub" in
      let signal = Ui.signal ui ruler in
      let scrub = if (signal.held || signal.released) && ruler_w > 1. then begin
          let px = fst (if signal.released then signal.release_point else signal.pointer) in
          let rx, _, _, _ = Ui.rect ui ruler in
          Some (Float.round (Float.max 0. (Float.min 1. ((px -. rx) /. (ruler_w -. 1.))) *. range))
        end else None in
      Ui.draw ui bar (fun paint (x, y, _, h) ->
        Ui.Paint.cap paint ~at:(x +. label_x, Kit.cap_y ui y h) "F";
        Ui.Paint.text paint ~at:(x +. field_x +. 56., Kit.text_y ui y h)
          ~color:(Pxui.Theme.ink_2 theme) readout);
      Ui.draw ui ruler (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y:(y +. 1.) ~w ~h:(h -. 1.) theme.input;
        Ui.Paint.fill paint ~x ~y ~w:1. ~h (Pxui.Theme.edge theme);
        let head = x +. Float.floor ((Int64.to_float frame /. Float.max 1. range) *. (w -. 2.)) in
        Ui.Paint.fill paint ~x ~y:(y +. 1.) ~w:(head -. x) ~h:(h -. 1.) (Pxui.Theme.tint theme);
        (* fifty minor ticks, every fifth one major *)
        for tick = 0 to 50 do
          let tx = x +. Float.floor (float tick *. (w -. 1.) /. 50.) in
          if tick mod 5 = 0 then Ui.Paint.fill paint ~x:tx ~y:(y +. h -. 10.) ~w:1. ~h:10. (Pxui.Theme.border theme)
          else Ui.Paint.fill paint ~x:tx ~y:(y +. h -. 5.) ~w:1. ~h:5. (Pxui.Theme.edge theme)
        done;
        Ui.Paint.fill paint ~x:head ~y ~w:2. ~h theme.accent;
        Ui.Paint.cap paint ~color:theme.accent ~at:(head +. 5., y +. 1.) (Int64.to_string frame));
      List.filter_map Fun.id [
        (* a typed frame clamps to the timeline: 0 to the last frame *)
        (if typed <> current then Option.map (fun n ->
           Seek_playback (Int64.max 0L (Int64.min (Int64.of_int max_frame) n)))
           (Int64.of_string_opt (String.trim typed)) else None);
        (if pause then Some Pause_toggle else None);
        (if stop then Some Stop_playback else None);
        (if reset then Some Reset_playback else None);
        (match scrub with
         | Some target when target <> Int64.to_float frame -> Some (Seek_playback (Int64.of_float target))
         | _ -> None)])
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

  type macro = { name : string; holes : (bool * string) array }

  (* ponytail: the first 12 literals only; a template with more is rare and the
     rest stay copied into it *)
  let macro ui ~key ~title ~literals ~free (m : macro) =
    Pxui.Ui.modal ui ~width:480. key (fun () ->
      (* Enter in one of its fields creates the macro, like the button *)
      let enter = Pxui.Ui.text_input_focused ui && Pxui.Ui.key_pressed ui Rays.Input.Enter in
      Pxui.Ui.label ui title;
      Pxui.Ui.inspector_message ui ~key:(key ^ "-hint")
        (match free with
         | [] -> "Tick the literals that become holes."
         | names -> "Holes: ticked literals and " ^ String.concat ", " names);
      let holes = Array.mapi (fun i (on, name) ->
        if i >= 12 || i >= Array.length literals then on, name else begin
          let on = Pxui.Ui.toggle ui (Printf.sprintf "%d  %s" (i + 1) literals.(i)) on in
          let name = if on then Pxui.Ui.text_field ui (Printf.sprintf "hole %d" (i + 1)) name else name in
          on, name
        end) m.holes in
      let name = Pxui.Ui.text_field ui "Macro name" m.name in
      let submit = Pxui.Ui.button ui "Create macro" in
      { name; holes }, if submit || enter then `Submit else `None)
end

module Tree = struct
  module Ui = Pxui.Ui
  module Ids = Set.Make (Int)

  type row = { id : int; depth : int; label : string; detail : string;
               badge : string * Rays.Color.t;
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
    | Rename_row | Delete_rows | Filter | Hide | Activate_row

  type drag =
    | Rows of { ids : int list; moved : bool }
    | Paint of { column : int; value : bool; painted : int list }

  type t = { focus : int option; anchor : int option; folded : Ids.t;
             filter : string option; renaming : (int * string) option;
             drag : drag option; reveal : bool;
             context : (float * float * int * int list) option;
             shown : (row array * Ids.t * string option * int array) option }

  let create () = { focus = None; anchor = None; folded = Ids.empty; filter = None;
    renaming = None; drag = None; reveal = false; context = None;
    shown = None }
  let reveal t = { t with reveal = true }
  let focused t = t.focus
  let editing t = t.renaming <> None || t.filter <> None
  let summary t = Printf.sprintf "focus %s, %d folded, filter %s"
    (Option.fold ~none:"-" ~some:string_of_int t.focus) (Ids.cardinal t.folded)
    (Option.fold ~none:"-" ~some:(Printf.sprintf "%S") t.filter)

  let bindings =
    let open Editor_core.Keymap in
    let key ?(modifiers = []) id label key action = Editor_core.Command.make
        ~id:("list." ^ id) ~label ~trigger:(Chord (key, modifiers)) action in
    let open Rays.Input in
    [ key "up" "previous row" ArrowUp Up; key "down" "next row" ArrowDown Down;
      key "up" "previous row" (KeyChar 'k') Up; key "down" "next row" (KeyChar 'j') Down;
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
      key "delete" "delete" Delete Delete_rows; key "delete" "delete" Backspace Delete_rows;
      key "filter" "filter" (KeyChar '/') Filter;
      key "hide" "hide / show" (KeyChar 'h') Hide;
      key "activate" "open selected in graph" Enter Activate_row ]

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
    | Delete_rows, _ -> t, [Delete targets]
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

  let flag_width = 20.  (* a 12-point flag and its 8-point gap *)
  let indent_step = 12.

  (* The row list, its toggle columns, and the filter and rename prompts,
     built inside [Ui.frame]. One box takes every pointer gesture; rows are
     found from the pointer, so only the visible slice is painted. *)
  let update t ui (_frame : Rays.Frame.t) ~bounds:(x, y, w, h) ?(title = "") ~columns rows
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
        ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(x, y)
        ~scroll_step:height "tree" in
    let signal = Ui.signal ui box in
    let scroll = Ui.scroll_offset ui box in
    let scroll = match t.reveal, Option.bind t.focus (position rows shown) with
      | true, Some k ->
          let row_top = float_of_int k *. height in
          if row_top < scroll then row_top
          else if row_top +. height > scroll +. body then row_top +. height -. body
          else scroll
      | _ -> scroll in
    let scroll = Float.max 0. (Float.min scroll
        (Float.max 0. (float_of_int count *. height -. body))) in
    if t.reveal then Ui.set_scroll_offset ui box scroll;
    ignore (Ui.within ui box (fun () ->
      Ui.box ui ~w:(Ui.Px w)
        ~h:(Ui.Px (float_of_int (count + 1) *. height)) "tree-content"));
    let row_at (_, py) =
      let k = int_of_float (Float.floor ((py -. top +. scroll) /. height)) in
      if py < top || k < 0 || k >= count then None else Some k in
    let columns_x = x +. w -. 8. -. flag_width *. float_of_int (List.length columns) in
    let column_at (px, _) =
      if px < columns_x -. 4. then None
      else Some (int_of_float ((px -. columns_x) /. flag_width)) in
    let flag k column = match List.nth_opt (at k).flags column with
      | Some value -> value | None -> false in
    let is_selected id = List.mem id selected in
    let left = signal.button = Some Rays.Input.LeftButton in
    let modifier key = List.mem key (Ui.press_keys ui box) in
    (* Presses: select, start a row drag or a toggle paint. *)
    let t, intents = if not (signal.pressed && left) then t, [] else
      match row_at signal.press_point with
      | None -> { t with drag = None }, [Select []]
      | Some k ->
          let row = at k in
          let px, _ = signal.press_point in
          let chevron_x = x +. 12. +. float_of_int row.depth *. indent_step in
          if has_children rows shown.(k) && px >= chevron_x -. 6.
              && px < chevron_x +. 10. then
            { t with folded = (if Ids.mem row.id t.folded
                then Ids.remove row.id t.folded else Ids.add row.id t.folded);
              drag = None }, []
          else (match column_at signal.press_point with
           | Some column when column < List.length row.flags && not row.ghost ->
               let value = not (flag k column) in
               let ids = if is_selected row.id then selected else [row.id] in
               { t with drag = Some (Paint { column; value; painted = ids }) },
               [Flag { ids; column; value }]
           | _ ->
               let selection =
                 if modifier Rays.Input.Shift then
                   let anchor = Option.value ~default:k
                       (Option.bind t.anchor (position rows shown)) in
                   row.id :: List.filter (( <> ) row.id) (span rows shown anchor k)
                 else if modifier Rays.Input.Meta || modifier Rays.Input.Ctrl then
                   if is_selected row.id then List.filter (( <> ) row.id) selected
                   else row.id :: selected
                 else if is_selected row.id then
                   row.id :: List.filter (( <> ) row.id) selected
                 else [row.id] in
               { t with focus = Some row.id;
                 anchor = (if modifier Rays.Input.Shift then t.anchor else Some row.id);
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
    let ancestors k =
      let chain = ref [] and depth = ref (at k).depth in
      for candidate = k - 1 downto 0 do
        if (at candidate).depth < !depth then begin
          chain := candidate :: !chain; depth := (at candidate).depth end
      done;
      !chain in
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
      let scroll = Ui.scroll_position ui box in
      let first = max 0 (int_of_float (Float.floor (scroll /. height))) in
      let last = min (count - 1)
          (int_of_float (Float.ceil ((scroll +. body) /. height))) in
      let sticky = if count = 0 || scroll <= 0. then []
        else List.filteri (fun index _ -> index < 3) (ancestors first) in
      let text ?(color = theme.foreground) at label =
        Ui.Paint.text paint ~at ~color label in
      Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
      let ink_2 = Pxui.Theme.ink_2 theme and ink_3 = Pxui.Theme.ink_3 theme in
      let hover = if signal.hovered && t.drag = None then row_at signal.pointer else None in
      let draw_row k row_y =
        let row = at k in
        let index = shown.(k) in
        let selected = is_selected row.id in
        (* current (the keyboard cursor) and selected are the control fill; selected adds the
           accent brackets, drawn once the rows are down *)
        Ui.Paint.fill paint ~x ~y:row_y ~w ~h:height theme.panel;
        if selected then Ui.Paint.fill paint ~x:(x +. 4.) ~y:row_y ~w:(w -. 8.) ~h:height theme.control
        else if t.focus = Some row.id then Ui.Paint.fill paint ~x ~y:row_y ~w ~h:height theme.control
        else if hover = Some k then Ui.Paint.fill paint ~x ~y:row_y ~w ~h:height (Pxui.Theme.faint_border theme);
        let indent level = x +. 12. +. float_of_int level *. indent_step in
        let text_y = Kit.text_y ui row_y height in
        if has_children rows index then
          Ui.Paint.chevron paint ~at:(indent row.depth +. 3., row_y +. height /. 2.)
            (if Ids.mem row.id t.folded && t.filter = None then `Right else `Down) ink_2;
        (* the kind: a letter in the label style, in ink once selected *)
        let badge_x = indent row.depth +. 14. in
        let letter = if row.link then "\xe2\x86\xb3" else fst row.badge in
        Ui.Paint.cap paint ~at:(badge_x, Kit.cap_y ui row_y height)
          ~color:(if selected then theme.foreground else ink_2) letter;
        let label_x = badge_x +. 16. in
        let hidden = match row.flags with shown :: _ -> not shown | [] -> false in
        let color = if row.ghost || row.link || hidden then ink_3 else theme.foreground in
        text ~color (label_x, text_y) row.label;
        if row.detail <> "" then begin
          (* the detail sits before the flags, where the label leaves room *)
          let dw = Ui.Paint.text_width paint row.detail in
          let dx = columns_x -. 8. -. dw in
          if dx > label_x +. Ui.Paint.text_width paint row.label +. 8. then
            text ~color:ink_2 (dx, text_y) row.detail
        end;
        (* Flags: a square for the first column (visible), a round one for the others. *)
        List.iteri (fun column value ->
          let cx = columns_x +. (float_of_int column *. flag_width) +. 6.
          and cy = row_y +. (height /. 2.) in
          if column = 0 then begin
            Ui.Paint.rect paint ~x:(cx -. 6.) ~y:(cy -. 6.) ~w:12. ~h:12. ~fill:theme.input
              ~stroke:(Pxui.Theme.border theme) ();
            if value then Ui.Paint.fill paint ~x:(cx -. 3.) ~y:(cy -. 3.) ~w:6. ~h:6. ink_2
          end else begin
            Ui.Paint.circle paint ~at:(cx, cy) ~radius:6. ~fill:theme.input
              ~stroke:(Pxui.Theme.border theme) ();
            if value then Ui.Paint.circle paint ~at:(cx, cy) ~radius:3. ~fill:ink_2 ()
          end) row.flags;
        if selected then Ui.Paint.brackets paint ~x:(x +. 4.) ~y:row_y ~w:(w -. 8.) ~h:height
          ~offset:(-1.) ~length:6. theme.accent in
      for k = first to last do
        draw_row k (top +. float_of_int k *. height -. scroll)
      done;
      List.iteri (fun slot k -> draw_row k (top +. float_of_int slot *. height)) sticky;
      if sticky <> [] then
        Ui.Paint.line paint ~from_:(x, top +. float_of_int (List.length sticky) *. height)
          ~to_:(x +. w, top +. float_of_int (List.length sticky) *. height)
          (Pxui.Theme.edge theme);
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
      (* Header: the level as a section label and the flag columns, or the filter under a prompt. *)
      Ui.Paint.fill paint ~x ~y ~w ~h:height theme.panel;
      if t.filter = None then begin
        Ui.Paint.cap paint ~at:(x +. 12., Kit.cap_y ui y height) ~color:ink_3 title;
        List.iteri (fun column name ->
          Ui.Paint.cap paint ~color:ink_2
            ~at:(columns_x +. (float_of_int column *. flag_width) +. 6.
                 -. (Ui.Paint.cap_width paint name /. 2.), Kit.cap_y ui y height) name) columns
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
    { t with reveal = false }, intents
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

  type 'a item = Field of 'a | Folder of string * 'a item list

  type flow_row = {
    path : string;
    fields : Param.field_view list;
    shown : bool;
    locked : bool;
    drive : string option;
    live : string option;
    components : (string * string * string option) list;
    split : bool option;
  }

  type flow_change = Edited of string * Param.value
    | Pinned of string * bool | Split of string * bool | Reset of string
    | Expression of string * string

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

  let flow_fields ui ?(expanded = []) ?width ?(actions = true) ?(chips = [])
      ?(on_choice = fun _ _ -> ()) rows =
    (* the rows fill the panel they are built in *)
    let width = Option.value width ~default:(Ui.inspector_width ui) in
    let theme = Ui.theme ui in
    let expression text = String.starts_with ~prefix:"=" text
      && String.length (String.trim text) > 1 in
    let action ui key label ~x ~y ~enabled =
      let pin = label = "\xe2\x97\x8f" || label = "\xe2\x97\x8b" in
      let x = if pin then 6. else x and w = if pin then 18. else 20. in
      let box = Ui.box ui ~flags:(if enabled then Ui.(clickable + tab_stop) else Ui.none)
          ~at:(x, y) ~w:(Ui.Px w) ~h:(Ui.Px 20.) key in
      let signal = Ui.signal ui box in
      let clicked = enabled && signal.clicked in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        let color = if enabled && signal.hovered then theme.foreground else Pxui.Theme.ink_3 theme in
        if pin then
          Ui.Paint.circle paint ~at:(x +. 9., y +. (h /. 2.)) ~radius:3.
            ?fill:(if label = "\xe2\x97\x8f" then Some theme.foreground else None)
            ?stroke:(if label = "\xe2\x97\x8f" then None else Some color) ()
        else if label = "\xc3\x97" then begin
          let cx = x +. (w /. 2.) and cy = y +. (h /. 2.) in
          Ui.Paint.line paint ~from_:(cx -. 3.5, cy -. 3.5) ~to_:(cx +. 3.5, cy +. 3.5) color;
          Ui.Paint.line paint ~from_:(cx -. 3.5, cy +. 3.5) ~to_:(cx +. 3.5, cy -. 3.5) color
        end else Ui.Paint.text paint ~at:(x +. 1., Kit.cap_y ui y h) ~size:(Kit.cap_size ui) ~color label);
      clicked in
    let input field path ~edit ~x ~y ~w =
      let key = "flow-value-" ^ path in
      let numeric text valid ?display ?fraction ?slide convert =
        let changed, _ = Ui.value_field ui ~at:(x, y) ~w ~h:20.
            ?display ?fraction ?slide ~edit ~left:(expression text) ~valid:(fun text -> valid text || expression text)
            key text in
        if changed = text then [] else if expression changed then
          [Expression (path, changed)]
        else Option.fold ~none:[] ~some:(fun value -> [Edited (field.Param.name, value)])
            (convert changed) in
      match field.Param.kind, field.current with
      | Param.Integer_view range, Param.Int_value value ->
          let fraction = float (value - range.soft_min)
            /. float (max 1 (range.soft_max - range.soft_min)) in
          let slide fraction = string_of_int (range.soft_min + int_of_float
            (Float.round (fraction *. float (range.soft_max - range.soft_min)))) in
          numeric (string_of_int value) (fun text -> int_of_string_opt text <> None)
            ~fraction ~slide (fun text -> Option.map (fun n -> Param.Int_value n)
              (int_of_string_opt text))
      | Param.Floating_view range, Param.Float_value value ->
          let fraction = (value -. range.soft_min)
            /. Float.max 0.000001 (range.soft_max -. range.soft_min) in
          let slide fraction = Printf.sprintf "%.6g"
            (range.soft_min +. fraction *. (range.soft_max -. range.soft_min)) in
          numeric (Printf.sprintf "%.17g" value)
            (fun text -> Option.fold ~none:false ~some:Float.is_finite
              (float_of_string_opt text)) ~display:(Printf.sprintf "%.6g" value)
            ~fraction ~slide
            (fun text -> Option.map (fun n -> Param.Float_value n)
              (float_of_string_opt text))
      | Param.Text_view, Param.Text_value value ->
          let text, _ = Ui.value_field ui ~at:(x, y) ~w ~h:20.
              ~left:true ~valid:(fun _ -> true) key value in
          if text = value then [] else [Edited (field.name, Param.Text_value text)]
      | Param.Choice_view choices, Param.Choice_value value ->
          let box = Ui.box ui ~flags:Ui.(clickable + tab_stop + clip)
              ~at:(x, y) ~w:(Ui.Px w) ~h:(Ui.Px 20.) key in
          let index = Option.value ~default:0 (Array.find_index (( = ) value) choices) in
          on_choice field.Param.name box;
          let just_opened = (Ui.signal ui box).clicked in
          let open_ = just_opened || Ui.state ui box ~default:0 = 1 in
          Ui.set_state ui box (if open_ then 1 else 0);
          let hovered = (Ui.signal ui box).hovered in
          Ui.draw ui box (fun paint (x, y, w, h) ->
            if hovered then Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.hover_fill theme);
            Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1.
              (if open_ then theme.accent else Pxui.Theme.edge theme);
            let pad = match List.assoc_opt choices.(index) chips with
              | Some color ->
                  Ui.Paint.rect paint ~x:(x +. 2.) ~y:(y +. 6.) ~w:8. ~h:8. ~fill:color
                    ~stroke:(Pxui.Theme.edge theme) (); 14.
              | None -> 0. in
            Ui.Paint.text paint ~at:(x +. 2. +. pad, Kit.text_y ui y h)
              ~color:theme.foreground choices.(index);
            Ui.Paint.chevron paint ~at:(x +. w -. 6., y +. (h /. 2.)) (if open_ then `Up else `Down) theme.foreground);
          if not open_ || just_opened then [] else
            let bx, by, bw, bh = Ui.rect ui box in
            (match Ui.context_menu ui ~at:(bx, by +. bh) ~width:bw ~selected:index
                ~swatches:(Array.to_list (Array.map (fun choice -> List.assoc_opt choice chips) choices))
                (key ^ "-options")
                (Array.to_list (Array.map (fun choice -> choice, true) choices)) with
             | `Open -> []
             | `Dismiss -> Ui.set_state ui box 0; []
             | `Pick selected ->
                 Ui.set_state ui box 0;
                 if selected = index then [] else
                   [Edited (field.name, Param.Choice_value choices.(selected))])
      | Param.Toggle_view, Param.Bool_value value ->
          let edited = Ui.inspector_toggle_value ui ~key ~at:(x, y) value in
          if edited = value then [] else
            [Edited (field.name, Param.Bool_value edited)]
      | _ -> [] in
    let driven path title source live shown =
      let box, control_x, control_y, control_w = Ui.inspector_row ui
          ~width ~key:("flow-row-" ^ path) ~label:title () in
      Ui.within ui box (fun () ->
        let source_width = max 4 (int_of_float ((control_w -. 24.) /. 7.)) in
        let display = if String.length source > source_width then
          String.sub source 0 (max 0 (source_width - 1)) ^ "…" else source in
        let edits = if String.starts_with ~prefix:"=" source then
          let text, _ = Ui.value_field ui ~at:(control_x, control_y)
              ~w:(control_w -. 24.) ~h:20.
              ~left:true ~valid:expression ("flow-expression-" ^ path) source in
          if text = source then [] else [Expression (path, text)]
        else (Ui.draw ui box (fun paint (x, y, _, _) ->
          let ty = Kit.text_y ui (y +. control_y) 20. in
          Ui.Paint.text paint ~at:(x +. control_x +. 2., ty) ~color:theme.accent "\xe2\x86\x90";
          Ui.Paint.text paint ~at:(x +. control_x +. 18., ty) ~color:(Pxui.Theme.ink_2 theme) display;
          Option.iter (fun value ->
            Ui.Paint.text paint ~color:theme.foreground
              ~at:(x +. control_x +. control_w -. 26. -. Ui.Paint.text_width paint value, ty) value) live); []) in
        let reset = action ui ("reset-" ^ path) "×" ~x:(width -. 32.)
            ~y:control_y ~enabled:true in
        let pin = action ui ("pin-" ^ path) (if shown then "●" else "○")
            ~x:0. ~y:control_y ~enabled:false in
        let _ = pin in
        if reset then Reset path :: edits else edits) in
    let scalar path title field shown =
      let box, control_x, control_y, control_w = Ui.inspector_row ui
          ~width ~key:("flow-row-" ^ path) ~label:title () in
      Ui.within ui box (fun () ->
        (* the label's own extent: its column, or the whole row above a stacked control *)
        let label = Ui.box ui ~flags:Ui.clickable ~at:(26., 2.)
            ~w:(Ui.Px (if control_y > 20. then width -. 38. else Float.max 1. (control_x -. 34.)))
            ~h:(Ui.Px 20.) "label-edit" in
        let edit = (Ui.signal ui label).double_clicked in
        let edits = input field path ~x:control_x ~y:control_y ~w:control_w ~edit in
        let pinned = actions && action ui ("pin-" ^ path)
            (if shown then "●" else "○") ~x:0.
            ~y:control_y ~enabled:true in
        if pinned then Pinned (path, not shown) :: edits else edits) in
    let has_substr sub s =
      let len_s = String.length s and len_sub = String.length sub in
      let rec check i =
        if i + len_sub > len_s then false
        else if String.sub s i len_sub = sub then true
        else check (i + 1) in
      check 0 in
    let is_color_3 (row : flow_row) =
      List.length row.fields = 3 && (
        has_substr "color" row.path
        || List.for_all (fun (f : Param.field_view) -> has_substr "color" f.name) row.fields
      ) in
    let is_color_1 (field : Param.field_view) =
      match field.kind, field.current with
      | Param.Text_view, Param.Text_value text ->
          (String.starts_with ~prefix:"#" text || has_substr "color" field.name)
          && Result.is_ok (Color.hex text)
      | _ -> false in
    let color_row_3 (row : flow_row) title fields shown =
      let path = row.path in
      let to_f = function
        | Param.Float_value x -> x
        | Int_value x -> float x
        | _ -> 0. in
      let r, g, b = match fields with
        | [ f0; f1; f2 ] -> to_f f0.Param.current, to_f f1.current, to_f f2.current
        | _ -> 0., 0., 0. in
      let clamp x = max 0 (min 255 (int_of_float (Float.round (x *. 255.)))) in
      let hex_str = Printf.sprintf "#%02x%02x%02x" (clamp r) (clamp g) (clamp b) in
      let swatch_color = Color.rgb (clamp r) (clamp g) (clamp b) in
      let box, control_x, control_y, control_w = Ui.inspector_row ui
          ~width ~key:("flow-row-" ^ path) ~label:title () in
      let whole = Ui.within ui box (fun () ->
        let split = Option.value ~default:false row.split in
        let swatch_w = 20. and swatch_h = 20. in
        let swatch = Ui.box ui ~at:(control_x, control_y) ~w:(Ui.Px swatch_w) ~h:(Ui.Px swatch_h) ("swatch-" ^ path) in
        Ui.draw ui swatch (fun paint (sx, sy, sw, sh) ->
          Ui.Paint.rect paint ~x:sx ~y:sy ~w:sw ~h:sh ~fill:swatch_color
            ~stroke:(Pxui.Theme.edge theme) ());
        let hex_x = control_x +. swatch_w +. 8. in
        let hex_w = 64. in
        let text, _ = Ui.value_field ui ~at:(hex_x, control_y) ~w:hex_w ~h:20.
            ~left:true ~valid:(fun t -> Result.is_ok (Color.hex t)) ("hex-" ^ path) hex_str in
        let hex_edits =
          if text = hex_str then [] else
          match Color.hex text with
          | Ok c ->
              let nr, ng, nb, _ = Color.to_floats c in
              (match fields with
               | [ f0; f1; f2 ] ->
                   [ Edited (f0.Param.name, Param.Float_value nr);
                     Edited (f1.name, Param.Float_value ng);
                     Edited (f2.name, Param.Float_value nb) ]
               | _ -> [])
          | Error _ -> [] in
        let sliders_x = hex_x +. hex_w +. 8. in
        let sliders_w = Float.max 60. (control_w -. (swatch_w +. 8. +. hex_w +. 8.) -. 24.) in
        let field_w = (sliders_w -. 16.) /. 3. in
        let slider_edits = if split || row.components <> [] || control_w < 140. then [] else
          List.concat (List.mapi (fun index field ->
            let axis = List.nth [ "r"; "g"; "b" ] index in
            let ax_x = sliders_x +. float index *. (field_w +. 8.) in
            Ui.draw ui box (fun paint (x, y, _, _) ->
              Ui.Paint.text paint ~at:(x +. ax_x +. 2., Kit.cap_y ui (y +. control_y) 20.)
                ~size:(Kit.cap_size ui) ~color:(Pxui.Theme.ink_3 theme) axis);
            input field (path ^ "." ^ axis)
              ~edit:false
              ~x:ax_x
              ~y:control_y
              ~w:field_w) fields) in
        let toggle = actions && action ui ("split-" ^ path) "rgb"
            ~x:(width -. 32.) ~y:control_y
            ~enabled:(not row.locked) in
        let pin = actions && action ui ("pin-" ^ path)
            (if shown then "●" else "○")
            ~x:0. ~y:control_y
            ~enabled:(not row.locked) in
        slider_edits @ hex_edits
        @ (if toggle then [ Split (path, not split) ] else [])
        @ (if pin then [ Pinned (path, not shown) ] else [])) in
      if row.split = Some true || row.components <> [] || control_w < 140. then
        whole @ List.concat (List.mapi (fun index field ->
          let axis = List.nth [ "r"; "g"; "b" ] index in
          let path = path ^ "." ^ axis in
          match List.find_opt (fun (name, _, _) -> name = path) row.components with
          | Some (_, source, live) -> driven path field.Param.label source live shown
          | None -> scalar path field.label field shown) fields)
      else whole in
    let color_row_1 path title field shown =
      let text_val = match field.Param.current with Param.Text_value t -> t | _ -> "#ffffff" in
      let c = Result.value (Color.hex text_val) ~default:Color.white in
      let r, g, b, _ = Color.to_floats c in
      let clamp x = max 0 (min 255 (int_of_float (Float.round (x *. 255.)))) in
      let hex_str = Printf.sprintf "#%02x%02x%02x" (clamp r) (clamp g) (clamp b) in
      let swatch_color = Color.rgb (clamp r) (clamp g) (clamp b) in
      let box, control_x, control_y, control_w = Ui.inspector_row ui
          ~width ~key:("flow-row-" ^ path) ~label:title () in
      Ui.within ui box (fun () ->
        let swatch_w = 20. and swatch_h = 20. in
        let swatch = Ui.box ui ~at:(control_x, control_y) ~w:(Ui.Px swatch_w) ~h:(Ui.Px swatch_h) ("swatch-" ^ path) in
        Ui.draw ui swatch (fun paint (sx, sy, sw, sh) ->
          Ui.Paint.rect paint ~x:sx ~y:sy ~w:sw ~h:sh ~fill:swatch_color
            ~stroke:(Pxui.Theme.edge theme) ());
        let hex_x = control_x +. swatch_w +. 8. in
        let hex_w = 64. in
        let text, _ = Ui.value_field ui ~at:(hex_x, control_y) ~w:hex_w ~h:20.
            ~left:true ~valid:(fun t -> Result.is_ok (Color.hex t)) ("hex-" ^ path) hex_str in
        let hex_edits =
          if text = hex_str then [] else
          match Color.hex text with
          | Ok _ -> [ Edited (field.Param.name, Param.Text_value text) ]
          | Error _ -> [] in
        let sliders_x = hex_x +. hex_w +. 8. in
        let sliders_w = Float.max 60. (control_w -. (swatch_w +. 8. +. hex_w +. 8.) -. 24.) in
        let field_w = (sliders_w -. 16.) /. 3. in
        let slider_edits = if control_w < 140. then [] else
          List.concat (List.mapi (fun index (axis, cur) ->
            let ax_x = sliders_x +. float index *. (field_w +. 8.) in
            Ui.draw ui box (fun paint (x, y, _, _) ->
              Ui.Paint.text paint ~at:(x +. ax_x +. 2., Kit.cap_y ui (y +. control_y) 20.)
                ~size:(Kit.cap_size ui) ~color:(Pxui.Theme.ink_3 theme) axis);
            let key = "flow-value-" ^ path ^ "." ^ axis in
            let changed, _ = Ui.value_field ui ~at:(ax_x, control_y) ~w:field_w ~h:20.
                ~display:(Printf.sprintf "%.2f" cur) ~fraction:cur
                ~slide:(fun f -> Printf.sprintf "%.2f" f)
                ~edit:false ~left:false ~valid:(fun t -> float_of_string_opt t <> None)
                key (Printf.sprintf "%.2f" cur) in
            if changed = Printf.sprintf "%.2f" cur then [] else
            match float_of_string_opt changed with
            | Some v ->
                let v = Float.max 0. (Float.min 1. v) in
                let nr = if index = 0 then v else r in
                let ng = if index = 1 then v else g in
                let nb = if index = 2 then v else b in
                let new_hex = Printf.sprintf "#%02x%02x%02x" (clamp nr) (clamp ng) (clamp nb) in
                [ Edited (field.Param.name, Param.Text_value new_hex) ]
            | None -> []) [ "r", r; "g", g; "b", b ]) in
        let pin = actions && action ui ("pin-" ^ path)
            (if shown then "●" else "○")
            ~x:0. ~y:control_y ~enabled:true in
        slider_edits @ hex_edits @ (if pin then [ Pinned (path, not shown) ] else [])) in
    let row_widget (row : flow_row) =
      let title = match row.fields with
        | [field] -> field.Param.label | _ -> row.path in
      match row.drive, row.fields with
      | Some source, _ -> driven row.path title source row.live row.shown
      | None, [field] when is_color_1 field -> color_row_1 row.path title field row.shown
      | None, [field] -> scalar row.path title field row.shown
      | None, fields when is_color_3 row -> color_row_3 row title fields row.shown
      | None, fields ->
          let box, control_x, control_y, control_w = Ui.inspector_row ui
              ~width ~key:("flow-row-" ^ row.path) ~label:title () in
          let whole = Ui.within ui box (fun () ->
            let split = Option.value ~default:false row.split in
            let field_width = (control_w -. (if actions then 24. else 0.) +. 8.) /. 3. in
            let edits = if split || row.components <> [] || control_w < 140. then [] else
              List.concat (List.mapi (fun index field ->
                let axis = List.nth ["x"; "y"; "z"] index in
                Ui.draw ui box (fun paint (x, y, _, _) ->
                  Ui.Paint.text paint ~at:(x +. control_x +. float index *. field_width +. 2.,
                    Kit.cap_y ui (y +. control_y) 20.)
                    ~size:(Kit.cap_size ui) ~color:(Pxui.Theme.ink_3 theme) axis);
                input field (row.path ^ "." ^ axis)
                  ~edit:false
                  ~x:(control_x +. float index *. field_width)
                  ~y:control_y
                  ~w:(field_width -. 8.)) fields) in
            let toggle = actions && action ui ("split-" ^ row.path) "xyz"
                ~x:(width -. 32.) ~y:control_y
                ~enabled:(not row.locked) in
            let pin = actions && action ui ("pin-" ^ row.path)
                (if row.shown then "●" else "○")
                ~x:0. ~y:control_y
                ~enabled:(not row.locked) in
            edits @ (if toggle then [Split (row.path, not split)] else [])
            @ (if pin then [Pinned (row.path, not row.shown)] else [])) in
          if row.split = Some true || row.components <> [] || control_w < 140. then
            whole @ List.concat (List.mapi (fun index field ->
              let axis = List.nth ["x"; "y"; "z"] index in
              let path = row.path ^ "." ^ axis in
              match List.find_opt (fun (name, _, _) -> name = path) row.components with
              | Some (_, source, live) -> driven path field.Param.label source live row.shown
              | None -> scalar path field.label field row.shown) fields)
          else whole in
    let rec build path items = List.concat_map (function
      | Field row -> row_widget row
      | Folder (label, children) ->
          let path = path @ [label] in
          let key = String.concat "/" path in
          Option.value ~default:[]
            (Ui.inspector_section ui ~key:("flow-section-" ^ key)
              ~expanded:(List.mem key expanded) label
              (fun () -> build path children))) items in
    if rows = [] then (Ui.inspector_message ui ~key:"no-parameters" "No parameters"; []) else
      build [] (List.fold_left (fun items (row : flow_row) ->
        let folder = match row.fields with
          | (field : Param.field_view) :: _ -> field.folder | [] -> [] in
        insert folder row items) [] rows)

  let fields ui ?expanded ?width views =
    let rows = List.map (fun (field : Param.field_view) ->
      { path = field.name; fields = [field]; shown = false; locked = true;
        drive = None; live = None; components = []; split = None }) views in
    flow_fields ui ?expanded ?width ~actions:false rows
    |> List.filter_map (function Edited (name, value) -> Some (name, value)
      | _ -> None)

  let record ui ?expanded schema values =
    match fields ui ?expanded (Param.view schema values) with
    | [] -> Ok (values, Param.no_effects)
    | changes -> Param.apply_all schema values changes
end
