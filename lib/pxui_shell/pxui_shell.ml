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
  let header_margin = 4
  let status_height = 25  (* the line-2 hairline and the 24-point bar *)
  let timeline_height = 24
  let timeline_strip = 25  (* the strip under a tree without a timeline: hairline and bar *)

  (* a collapsed panel is its header: as tall in a stack, a 28-point column in a row *)
  let strip axis = if axis = `V then header_height else collapsed_width

  type leaf = { path : path; panel : panel; frame : bounds; header : bounds; body : bounds; floating : bool }
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
      then 0 else min timeline_strip (max 0 (frame.height - header - 1)) in
    (* the status strip spans the window below the tree and the timeline strip *)
    let status = min status_height (max 0 (frame.height - header - timeline - 1)) in
    let bottom = frame.height - status - timeline in
    let leaves = ref [] and splitters = ref [] and floats = ref [] in
    let leaf ?(floating = false) path panel ((fx, fy, fw, fh) as outer) =
      (* a window keeps its 1-point line-3 edge on all four sides: header and body lie inside it *)
      let x, y, w, h = if floating then fx + 1, fy + 1, max 1 (fw - 2), max 1 (fh - 2) else outer in
      (* a docked timeline is its strip alone *)
      let collapsed = (state path).Editor_core.Panels.collapsed in
      (* a header is a 24-point row under a 4-point margin; a docked collapsed pane is its row alone *)
      (* a docked timeline under 90 points is its strip alone; a taller one (timeline.html) has
         a header too *)
      let strip = panel = Timeline && not floating && h < 90 in
      let margin = if (strip || collapsed) && not floating then 0 else min header_margin (max 0 (h - 2)) in
      let hh = if strip then 0
        else min header_height (max 0 (if collapsed then h - margin else h - margin - 1)) in
      let body = if collapsed then 0 else max 1 (h - margin - hh) in
      (* a viewport window's picture stands 12 points in from the sheet, under a frame (windows.html) *)
      let inset = floating && (match panel with View _ -> true | _ -> false) && not collapsed && w > 40 && body > 40 in
      leaves := { path; panel; floating; frame = outer; header = (x, y + margin, w, hh);
                  body = (if inset then (x + 12, y + margin + hh, w - 24, body - 12) else (x, y + margin + hh, w, body)) } :: !leaves in
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
          leaf ~floating:true path panel (x, y, w, if (state path).collapsed then header_margin + header_height + 2 else min h (frame.height - y))) all;
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
  let text_y ui y h = Ui.text_top ui y h
  let cap_y ui y h = Ui.text_top ui ~size:(max 8 (Ui.font_size ui - 2)) y h
  let cap_size ui = max 8 (Ui.font_size ui - 2)

  (* the width of a label ({!Ui.Paint.cap}): upper case, 0.08 em of tracking after each letter *)
  let cap_width ui text =
    let count = ref 0 in
    String.iter (fun c -> if Char.code c land 0xC0 <> 0x80 then incr count) text;
    Ui.text_width ui ~size:(cap_size ui) (String.uppercase_ascii text)
    +. (0.08 *. float (cap_size ui) *. float !count)

  (* the width of a text button, the kit's [.btn]: a transparent 1-point edge, 6, the label, 6 and
     the key, 6, the edge *)
  let button_width ui ?hint ?(icon = false) label =
    14. +. Ui.text_width ui label +. (if icon then 13. else 0.)
    +. (match hint with Some hint -> 6. +. Ui.text_width ui ~size:(cap_size ui) hint | None -> 0.)

  (* A button is its text and, in ink-3, its key: a fill on hover and press, the control fill
     while [active]; [primary] is the one outlined button of a panel.  [icon] draws a play
     triangle or a stop square before the label. *)
  let button ui ~key ~at:(bx, by) ~w ?(h = 20.) ?(enabled = true) ?(active = false) ?(primary = false)
      ?(centered = false) ?hint ?icon label =
    let theme = Ui.theme ui in
    let box = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(bx, by) key in
    let signal = Ui.signal ui box in
    Ui.draw ui box (fun paint (x, y, w, h) ->
      Ui.paint_button_ground paint theme ~held:(enabled && signal.held)
        ~hovered:(enabled && signal.hovered) ~on:active ~primary (x, y, w, h);
      let color = if enabled then theme.foreground else Pxui.Theme.ink_3 theme in
      let tx = match icon with
        | None when centered -> x +. Float.floor ((w -. Ui.Paint.text_width paint label) /. 2.)
        | None -> x +. 7.
        | Some shape ->
            let cy = y +. (h /. 2.) in
            (match shape with
             | `Play ->
                 (* the sheet's 7 x 8 triangle: half-point scanlines, so a Retina pixel row is one *)
                 for row = 0 to 15 do
                   let top = cy -. 4. +. (0.5 *. float row) in
                   let reach = 1. -. (Float.abs (top +. 0.25 -. cy) /. 4.) in
                   Ui.Paint.fill paint ~x:(x +. 7.) ~y:top ~w:(7. *. reach) ~h:0.5 color
                 done
             | `Stop -> Ui.Paint.fill paint ~x:(x +. 7.) ~y:(cy -. 4.) ~w:8. ~h:8. color);
            x +. 20. in
      Ui.Paint.text paint ~at:(tx, text_y ui y h) ~color label;
      Option.iter (fun hint ->
        Ui.Paint.text paint ~size:(cap_size ui) ~color:(Pxui.Theme.ink_3 theme)
          ~at:(tx +. Ui.Paint.text_width paint label +. 6., cap_y ui y h) hint) hint);
    signal.clicked && enabled

  (* A colour: a 20-point swatch, then its hex field to the right edge of the control column;
     the hex text typed (or [hex] unchanged).  [key] names the pair; [at] is the control column. *)
  let colour ui ~key ~at:(x, y) ~w ~swatch ~hex =
    let box = Ui.box ui ~at:(x, y) ~w:(Ui.Px 20.) ~h:(Ui.Px 20.) ("swatch-" ^ key) in
    Ui.draw ui box (fun paint (sx, sy, sw, sh) ->
      (* a 20-point square with its border inside *)
      Ui.Paint.fill paint ~x:sx ~y:sy ~w:sw ~h:sh swatch;
      Ui.Paint.stroke paint ~x:(sx +. 0.5) ~y:(sy +. 0.5) ~w:(sw -. 1.) ~h:(sh -. 1.)
        (Pxui.Theme.edge (Ui.theme ui)));
    fst (Ui.value_field ui ~at:(x +. 28., y) ~w:(w -. 28.) ~h:20.
      ~left:true ~valid:(fun t -> Result.is_ok (Color.hex t)) ("hex-" ^ key) hex)

  (* A vector: three cells in the control column, 8 between, each with its axis letter in ink-3
     drawn on [box] (the row); [cell index ~x ~w] makes the cell's own field (x, w relative to
     [box]) and returns what it asks for.  [reserve] keeps room at the right for a row's toggle. *)
  let vector ui box ~at:(cx, cy) ~w ?(reserve = 0.) ?(axes = [ "x"; "y"; "z" ]) cell =
    let n = float (List.length axes) in
    let cell_w = (w -. reserve -. (8. *. (n -. 1.))) /. n in
    List.concat (List.mapi (fun index axis ->
      (* the cells' edges land on whole points, as the sheet's do *)
      let start = cx +. float index *. (cell_w +. 8.) in
      let fx = Float.round start and fw = Float.round (start +. cell_w) -. Float.round start in
      Ui.draw ui box (fun paint (x, y, _, _) ->
        Ui.Paint.text paint ~at:(x +. fx +. 2., cap_y ui (y +. cy -. 0.5) 20.)
          ~size:(cap_size ui) ~color:(Pxui.Theme.ink_3 (Ui.theme ui)) axis);
      cell index ~x:fx ~w:fw) axes)

  (* The kit's switch: 28 x 14, a line-3 edge, an 8-point knob that is ink-3 on the track at the left
     and the accent on white at the right.  True on a click. *)
  let switch ui ~key ~at:(sx, sy) on =
    let box = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px 28.) ~h:(Ui.Px 14.) ~at:(sx, sy) key in
    let signal = Ui.signal ui box in
    Ui.draw ui box (fun paint (x, y, w, h) ->
      let theme = Ui.theme ui in
      Ui.Paint.fill paint ~x ~y ~w ~h (if on then theme.input else theme.track);
      Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) (Pxui.Theme.border theme);
      Ui.Paint.fill paint ~x:(x +. (if on then 17. else 3.)) ~y:(y +. 3.) ~w:8. ~h:8.
        (if on then theme.accent else Pxui.Theme.ink_3 theme));
    signal.clicked

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
  (* a title's path is its parts joined by " / "; a bare slash ("fixed dt 1/60") is part of a word *)
  let split_crumbs sub =
    let n = String.length sub in
    let rec go from i acc =
      if i + 3 > n then List.rev (String.sub sub from (n - from) :: acc)
      else if String.sub sub i 3 = " / " then go (i + 3) (i + 3) (String.sub sub from (i - from) :: acc)
      else go from (i + 1) acc in
    List.map String.trim (go 0 0 [])
  let has_crumbs sub = List.length (split_crumbs sub) > 1
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
  (* The one layout of a header's right end: the groups of tabs standing there, outermost first and
     [widths] wide, end 8 points apart before the collapse button (a window's dock and close).  The
     right edge of each, and where the title must end.  The title gives way first (its
     breadcrumb, then its label and the focus square: tabs are how a pane is used, the title only
     names it); a group that would not fit in the header is left out, with those after it. *)
  let header_slots (l : leaf) widths =
    let x, _, w, _ = l.header in
    let left = float x +. 4. in
    let right = ref (float (x + w) -. (if l.floating then 64. else 36.)) and fits = ref true in
    let slots = List.map (fun width ->
      fits := !fits && !right -. width >= left;
      if !fits then (let at = !right in right := at -. width -. 8.; Some at) else None) widths in
    slots, !right

  let update ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) ?(title = fun (l : leaf) -> Editor_core.Panels.name l.panel) ?(groups = fun (_ : leaf) -> [])
      ?(key_of = fun _ -> "") ?focus tree ui (frame : Frame.t) =
    let module Ui = Pxui.Ui in
    let geometry = geometry ~state ~hidden tree frame in
    let theme = Ui.theme ui in
    (* the window being carried: its edge is the accent and four brackets stand round it *)
    let moving = ref None in
    let edge_color path = if !moving = Some path then theme.accent else Pxui.Theme.border theme in
    List.iteri (fun order l -> match l.panel with
      (* a view paints its own picture; a window over one still has its line-3 edge and the
         sheet fill of its title row's margin *)
      | View _ | Timeline when l.floating ->
          let box = floating ui l.frame ("workspace-window-edge" ^ key l.path) in
          Ui.to_front ui ~order box;
          Ui.draw_over ui box (fun paint (x, y, w, h) ->
            let line = edge_color l.path in
            let _, hy, _, _ = l.header and _, fy, _, _ = l.frame in
            Ui.Paint.fill paint ~x ~y ~w ~h:(float (hy - fy)) theme.input;
            (* a viewport window: the sheet's white round the picture and a line-2 frame on it *)
            (match l.panel with
             | View _ when (let _, _, bw, _ = l.body in bw > 0) ->
                 let bx, by, bw, bh = l.body in
                 let bx = float bx and by = float by and bw = float bw and bh = float bh in
                 Ui.Paint.fill paint ~x ~y:(float hy) ~w ~h:(by -. float hy) theme.input;
                 Ui.Paint.fill paint ~x ~y:by ~w:(bx -. x) ~h:(y +. h -. by) theme.input;
                 Ui.Paint.fill paint ~x:(bx +. bw) ~y:by ~w:(x +. w -. bx -. bw) ~h:(y +. h -. by) theme.input;
                 Ui.Paint.fill paint ~x:(bx) ~y:(by +. bh) ~w:bw ~h:(y +. h -. by -. bh) theme.input;
                 Ui.Paint.frame paint ~x:bx ~y:by ~w:bw ~h:bh (Pxui.Theme.edge theme)
             | _ -> ());
            Ui.Paint.fill paint ~x ~y ~w ~h:1. line;
            Ui.Paint.fill paint ~x ~y ~w:1. ~h line; Ui.Paint.fill paint ~x:(x +. w -. 1.) ~y ~w:1. ~h line;
            Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. line)
      | View _ | Timeline -> ()
      | p ->
          let box = floating ui l.frame ("workspace-" ^ String.lowercase_ascii (Editor_core.Panels.name p)
                                        ^ key l.path) in
          if l.floating then Ui.to_front ui ~order box;
          Ui.draw ui box (fun paint (x, y, w, h) ->
            (* a window is a sheet with one line-3 edge; a docked panel is the ground *)
            if l.floating then begin
              Ui.Paint.fill paint ~x ~y ~w ~h theme.input;
              Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) (edge_color l.path)
            end else Ui.Paint.fill paint ~x ~y ~w ~h theme.panel))
      geometry.leaves;
    let intents = ref [] in
    let emit i = intents := i :: !intents in
    (* where the drag tip goes: over the right of the window being moved *)
    let tip = ref None in
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
      let size = min h 20 in
      (* docked: the collapse chevron, a 20-point button 8 points from the edge.  A window: dock,
         then close. *)
      let windowed = (state l.path).window <> None && not (state l.path).collapsed in
      let button = floating ui ~flags:Ui.(clickable + tab_stop_marked)
          (x + max 0 (w - 8 - size), y + ((h - size) / 2), size, size) ("workspace-collapse-" ^ label) in
      if l.floating then Ui.to_front ui ~order button;
      if (Ui.signal ui button).clicked then emit (if windowed then Close_panel l.path else Toggle l.path);
      let tools = 8 + size + (if windowed then size + 8 else 0) in
      if windowed then begin
        let dock = floating ui ~flags:Ui.(clickable + tab_stop_marked)
            (x + max 0 (w - tools), y + ((h - size) / 2), size, size) ("workspace-dock-" ^ label) in
        Ui.to_front ui ~order dock;
        let signal = Ui.signal ui dock in
        if signal.clicked then emit (Window (l.path, None));
        Ui.draw ui dock (fun paint (x, y, w, h) ->
          if signal.hovered then Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.hover_fill theme);
          if Ui.focused ui dock then Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. theme.accent;
          (* the dock mark: a chevron-down in ink-2, as the sheet's window rows *)
          Ui.Paint.chevron paint ~at:(x +. (w /. 2.), y +. (h /. 2.)) `Down (Pxui.Theme.ink_2 theme))
      end;
      let grip = floating ui ~flags:Ui.(clickable + blocking)
          (x, y, max 0 (w - tools), h) ("workspace-drag-" ^ label) in
      if l.floating then Ui.to_front ui ~order grip;
      let drag = Ui.signal ui grip in
      (* a window is dragged from where it is drawn (the layout keeps it inside the frame, whatever
         its saved place says), with the size it has when it is not collapsed *)
      let original = match (state l.path).window with
        | Some (_, _, ww, wh) when l.floating -> let fx, fy, _, _ = l.frame in fx, fy, ww, wh
        | Some window -> window
        | None -> if l.floating then l.frame else (x, y, max 120 w, max 80 (let _, _, _, bh = l.body in h + bh)) in
      let ox, oy, ow, oh = drag_origin ui grip original drag in
      (* Escape puts the panel back where the drag began (a docked one stays docked) *)
      let cancelled = (Ui.state ui grip ~default:0 = 1 && not drag.pressed)
                      || (drag.held && Ui.key_pressed ui Rays.Input.Escape) in
      Ui.set_state ui grip (if cancelled && not drag.released then 1 else 0);
      if drag.held || drag.released then begin
        let px, py = if drag.released then drag.release_point else drag.pointer in
        let sx, sy = drag.press_point in
        if Float.hypot (px -. sx) (py -. sy) >= 4. then begin
          if cancelled then begin
            if (state l.path).window <> None then emit (Window_drag (l.path, (ox, oy, ow, oh), drag.released))
          end else begin
            emit (Dragging (l.path, drag.released));
            (* as far as the layout shows it ({!Layout.geometry}): a place past the edge would be
               saved and not drawn, and the next drag would start from where the window is not *)
            let wx = max 0 (min (frame.width - min frame.width ow) (ox + int_of_float (Float.round (px -. sx))))
            and wy = max 0 (min (frame.height - header_height) (oy + int_of_float (Float.round (py -. sy)))) in
            if not drag.released then (tip := Some (wx, wy, ow); moving := Some l.path);
            emit (Window_drag (l.path, (wx, wy, ow, oh), drag.released))
          end
        end
      end;
      let opened = Ui.state ui box ~default:0 = 1 in
      (* the whole empty header drags; a click that did not move opens the menu *)
      let still = Float.hypot (fst drag.release_point -. fst drag.press_point)
          (snd drag.release_point -. snd drag.press_point) < 4. in
      let opened = opened || Ui.context_clicked drag || (drag.clicked && still) in
      Ui.set_state ui box (if opened then 1 else 0);
      if opened then begin
        (* the sheet's [04]: the four actions with their leader keys, a rule, the panel kinds (a square
           before the one in use, the key that makes the panel one at the right); the keys are the
           host's own ([key_of] a command id), the kinds' one letter.  The size of the split is the
           gutter's right-click. *)
        let rows = [ "Split right", true; "Split down", true;
                     (if (state l.path).window = None then "Float" else "Dock"), true; "Close", true;
                     "", false ]
          @ List.map (fun (name, _) -> name, true) retypes in
        let last key = if key = "" then "" else String.sub key (String.length key - 1) 1 in
        let keys = [ key_of "panel.split-right"; key_of "panel.split-below"; key_of "panel.float";
                     key_of "panel.close"; "" ]
          @ List.map (fun (_, panel) -> last (key_of (match panel with
              | Graph -> "panel.graph" | List -> "panel.list" | Lisp -> "panel.lisp"
              | Inspector -> "panel.inspector" | Outline -> "panel.outline"
              | Timeline -> "panel.timeline" | View _ -> "panel.viewport"))) retypes in
        let current = let rec find i = function
          | [] -> 5
          | (_, panel) :: rest ->
              (* every viewport is the Viewport row, whatever its key *)
              if (match panel, l.panel with View _, View _ -> true | a, b -> a = b) then 5 + i
              else find (i + 1) rest in
          find 0 retypes in
        match Ui.context_menu ui ~at:(float x, float (y + h)) ~width:232. ~keys ~selected:current ~lead_from:5
            ("workspace-menu-" ^ label) rows with
        | `Open -> ()
        | `Dismiss -> Ui.set_state ui box 0
        | `Pick i -> Ui.set_state ui box 0;
            emit (match i with
              | 0 -> Split_panel (l.path, `H) | 1 -> Split_panel (l.path, `V)
              | 2 -> Window (l.path, if (state l.path).window <> None then None else
                    Some (let fx, fy, _, fh = l.frame in fx, fy, max 120 w, max 80 fh))
              | 3 -> Close_panel l.path
              | i -> Retype_panel (l.path, snd (List.nth retypes (i - 5))))
      end;
      l, title l, box, button, grip) headed in
    (* the tip of a panel being moved: a 20-point sheet with a line-2 edge, the label size in ink *)
    Option.iter (fun (wx, wy, ww) ->
      let words = "release to dock \xc2\xb7 esc keeps it floating" in
      let tw = Ui.text_width ui ~size:(Kit.cap_size ui) words in
      let w = tw +. 14. in
      let tx = Float.min (float (frame.width - 4) -. w) (float wx +. (0.625 *. float ww))
      and ty = Float.max 4. (float wy -. 30.) in
      let box = Ui.box ui ~w:(Ui.Px w) ~h:(Ui.Px 20.) ~at:(tx, ty) "workspace-drag-tip" in
      Ui.to_front ui ~order:max_int box;
      Ui.draw ui box (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h theme.input;
        Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) (Pxui.Theme.edge theme);
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~at:(x +. 7., Kit.cap_y ui y h) ~color:theme.foreground words)) !tip;
    Option.iter (fun path ->
      List.iter (fun (l : leaf) -> if l.path = path then begin
        let fx, fy, fw, fh = l.frame in
        let box = floating ui (fx - 8, fy - 8, fw + 16, fh + 16) "workspace-moving" in
        Ui.to_front ui ~order:(max_int - 1) box;
        (* the padding box of the window, brackets 4 points outside it *)
        Ui.draw ui box (fun paint _ ->
          Ui.Paint.brackets paint ~x:(float fx +. 1.) ~y:(float fy +. 1.) ~w:(float fw -. 2.) ~h:(float fh -. 2.) theme.accent)
      end) geometry.leaves) !moving;
    List.iter (fun ((l : leaf), text, box, button, _grip) ->
      let collapse_hovered = (Ui.signal ui button).hovered in
      (* the keyboard's mark is the sheet's: an accent line over the last row of the button *)
      if Ui.focused ui button then Ui.draw_over ui button (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. theme.accent);
      let panel_state = state l.path in
      let collapsed = panel_state.collapsed || List.mem l.panel hidden in
      let windowed = panel_state.window <> None && not panel_state.collapsed in
      let focused = focus = Some l.path in
      let text_box = Ui.within ui box (fun () -> Ui.box ui ~w:Ui.Grow ~h:Ui.Grow "header-text") in
      Ui.draw ui text_box (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h (if l.floating then theme.input else theme.panel);
        let ink_2 = Pxui.Theme.ink_2 theme and ink_3 = Pxui.Theme.ink_3 theme in
        (* "Title<TAB>a / b": the kind as a label, then the breadcrumb, its last part in ink *)
        let main, sub = match String.index_opt text '\t' with
          | Some i -> String.sub text 0 i, String.sub text (i + 1) (String.length text - i - 1)
          | None -> text, "" in
        if w >= 60. then begin
          let tx = ref (x +. 12.) in
          (* the accent square marks the focused pane, docked or floating *)
          (* the title ends before what follows it: the pane's tabs, then the window's tools; a
             square or a label with no room is left out whole, and the breadcrumb with it *)
          let limit = snd (header_slots l (groups l)) in
          if focused then begin
            if !tx +. 6. <= limit then
              Ui.Paint.fill paint ~x:!tx ~y:(y +. (h /. 2.) -. 3.) ~w:6. ~h:6. theme.accent;
            tx := !tx +. 12.
          end;
          let labelled = !tx +. Ui.Paint.cap_width paint main <= limit in
          let limit = if labelled then limit else !tx in
          if labelled then
            Ui.Paint.cap paint ~at:(!tx, Kit.cap_y ui y h) ~color:(if focused then theme.foreground else ink_2) main;
          tx := !tx +. Ui.Paint.cap_width paint main +. 8.;
          let ty = Kit.text_y ui y h in
          let cut ?size part = Ui.ellipsis ~width:(Ui.Paint.text_width paint ?size) ~limit:(Float.max 0. (limit -. !tx)) part in
          let put color part = let part = cut part in
            if part <> "" then Ui.Paint.text paint ~at:(!tx, ty) ~color part;
            tx := !tx +. Ui.Paint.text_width paint part +. 8. in
          let rec crumbs = function
            | [] -> ()
            | [ last ] -> put (if has_crumbs sub then theme.foreground else ink_2) last
            | part :: rest -> put ink_2 part; put ink_3 "/"; crumbs rest in
          (* a path too long for its room loses its head, not its subject: "… / sop" *)
          let rec fitted parts =
            let row = List.fold_left (fun w part -> w +. Ui.Paint.text_width paint part +. 8.)
                (float (List.length parts - 1) *. (Ui.Paint.text_width paint "/" +. 8.) -. 8.) parts in
            let over = row > limit -. !tx and dots = "\xe2\x80\xa6" in
            match parts with
            | [ head; last ] when over && head = dots -> [ last ]
            | head :: _ :: (_ :: _ as rest) when over && head = dots -> fitted (dots :: rest)
            | _ :: (_ :: _ as rest) when over -> fitted (dots :: rest)
            | parts -> parts in
          let crumbs parts = crumbs (fitted parts) in
          (* a window's title row: the path is one string in ink-2 at the label size *)
          if sub <> "" && l.floating && not collapsed then begin
            (* the subject follows the kind, 8 points on (windows.html's title row) *)
            let size = Kit.cap_size ui in
            Ui.Paint.text paint ~size ~at:(!tx, Kit.cap_y ui y h)
              ~color:(Rays.Color.with_alpha ink_2 179) (cut ~size sub)
          end
          else if sub <> "" && not collapsed then crumbs (split_crumbs sub);
          if collapsed then put ink_3 "collapsed"
        end;
        let cx = x +. w -. 18. and cy = y +. (h /. 2.) in
        if collapse_hovered then Ui.Paint.fill paint ~x:(cx -. 10.) ~y:(cy -. 10.)
          ~w:20. ~h:20. (Pxui.Theme.hover_fill theme);
        if windowed then begin
          (* the window's close mark is the label-size multiplication sign, centred in its button *)
          let size = Kit.cap_size ui in
          Ui.Paint.text paint ~size ~color:ink_2
            ~at:(cx -. (Ui.Paint.text_width paint ~size "\xc3\x97" /. 2.), Kit.cap_y ui y h) "\xc3\x97"
        end else Ui.Paint.chevron paint ~at:(cx, cy) (if collapsed then `Down else `Left)
                                     (if l.floating then ink_2 else theme.foreground))) headers;
    List.rev !intents

  (* where a header's tools begin: after its title, the 8-point gap, the 1 x 12 rule between
     two 4-point margins and the next 8-point gap (the title is laid out as [update] draws it) *)
  let tools_start ui ~focused ~floating ~collapsed text =
    let main, sub = match String.index_opt text '\t' with
      | Some i -> String.sub text 0 i, String.sub text (i + 1) (String.length text - i - 1)
      | None -> text, "" in
    let x = 12. +. (if focused then 12. else 0.) +. Kit.cap_width ui main in
    let x = if sub = "" then x
      else if floating then x +. 8. +. Pxui.Ui.text_width ui ~size:(Kit.cap_size ui) sub
      else List.fold_left (fun x part -> x +. 8. +. Pxui.Ui.text_width ui part) x
          (List.concat (List.mapi (fun i part -> if i = 0 then [ part ] else [ "/"; part ])
             (split_crumbs sub))) in
    let x = if collapsed then x +. 8. +. Pxui.Ui.text_width ui "collapsed" else x in
    x +. 25.

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
          let x, y, w, h = leaf.body in
          let ex = min 36 (w / 3) and ey = min 36 (h / 3) in
          (* the pane's own box sits under its four edges, so the pane under the pointer is known *)
          let pane = floating ui ~flags:Pxui.Ui.clickable (x, y, w, h) ("workspace-drop-pane-" ^ key leaf.path) in
          Pxui.Ui.to_front ui ~order:max_int pane;
          let pane_hovered = (Pxui.Ui.signal ui pane).hovered in
          let edges = List.map (fun (side, rect) ->
            let suffix = match side with `Left -> "left" | `Right -> "right" | `Top -> "top" | `Bottom -> "bottom" in
            let box = floating ui ~flags:Pxui.Ui.(clickable + blocking) rect
              ("workspace-drop-" ^ key leaf.path ^ suffix) in
            Pxui.Ui.to_front ui ~order:max_int box;
            side, suffix, box, (Pxui.Ui.signal ui box).hovered)
            [ `Left, (x, y + ey, ex, max 0 (h - 2 * ey));
              `Right, (x + w - ex, y + ey, ex, max 0 (h - 2 * ey));
              `Top, (x, y, w, ey); `Bottom, (x, y + h - ey, w, ey)] in
          (* only the pane under the pointer shows its four bars; the nearest turns accent and the
             half it would take is tinted *)
          let under = pane_hovered || List.exists (fun (_, _, _, hovered) -> hovered) edges in
          let theme = Pxui.Ui.theme ui in
          let fx = float x and fy = float y and fw = float w and fh = float h in
          List.filter_map (fun (side, suffix, box, hovered) ->
            if under then Pxui.Ui.draw ui box (fun paint _ ->
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
            if released && hovered then Some (Dock_panel (source, leaf.path, side)) else None) edges)
          geometry.leaves

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
          if signal.held then begin
            Ui.draw ui box (fun paint (x, y, w, h) ->
              Ui.Paint.fill paint ~x ~y ~w ~h (Ui.theme ui).accent);
            (* the ratio it makes, in a tip beside the gutter: "58 / 42" *)
            let first, second = sides s in
            let a = int_of_float (Float.round (100. *. float first /. float (max 1 (first + second)))) in
            let tw = Kit.cap_width ui (Printf.sprintf "%d / %d" a (100 - a)) in
            let px, py = signal.pointer in
            let tx, ty = if s.axis = `H then float (x + 8), py -. 10. else px +. 8., float (y + 8) in
            let tip = Ui.box ui ~w:(Ui.Px tw) ~h:(Ui.Px 20.) ~at:(tx, ty) "workspace-gutter-tip" in
            Ui.to_front ui ~order:max_int tip;
            Ui.draw ui tip (fun paint (x, y, _, h) ->
              Ui.Paint.ratio paint ~at:(x, Kit.cap_y ui y h) a (100 - a))
          end;
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
          let bounds = leaf.frame in
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
            (* an 8-point corner of two 1-point lines, 4 points in from the window's edges *)
            Ui.Paint.fill paint ~x:(x +. w -. 5.) ~y:(y +. h -. 12.) ~w:1. ~h:8. ink;
            Ui.Paint.fill paint ~x:(x +. w -. 12.) ~y:(y +. h -. 5.) ~w:8. ~h:1. ink)
      | Some _ -> ()) (geometry ~state ~hidden tree frame).leaves;
    List.rev !intents

