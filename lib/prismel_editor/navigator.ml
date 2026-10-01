(* The Navigator panel: see navigator.mli.  The study's outline is
   prototype/src/e4.js ([fillOutline]). *)
module Ui = Pxui.Ui
module W = Flow.Workspace
module P = Flow_sop.Projection
module S = Flow.Syntax
module Panels = Editor_core.Panels

type path = W.path

type intent =
  | Open of { graph : string; node : path option }
  | Set_default of { graph : string; input : string; value : float; integer : bool }
  | Macro of string

type state = { query : string; typing : bool }

let initial = { query = ""; typing = false }
let editing s = s.typing
let with_query query s = { s with query }

type params = {
  workspace : W.t;
  title : string;
  active : string option;
  scope : P.scope option;
  records : Flow_sop.Probe.t option;
  probes : path -> int;
  selected : path list;
  shell : Panels.t option;
}

type row =
  | Head of string
  | Case of string * string list
  | Note of string list
  | Input_row of { graph : string; name : string; integer : bool; value : float }
  | Graph_row of { graph : string; label : string; context : W.context option; detail : string;
                   active : bool }
  | Node_row of { graph : string; path : path; depth : int; label : string; detail : string;
                  zone : string option; ty : Flow.Ty.t; result : bool; selected : bool }
  | Macro_row of string * int
  | Link_row of { label : string; graph : string; outgoing : bool }
  | Shell_row of { depth : int; label : string; detail : string }
  | Empty of string

(* ---- reading the source ---- *)

let rec walk f (form : S.t) = f form; List.iter (walk f) (S.children form)

let head (form : S.t) = match form.node with
  | S.List ({ S.node = S.Sym h; _ } :: _) -> Some h
  | _ -> None

let count_where pred form =
  let n = ref 0 in walk (fun f -> if pred f then incr n) form; !n

let loops (form : S.t) =
  count_where (fun f -> match head f with Some ("for" | "fold" | "scan" | "sum") -> true | _ -> false) form

(* the graphs a graph form reads with (ref name ...) *)
let reads (form : S.t) =
  let names = ref [] in
  walk (fun f -> match f.node with
    | S.List [ { S.node = S.Sym "ref"; _ }; { S.node = S.Sym n; _ } ]
    | S.List ({ S.node = S.Sym "ref"; _ } :: { S.node = S.Sym n; _ } :: _) ->
        if not (List.mem n !names) then names := n :: !names
    | _ -> ()) form;
  List.rev !names

let calls (ws : W.t) name =
  List.fold_left (fun n (g : W.graph) -> n + count_where (fun f -> head f = Some name) g.form) 0
    (ws.graphs @ List.filter (fun (d : W.graph) -> d.name <> name) ws.defs)

let macro_name (form : S.t) = match form.node with
  | S.List ({ S.node = S.Sym "defmacro"; _ } :: { S.node = S.Sym n; _ } :: _) -> Some n
  | _ -> None

let macro_uses (ws : W.t) name =
  List.fold_left (fun n (g : W.graph) -> n + count_where (fun f -> head f = Some name) g.form) 0
    (ws.graphs @ ws.defs)

let pretty name =
  let s = String.map (function '_' | '-' -> ' ' | c -> c) name in
  String.capitalize_ascii s

let plural n what = Printf.sprintf "%d %s%s" n what (if n = 1 then "" else "s")

let wrap width text =
  let words = String.split_on_char ' ' text in
  let lines, line = List.fold_left (fun (lines, line) word ->
    if line = "" then lines, word
    else if String.length line + 1 + String.length word <= width then lines, line ^ " " ^ word
    else line :: lines, word) ([], "") words in
  List.rev (if line = "" then lines else line :: lines)

let zone_glyph : P.zone_kind -> string = function
  | For -> "for" | Fold -> "fold" | Scan -> "scan" | Sum -> "sum" | Let -> "let*" | Fn -> "λ"

let number (form : S.t) = match form.node with
  | S.Num text -> float_of_string_opt text
  | _ -> None

(* ---- rows ---- *)

