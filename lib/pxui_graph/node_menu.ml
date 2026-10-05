open Procedural
module Ui = Pxui.Ui
module String_set = Set.Make (String)

type entry = {
  key : string; label : string; category : string list; arity : int;
  context : string;  (* the kind's graph: "sop", "value", "scene" ... *)
  output : Flow.Ty.t;  (* what the node makes: the colour of its square *)
  off : string option;  (* why the kind cannot be placed in this graph, if it cannot *)
}

(* a SOP kind makes geometry *)
let entries_of_factories ?(context = "sop") factories = List.map (fun factory -> {
    key = Edit_graph.factory_key factory;
    label = Edit_graph.factory_label factory;
    category = Edit_graph.factory_category factory;
    arity = Edit_graph.factory_arity factory;
    context; output = Flow.Ty.Geometry; off = None }) factories

type item = { entry : entry; lower_key : string; lower_label : string; lower_category : string }
type row = Category of string | Entry of entry

type t = {
  items : item array;
  x : int;
  y : int;
  query : string;
  path : string list;
  after : string option;  (* the node the new one goes after: the title says so *)
}

let menu_width = 320
let position menu = menu.x, menu.y
let menu_limit = 10

let create ?after ~x ~y entries =
  let seen = Hashtbl.create (List.length entries) in
  let items = List.filter (fun entry ->
    if String.trim entry.key = "" || String.trim entry.label = "" || entry.category = []
       || List.exists (fun part -> String.trim part = "") entry.category
       || entry.arity < 0 || Hashtbl.mem seen entry.key then false
    else begin Hashtbl.add seen entry.key (); true end) entries
    |> List.map (fun entry -> { entry;
      lower_key = String.lowercase_ascii entry.key;
      lower_label = String.lowercase_ascii entry.label;
      lower_category = String.lowercase_ascii (String.concat " / " entry.category) }) in
  { items = Array.of_list items; x; y; query = ""; path = []; after }


let search_rank query item =
  let contains text =
    let rec at index = index + String.length query <= String.length text
      && (String.sub text index (String.length query) = query || at (index + 1)) in
    at 0 in
  if String.starts_with ~prefix:query item.lower_label then 0
  else if List.exists (String.starts_with ~prefix:query)
      (String.split_on_char ' ' item.lower_label) then 1
  else if contains item.lower_label || contains item.lower_key then 2
  else if Ui.fuzzy_match ~query item.lower_label || Ui.fuzzy_match ~query item.lower_key then 3
  else 4

let rec category_remainder path category = match path, category with
  | [], category -> Some category
  | expected :: path, actual :: category when expected = actual -> category_remainder path category
  | _ -> None

(* The rows of one column (a category path), or every match of the query. *)
let rows menu =
  let items = Array.to_list menu.items in
  if menu.query <> "" then begin
    let query = String.lowercase_ascii menu.query in
    (* the kinds that cannot be placed here follow the ones that can *)
    items |> List.filter (fun item ->
      Ui.fuzzy_match ~query item.lower_label || Ui.fuzzy_match ~query item.lower_category
      || Ui.fuzzy_match ~query item.lower_key)
    |> List.sort (fun left right ->
      let off item = if item.entry.off = None then 0 else 1 in
      let order = Int.compare (off left) (off right) in
      let order = if order <> 0 then order else Int.compare (search_rank query left) (search_rank query right) in
      if order <> 0 then order else String.compare left.entry.label right.entry.label)
    |> List.map (fun item -> Entry item.entry) |> Array.of_list
  end else
    let items = List.filter (fun item -> item.entry.off = None) items in
    let categories, exact = List.fold_left (fun (categories, exact) item ->
      match category_remainder menu.path item.entry.category with
      | Some (child :: _) -> String_set.add child categories, exact
      | Some [] -> categories, item.entry :: exact
      | None -> categories, exact) (String_set.empty, []) items in
    Array.of_list (List.map (fun c -> Category c) (String_set.elements categories)
      @ List.map (fun entry -> Entry entry)
          (List.sort (fun a b -> String.compare a.label b.label) exact))

let parent_path path = match List.rev path with [] -> [] | _ :: rest -> List.rev rest

(* what a row says on the right: the graph the kind is for and its category ([sop / points]), or why
   it cannot go here *)
let entry_detail entry = match entry.off with
  | Some reason -> reason
  | None ->
      entry.context ^ (match List.rev entry.category with
        | last :: _ -> " / " ^ String.lowercase_ascii last | [] -> "")

(* a row of the results; an unplaceable kind is named by its graph and key *)
let entry_label entry = match entry.off with
  | Some _ -> entry.context ^ "/" ^ entry.key
  | None -> entry.label

(* the colour of a kind's square: its output type's port *)
let port_color theme (ty : Flow.Ty.t) =
  let ports = Pxui.Theme.ports theme in
  match ty with
  | Geometry -> ports.geometry | Float -> ports.float | Int -> ports.int | Vec3 -> ports.vec3
  | Bool -> ports.bool | Text -> ports.text | Fn -> ports.fn | Record _ -> ports.record
  | _ -> ports.compound

let picker_rows menu query =
  rows { menu with path = []; query } |> Array.map (function
    | Category category -> category, "›"
    | Entry entry -> entry_label entry, entry_detail entry)

(* The node menu: a search field over the top-level column. Hovering or clicking a category
   opens its column to the right; clicking an entry picks it. Typing lists every matching
   node instead (arrows and Enter pick). All columns share one popup, so a press in any of
   them keeps it open; a press outside or Escape closes it.  Returns the menu while it stays
   open and the key of the entry picked this frame. *)
let update menu ui ~bounds:(bx, by, bw, bh) =
  let row = Ui.row_height ui in
  let searching = menu.query <> "" in
  let rows_of prefix = rows { menu with path = prefix; query = "" } in
  (* a lone top-level category (the scene's Object, the World's Layer) opens by itself *)
  let base = match rows_of [] with [| Category category |] -> [ category ] | _ -> [] in
  let menu = if menu.path = [] then { menu with path = base } else menu in
  let levels = if searching then []
    else List.init (List.length menu.path + 1 - List.length base) (fun depth ->
      List.filteri (fun index _ -> index < depth + List.length base) menu.path) in
  let shown = if searching then Array.length (rows { menu with path = []; query = "" })
    else List.fold_left (fun most prefix -> max most (Array.length (rows_of prefix))) 0 levels in
  (* the edge, the title (4 above its row), the search row, the rows and the foot (a hairline under 4,
     then a bar) *)
  let height = 2 + (4 + row) + 28 + (min menu_limit shown * row) + (5 + row) in
  let width = max 1 (List.length levels) * menu_width in
  let x = max bx (min menu.x (bx + bw - width)) and y = max by (min menu.y (by + bh - height)) in
  let result = Ui.popup ui ~stroke:(Pxui.Theme.border (Ui.theme ui)) ~at:(float_of_int x, float_of_int y)
      ~width:(float_of_int width) ~height:(float_of_int height) "pxui-graph-menu" (fun () ->
      let theme = Ui.theme ui in
      (* the title row: the label at 12 and, right-aligned 8 from the edge in ink-2 at the label size,
         the node the new one goes after *)
      let title = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px (float_of_int (4 + row))) "pxui-graph-menu-title" in
      Ui.draw ui title (fun paint (x, y, w, h) ->
        let size = Ui.Paint.label_size paint in
        let top = Ui.text_top ui ~size (y +. 4.) (h -. 4.) in
        Ui.Paint.cap paint ~at:(x +. 12., top) "Add node";
        Option.iter (fun name ->
          let text = "after " ^ name in
          Ui.Paint.text paint ~size ~color:(Pxui.Theme.ink_2 theme)
            ~at:(x +. w -. 8. -. Ui.Paint.text_width paint ~size text, top) text) menu.after);
      (* the rows of the query being typed, kept so that a row's square and unavailability are known *)
      let latest = ref [||] in
      let query, pick = Ui.picker ui ~limit:menu_limit "type to search" ~query:menu.query
          ~mark:(fun index -> match (if index < Array.length !latest then Some !latest.(index) else None) with
            | Some (Entry entry) -> Some (port_color theme entry.output)
            | _ -> None)
          ~off:(fun index -> index < Array.length !latest
                  && (match !latest.(index) with Entry { off = Some _; _ } -> true | _ -> false))
          (fun query ->
            let found = if query = "" then [||] else rows { menu with path = []; query } in
            latest := found;
            if query = "" then [||] else picker_rows menu query) in
      (* a cross at the right of the search row clears it *)
      let clear = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px 20.) ~h:(Ui.Px 20.)
          ~at:(float_of_int (x + width - 25), float_of_int (y + 1 + row + 4 + 4)) "pxui-graph-menu-clear" in
      if query <> "" then Ui.draw ui clear (fun paint (cx, cy, _, _) ->
        Ui.Paint.text paint ~at:(cx +. 6.5, Ui.text_top ui cy 20.) ~color:(Pxui.Theme.muted (Ui.theme ui)) "\xc3\x97");
      let query = if (Ui.signal ui clear).clicked then "" else query in
      let hovered = ref None and clicked = ref None in
      if query = "" then
        Ui.row ui "pxui-graph-menu-columns" (fun () ->
          List.iteri (fun depth prefix ->
            let column = Ui.box ui ~flags:Ui.(scroll + clip) ~w:(Ui.Px (float_of_int menu_width))
                ~h:Ui.Fit ~max_h:(float_of_int (menu_limit * row)) ~axis:Ui.Column
                (Printf.sprintf "column-%d" depth) in
            Ui.within ui column (fun () ->
              Array.iteri (fun index item ->
                let item_box = Ui.box ui ~flags:Ui.(clickable + tab_stop + blocking) ~w:Ui.Grow
                    ~h:(Ui.Px (float_of_int row)) (Printf.sprintf "item-%d" index) in
                let signal = Ui.signal ui item_box in
                let label, detail, opened = match item with
                  | Category category ->
                      category, "", List.nth_opt menu.path (depth + List.length base) = Some category
                  | Entry entry -> entry.label, entry_detail entry, false in
                if signal.hovered then hovered := Some (prefix, item);
                if signal.clicked then clicked := Some (prefix, item);
                let theme = Ui.theme ui in
                Ui.draw ui item_box (fun paint (x, y, w, h) ->
                  (* the open category and the row under the pointer: the control fill *)
                  if opened || signal.hovered then Ui.Paint.fill paint ~x ~y ~w ~h theme.control;
                  (* the rows of the sheet: a kind has its type square at 12 and its name at 28, its graph
                     and category at the right; a category has its name at 12 and a chevron *)
                  let text_y = Ui.text_top ui y h in
                  match item with
                  | Category _ ->
                      Ui.Paint.text paint ~at:(x +. 12., text_y) ~color:theme.foreground label;
                      Ui.Paint.chevron paint ~at:(x +. w -. 17., y +. (h /. 2.)) `Right (Pxui.Theme.ink_3 theme)
                  | Entry entry ->
                      let detail_x = x +. w -. 12. -. Ui.Paint.text_width paint detail in
                      Ui.Paint.fill paint ~x:(x +. 12.) ~y:(y +. ((h -. 8.) /. 2.)) ~w:8. ~h:8.
                        (port_color theme entry.output);
                      Ui.Paint.text paint ~at:(x +. 28., text_y) ~color:theme.foreground
                        (Ui.ellipsis ~width:(Ui.Paint.text_width paint) ~limit:(detail_x -. x -. 36.) label);
                      Ui.Paint.text paint ~at:(detail_x, text_y) ~color:(Pxui.Theme.ink_2 theme) detail))
                (rows_of prefix))) levels);
      Ui.footer ui ~right:(Printf.sprintf "%d of %d" (if query = "" then Array.length (rows_of menu.path) else Array.length (rows { menu with path = []; query }))
          (Array.length menu.items)) ["\xe2\x86\x91\xe2\x86\x93", "move"; "\xe2\x86\xb5", "place"];
      query, pick, !hovered, !clicked) in
  let menu, picked = match result with
    | None -> None, None
    | Some (query, pick, hovered, clicked) ->
        let menu = { menu with query } in
        (match pick, clicked, hovered with
         | `Cancel, _, _ -> None, None
         | `Back, _, _ -> Some { menu with path = parent_path menu.path; query = "" }, None
         | `Pick index, _, _ ->
             (match (rows { menu with path = [] }).(index) with
              | Category category -> Some { menu with path = [ category ]; query = "" }, None
              | Entry entry -> None, Some entry.key)
         | _, Some (_, Entry entry), _ -> None, Some entry.key
         | _, Some (prefix, Category category), _
         | _, None, Some (prefix, Category category) -> Some { menu with path = prefix @ [ category ] }, None
         | _, None, Some (prefix, Entry _) when List.length prefix < List.length menu.path ->
             Some { menu with path = prefix }, None
         | _ -> Some menu, None) in
  if menu = None then Ui.dismiss_popup ui;
  menu, picked

module Private = struct
  let keys menu ~query = rows { menu with query } |> Array.to_list |> List.filter_map (function
    | Entry entry -> Some entry.key | Category _ -> None)
end