end

module Which_key = struct
  open Editor_core.Keymap
  open Editor_core.Command

  let first_word label = List.hd (String.split_on_char ' ' label)

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
            else "+" ^ first_word command.label]
      | Some (Chord (key, modifiers)) when prefix = "" && command.scope = scope ->
          rows @ [Editor_core.Keymap.label (Chord (key, modifiers)), command.label]
      | _ -> rows) [] keymap

  (* The sheet's order of the leader's sections; a category it does not know follows them. *)
  let category_order = [ "Add"; "Panel"; "Layout"; "Go"; "Time"; "File" ]

  (* The leader's page by category: one-letter continuations only, no chords.  A key that
     continues into longer sequences is "+" and a name from [describe], else the first word of its
     first command. *)
  let by_category keymap ~prefix ~focus ~category ~describe ~order =
    let rows = List.fold_left (fun rows command -> match command.trigger with
      | Some (Leader sequence) when (command.scope = None || command.scope = Some focus)
          && String.length sequence > String.length prefix
          && String.starts_with ~prefix sequence ->
          let key = String.make 1 sequence.[String.length prefix] and title = category command in
          if List.exists (fun (t, k, _) -> t = title && k = key) rows then rows
          else rows @ [ title, key,
            if String.length sequence = String.length prefix + 1 then command.label
            else "+" ^ Option.value (describe (prefix ^ key)) ~default:(first_word command.label) ]
      | _ -> rows) [] keymap in
    let titles = List.fold_left (fun acc (t, _, _) -> if List.mem t acc then acc else acc @ [ t ]) [] rows in
    let ordered = List.filter (fun t -> List.mem t titles) category_order
      @ List.filter (fun t -> not (List.mem t category_order)) titles in
    (* the host's order of a section's keys; keys it does not name keep the keymap's order after them *)
    let rank title key =
      let rec find i = function [] -> max_int | k :: rest -> if k = key then i else find (i + 1) rest in
      find 0 (order title) in
    List.map (fun title -> title,
      List.stable_sort (fun (a, _) (b, _) -> compare (rank title a) (rank title b))
        (List.filter_map (fun (t, k, l) -> if t = title then Some (k, l) else None) rows)) ordered

  (* Sections of key rows, one to a column, painted by one box.  A section is a label in ink-3
     ([gap] points above it) over rows of 24: the key in ink-3 at the label size, 8 points on,
     what it does, and a chevron when the key continues into more keys.  [cols] columns share [w]. *)
  let columns ui paint (x, y, w) ~cols ~gap ~label_ink sections =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let row = float (Ui.row_height ui) in
    let col_w = w /. float (max 1 cols) in
    List.iteri (fun column (title, rows) ->
      let cx = x +. (float column *. col_w) in
      Ui.Paint.cap paint ~at:(cx +. 12., Kit.cap_y ui (y +. gap) row) ~color:(Pxui.Theme.ink_3 theme) title;
      List.iteri (fun k (key, label) ->
        let rx = cx and ry = y +. gap +. row +. (float k *. row) in
        let group = String.starts_with ~prefix:"+" label in
        let label = if group then String.sub label 1 (String.length label - 1) else label in
        let key_width = Ui.Paint.text_width paint ~size:(Kit.cap_size ui) key in
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~at:(rx +. 12., Kit.cap_y ui ry row)
          ~color:(Pxui.Theme.ink_3 theme) key;
        let lx = rx +. 12. +. key_width +. 8. in
        Ui.Paint.text paint ~at:(lx, Kit.text_y ui ry row) ~color:label_ink
          (Ui.ellipsis ~width:(Ui.Paint.text_width paint) ~limit:(rx +. col_w -. lx -. (if group then 20. else 12.)) label);
        (* a key that continues into more keys *)
        if group then Ui.Paint.chevron paint ~at:(rx +. col_w -. 17., ry +. (row /. 2.)) `Right
          (Pxui.Theme.ink_3 theme)) rows) sections

  let tallest sections = List.fold_left (fun most (_, rows) -> max most (List.length rows)) 0 sections

  (* The leader: a sheet over the status strip, the [Space] key and its name over six columns.  Hosts
     that give a [category] get the sections of the sheet (the keys of the leader only); without it the
     sections are the commands everywhere and those of the focused pane, with the key chords. *)
  let panel ui ?category ?(describe = fun _ -> None) ?(order = fun _ -> []) keymap ~prefix ~focus ~focus_name =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let sections = match category with
      | Some category -> by_category keymap ~prefix ~focus ~category ~describe ~order
      | None -> List.filter (fun (_, rows) -> rows <> [])
          [ "Global", page keymap ~prefix None; focus_name, page keymap ~prefix (Some focus) ] in
    let view_w, view_h = Ui.view_size ui in
    let row = float (Ui.row_height ui) in
    let cols = max 6 (List.length sections) in
    (* the edge, 8, the head row, a section label under 4, its rows, 8; never under the sheet's 183 *)
    let height = Float.max 183. (1. +. 8. +. row +. 4. +. row +. (float (tallest sections) *. row) +. 8.) in
    let y = Float.max 0. (view_h -. float Layout.status_height -. height) in
    let leader = if prefix = "" then "Space" else "Space " ^ prefix in
    (* build before the body it shields; the host closes it on any key *)
    ignore (Ui.popup ui ~dismiss_initial:false ~at:(0., y) ~width:view_w ~height "leader" (fun () ->
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px height) "leader-sheet" in
      Ui.draw ui box (fun paint (x, y, w, _) ->
        Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.border theme);
        let y = y +. 9. in
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~at:(x +. 12., Kit.cap_y ui y row)
          ~color:(Pxui.Theme.ink_3 theme) leader;
        Ui.Paint.cap paint ~at:(x +. 20. +. Ui.Paint.text_width paint ~size:(Kit.cap_size ui) leader, Kit.cap_y ui y row)
          "Leader";
        let hint = "a key continues \xc2\xb7 esc closes" in
        Ui.Paint.text paint ~size:(Kit.cap_size ui) ~color:(Pxui.Theme.ink_2 theme)
          ~at:(x +. w -. 12. -. Ui.Paint.text_width paint ~size:(Kit.cap_size ui) hint, Kit.cap_y ui y row) hint;
        columns ui paint (x +. 16., y +. row, w -. 32.) ~cols ~gap:4.
          ~label_ink:theme.foreground sections)))

  (* The key sheet: a title row ([Keys], what has the focus, a close button), the filter, and the
     commands in three columns, one section each. *)
  (* The key sheet's sections: every command a key reaches, once per id with all its keys (the
     Ctrl twins of the Command chords left out), under the section [category] gives it, the
     leader sheet's sections first. *)
  let sheet_sections ?(category = fun _ -> "Keys") keymap =
    let commands = List.fold_left (fun seen command ->
      if command.trigger = None || List.exists (fun previous -> previous.id = command.id) seen then seen
      else command :: seen) [] keymap |> List.rev in
    let titles = List.fold_left (fun acc command ->
      let title = category command in if List.mem title acc then acc else acc @ [ title ]) [] commands in
    List.map (fun title -> title, List.filter_map (fun command ->
      if category command <> title then None else
      let keys = List.filter_map (fun alias -> if alias.id <> command.id then None
        else match alias.trigger with
          | Some (Chord (_, modifiers)) when List.mem Input.Ctrl modifiers -> None
          | Some trigger -> Some (Editor_core.Keymap.label trigger) | None -> None) keymap
        |> List.sort_uniq String.compare |> String.concat " / " in
      Some (keys, command.label)) commands)
      (List.filter (fun t -> List.mem t titles) category_order
       @ List.filter (fun t -> not (List.mem t category_order)) titles)

  let sheet ui ?(context = "") ?category keymap =
    let module Ui = Pxui.Ui in
    let sections = sheet_sections ?category keymap in
    match Ui.modal ui ~width:572. "guide-keys" (fun () ->
      let theme = Ui.theme ui in
      let closed = ref false in
      (* the title row: 4 above, then 24: the label, what has the focus (ink-2 at 70 percent, as
         written) 8 before the close button, which ends 8 from the edge *)
      let title = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px 28.) "keys-title" in
      Ui.draw ui title (fun paint (x, y, w, _) ->
        Ui.Paint.cap paint ~at:(x +. 12., Kit.cap_y ui (y +. 4.) 24.) ~color:(Pxui.Theme.ink_2 theme) "Keys";
        if context <> "" then
          Ui.Paint.text paint ~size:(Kit.cap_size ui)
            ~color:(Rays.Color.with_alpha (Pxui.Theme.ink_2 theme) 179)
            ~at:(x +. w -. 36. -. Ui.Paint.text_width paint ~size:(Kit.cap_size ui) context,
                 Kit.cap_y ui (y +. 4.) 24.) context);
      Ui.within ui title (fun () ->
        let holder = Ui.box ui ~w:(Ui.Px 40.) ~h:(Ui.Px 24.) ~at:(530., 4.) "keys-close-holder" in
        Ui.within ui holder (fun () ->
          if Ui.button ui ~icon:true ~bare:true ~at_end:true ~ink:(Pxui.Theme.ink_2 theme) "\xc3\x97###guide-close"
          then closed := true));
      (* the filter: what is typed narrows the rows to the commands and keys that match; the
         query lives with its box, Escape closes the sheet *)
      let memory = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px 0.) "keys-filter-memory" in
      let query, pick = Ui.picker ui ~at_rest:true "filter commands"
          ~query:(Option.value ~default:"" (Ui.text_state ui memory)) (fun _ -> [||]) in
      Ui.set_text_state ui memory (Some query);
      let sections = if query = "" then sections else List.filter_map (fun (title, rows) ->
        match List.filter (fun (keys, label) -> Ui.fuzzy_match ~query label || Ui.fuzzy_match ~query keys) rows with
        | [] -> None | rows -> Some (title, rows)) sections in
      (* three columns: each section goes under the shortest column so far *)
      let rows_of (_, rows) = 1 + List.length rows in
      let stacks = List.fold_left (fun stacks section ->
        let height stack = List.fold_left (fun n s -> n + rows_of s) 0 stack in
        let shortest = List.fold_left (fun best i ->
          if height (List.nth stacks i) < height (List.nth stacks best) then i else best) 0 [ 1; 2 ] in
        List.mapi (fun i stack -> if i = shortest then stack @ [ section ] else stack) stacks)
        [ []; []; [] ] sections in
      let tallest = List.fold_left (fun most stack ->
        max most (List.fold_left (fun n s -> n + rows_of s) 0 stack)) 0 stacks in
      let row = float (Ui.row_height ui) in
      let box = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float tallest *. row +. 8.)) "keys-sheet" in
      Ui.draw ui box (fun paint (x, y, w, _) ->
        List.iteri (fun column stack ->
          ignore (List.fold_left (fun top section ->
            columns ui paint (x +. (float column *. w /. 3.), top, w /. 3.) ~cols:1 ~gap:0.
              ~label_ink:(Pxui.Theme.ink_2 theme) [ section ];
            top +. (float (rows_of section) *. row)) y stack)) stacks);
      pick <> `Cancel && not !closed) with
    | Some open_ -> open_ | None -> false
end

module Status_bar = struct
  type state = [ `Ok | `Busy | `Error ]

  (* What every strip starts with: the file, a dot for the state (checked, cooking, refused) and
     the status line in ink-2, cut to [limit]; where the next thing goes. *)
  (* where the lead's parts go: the file, the dot, the status cut to [limit], and the end *)
  let lead_plan ui ~x ~file ~limit text =
    let module Ui = Pxui.Ui in
    let tx = x +. 12. in
    let file_x = tx in
    let tx = if file <> "" then tx +. Ui.text_width ui file +. 8. else tx in
    let dot_x = tx in
    let tx = tx +. 14. in
    let shown = Ui.ellipsis ~width:(Ui.text_width ui) ~limit:(Float.max 0. (limit -. tx)) text in
    file_x, dot_x, tx, shown, tx +. Ui.text_width ui shown +. 8.

  let lead ui paint (x, y, h) ~file ~state ~limit text =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let ty = Kit.text_y ui y h in
    let file_x, dot_x, text_x, shown, after = lead_plan ui ~x ~file ~limit text in
    if file <> "" then Ui.Paint.text paint ~at:(file_x, ty) ~color:theme.foreground file;
    Ui.Paint.circle paint ~at:(dot_x +. 3., y +. (h /. 2.)) ~radius:3.
      ~fill:(match state with `Ok -> (Pxui.Theme.ports theme).int | `Busy -> theme.accent | `Error -> Pxui.Theme.invalid) ();
    Ui.Paint.text paint ~at:(text_x, ty)
      ~color:(if state = `Error then Pxui.Theme.invalid else Pxui.Theme.ink_2 theme) shown;
    after

  (* where the end's parts start (the layout, then the frame rate), 12 from the edge, 8 apart *)
  let trail_start ui ~x ~w ?(notes = []) ?(readout = "") ~layout ~fps () =
    let right = x +. w -. 12. in
    let right = match fps with
      | Some fps -> right -. Kit.cap_width ui (Printf.sprintf "%d fps" fps) -. 8. | None -> right in
    let right = if layout <> "" then right -. Kit.cap_width ui layout -. 8. else right in
    let right = List.fold_left (fun right note -> right -. Kit.cap_width ui note -. 8.) right (List.rev notes) in
    if readout = "" then right else right -. Pxui.Ui.text_width ui readout -. 8.

  (* the strip's end: the layout in use, then the frame rate in ink, 8 apart; where they start *)
  let trail ui paint (x, y, w, h) ?(notes = []) ?(readout = "") ~layout ~fps () =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let right = ref (x +. w -. 12.) in
    Option.iter (fun fps ->
      let fps = Printf.sprintf "%d fps" fps in
      right := !right -. Ui.Paint.cap_width paint fps;
      Ui.Paint.cap paint ~color:theme.foreground ~at:(!right, Kit.cap_y ui y h) fps;
      right := !right -. 8.) fps;
    if layout <> "" then begin
      right := !right -. Ui.Paint.cap_width paint layout;
      Ui.Paint.cap paint ~at:(!right, Kit.cap_y ui y h) layout;
      right := !right -. 8.
    end;
    (* notes ("3 floating", "3 graphs") stand left of the layout *)
    List.iter (fun note ->
      right := !right -. Ui.Paint.cap_width paint note;
      Ui.Paint.cap paint ~at:(!right, Kit.cap_y ui y h) note;
      right := !right -. 8.) (List.rev notes);
    (* a graph alone in the strip: its counts in ink-2 before the zoom *)
    if readout <> "" then begin
      right := !right -. Ui.Paint.text_width paint readout;
      Ui.Paint.text paint ~at:(!right, Kit.text_y ui y h) ~color:(Pxui.Theme.ink_2 theme) readout;
      right := !right -. 8.
    end;
    !right

  (* the hairline above the bar; the bar is the 24 points under it *)
  let ground ui paint (x, y, w, h) =
    let theme = Pxui.Ui.theme ui in
    Pxui.Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
    Pxui.Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.edge theme);
    x, y +. 1., w, h -. 1.

  (* the rule, then the focused pane's kind (ink) and what is selected (ink-2), both labels;
     where the next thing goes *)
  let focus_labels ui paint (_, y, h) ?(rule = true) ?(accent = false) ~after ?kind ?selection () =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let tx = ref (after +. 17.) in
    if rule then
      Ui.Paint.fill paint ~x:(after +. 4.) ~y:(y +. ((h -. 12.) /. 2.)) ~w:1. ~h:12. (Pxui.Theme.border theme);
    List.iter (fun (text, color) ->
      Ui.Paint.cap paint ~at:(!tx, Kit.cap_y ui y h) ~color text;
      tx := !tx +. Ui.Paint.cap_width paint text +. 8.)
      (List.filter_map Fun.id
         [ Option.map (fun k -> k, if accent then theme.accent else theme.foreground) kind;
           Option.map (fun s -> s, Pxui.Theme.ink_2 theme) selection ]);
    !tx

  (* where the labels of [focus_labels] end, without painting *)
  let focus_end ui ~after ?kind ?selection () =
    List.fold_left (fun tx text -> tx +. Kit.cap_width ui text +. 8.)
      (after +. 17.) (List.filter_map Fun.id [ kind; selection ])

  let draw ui ~bounds:(x, y, width, height) ?(file = "") ?(state = `Ok) ?(layout = "") ?(notes = []) ?(readout = "")
      ?(accent = false) ?kind ?selection ~text ~fps () =
    if height > 0 then begin
      let module Ui = Pxui.Ui in
      let box = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px (float_of_int width))
          ~h:(Ui.Px (float_of_int height))
          ~at:(float_of_int x, float_of_int y) "workspace-status" in
      Ui.draw ui box (fun paint bounds ->
        let x, y, w, h = ground ui paint bounds in
        let right = trail ui paint (x, y, w, h) ~notes ~readout ~layout ~fps () in
        let limit = if kind = None && selection = None then right else right -. 160. in
        let after = lead ui paint (x, y, h) ~file ~state ~limit text in
        if kind <> None || selection <> None then
          ignore (focus_labels ui paint (x, y, h) ~accent ~after ?kind ?selection ()))
    end

  let guide ui ~bounds:(x, y, width, height) ?(file = "") ?(state = `Ok) ?(layout = "") ?(text = "") ?fps
      ?(notes = []) ?(readout = "") ?(accent = false) ?(extra = []) ?leader ?kind ?selection ~context commands =
    let module Ui = Pxui.Ui in
    if height <= 0 then false else
    match leader with
    | Some pending ->
        (* an open leader: the file and its state, a rule, the pending prefix in the accent and
           [waiting for a key], the frame rate at the end *)
        let box = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px (float width)) ~h:(Ui.Px (float height))
            ~at:(float x, float y) "workspace-guide" in
        Ui.draw ui box (fun paint bounds ->
          let x, y, w, h = ground ui paint bounds in
          let theme = Ui.theme ui in
          let right = trail ui paint (x, y, w, h) ~notes ~readout ~layout ~fps () in
          let after = lead ui paint (x, y, h) ~file ~state ~limit:(x +. Float.min 320. (w /. 4.)) text in
          ignore right;
          let tx = focus_labels ui paint (x, y, h) ~accent:true ~after ~kind:pending () in
          Ui.Paint.text paint ~at:(tx, Kit.text_y ui y h) ~color:(Pxui.Theme.ink_2 theme) "waiting for a key");
        false
    | None ->
    let bar = Ui.box ui ~flags:Ui.(clickable + clip)
        ~w:(Ui.Px (float width)) ~h:(Ui.Px (float height))
        ~at:(float x, float y) "workspace-guide" in
    let keys = List.filter_map (fun (command : _ Editor_core.Command.t) ->
        Option.map (fun trigger -> Editor_core.Keymap.label trigger, command.label) command.trigger) commands
      @ extra in
    let title = Editor_core.Guide_context.name context in
    (* the kind and what is selected; a context that is no node's (the leader, a search) names itself *)
    let kind = Some (Option.value kind ~default:title) in
    let selection = match context with
      | Editor_core.Guide_context.Canvas | Node | Multi | List | Text -> selection
      | _ -> Some title in
    let theme = Ui.theme ui in
    (* the strip is laid out before it is painted, so the "toggle guide" pair, where a click hides
       the strip, is known to the box built for it *)
    let fx = float x and fw = float width in
    let limit = trail_start ui ~x:fx ~w:fw ~notes ~readout ~layout ~fps () in
    let has_lead = not (file = "" && text = "") in
    let after_lead = if has_lead then (let _, _, _, _, after = lead_plan ui ~x:fx ~file ~limit:(fx +. Float.min 320. (fw /. 4.)) text in after)
      else fx -. 5. in
    let labels_end = focus_end ui ~after:after_lead ?kind ?selection () in
    let small = Kit.cap_size ui in
    let pairs = fst (List.fold_left (fun (acc, tx) (key, label) ->
      let kw = Ui.text_width ui ~size:small key and lw = Ui.text_width ui label in
      if tx +. kw +. 8. +. lw > limit -. 8. then acc, infinity
      else (tx, key, label, kw, lw) :: acc, tx +. kw +. 8. +. lw +. 8.) ([], labels_end) keys) |> List.rev in
    let hide_rect = List.find_map (fun (tx, _, label, kw, lw) ->
      if label = "toggle guide" then Some (tx, kw +. 8. +. lw) else None) pairs in
    Ui.draw ui bar (fun paint bounds ->
      let x, y, w, h = ground ui paint bounds in
      let limit = trail ui paint (x, y, w, h) ~notes ~readout ~layout ~fps () in
      ignore limit;
      (* the file and its state take at most a quarter of the strip, then the labels *)
      if has_lead then begin
        let after = lead ui paint (x, y, h) ~file ~state ~limit:(x +. Float.min 320. (w /. 4.)) text in
        ignore (focus_labels ui paint (x, y, h) ~accent ~after ?kind ?selection ())
      end else ignore (focus_labels ui paint (x, y, h) ~rule:false ~accent ~after:(x -. 5.) ?kind ?selection ());
      (* each key in ink-3 at the label size before what it does in ink-2, 8 apart *)
      List.iter (fun (tx, key, label, kw, _) ->
        Ui.Paint.text paint ~size:small ~at:(tx, Kit.cap_y ui y h) ~color:(Pxui.Theme.ink_3 theme) key;
        Ui.Paint.text paint ~at:(tx +. kw +. 8., Kit.text_y ui y h) ~color:(Pxui.Theme.ink_2 theme) label) pairs);
    let hide = Ui.within ui bar (fun () ->
      let hx, hw = Option.value hide_rect ~default:(0., 0.) in
      Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px hw) ~h:(Ui.Px (float height))
        ~at:(hx -. fx, 0.) "guide-hide") in
    let hide_hovered = (Ui.signal ui hide).hovered in
    if hide_hovered && hide_rect <> None then Ui.draw ui hide (fun paint (x, y, w, h) ->
      Ui.Paint.fill paint ~x ~y:(y +. 1.) ~w ~h:(h -. 1.) (Pxui.Theme.faint_border theme));
    if (Ui.signal ui bar).hovered then
      Ui.tooltip ui ~key:"guide-strip" ~text:(title ^ " \xc2\xb7 "
        ^ String.concat "  " (List.map fst keys) ^ " \xc2\xb7 Space ?: all keys");
    hide_rect <> None && (Ui.signal ui hide).clicked

  (* Echo, the sheet's [08]: tips stacked 4 apart in the pane's bottom-left corner, the last at the
     bottom.  A tip is 24 high on the sheet fill with a line-2 edge and 13-point text 7 in; information
     starts with a 6-point dot in the hint colour, a refusal reads in the error ink. *)
  let tips ui ~bounds:(x, y, width, height) ?(avoid = []) tips =
    let module Ui = Pxui.Ui in
    if width > 0 && height > 0 && tips <> [] then begin
      let theme = Ui.theme ui in
      let count = List.length tips in
      List.iteri (fun index (text, kind) ->
        let w = Float.min (float (max 0 (width - 24)))
            (Ui.text_width ui text +. (match kind with `Info -> 32. | `Refusal -> 14.)) in
        let top = float (y + max 0 (height - 12)) -. (float (count - index) *. 28.) +. 4. in
        (* a tip that would sit on a rectangle of [avoid] (a graph card) moves up above it *)
        let left = float (x + 12) in
        let top = List.fold_left (fun top (ax, ay, aw, ah) ->
          if left < ax +. aw && ax < left +. w && top < ay +. ah && ay < top +. 24.
          then ay -. 28. else top) top
          (List.sort (fun (_, a, _, _) (_, b, _, _) -> compare b a) avoid) in
        let box = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px w) ~h:(Ui.Px 24.) ~at:(float (x + 12), top)
            (Printf.sprintf "echo-tip-%d" index) in
        Ui.draw ui box (fun paint (x, y, w, h) ->
          Ui.Paint.fill paint ~x ~y ~w ~h theme.input;
          Ui.Paint.frame paint ~x ~y ~w ~h (Pxui.Theme.edge theme);
          match kind with
          | `Info ->
              Ui.Paint.circle paint ~at:(x +. 10., y +. (h /. 2.)) ~radius:3.
                ~fill:(Pxui.Theme.ports theme).hint ();
              Ui.Paint.text paint ~at:(x +. 19., Kit.text_y ui y h) ~color:theme.foreground text
          | `Refusal ->
              Ui.Paint.text paint ~at:(x +. 7., Kit.text_y ui y h) ~color:Pxui.Theme.invalid text)) tips
    end
end

module Timeline_bar = struct
  type intent = Pause_toggle | Stop_playback | Reset_playback
    | Seek_playback of int64 | Set_end of int

  (* The strip of the workspace sheet is one 24-point bar: Play, Stop, F, the frame field, the time and
     the ruler to the edge.  A taller panel (timeline.html) has the bar, Reset, the rule, Frame, Time and End,
     a hairline and the ruler under it.  [edge] draws the line-2 hairline above a strip that has
     no gutter over it. *)
  let draw ui ~bounds:(x, y, width, height) ?(edge = false) ~playing ~frame ~time ~max_frame () =
    let module Ui = Pxui.Ui in
    let theme = Ui.theme ui in
    let fx = float x and fy = float y and fw = float width and fh = float height in
    let bar = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px fw) ~h:(Ui.Px fh) ~at:(fx, fy) "workspace-timeline" in
    let top = if edge then 1. else 0. in
    Ui.draw ui bar (fun paint (x, y, w, h) ->
      Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
      if edge then Ui.Paint.fill paint ~x ~y ~w ~h:1. (Pxui.Theme.edge theme));
    let tall = fh -. top >= 56. in
    let bar_h = if tall then 24. else fh -. top in
    Ui.within ui bar (fun () ->
      let cy = top +. ((bar_h -. 20.) /. 2.) in
      let cx = ref 12. in
      let button key ?icon ?hint ?active ?enabled label =
        let w = Kit.button_width ui ~icon:(icon <> None) ?hint label in
        let clicked = Kit.button ui ~key ~at:(!cx, cy) ~w ?icon ?hint ?active ?enabled label in
        cx := !cx +. w +. 8.; clicked in
      let pause = button "timeline-play" ~icon:`Play ~active:playing
          ?hint:(if tall then Some "Space p" else None) "Play" in
      let stop = button "timeline-stop" ~icon:`Stop "Stop" in
      let reset = tall && button "timeline-reset" "Reset" in
      (* the rule between the buttons and the fields: 4 points of margin each side *)
      let rule_x = !cx +. 4. in
      if tall then cx := !cx +. 4. +. 1. +. 4. +. 8.;
      let label text =
        let at = !cx in
        cx := !cx +. Kit.cap_width ui text +. 8.; at in
      let frame_label = label (if tall then "Frame" else "F") in
      let field_w = if tall then 64. else 48. in
      let field_x = !cx in
      let current = Int64.to_string frame in
      let typed = fst (Ui.value_field ui ~at:(field_x, cy) ~w:field_w ~h:20.
          ~valid:(fun text -> Int64.of_string_opt (String.trim text) <> None)
          "timeline-frame-field" current) in
      cx := !cx +. field_w +. 8.;
      let time_label = if tall then label "Time" else !cx in
      let readout = Printf.sprintf "%.2f s" time in
      let readout_x = !cx in
      cx := !cx +. Ui.text_width ui readout +. 8.;
      (* the last frame, typed, at the end of a tall panel's bar *)
      let last = string_of_int max_frame in
      let end_x = fw -. 12. -. 64. in
      let ended = if not tall then last else
        fst (Ui.value_field ui ~at:(end_x, cy) ~w:64. ~h:20.
          ~valid:(fun text -> match int_of_string_opt (String.trim text) with Some n -> n >= 1 | None -> false)
          "timeline-end-field" last) in
      let ruler_x = if tall then 0. else !cx in
      let ruler_y = if tall then top +. bar_h +. 1. else top in
      let ruler_w = Float.max 0. (fw -. ruler_x) and ruler_h = fh -. ruler_y in
      (* the ruler's own line-2 edge is its first column; the ticks divide what is inside it *)
      let inner_x = if tall then 0. else 1. in
      let span = Float.max 1. (ruler_w -. inner_x) in
      let range = Float.max (Int64.to_float frame) (float_of_int max_frame) in
      let ruler = Ui.box ui ~flags:Ui.(clickable + blocking) ~at:(ruler_x, ruler_y)
          ~w:(Ui.Px ruler_w) ~h:(Ui.Px ruler_h) "timeline-scrub" in
      let signal = Ui.signal ui ruler in
      let scrub = if (signal.held || signal.released) && ruler_w > 1. then begin
          let px = fst (if signal.released then signal.release_point else signal.pointer) in
          let rx, _, _, _ = Ui.rect ui ruler in
          Some (Float.round (Float.max 0. (Float.min 1. ((px -. rx -. inner_x) /. span)) *. range))
        end else None in
      Ui.draw ui bar (fun paint (x, y, w, _) ->
        let y = y +. top in
        let h = bar_h in
        Ui.Paint.cap paint ~at:(x +. frame_label, Kit.cap_y ui y h) (if tall then "Frame" else "F");
        if tall then begin
          Ui.Paint.cap paint ~at:(x +. time_label, Kit.cap_y ui y h) "Time";
          Ui.Paint.cap paint ~at:(x +. end_x -. 8. -. Kit.cap_width ui "End", Kit.cap_y ui y h) "End";
          Ui.Paint.fill paint ~x:(x +. rule_x) ~y:(y +. ((h -. 12.) /. 2.)) ~w:1. ~h:12. (Pxui.Theme.border theme);
          Ui.Paint.fill paint ~x ~y:(y +. bar_h) ~w ~h:1. (Pxui.Theme.edge theme)
        end;
        Ui.Paint.text paint ~at:(x +. readout_x, Kit.text_y ui y h)
          ~color:(if tall then theme.foreground else Pxui.Theme.ink_2 theme) readout);
      Ui.draw ui ruler (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h theme.input;
        if not tall then Ui.Paint.fill paint ~x ~y ~w:1. ~h (Pxui.Theme.edge theme);
        let left = x +. inner_x in
        let at fraction = left +. Float.floor (fraction *. span) in
        let head = at (Int64.to_float frame /. Float.max 1. range) in
        Ui.Paint.fill paint ~x:left ~y ~w:(head -. left) ~h (Pxui.Theme.tint theme);
        (* a strip has fifty minor ticks and a major one in five; a taller ruler a tick a hundredth
           and a major one in ten, numbered *)
        let minors = if tall then 100 else 50 and every = if tall then 10 else 5 in
        let minor_h = if tall then 6. else 5. and major_h = if tall then 14. else 10. in
        for tick = 0 to minors - 1 do
          let tx = at (float tick /. float minors) in
          if tick mod every = 0 then begin
            Ui.Paint.fill paint ~x:tx ~y:(y +. h -. major_h) ~w:1. ~h:major_h (Pxui.Theme.border theme);
            if tall then
              Ui.Paint.text paint ~size:(Kit.cap_size ui) ~color:(Pxui.Theme.ink_3 theme)
                ~at:(tx +. 4., Kit.cap_y ui (y +. 16.) 24.)
                (string_of_int (int_of_float (Float.round (range *. float tick /. float minors))))
          end else Ui.Paint.fill paint ~x:tx ~y:(y +. h -. minor_h) ~w:1. ~h:minor_h (Pxui.Theme.edge theme)
        done;
        (* the 2-point accent playhead, and the frame as an accent label right of it *)
        let head = if tall then head -. 1. else head in
        Ui.Paint.fill paint ~x:head ~y ~w:2. ~h theme.accent;
        let tag_h = if tall then 24. else 14. in
        Ui.Paint.cap paint ~color:theme.accent ~at:(head +. 2., Kit.cap_y ui y tag_h) (Int64.to_string frame));
      List.filter_map Fun.id [
        (* a typed frame clamps to the timeline: 0 to the last frame *)
        (if typed <> current then Option.map (fun n ->
           Seek_playback (Int64.max 0L (Int64.min (Int64.of_int max_frame) n)))
           (Int64.of_string_opt (String.trim typed)) else None);
        (if ended <> last then Option.map (fun n -> Set_end n) (int_of_string_opt (String.trim ended)) else None);
        (if pause then Some Pause_toggle else None);
        (if stop then Some Stop_playback else None);
        (if reset then Some Reset_playback else None);
        (match scrub with
         | Some target when target <> Int64.to_float frame -> Some (Seek_playback (Int64.of_float target))
         | _ -> None)])
end

module Prompt = struct
  module Ui = Pxui.Ui

  (* The sheet's button row: 20 points, [Cancel esc] and the primary [accept] with its key, right-aligned
     8 from the edge of a window [width] wide (its 1-point edges inside), 4 apart, and 8 under it.  A click
     is the same as the key. *)
  let buttons ui ~key ~width ~accept =
    let row = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px 28.) (key ^ "-buttons") in
    Ui.within ui row (fun () ->
      let primary_w = Kit.button_width ui ~hint:"\xe2\x86\xb5" accept
      and cancel_w = Kit.button_width ui ~hint:"esc" "Cancel" in
      let primary_x = width -. 2. -. 8. -. primary_w in
      let cancel = Kit.button ui ~key:(key ^ "-cancel") ~at:(primary_x -. 4. -. cancel_w, 0.) ~w:cancel_w
          ~hint:"esc" "Cancel" in
      let submit = Kit.button ui ~key:(key ^ "-accept") ~at:(primary_x, 0.) ~w:primary_w ~primary:true
          ~hint:"\xe2\x86\xb5" accept in
      if cancel then `Cancel else if submit then `Submit else `None)

  let spacer ui key height = ignore (Ui.box ui ~w:Ui.Grow ~h:(Ui.Px height) key)

  (* A name prompt, the sheet's [06]: the title, what is asked in ink-2, the field and the buttons *)
  let name ui ~key ~title ~description ~label ~query =
    Ui.modal ui ~width:320. key (fun () ->
      Ui.label ui title;
      spacer ui "prompt-above" 8.;
      let line = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px 24.) "prompt-description" in
      Ui.draw ui line (fun paint (x, y, w, h) ->
        Ui.Paint.text paint ~at:(x +. 8., Kit.text_y ui y h) ~color:(Pxui.Theme.ink_2 (Ui.theme ui))
          (Ui.ellipsis ~width:(Ui.Paint.text_width paint) ~limit:(w -. 16.) description));
      let query, result = Ui.col ui ~padding:4. "prompt-field" (fun () ->
        Ui.picker ui ~slash:false label ~query (fun _ -> [||])) in
      let clicked = buttons ui ~key ~width:320. ~accept:"Save" in
      query, (match clicked with `None -> result | (`Cancel | `Submit) as pick -> pick))

  (* A searchable prompt, the sheet's [01] window: the field, the rows in the picker's style (labels
     cut with an ellipsis), then the hairline and the hint bar with [N of M]; no buttons *)
  let search ui ~key ~title ~label ~query ~rows =
    Ui.modal ui ~width:320. key (fun () ->
      Ui.label ui title;
      let query, result = Ui.picker ui label ~query rows in
      Ui.footer ui ~right:(Printf.sprintf "%d of %d" (Array.length (rows query)) (Array.length (rows "")))
        [ "\xe2\x86\x91\xe2\x86\x93", "move"; "\xe2\x86\xb5", "pick" ];
      query, result)

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
    let ancestors k =
      let chain = ref [] and depth = ref (at k).depth in
      for candidate = k - 1 downto 0 do
        if (at candidate).depth < !depth then begin
          chain := candidate :: !chain; depth := (at candidate).depth end
      done;
      !chain in
    (* the ancestors of the first row in view stay at the top while the list is scrolled *)
    let sticky_of scroll = if count = 0 || scroll <= 0. then []
      else List.filteri (fun index _ -> index < 3)
          (ancestors (max 0 (min (count - 1) (int_of_float (Float.floor (scroll /. height)))))) in
    let row_at (_, py) =
      (* a sticky row is the row under the pointer, not the one scrolled beneath it *)
      let slot = int_of_float (Float.floor ((py -. top) /. height)) in
      match if py < top then None else List.nth_opt (sticky_of scroll) slot with
      | Some k -> Some k
      | None ->
          let k = int_of_float (Float.floor ((py -. top +. scroll) /. height)) in
          if py < top || k < 0 || k >= count then None else Some k in
    (* the last flag ends 12 from the edge, a flag column is a 12-point flag and an 8-point gap *)
    let columns_x = x +. w -. 24. -. flag_width *. float_of_int (max 0 (List.length columns - 1)) in
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
      let sticky = sticky_of scroll in
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
        if selected then Ui.Paint.fill paint ~x:(x +. 6.) ~y:row_y ~w:(w -. 12.) ~h:height theme.control
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
          ~color:(if selected || t.focus = Some row.id then theme.foreground else ink_2) letter;
        let label_x = badge_x +. Ui.Paint.cap_width paint letter +. 8. in
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
          Ui.Paint.flag paint ~at:(cx, cy) ~round:(column > 0) value) row.flags in
      for k = first to last do
        draw_row k (top +. float_of_int k *. height -. scroll)
      done;
      (* the sheet's brackets: 4 points out of the fill, which is 6 in from the list's edge; after
         every row, since they reach into the rows above and below, whose ground would cover them *)
      let mark k row_y = if is_selected (at k).id then
        Ui.Paint.brackets paint ~x:(x +. 6.) ~y:row_y ~w:(w -. 12.) ~h:height ~offset:4. ~length:8. theme.accent in
      for k = first to last do mark k (top +. float_of_int k *. height -. scroll) done;
      List.iteri (fun slot k -> draw_row k (top +. float_of_int slot *. height)) sticky;
      List.iteri (fun slot k -> mark k (top +. float_of_int slot *. height)) sticky;
      if sticky <> [] then
        Ui.Paint.fill paint ~x ~y:(top +. float_of_int (List.length sticky) *. height) ~w ~h:1.
          (Pxui.Theme.edge theme);
      (match drop_hint with
       | Some (k, drop) ->
           let row_y = top +. float_of_int k *. height -. scroll in
           (match drop with
            | Inside -> Ui.Paint.frame paint ~x ~y:row_y ~w ~h:height ~width:2. theme.accent
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
              ~description:"A new name for the row" ~query:name with
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

  (* Sections are one level deep: the top folder of a parameter, never the vector's own folder
     (its row is one row, in the section it belongs to). *)
  let top_folder (row : flow_row) =
    let folder = match row.fields with
      | (field : Param.field_view) :: _ -> field.folder | [] -> [] in
    let squash name = String.lowercase_ascii (String.concat "" (String.split_on_char ' ' name)) in
    let folder = match List.rev folder with
      | last :: rest when squash last = squash row.path -> List.rev rest
      | _ -> folder in
    match folder with first :: _ -> [ first ] | [] -> []

  let flow_fields ui ?(expanded = []) ?width ?(actions = true) ?(pins = false) ?(pin_click = false) ?(chips = [])
      ?kind_label ?(on_choice = fun _ _ -> ()) rows =
    (* the rows fill the panel they are built in *)
    let width = Option.value width ~default:(Ui.inspector_width ui) in
    let theme = Ui.theme ui in
    let ink_2 = Pxui.Theme.ink_2 theme and ink_3 = Pxui.Theme.ink_3 theme in
    let expression text = String.starts_with ~prefix:"=" text
      && String.length (String.trim text) > 1 in
    (* the dot of a row is drawn by the row ([pins]); with [actions] a click on it pins the row *)
    let pin_of shown = if pins then Some shown else None in
    let pinnable = actions || pin_click in
    (* a click on the dot, or the s key over the row, asks to flip the row's pin *)
    let pin_change box path shown clicked edits =
      let key = pinnable && Ui.hovered_within ui box && not (Ui.text_input_focused ui)
        && Ui.key_pressed ui (Rays.Input.KeyChar 's') in
      (if clicked || key then [ Pinned (path, not shown) ] else []) @ edits in
    let action ui key label ~x ~y ~enabled ?(visible = true) () =
      let pin = label = "pin" in
      let x = if pin then 6. else x and w = if pin then 18. else 20. in
      let box = Ui.box ui ~flags:(if enabled then Ui.(clickable + tab_stop) else Ui.none)
          ~at:(x, y) ~w:(Ui.Px w) ~h:(Ui.Px 20.) key in
      let signal = Ui.signal ui box in
      let clicked = enabled && signal.clicked in
      if visible && not pin then Ui.draw ui box (fun paint (x, y, w, h) ->
        let color = if enabled && signal.hovered then theme.foreground else ink_3 in
        if label = "\xc3\x97" then begin
          let cx = x +. (w /. 2.) and cy = y +. (h /. 2.) in
          Ui.Paint.line paint ~from_:(cx -. 3.5, cy -. 3.5) ~to_:(cx +. 3.5, cy +. 3.5) color;
          Ui.Paint.line paint ~from_:(cx -. 3.5, cy +. 3.5) ~to_:(cx +. 3.5, cy -. 3.5) color
        end else Ui.Paint.text paint ~at:(x +. 1., Kit.cap_y ui y h) ~size:(Kit.cap_size ui) ~color label);
      clicked in
    let input ?(ranged = true) field path ~edit ~x ~y ~w =
      let key = "flow-value-" ^ path in
      let numeric text valid ?display ?fraction ?slide ~step convert =
        (* a field with a range slides to where the pointer is on its track; one without (a
           vector's cell) has no track: a drag changes it from the value it had, so a click
           without a drag writes nothing *)
        let fraction = if ranged then fraction else None
        and slide = if ranged then slide else None
        and scrub = if ranged then None else Some (fun origin dx shift -> step origin dx shift) in
        let changed, _ = Ui.value_field ui ~at:(x, y) ~w ~h:20.
            ?display ?fraction ?slide ?scrub ~edit ~left:(expression text)
            ?trail:(Option.map (fun unit -> unit, ink_3) field.Param.unit) ~valid:(fun text -> valid text || expression text)
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
            ~fraction ~slide
            ~step:(fun origin dx _ -> match int_of_string_opt origin with
              | Some n -> string_of_int (n + int_of_float (Float.round (dx /. 6.))) | None -> origin)
            (fun text -> Option.map (fun n -> Param.Int_value n)
              (int_of_string_opt text))
      | Param.Floating_view range, Param.Float_value value ->
          let fraction = (value -. range.soft_min)
            /. Float.max 0.000001 (range.soft_max -. range.soft_min) in
          let slide fraction = Printf.sprintf "%.6g"
            (range.soft_min +. fraction *. (range.soft_max -. range.soft_min)) in
          numeric (Printf.sprintf "%.6g" value)
            (fun text -> Option.fold ~none:false ~some:Float.is_finite
              (float_of_string_opt text)) ~display:(Printf.sprintf "%.6g" value)
            ~fraction ~slide
            ~step:(fun origin dx shift -> match float_of_string_opt origin with
              | Some v -> Printf.sprintf "%.6g" (v +. (dx *. (if shift then 0.005 else 0.05))) | None -> origin)
            (fun text -> Option.map (fun n -> Param.Float_value n)
              (float_of_string_opt text))
      | Param.Text_view, Param.Text_value value ->
          (* an empty group means every element of its owner *)
          let placeholder = match field.default with
            | Param.Text_value "" when field.name = "group" -> Some "all points"
            | Param.Text_value "" when String.ends_with ~suffix:"_group" field.name -> Some "all"
            | _ -> None in
          let text, _ = Ui.value_field ui ~at:(x, y) ~w ~h:20. ?placeholder
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
          Ui.draw ui box (fun paint (x, y, w, h) ->
            Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1.
              (if open_ then theme.accent else Pxui.Theme.edge theme);
            let pad = match List.assoc_opt choices.(index) chips with
              | Some color ->
                  Ui.Paint.rect paint ~x:(x +. 2.) ~y:(y +. 6.) ~w:8. ~h:8. ~fill:color
                    ~stroke:(Pxui.Theme.edge theme) (); 14.
              | None -> 0. in
            Ui.Paint.text paint ~at:(x +. 2. +. pad, Kit.text_y ui (y -. 0.5) h)
              ~color:theme.foreground choices.(index);
            Ui.Paint.chevron paint ~at:(x +. w -. 5., y +. (h /. 2.))
              (if open_ then `Up else `Down) theme.foreground);
          if not open_ || just_opened then [] else
            let bx, by, bw, bh = Ui.rect ui box in
            (match Ui.context_menu ui ~at:(bx, by +. bh +. 1.) ~width:bw ~selected:index
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
          ~width ?pin:(pin_of shown) ~key:("flow-row-" ^ path) ~label:title () in
      (* the cross that removes a drive shows on the hovered row, in place of the live value *)
      let hovered = Ui.hovered_within ui box in
      Ui.within ui box (fun () ->
        let live = if hovered then None else live in
        let edits = if expression source then
          let text, _ = Ui.value_field ui ~at:(control_x, control_y) ~w:control_w ~h:20.
              ~display:(String.sub source 1 (String.length source - 1))
              ~lead:("\xc6\x92", ink_2)
              ?trail:(Option.map (fun value -> value, ink_2) live)
              ~line:(Pxui.Theme.ports theme).float
              ~valid:expression ("flow-expression-" ^ path) source in
          if text = source then [] else [Expression (path, text)]
        else (Ui.draw ui box (fun paint (x, y, _, _) ->
          let ty = Kit.text_y ui (y +. control_y -. 0.5) 20. in
          let left = x +. control_x +. 2. and right = x +. control_x +. control_w -. 2. in
          Ui.Paint.text paint ~at:(left, ty) ~color:theme.accent "\xe2\x86\x90";
          let source_x = left +. Ui.Paint.text_width paint "\xe2\x86\x90" +. 6. in
          let live_w = Option.fold ~none:0. ~some:(fun v -> Ui.Paint.text_width paint v +. 6.) live in
          Ui.Paint.text paint ~at:(source_x, ty) ~color:ink_2
            (Ui.ellipsis ~width:(Ui.Paint.text_width paint ~size:(Ui.font_size ui)) ~limit:(right -. source_x -. live_w) source);
          Option.iter (fun value ->
            Ui.Paint.text paint ~color:theme.foreground
              ~at:(right -. Ui.Paint.text_width paint value, ty) value) live); []) in
        let reset = hovered && action ui ("reset-" ^ path) "\xc3\x97" ~x:(width -. 32.)
            ~y:control_y ~enabled:true () in
        let pin = pinnable && action ui ("pin-" ^ path) "pin" ~x:0. ~y:control_y ~enabled:true () in
        pin_change box path shown pin (if reset then Reset path :: edits else edits)) in
    let scalar path title field shown =
      let box, control_x, control_y, control_w = Ui.inspector_row ui
          ~width ?pin:(pin_of shown) ~key:("flow-row-" ^ path) ~label:title () in
      Ui.within ui box (fun () ->
        (* the label's own extent: its column *)
        let label_x = Ui.inspector_label_x ui in
        let label = Ui.box ui ~flags:Ui.clickable ~at:(label_x, 2.)
            ~w:(Ui.Px (Float.max 1. (control_x -. label_x -. 8.))) ~h:(Ui.Px 20.) "label-edit" in
        let edit = (Ui.signal ui label).double_clicked in
        let edits = input field path ~x:control_x ~y:control_y ~w:control_w ~edit in
        let pinned = pinnable && action ui ("pin-" ^ path) "pin" ~x:0. ~y:control_y ~enabled:true () in
        pin_change box path shown pinned edits) in
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
    let swatch_and_hex ~path ~control_x ~control_y ~control_w ~swatch_color ~hex_str =
      Kit.colour ui ~key:path ~at:(control_x, control_y) ~w:control_w ~swatch:swatch_color ~hex:hex_str in
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
          ~width ?pin:(pin_of shown) ~key:("flow-row-" ^ path) ~label:title () in
      let whole = Ui.within ui box (fun () ->
        let split = Option.value ~default:false row.split in
        let text = swatch_and_hex ~path ~control_x ~control_y ~control_w ~swatch_color ~hex_str in
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
        let toggle = actions && action ui ("split-" ^ path) "rgb"
            ~x:(width -. 32.) ~y:control_y
            ~enabled:(not row.locked) () in
        let pin = pinnable && action ui ("pin-" ^ path) "pin" ~x:0. ~y:control_y
            ~enabled:(not row.locked) () in
        hex_edits
        @ (if toggle then [ Split (path, not split) ] else [])
        @ pin_change box path shown pin []) in
      if row.split = Some true || row.components <> [] then
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
          ~width ?pin:(pin_of shown) ~key:("flow-row-" ^ path) ~label:title () in
      Ui.within ui box (fun () ->
        let text = swatch_and_hex ~path ~control_x ~control_y ~control_w ~swatch_color ~hex_str in
        let hex_edits =
          if text = hex_str then [] else
          match Color.hex text with
          | Ok _ -> [ Edited (field.Param.name, Param.Text_value text) ]
          | Error _ -> [] in
        let pin = pinnable && action ui ("pin-" ^ path) "pin" ~x:0. ~y:control_y ~enabled:true () in
        hex_edits @ pin_change box path shown pin []) in
    let row_widget (row : flow_row) =
      (* a row is named by its argument, as the sheet and the card name it *)
      let title = match row.fields with
        | [field] when String.starts_with ~prefix:"@" row.path -> field.Param.label
        | _ -> row.path in
      match row.drive, row.fields with
      | Some source, _ -> driven row.path title source row.live row.shown
      | None, [field] when is_color_1 field -> color_row_1 row.path title field row.shown
      | None, [field] -> scalar row.path title field row.shown
      | None, fields when is_color_3 row -> color_row_3 row title fields row.shown
      | None, fields ->
          (* a vector: three fields in the control column, 8 between, each with its axis letter *)
          let box, control_x, control_y, control_w = Ui.inspector_row ui
              ~width ?pin:(pin_of row.shown) ~key:("flow-row-" ^ row.path) ~label:title () in
          let whole = Ui.within ui box (fun () ->
            let split = Option.value ~default:false row.split in
            let edits = if split || row.components <> [] then [] else
              Kit.vector ui box ~at:(control_x, control_y) ~w:control_w
                ~reserve:(if actions then 24. else 0.) (fun index ~x ~w ->
                  let field = List.nth fields index in
                  input ~ranged:false field (row.path ^ "." ^ List.nth ["x"; "y"; "z"] index)
                    ~edit:false ~x ~y:control_y ~w) in
            let toggle = actions && action ui ("split-" ^ row.path) "xyz"
                ~x:(width -. 32.) ~y:control_y
                ~enabled:(not row.locked) () in
            let pin = pinnable && action ui ("pin-" ^ row.path) "pin" ~x:0. ~y:control_y
                ~enabled:(not row.locked) () in
            edits @ (if toggle then [Split (row.path, not split)] else [])
            @ pin_change box row.path row.shown pin []) in
          if row.split = Some true || row.components <> [] then
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
              ~expanded:(List.mem key expanded || (path = [ label ] && Some label = kind_label)) label
              (fun () -> build path children))) items in
    if rows = [] then (Ui.inspector_message ui ~key:"no-parameters" "No parameters"; []) else
      (* a kind's own section first, for the arguments that have no folder *)
      let folder_of row = match top_folder row, kind_label with
        | [], Some label -> [ label ] | folder, _ -> folder in
      let own, others = List.partition (fun row -> top_folder row = []) rows in
      build [] (List.fold_left (fun items (row : flow_row) -> insert (folder_of row) row items) []
                  (own @ others))

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