let rec node_rows ~graph ~depth p (scope : P.scope) chains counts acc =
  List.iter (fun (n : P.node) ->
    let chain = Option.value ~default:[] (Hashtbl.find_opt chains n.path) in
    let detail = match n.zone, p.records with
      | Some z, _ when z.kind = Let -> "scope"
      | Some _, _ ->
          (match List.assoc_opt n.path counts with Some c -> string_of_int c ^ "×" | None -> "")
      | None, Some records ->
          (Flow_sop.Probe.footer records n ~probes:(List.map p.probes chain)).value
      | None, None -> "" in
    acc := Node_row { graph; path = n.path; depth; detail; ty = n.ty; result = n.synthetic;
                      label = (if n.synthetic then "result" else n.name);
                      zone = Option.map (fun (z : P.zone) -> zone_glyph z.kind) n.zone;
                      selected = List.mem n.path p.selected } :: !acc;
    Option.iter (fun (z : P.zone) -> node_rows ~graph ~depth:(depth + 1) p z.scope chains counts acc)
      n.zone) scope.nodes

let rec shell_rows depth acc = function
  | Panels.Leaf panel -> acc := Shell_row { depth; label = Panels.name panel; detail = "" } :: !acc
  | Panels.Split { axis; ratio; a; b } ->
      let pct = int_of_float (Float.round (ratio *. 100.)) in
      acc := Shell_row { depth; label = (if axis = `H then "split side by side" else "split stacked");
                         detail = Printf.sprintf "%d / %d" pct (100 - pct) } :: !acc;
      shell_rows (depth + 1) acc a; shell_rows (depth + 1) acc b
  | Panels.Tile cells ->
      acc := Shell_row { depth; label = "tile"; detail = string_of_int (List.length cells) } :: !acc;
      List.iter (shell_rows (depth + 1) acc) cells
  | Panels.Float t ->
      acc := Shell_row { depth; label = "floating"; detail = "" } :: !acc;
      shell_rows (depth + 1) acc t

let contains ~query text =
  let q = String.lowercase_ascii query and t = String.lowercase_ascii text in
  let n = String.length q and m = String.length t in
  let rec at i = i + n <= m && (String.sub t i n = q || at (i + 1)) in
  n = 0 || at 0

let search state p chains counts =
  let q = String.trim state.query in
  let acc = ref [] in
  let ws = p.workspace in
  let hits = ref 0 in
  let add row = incr hits; acc := row :: !acc in
  List.iter (fun (g : W.graph) ->
    if contains ~query:q g.name then
      add (Graph_row { graph = g.name; label = g.name; context = Some g.context;
                       detail = W.context_name g.context; active = p.active = Some g.name })) ws.graphs;
  List.iter (fun (d : W.graph) ->
    if contains ~query:q d.name then
      add (Graph_row { graph = "def:" ^ d.name; label = "ƒ " ^ d.name; context = None;
                       detail = "function"; active = p.active = Some ("def:" ^ d.name) })) ws.defs;
  (match p.scope, p.active with
   | Some scope, Some graph ->
       let inner = ref [] in
       node_rows ~graph ~depth:0 p scope chains counts inner;
       List.iter (function
         | Node_row n as row when contains ~query:q n.label -> add row
         | _ -> ()) (List.rev !inner)
   | _ -> ());
  Head (Printf.sprintf "%s · click opens" (plural !hits "match")) :: List.rev !acc
  |> fun rows -> if !hits = 0 then rows @ [ Empty "nothing matches" ] else rows

let rows state p =
  let ws = p.workspace in
  let chains = match p.scope with Some s -> Flow_sop.Probe.chains s | None -> Hashtbl.create 1 in
  let counts = match p.scope, p.records with
    | Some scope, Some records -> Flow_sop.Probe.counts records scope ~probe:p.probes
    | _ -> [] in
  if String.trim state.query <> "" then Array.of_list (search state p chains counts) else begin
    let acc = ref [] in
    let add row = acc := row :: !acc in
    let loops_total = List.fold_left (fun n (g : W.graph) -> n + loops g.form) 0 (ws.graphs @ ws.defs) in
    add (Case (pretty p.title,
      [ plural (List.length ws.graphs) "graph" ^ " · " ^ plural loops_total "loop"; plural (List.length ws.defs) "function" ^ " · " ^ plural (List.length ws.macros) "macro" ]));
    (* the active graph's inputs *)
    (match p.scope, p.active with
     | Some scope, Some graph when scope.inputs <> [] ->
         add (Head ("INPUTS · " ^ (if String.length graph > 4 && String.sub graph 0 4 = "def:"
                                     then String.sub graph 4 (String.length graph - 4) else graph)));
         add (Note [ "Defaults. An OCaml host and (ref …) can override them." ]);
         List.iter (fun (i : P.input) ->
           match Option.bind i.default number with
           | Some value when i.ty = Flow.Ty.Int || i.ty = Flow.Ty.Float ->
               add (Input_row { graph; name = i.name; integer = i.ty = Flow.Ty.Int; value })
           | _ -> ()) scope.inputs
     | _ -> ());
    add (Head "COMPOSITION");
    let active_tree graph =
      match p.scope with
      | Some scope when p.active = Some graph -> node_rows ~graph ~depth:1 p scope chains counts acc
      | _ -> () in
    List.iter (fun (g : W.graph) ->
      let n = loops g.form in
      add (Graph_row { graph = g.name; label = g.name; context = Some g.context;
                       detail = (if n > 0 then plural n "loop" else W.context_name g.context);
                       active = p.active = Some g.name });
      active_tree g.name) ws.graphs;
    if ws.defs <> [] || ws.macros <> [] then begin
      add (Head "REUSABLE");
      List.iter (fun (d : W.graph) ->
        let n = calls ws d.name in
        add (Graph_row { graph = "def:" ^ d.name; label = "ƒ " ^ d.name; context = None;
                         detail = plural n "call"; active = p.active = Some ("def:" ^ d.name) });
        active_tree ("def:" ^ d.name)) ws.defs;
      List.iter (fun m -> Option.iter (fun name ->
        add (Macro_row (name, macro_uses ws name))) (macro_name m)) ws.macros
    end;
    (match p.active with
     | Some graph when not (String.length graph > 4 && String.sub graph 0 4 = "def:") ->
         let out = match List.find_opt (fun (g : W.graph) -> g.name = graph) ws.graphs with
           | Some g -> List.filter (fun n -> List.exists (fun (x : W.graph) -> x.name = n) ws.graphs) (reads g.form)
           | None -> [] in
         let by = List.filter_map (fun (g : W.graph) ->
           if g.name <> graph && List.mem graph (reads g.form) then Some g.name else None) ws.graphs in
         add (Head ("DATA FLOW · " ^ graph));
         List.iter (fun n -> add (Link_row { label = "reads"; graph = n; outgoing = true })) out;
         List.iter (fun n -> add (Link_row { label = "read by"; graph = n; outgoing = false })) by;
         if out = [] && by = [] then add (Empty "no other graph reads or is read")
     | _ -> ());
    Option.iter (fun tree ->
      add (Head "SHELL · the applied editor graph"); shell_rows 0 acc tree) p.shell;
    Array.of_list (List.rev !acc)
  end

let describe = function
  | Head s -> s
  | Case (t, tag) -> String.concat " | " (t :: tag)
  | Note lines -> String.concat " " lines
  | Input_row { name; value; _ } -> Printf.sprintf "input %s = %g" name value
  | Graph_row { label; detail; active; _ } ->
      Printf.sprintf "%s%s · %s" (if active then "> " else "") label detail
  | Node_row { label; detail; depth; zone; _ } ->
      Printf.sprintf "%s%s%s · %s" (String.make (2 * depth) ' ')
        (match zone with Some z -> z ^ " " | None -> "") label detail
  | Macro_row (name, n) -> Printf.sprintf "λ %s · %s" name (plural n "use")
  | Link_row { label; graph; _ } -> label ^ " " ^ graph
  | Shell_row { depth; label; detail } -> String.make (2 * depth) ' ' ^ label ^ " " ^ detail
  | Empty s -> s

(* ---- drawing ---- *)

let context_color = function
  | Some W.Sop -> Prismel.Color.hex_exn "#2f6ea5"
  | Some Scene -> Prismel.Color.hex_exn "#6a5cb0"
  | Some World -> Prismel.Color.hex_exn "#3f8a55"
  | Some Settings -> Prismel.Color.hex_exn "#b0485a"
  | Some Editor -> Prismel.Color.hex_exn "#b5651d"
  | Some Value -> Prismel.Color.hex_exn "#b5651d"
  | None -> Prismel.Color.hex_exn "#2f6ea5"

let type_color theme (ty : Flow.Ty.t) =
  let ports = Pxui.Theme.ports theme in
  match ty with
  | Geometry -> ports.geometry | Float -> ports.float | Int -> ports.int | Bool -> ports.bool
  | Vec3 -> ports.vec3 | Text -> ports.text | Fn -> ports.fn | Record _ -> ports.record
  | List _ | Color | Any | Scene | World | Settings | Panel | Editor -> ports.compound

let height_of ~rh ~width_chars = function
  | Head _ -> rh +. 8.
  | Case (_, tag) -> rh *. float (2 + List.length tag) +. 8.
  | Note lines -> 16. *. float (List.length (List.concat_map (wrap width_chars) lines)) +. 6.
  | _ -> rh

(* the top of every row below the search field, and the total *)
let tops ~rh ~w rows =
  let width_chars = max 12 (int_of_float ((w -. 20.) /. 7.)) in
  let tops = Array.make (Array.length rows + 1) 0. in
  Array.iteri (fun i r -> tops.(i + 1) <- tops.(i) +. height_of ~rh ~width_chars r) rows;
  tops

let search_height = 32.

let row_rects ?(row_height = 24) state p ~bounds:(x, y, w, _) =
  let rh = float row_height and x = float x and y = float y and w = float w in
  let rows = rows state p in
  let t = tops ~rh ~w rows in
  Array.mapi (fun i r -> r, (x, y +. search_height +. t.(i), w, t.(i + 1) -. t.(i))) rows

let view state ui ~bounds:(x, y, w, h) p =
  let theme = Ui.theme ui in
  let rh = float (Ui.row_height ui) in
  let x = float x and y = float y and w = float w and h = float h in
  let muted = Pxui.Theme.muted theme in
  (* the search field above the list *)
  let query, _ = Ui.value_field ui ~at:(x +. 8., y +. 6.) ~w:(w -. 24.) ~h:21. ~size:11
      ~valid:(fun _ -> true) "navigator-search" state.query in
  let typing = Ui.text_input_focused ui in
  let state = { query; typing } in
  if query = "" && not typing then
    Ui.draw ui (Ui.box ui ~w:(Ui.Px 170.) ~h:(Ui.Px 14.) ~at:(x +. 16., y +. 10.) "navigator-placeholder")
      (fun paint (px, py, _, _) -> Ui.Paint.text paint ~at:(px, py) ~size:11 ~color:muted "Go to node, loop, fun...");
  let rows = rows state p in
  let width_chars = max 12 (int_of_float ((w -. 20.) /. 7.)) in
  let height_of = height_of ~rh ~width_chars in
  let tops = tops ~rh ~w rows in
  let total = tops.(Array.length rows) in
  let top = y +. search_height in
  let body = Float.max rh (h -. search_height) in
  let box = Ui.box ui ~flags:Ui.(clickable + scroll + clip + blocking)
      ~w:(Ui.Px w) ~h:(Ui.Px body) ~at:(x, top) ~scroll_step:rh "navigator-list" in
  let signal = Ui.signal ui box in
  (* the painted position, elastic edge movement included: a click lands on the row it sees *)
  let scroll = Ui.scroll_position ui box in
  (* the rows paint in the child so the list's clip holds them: a box's own painter is not clipped *)
  let content = Ui.within ui box (fun () ->
    Ui.box ui ~w:(Ui.Px w) ~h:(Ui.Px (total +. rh)) "navigator-content") in
  let row_at (_, py) =
    let off = py -. top +. scroll in
    if py < top || off >= total then None
    else begin
      let k = ref 0 in
      while tops.(!k + 1) <= off do incr k done;
      Some !k
    end in
  let intents = ref [] in
  let emit i = intents := i :: !intents in
  (if signal.clicked then match Option.map (fun k -> rows.(k)) (row_at signal.release_point) with
   | Some (Graph_row { graph; _ }) -> emit (Open { graph; node = None })
   | Some (Node_row { graph; path; _ }) -> emit (Open { graph; node = Some path })
   | Some (Link_row { graph; _ }) -> emit (Open { graph; node = None })
   | Some (Macro_row (name, _)) -> emit (Macro name)
   | _ -> ());
  if typing && Ui.key_pressed ui Prismel.Input.Enter then
    (match List.find_map (function
       | Graph_row { graph; _ } -> Some (Open { graph; node = None })
       | Node_row { graph; path; _ } -> Some (Open { graph; node = Some path })
       | _ -> None) (Array.to_list rows) with
     | Some intent -> emit intent | None -> ());
  let hovered = if signal.hovered then row_at signal.pointer else None in
  Ui.draw ui content (fun paint _ ->
    let scroll = Ui.scroll_position ui box in
    Ui.Paint.fill paint ~x ~y:top ~w ~h:body theme.panel;
    Array.iteri (fun k row ->
      let ry = top +. tops.(k) -. scroll and rhh = height_of row in
      if ry +. rhh > top && ry < top +. body then begin
        let text ?(color = theme.foreground) ?(dy = 5.) at label =
          Ui.Paint.text paint ~at:(fst at, ry +. dy) ~color label in
        let tag ~at:tx glyph =
          let tw = Ui.Paint.text_width paint ~size:10 glyph +. 10. in
          Ui.Paint.rect paint ~x:tx ~y:(ry +. 4.) ~w:tw ~h:(rh -. 8.) ~fill:theme.accent ~radius:2. ();
          Ui.Paint.text paint ~at:(tx +. 5., ry +. 7.) ~size:10 ~color:theme.input glyph;
          tx +. tw +. 6. in
        let shade selected =
          if selected then Ui.Paint.fill paint ~x ~y:ry ~w ~h:rhh (Pxui.Theme.pressed_fill theme)
          else if hovered = Some k then
            Ui.Paint.fill paint ~x ~y:ry ~w ~h:rhh (Pxui.Theme.hover_fill theme) in
        let right_text label =
          let tw = Ui.Paint.text_width paint label in
          Ui.Paint.text paint ~at:(x +. w -. tw -. 10., ry +. 5.) ~color:muted label;
          x +. w -. tw -. 16. in
        (* a label with a detail at the right stops short of it instead of running under it *)
        let labelled ?color from label detail =
          let edge = right_text detail in
          text ?color (from, 0.) (Ui.ellipsis ~width:(Ui.Paint.text_width paint) ~limit:(edge -. from) label) in
        match row with
        | Head s ->
            Ui.Paint.text paint ~at:(x +. 8., ry +. rhh -. rh +. 5.) ~color:theme.accent s
        | Case (title, tags) ->
            Ui.Paint.text paint ~at:(x +. 8., ry +. 2.) ~color:muted "CASE STUDY";
            Ui.Paint.text paint ~at:(x +. 8., ry +. rh) ~color:theme.foreground title;
            List.iteri (fun i t ->
              Ui.Paint.text paint ~at:(x +. 8., ry +. rh *. float (i + 2) -. 2.) ~color:muted t) tags
        | Note lines ->
            List.iteri (fun i line ->
              Ui.Paint.text paint ~at:(x +. 8., ry +. 2. +. 16. *. float i) ~color:muted line)
              (List.concat_map (wrap width_chars) lines)
        | Input_row { name; _ } -> text (x +. 8., 0.) ~color:theme.foreground name
        | Graph_row { label; context; detail; active; _ } ->
            shade active;
            Ui.Paint.fill paint ~x:(x +. 8.) ~y:(ry +. 8.) ~w:8. ~h:8. (context_color context);
            labelled (x +. 22.) label detail
        | Node_row { depth; label; detail; zone; ty; result; selected; _ } ->
            shade selected;
            let nx = x +. 22. +. 14. *. float depth in
            (match zone with
             | Some glyph -> labelled (tag ~at:nx glyph) label detail
             | None ->
                 Ui.Paint.fill paint ~x:nx ~y:(ry +. 8.) ~w:8. ~h:8. (type_color theme ty);
                 labelled ~color:(if result then muted else theme.foreground) (nx +. 14.) label detail)
        | Macro_row (name, uses) ->
            shade false;
            text (x +. 8., 0.) ~color:theme.accent "λ";
            labelled (x +. 22.) name (plural uses "use")
        | Link_row { label; graph; _ } ->
            shade false;
            text (x +. 8., 0.) ~color:muted label;
            text (x +. 80., 0.) ~color:theme.accent graph
        | Shell_row { depth; label; detail } ->
            labelled (x +. 8. +. 14. *. float depth) label detail
        | Empty s -> text (x +. 8., 0.) ~color:muted s
      end) rows);
  (* the sliders of the inputs, over their rows *)
  Array.iteri (fun k row -> match row with
    | Input_row { graph; name; integer; value } ->
        let ry = top +. tops.(k) -. scroll in
        if ry >= top && ry +. rh <= top +. body then begin
          let show v = if integer then string_of_int (int_of_float (Float.round v)) else Printf.sprintf "%.3g" v in
          (* a scrub from the value at the press, like a card's field: 1 per 6 points for an
             integer, a hundredth of the magnitude per point for a float, Shift is finer *)
          let scrub origin dx shift = match float_of_string_opt origin with
            | None -> origin
            | Some o when integer -> show (o +. Float.round (dx /. (if shift then 24. else 6.)))
            | Some o -> show (o +. dx *. 0.01 *. Float.max 1. (Float.abs o) *. (if shift then 0.1 else 1.)) in
          let text = show value in
          let changed, _ = Ui.value_field ui ~at:(x +. 76., ry +. 1.) ~w:(w -. 86.) ~h:21. ~size:11
              ~scrub ~valid:(fun t -> float_of_string_opt t <> None)
              ("navigator-input-" ^ graph ^ "-" ^ name) text in
          if changed <> text then
            Option.iter (fun v -> emit (Set_default { graph; input = name; value = v; integer }))
              (float_of_string_opt changed)
        end
    | _ -> ()) rows;
  state, List.rev !intents
