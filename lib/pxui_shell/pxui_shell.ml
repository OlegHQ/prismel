open Prismel

module Layout = struct
  type panel = Editor_core.Panels.panel =
    | View of string | Graph | List | Lisp | Inspector | Outline | Timeline
  type axis = Editor_core.Panels.axis
  type t = Editor_core.Panels.t =
    | Leaf of panel
    | Split of { axis : axis; ratio : float; a : t; b : t }
    | Tile of t list
    | Float of t
  type path = int list
  type bounds = int * int * int * int

  let default = Editor_core.Panels.default

  let splitter_width = 1
  let collapsed_width = 28
  let header_height = 22
  let status_height = 28
  let timeline_height = 30

  type leaf = { path : path; panel : panel; header : bounds; body : bounds; floating : bool }
  type splitter = { node : path option; axis : axis; bounds : bounds; start : int; span : int }
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
    | Leaf _ when (state path).Editor_core.Panels.collapsed -> Strip
    | Leaf p -> if not (List.mem p hidden) then Live
        else (match p with View _ -> Strip | _ -> Gone)
    | Float _ -> Gone
    | Split { a; b; _ } -> join (presence ~state hidden (path @ [0]) a) (presence ~state hidden (path @ [1]) b)
    | Tile cells -> List.mapi (fun i c -> presence ~state hidden (path @ [i]) c) cells
        |> List.fold_left join Gone

  let is_float = function Float _ -> true | _ -> false

  (* A run of splits along one axis is one row of columns whose weights are the
     products of the ratios, so [0.45 | 0.55 * 0.6364 | ...] divides the width once. *)
  let rec columns axis weight path = function
    | Split s when s.axis = axis && not (is_float s.a || is_float s.b) ->
        columns axis (weight *. s.ratio) (path @ [ 0 ]) s.a
        @ columns axis (weight *. (1. -. s.ratio)) (path @ [ 1 ]) s.b
    | tree -> [ weight, path, tree ]

  let rec minimum axis = function
    | Leaf p when axis = `H ->
        (match p with View _ -> 220 | Graph | List | Lisp -> 180 | _ -> 120)
    | Split { a; b; _ } -> max (minimum axis a) (minimum axis b)
    | Tile cells -> List.fold_left (fun m c -> max m (minimum axis c)) 0 cells
    | Leaf _ | Float _ -> 0

  (* Sizes of the columns of one row: strips are fixed, the rest share what is
     left by weight, each at least its minimum when the minimums fit, the last
     live one taking the rounding remainder. *)
  let distribute total cols =
    let n = Array.length cols in
    let present = Array.fold_left (fun k (p, _, _) -> if p = Gone then k else k + 1) 0 cols in
    let available = max 3 (total - (max 0 (present - 1) * splitter_width)) in
    let sizes = Array.make n 0 in
    let fixed = ref 0 and weight = ref 0. and required = ref 0 and live = ref (-1)
    and last = ref (-1) in
    Array.iteri (fun i (p, w, m) ->
      if p <> Gone then last := i;
      match p with
      | Strip -> sizes.(i) <- collapsed_width; fixed := !fixed + collapsed_width
      | Live -> weight := !weight +. w; required := !required + m; live := i
      | Gone -> ()) cols;
    let flexible = max 3 (available - !fixed) in
    Array.iteri (fun i (p, w, _) -> if p = Live then
      sizes.(i) <- max 1 (int_of_float (float_of_int flexible *. w /. !weight))) cols;
    if !last >= 0 then begin
      let used = Array.fold_left ( + ) 0 sizes in
      sizes.(!last) <- max 1 (sizes.(!last) + available - used)
    end;
    let short = ref false in
    Array.iteri (fun i (p, _, m) -> if p = Live && sizes.(i) < m then short := true) cols;
    if !live >= 0 && !required <= flexible && !short then begin
      let extra = flexible - !required and assigned = ref 0 in
      Array.iteri (fun i (p, w, m) -> if p = Live then begin
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

  let geometry ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) ?(top = 0) tree (frame : Frame.t) =
    let all = Editor_core.Panels.leaves tree in
    let header = min header_height (max 0 (frame.height - 1)) in
    let timeline = if List.mem Timeline hidden || List.exists (fun (_, p) -> p = Timeline) all
      then 0 else min timeline_height (max 0 (frame.height - header - 1)) in
    let bottom = frame.height - timeline in
    let status_path = match List.find_opt (fun (_, p) -> match p with View _ -> true | _ -> false) all,
      all with
      | Some (path, _), _ | None, (path, _) :: _ -> path
      | None, [] -> [] in
    let leaves = ref [] and splitters = ref [] and status = ref (0, bottom, 0, 0)
    and floats = ref [] in
    let leaf ?(floating = false) path panel (x, y, w, h) =
      let hh = min header_height (max 0 (h - 1)) in
      let body = if (state path).Editor_core.Panels.collapsed then 0 else max 1 (h - hh) in
      let strip = if path = status_path then min status_height (max 0 (body - 1)) else 0 in
      if path = status_path then status := (x, y + hh + body - strip, w, strip);
      leaves := { path; panel; floating; header = (x, y, w, hh);
                  body = (x, y + hh, w, body - strip) } :: !leaves in
    let cut total n = (* n cells and n-1 gutters over [total] *)
      let cell = max 1 ((total - ((n - 1) * splitter_width)) / n) in
      Array.init n (fun i -> if i = n - 1 then max 1 (total - (i * (cell + splitter_width))) else cell) in
    let rec place ?(floating = false) ((x, y, w, h) as rect) path = function
      | Leaf p -> if presence ~state hidden path (Leaf p) <> Gone then leaf ~floating path p rect
      | Float t -> floats := ((x + (w / 8), y + (h / 8), w - (w / 4), h - (h / 4)), path @ [ 0 ], t)
                             :: !floats
      | Split { a; b; _ } when is_float a || is_float b ->
          place ~floating rect (path @ [ 0 ]) a; place ~floating rect (path @ [ 1 ]) b
      | Split { axis; _ } as tree ->
          let cols = Array.of_list (columns axis 1. [] tree) in
          let info = Array.map (fun (weight, col_path, sub) ->
            presence ~state hidden (path @ col_path) sub, weight, minimum axis sub) cols in
          let horizontal = axis = `H in
          let sizes = distribute (if horizontal then w else h) info in
          let cursor = ref (if horizontal then x else y) in
          let prior = ref None and placed = ref [] and gutters = ref [] in
          Array.iteri (fun i (_, col_path, sub) ->
            let p, _, _ = info.(i) in
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
            splitters := { node = Some (path @ node); axis; bounds; start; span } :: !splitters)
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
            if c > 0 then splitters := { node = None; axis = `H;
              bounds = (cx - splitter_width, cy, splitter_width, heights.(r)); start = 0; span = 1 }
              :: !splitters;
            if r > 0 && c = 0 then splitters := { node = None; axis = `V;
              bounds = (x, cy - splitter_width, w, splitter_width); start = 0; span = 1 } :: !splitters;
            place ~floating (cx, cy, widths.(r).(c), heights.(r)) (path @ [ original ]) cell) cells
          end in
    place (0, top, frame.width, max 1 (bottom - top)) [] tree;
    let rec drain () = match List.rev !floats with
      | [] -> ()
      | queue -> floats := [];
          List.iter (fun (rect, path, t) -> place ~floating:true rect path t) queue; drain () in
    drain ();
    List.iter (fun (path, panel) -> match (state path).Editor_core.Panels.window with
      | None -> ()
      | Some (x, y, w, h) ->
          let w = min frame.width w and h = min (frame.height - top) h in
          let x = max 0 (min x (frame.width - w)) and y = max top (min y (frame.height - header_height)) in
          leaf ~floating:true path panel (x, y, w, if (state path).collapsed then header_height else min h (frame.height - y))) all;
    { leaves = List.rev !leaves; splitters = List.rev !splitters; status_at = !status;
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

module Chrome = struct
  open Layout
  type intent =
    | Resize of { node : path; ratio : float }
    | Settled
    | Toggle of path
    | Window of path * bounds option
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
  let update ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) ?(top = 0) ?(title = fun (l : leaf) -> Editor_core.Panels.name l.panel)
      tree ui (frame : Frame.t) =
    let module Ui = Pxui.Ui in
    let geometry = geometry ~state ~hidden ~top tree frame in
    let theme = Ui.theme ui in
    List.iteri (fun order l -> match l.panel with
      | View _ | Timeline -> ()
      | p ->
          let box = floating ui l.body ("workspace-" ^ String.lowercase_ascii (Editor_core.Panels.name p)
                                        ^ key l.path) in
          if l.floating then Ui.to_front ui ~order box;
          Ui.draw ui box (fun paint (x, y, w, h) -> Ui.Paint.fill paint ~x ~y ~w ~h theme.panel))
      geometry.leaves;
    let intents = ref [] in
    let emit i = intents := i :: !intents in
    List.iteri (fun n (s : splitter) ->
      let box = floating ui s.bounds ("workspace-gutter-" ^ string_of_int n) in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.faint_border theme))) geometry.splitters;
    let headers = List.mapi (fun order (l : leaf) ->
      let x, y, w, h = l.header in
      let label = String.lowercase_ascii (Editor_core.Panels.name l.panel) ^ key l.path in
      let box = floating ui ~flags:Ui.(clickable + clip) l.header ("workspace-header-" ^ label) in
      if l.floating then Ui.to_front ui ~order box;
      let size = min h 26 in
      let button = floating ui ~flags:Ui.(clickable + tab_stop)
          (x + max 0 (w - size), y + ((h - size) / 2), size, size) ("workspace-collapse-" ^ label) in
      if l.floating then Ui.to_front ui ~order button;
      if (Ui.signal ui button).clicked then emit (Toggle l.path);
      let grip = floating ui ~flags:Ui.(clickable + blocking)
          (x, y, min 18 (max 0 (w - size)), h) ("workspace-drag-" ^ label) in
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
          emit (Window (l.path, Some (max 0 (min (frame.width - 18) (ox + int_of_float (Float.round (px -. sx)))),
            max top (min (frame.height - header_height) (oy + int_of_float (Float.round (py -. sy)))), ow, oh)))
        end
      end;
      let opened = Ui.state ui box ~default:0 = 1 in
      let header_signal = Ui.signal ui box in
      let opened = opened || Ui.context_clicked header_signal || header_signal.clicked in
      Ui.set_state ui box (if opened then 1 else 0);
      if opened then begin
        let rows = [ "Split side by side", true; "Split top and bottom", true; "Close", true;
                     (if (state l.path).window = None then "Undock" else "Dock"), true;
                     "", false; "Show as", false ]
          @ List.map (fun (name, panel) -> name, panel <> l.panel) retypes in
        match Ui.context_menu ui ~at:(float x, float (y + h)) ("workspace-menu-" ^ label) rows with
        | `Open -> ()
        | `Dismiss -> Ui.set_state ui box 0
        | `Pick i -> Ui.set_state ui box 0;
            emit (match i with
              | 0 -> Split_panel (l.path, `H) | 1 -> Split_panel (l.path, `V)
              | 2 -> Close_panel l.path
              | 3 -> Window (l.path, if (state l.path).window <> None then None else
                    Some (x, y, max 120 w, max 80 (let _, _, _, bh = l.body in h + bh)))
              | i -> Retype_panel (l.path, snd (List.nth retypes (i - 6))))
      end;
      l, title l, box, button, grip) geometry.leaves in
    List.iter (fun ((l : leaf), text, box, button, grip) ->
      let collapse_hovered = (Ui.signal ui button).hovered in
      let text_box = Ui.within ui box (fun () -> Ui.box ui ~w:Ui.Grow ~h:Ui.Grow "header-text") in
      Ui.draw ui text_box (fun paint (x, y, w, h) ->
        Ui.Paint.rect paint ~x ~y ~w ~h ~fill:theme.input
          ~stroke:(Pxui.Theme.faint_border theme) ();
        let x = int_of_float x and y = int_of_float y and w = int_of_float w in
        (* "Title<TAB>subtitle": the subtitle follows in the muted colour *)
        let main, sub = match String.index_opt text '\t' with
          | Some i -> String.sub text 0 i, String.sub text (i + 1) (String.length text - i - 1)
          | None -> text, "" in
        Ui.Paint.text paint ~at:(float_of_int (x + 22), float_of_int (y + 4)) ~size:11
          ~color:theme.foreground main;
        if not (List.mem l.panel hidden) then begin
          let cx = float (x + 30) +. Ui.Paint.text_width paint ~size:11 main in
          let cy = float y +. h /. 2. in
          Ui.Paint.line paint ~from_:(cx -. 3., cy -. 2.) ~to_:(cx, cy +. 1.) ~width:1.5 theme.foreground;
          Ui.Paint.line paint ~from_:(cx, cy +. 1.) ~to_:(cx +. 3., cy -. 2.) ~width:1.5 theme.foreground
        end;
        if sub <> "" then
          Ui.Paint.text paint ~at:(float_of_int (x + 22 + (7 * (String.length main + 4))), float_of_int (y + 4))
            ~size:11 ~color:(Pxui.Theme.muted theme) sub;
        let cx = float (x + max 7 (w - 13)) and cy = float y +. h /. 2. in
        if collapse_hovered then Ui.Paint.fill paint ~x:(cx -. 10.) ~y:(float y +. 1.)
          ~w:20. ~h:(h -. 2.) (Pxui.Theme.hover_fill theme);
        let direction = if (state l.path).collapsed || List.mem l.panel hidden then -1. else 1. in
        Ui.Paint.line paint ~from_:(cx +. 2. *. direction, cy -. 4.)
          ~to_:(cx -. 2. *. direction, cy) ~width:1.5 theme.accent;
        Ui.Paint.line paint ~from_:(cx -. 2. *. direction, cy)
          ~to_:(cx +. 2. *. direction, cy +. 4.) ~width:1.5 theme.accent);
      Ui.draw ui grip (fun paint (x, y, w, h) ->
        let signal = Ui.signal ui grip in
        let color = if signal.hovered || signal.held then theme.accent else Pxui.Theme.muted theme in
        for row = 0 to 2 do for col = 0 to 1 do
          Ui.Paint.circle paint ~at:(x +. w /. 2. -. 2. +. float col *. 4.,
            y +. h /. 2. -. 4. +. float row *. 4.) ~radius:0.8 ~fill:color ()
        done done)) headers;
    List.rev !intents

  let note ui ~bounds:(x, y, width, height) text =
    let theme = Pxui.Ui.theme ui in
    Pxui.Ui.draw ui (floating ui (x, y, width, height) (Printf.sprintf "workspace-note-%d-%d" x y))
      (fun paint (x, y, _, _) -> Pxui.Ui.Paint.text paint ~at:(x +. 10., y +. 8.) ~size:11
        ~color:(Pxui.Theme.muted theme) text)

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
            if hovered then Pxui.Ui.draw ui box (fun paint (x, y, w, h) ->
              let color = (Pxui.Ui.theme ui).accent in
              Pxui.Ui.Paint.rect paint ~x ~y ~w ~h ~fill:(Color.with_alpha color 45) ~stroke:color ());
            if released && hovered then Some (Dock_panel (source, leaf.path, side)) else None)
            [ `Left, (x, y + ey, ex, max 0 (h - 2 * ey));
              `Right, (x + w - ex, y + ey, ex, max 0 (h - 2 * ey));
              `Top, (x, y, w, ey); `Bottom, (x, y + h - ey, w, ey)]) geometry.leaves

  (* The draggable gutters, wider than they are drawn.  Build them after the panes so
     they sit on top of the neighbours' hit rectangles. *)
  let splitters ?(state = fun _ -> Editor_core.Panels.default_state) ?(hidden = [ Timeline ]) ?(top = 0) tree ui (frame : Frame.t) =
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
          let dx, dy = signal.drag in
          if (signal.held || signal.released) && (if s.axis = `H then dx else dy) <> 0. then begin
            let px, py = signal.pointer in
            let along = if s.axis = `H then px else py in
            intents := Resize { node; ratio = (along -. float s.start) /. float (max 1 s.span) }
                       :: !intents
          end;
          if signal.released then intents := Settled :: !intents)
      (geometry ~state ~hidden ~top tree frame).splitters;
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
            if px <> sx || py <> sy then intents := Window (leaf.path, Some (x, y,
              max 120 (w + int_of_float (Float.round (px -. sx))),
              max 80 (h + int_of_float (Float.round (py -. sy))))) :: !intents
          end;
          Ui.draw ui box (fun paint (x, y, w, h) ->
            for offset = 3 to 7 do
              if offset mod 2 = 1 then Ui.Paint.line paint ~from_:(x +. w -. float offset, y +. h -. 2.)
                ~to_:(x +. w -. 2., y +. h -. float offset) (Pxui.Theme.muted (Ui.theme ui))
            done)
      | Some _ -> ()) (geometry ~state ~hidden ~top tree frame).leaves;
    List.rev !intents

  let focus ui ~bounds:(x, y, width, height) =
    if width > 2 && height > 2 then begin
      let theme = Pxui.Ui.theme ui in
      Pxui.Ui.draw ui (floating ui (x, y, width, height) "workspace-focus")
        (fun paint _ -> Pxui.Ui.Paint.fill paint
          ~x:(float_of_int x) ~y:(float_of_int y)
          ~w:(float_of_int width) ~h:1. theme.accent)
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
          rows @ [Editor_core.Keymap.label (Chord (key, modifiers)), command.label]
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

  let sheet ui keymap =
    let module Ui = Pxui.Ui in
    let groups = ["Move", ["graph.walk."; "graph.frame-"; "scene.enter"; "scene.up"];
      "Build", ["graph.add"; "graph.repeat"; "graph.connect-hint"];
      "Shape", ["graph.open"; "graph.point"; "graph.group"; "graph.ungroup"];
      "Rows", ["row."];
      "Change", ["graph.display"; "graph.mute"; "graph.delete"; "graph.dissolve";
        "graph.copy"; "graph.cut"; "graph.paste"; "graph.duplicate"; "edit."];
      "Guide", ["guide."; "graph.find"; "graph.projection"]] in
    let theme = Ui.theme ui in
    match Ui.modal ui ~width:460. "guide-keys" (fun () ->
      Ui.label ui "Flow keys";
      List.iter (fun (title, prefixes) ->
        let commands = List.filter (fun command -> command.trigger <> None
          && List.exists (fun prefix -> String.starts_with ~prefix command.id) prefixes) keymap in
        let commands = List.fold_left (fun seen command ->
          if List.exists (fun previous -> previous.id = command.id) seen then seen
          else command :: seen) [] commands |> List.rev in
        if commands <> [] then begin
          Ui.label ui title;
          List.iter (fun command ->
            let keys = List.filter_map (fun alias -> if alias.id <> command.id then None
              else match alias.trigger with
                | Some (Chord (_, modifiers)) when List.mem Input.Ctrl modifiers -> None
                | Some trigger -> Some (Editor_core.Keymap.label trigger) | None -> None) keymap
              |> List.sort_uniq String.compare |> String.concat " / " in
            let row = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float (Ui.row_height ui)))
              ("keys-" ^ command.id) in
            Ui.draw ui row (fun paint (x, y, _, _) ->
              Ui.Paint.text paint ~at:(x +. 8., y +. 5.) ~size:11 ~color:theme.accent keys;
              Ui.Paint.text paint ~at:(x +. 180., y +. 5.) ~size:11
                ~color:theme.foreground command.label)) commands
        end) groups;
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
      let fps = match fps with
        | Some fps -> Printf.sprintf " · %d fps" fps | None -> "" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint _ ->
        Ui.Paint.fill paint ~x:(float_of_int x) ~y:(float_of_int y)
          ~w:(float_of_int width) ~h:(float_of_int height) theme.input;
        let at = float_of_int (x + 10), float_of_int (y + 8) in
        Ui.Paint.text paint ~at ~size:11 ~color:theme.foreground text;
        Ui.Paint.text paint
          ~at:(fst at +. Ui.Paint.text_width paint ~size:11 text, snd at)
          ~size:11 ~color:theme.foreground fps)
    end

  let guide ui ~bounds:(x, y, width, height) ~context commands =
    let module Ui = Pxui.Ui in
    if height <= 0 then false else
    let bar = Ui.box ui ~flags:Ui.(clickable + clip)
        ~w:(Ui.Px (float width)) ~h:(Ui.Px (float height))
        ~at:(float x, float y) "workspace-guide" in
    let keys = List.filter_map (fun (command : _ Editor_core.Command.t) ->
        Option.map Editor_core.Keymap.label command.trigger) commands |> String.concat "  " in
    let title = Editor_core.Guide_context.name context in
    let theme = Ui.theme ui in
    Ui.draw ui bar (fun paint (x, y, w, h) ->
      Ui.Paint.fill paint ~x ~y ~w ~h theme.foreground;
      Ui.Paint.text paint ~at:(x +. 8., y +. 8.) ~size:11 ~color:theme.input
        (let text = title ^ " · " ^ keys in
         if Ui.Paint.text_width paint ~size:11 text <= w -. 58. then text else
         let gap = Ui.Paint.text_width paint ~size:11 " " in
         let limit = w -. 58. -. Ui.Paint.text_width paint ~size:11 "…" in
         let rec fit prefix width = function
           | [] -> prefix ^ "…"
           | word :: rest ->
               let width = width +. (if prefix = "" then 0. else gap)
                 +. Ui.Paint.text_width paint ~size:11 word in
               let next = if prefix = "" then word else prefix ^ " " ^ word in
               if width > limit then prefix ^ "…" else fit next width rest in
         fit "" 0. (String.split_on_char ' ' text)));
    let hide = Ui.within ui bar (fun () ->
      Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px 42.) ~h:(Ui.Px (float height))
        ~at:(float (max 0 (width - 42)), 0.) "guide-hide") in
    Ui.draw ui hide (fun paint (x, y, w, h) ->
      Ui.Paint.fill paint ~x ~y ~w ~h theme.foreground;
      Ui.Paint.text paint ~at:(x +. 8., y +. 8.) ~size:11 ~color:theme.input "hide");
    if (Ui.signal ui bar).hovered then
      Ui.tooltip ui ~key:"guide-strip" ~text:(title ^ " · " ^ keys ^ " · Space k: all keys");
    (Ui.signal ui hide).clicked

  let hud ui ~bounds:(x, y, width, height) ~text =
    let module Ui = Pxui.Ui in
    if width > 0 && height > 0 then begin
      let box = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px (float (max 0 (width - 16))))
        ~h:(Ui.Px 24.) ~at:(float (x + 8), float (y + max 0 (height - 32))) "key-hud" in
      let theme = Ui.theme ui in
      Ui.draw ui box (fun paint (x, y, _, _) ->
        let w = Ui.Paint.text_width paint ~size:11 text +. 16. in
        Ui.Paint.fill paint ~x ~y ~w ~h:24. theme.foreground;
        Ui.Paint.text paint ~size:11 ~at:(x +. 8., y +. 6.) ~color:theme.input text)
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

  type macro = { name : string; holes : (bool * string) array }

  (* ponytail: the first 12 literals only; a template with more is rare and the
     rest stay copied into it *)
  let macro ui ~key ~title ~literals ~free (m : macro) =
    Pxui.Ui.modal ui ~width:480. key (fun () ->
      (* Enter in one of its fields creates the macro, like the button *)
      let enter = Pxui.Ui.text_input_focused ui && Pxui.Ui.key_pressed ui Prismel.Input.Enter in
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

  let bindings =
    let open Editor_core.Keymap in
    let key ?(modifiers = []) id label key action = Editor_core.Command.make
        ~id:("list." ^ id) ~label ~trigger:(Chord (key, modifiers)) action in
    let open Prismel.Input in
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
          let px, _ = signal.press_point in
          let chevron_x = x +. 8. +. float_of_int row.depth *. 14. in
          if has_children rows shown.(k) && px >= chevron_x -. 4.
              && px < chevron_x +. 14. then
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
        if has_children rows index then begin
          let cx = indent row.depth +. 5. and cy = row_y +. height /. 2. in
          let points = if Ids.mem row.id t.folded && t.filter = None then
              [cx -. 2., cy -. 4.; cx +. 2., cy; cx -. 2., cy +. 4.]
            else [cx -. 4., cy -. 2.; cx, cy +. 2.; cx +. 4., cy -. 2.] in
          (match points with
           | [ax, ay; bx, by; cx, cy] ->
               Ui.Paint.line paint ~from_:(ax, ay) ~to_:(bx, by) ~width:2. muted;
               Ui.Paint.line paint ~from_:(bx, by) ~to_:(cx, cy) ~width:2. muted
           | _ -> ())
        end;
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
      Ui.Paint.fill paint ~x ~y ~w ~h:height theme.input;
      if t.filter = None then begin
        text ~color:theme.foreground (x +. 8., y +. 5.) (title ^ "  · / filter");
        List.iteri (fun column name ->
          text ~color:theme.foreground (columns_x +. (float_of_int column +. 0.5) *. flag_width
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

  let flow_fields ui ?(expanded = []) ?(width = 280.) ?(actions = true) rows =
    let theme = Ui.theme ui in
    let expression text = String.starts_with ~prefix:"=" text
      && String.length (String.trim text) > 1 in
    let action ui key label ~x ~y ~enabled =
      let box = Ui.box ui ~flags:(if enabled then Ui.(clickable + tab_stop) else Ui.none)
          ~at:(x, y) ~w:(Ui.Px 20.) ~h:(Ui.Px 19.) key in
      let clicked = enabled && (Ui.signal ui box).clicked in
      Ui.draw ui box (fun paint (x, y, w, h) ->
        Ui.Paint.rect paint ~x ~y ~w ~h ~fill:theme.input
          ~stroke:(Pxui.Theme.faint_border theme) ~radius:3. ();
        let color = if enabled then theme.accent else Pxui.Theme.muted theme in
        if label = "●" || label = "○" then
          Ui.Paint.circle paint ~at:(x +. w /. 2., y +. h /. 2.) ~radius:4.
            ~fill:(if label = "●" then color else theme.input)
            ~stroke:color ()
        else if label = "×" then begin
          Ui.Paint.line paint ~from_:(x +. 6., y +. 5.)
            ~to_:(x +. 14., y +. 14.) color;
          Ui.Paint.line paint ~from_:(x +. 14., y +. 5.)
            ~to_:(x +. 6., y +. 14.) color
        end else Ui.Paint.text paint ~at:(x +. 4., y +. 3.) ~size:10
          ~color label);
      clicked in
    let input field path ~edit ~x ~y ~w =
      let key = "flow-value-" ^ path in
      let numeric text valid ?display ?fraction ?slide convert =
        let changed, _ = Ui.value_field ui ~at:(x, y) ~w ~h:21. ~size:11
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
          let text, _ = Ui.value_field ui ~at:(x, y) ~w ~h:21. ~size:11
              ~left:true ~valid:(fun _ -> true) key value in
          if text = value then [] else [Edited (field.name, Param.Text_value text)]
      | Param.Choice_view choices, Param.Choice_value value ->
          let box = Ui.box ui ~flags:Ui.(clickable + tab_stop + clip)
              ~at:(x, y) ~w:(Ui.Px w) ~h:(Ui.Px 21.) key in
          let index = Option.value ~default:0 (Array.find_index (( = ) value) choices) in
          let just_opened = (Ui.signal ui box).clicked in
          let open_ = just_opened || Ui.state ui box ~default:0 = 1 in
          Ui.set_state ui box (if open_ then 1 else 0);
          let hovered = (Ui.signal ui box).hovered in
          Ui.draw ui box (fun paint (x, y, w, h) ->
            let fill = if hovered then Pxui.Theme.hover_fill theme else theme.track in
            Ui.Paint.rect paint ~x ~y ~w ~h ~fill
              ~stroke:(if open_ then theme.accent else Pxui.Theme.faint_border theme) ();
            Ui.Paint.text paint ~at:(x +. 5., y +. 3.) ~size:11
              ~color:theme.foreground choices.(index);
            let cx = x +. w -. 10. and cy = y +. h /. 2. in
            Ui.Paint.fill paint ~x:(cx -. 6.) ~y:(y +. 1.) ~w:15. ~h:(h -. 2.) fill;
            Ui.Paint.line paint ~from_:(cx -. 3., cy -. 2.) ~to_:(cx, cy +. 1.) ~width:1.5 theme.foreground;
            Ui.Paint.line paint ~from_:(cx, cy +. 1.) ~to_:(cx +. 3., cy -. 2.) ~width:1.5 theme.foreground);
          if not open_ || just_opened then [] else
            let bx, by, bw, bh = Ui.rect ui box in
            (match Ui.context_menu ui ~at:(bx, by +. bh) ~width:bw ~selected:index
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
              ~w:(control_w -. 24.) ~h:21. ~size:11
              ~left:true ~valid:expression ("flow-expression-" ^ path) source in
          if text = source then [] else [Expression (path, text)]
        else (Ui.draw ui box (fun paint (x, y, _, _) ->
          Ui.Paint.text paint ~at:(x +. control_x, y +. control_y +. 3.) ~size:11
            ~color:theme.accent
            (display ^ Option.fold ~none:"" ~some:(fun value -> " " ^ value) live)); []) in
        let reset = action ui ("reset-" ^ path) "×" ~x:(width -. 55.)
            ~y:(control_y +. 1.) ~enabled:true in
        let pin = action ui ("pin-" ^ path) (if shown then "●" else "○")
            ~x:(width -. 28.) ~y:(control_y +. 1.) ~enabled:false in
        let _ = pin in
        if reset then Reset path :: edits else edits) in
    let scalar path title field shown =
      let box, control_x, control_y, control_w = Ui.inspector_row ui
          ~width ~key:("flow-row-" ^ path) ~label:title () in
      Ui.within ui box (fun () ->
        let label = Ui.box ui ~flags:Ui.clickable ~at:(8., 4.)
            ~w:(Ui.Px (control_x -. 8.)) ~h:(Ui.Px 21.) "label-edit" in
        let edit = (Ui.signal ui label).double_clicked in
        let edits = input field path ~x:control_x ~y:control_y ~w:control_w ~edit in
        let pinned = actions && action ui ("pin-" ^ path)
            (if shown then "●" else "○") ~x:(width -. 28.)
            ~y:(control_y +. 1.) ~enabled:true in
        if pinned then Pinned (path, not shown) :: edits else edits) in
    let row_widget (row : flow_row) =
      let title = match row.fields with
        | [field] -> field.Param.label | _ -> row.path in
      match row.drive, row.fields with
      | Some source, _ -> driven row.path title source row.live row.shown
      | None, [field] -> scalar row.path title field row.shown
      | None, fields ->
          let box, control_x, control_y, control_w = Ui.inspector_row ui
              ~width ~key:("flow-row-" ^ row.path) ~label:title () in
          let whole = Ui.within ui box (fun () ->
            let split = Option.value ~default:false row.split in
            let field_width = (control_w -. 22.) /. 3. in
            let edits = if split || row.components <> [] || control_w < 140. then [] else
              List.concat (List.mapi (fun index field ->
                let axis = List.nth ["x"; "y"; "z"] index in
                Ui.draw ui box (fun paint (x, y, _, _) ->
                  Ui.Paint.text paint ~at:(x +. control_x +. float index *. field_width,
                    y +. control_y +. 3.)
                    ~size:10 ~color:(Pxui.Theme.muted theme) axis);
                input field (row.path ^ "." ^ axis)
                  ~edit:false
                  ~x:(control_x +. float index *. field_width +. 11.)
                  ~y:control_y
                  ~w:(field_width -. 13.)) fields) in
            let toggle = actions && action ui ("split-" ^ row.path) "xyz"
                ~x:(width -. 55.) ~y:(control_y +. 1.)
                ~enabled:(not row.locked) in
            let pin = actions && action ui ("pin-" ^ row.path)
                (if row.shown then "●" else "○")
                ~x:(width -. 28.) ~y:(control_y +. 1.)
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
