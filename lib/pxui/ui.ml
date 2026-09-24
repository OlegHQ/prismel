open Prismel

module Int_table = Hashtbl.Make (Int)
module Batch = Scene_command.Ui_batch

(* ---------------------------------------------------------------- keys *)

(* 63-bit FNV-1a; keys 0 and 1 are the open-addressing empty/tombstone marks. *)
let fnv_prime = 0x100000001b3
let hash_range seed text first last =
  let hash = ref (seed lxor 0x2bf29ce484222325) in
  for index = first to last - 1 do
    hash := (!hash lxor Char.code (String.unsafe_get text index)) * fnv_prime
  done;
  let hash = !hash lxor (!hash lsr 29) in
  if hash = 0 || hash = 1 then hash + 2 else hash

let find_marker text marker =
  let length = String.length text and marker_length = String.length marker in
  let rec search index =
    if index + marker_length > length then None
    else if String.sub text index marker_length = marker then Some index
    else search (index + 1) in
  if String.contains text '#' then search 0 else None

let key_of seed text =
  match find_marker text "###" with
  | Some index -> hash_range 0x5bd1e995 text (index + 3) (String.length text)
  | None -> hash_range seed text 0 (String.length text)

let display text =
  match find_marker text "##" with
  | Some index -> String.sub text 0 index
  | None -> text

(* ------------------------------------------------------ retained cache *)

module Table = struct
  type t = { mutable keys : int array; mutable slots : int array;
    mutable filled : int }

  let create () = { keys = Array.make 256 0; slots = Array.make 256 0; filled = 0 }

  let index table key =
    let mask = Array.length table.keys - 1 in
    let rec probe position =
      let found = Array.unsafe_get table.keys position in
      if found = key || found = 0 then position
      else probe ((position + 1) land mask) in
    probe (key land mask)

  let find table key =
    let position = index table key in
    if Array.unsafe_get table.keys position = key
    then Array.unsafe_get table.slots position else -1

  let rec add table key slot =
    if 10 * (table.filled + 1) > 7 * Array.length table.keys then begin
      let keys = table.keys and slots = table.slots in
      let capacity = if 10 * table.filled > 3 * Array.length keys
        then 2 * Array.length keys else Array.length keys in
      table.keys <- Array.make capacity 0;
      table.slots <- Array.make capacity 0;
      table.filled <- 0;
      Array.iteri (fun position key ->
        if key <> 0 && key <> 1 then add table key slots.(position)) keys
    end;
    let position = index table key in
    if Array.unsafe_get table.keys position <> key then
      table.filled <- table.filled + 1;
    table.keys.(position) <- key;
    table.slots.(position) <- slot

  let remove table key =
    let position = index table key in
    if table.keys.(position) = key then table.keys.(position) <- 1
end

let grow_float values size default =
  if Array.length values >= size then values
  else begin
    let grown = Array.make (max size (2 * Array.length values)) default in
    Array.blit values 0 grown 0 (Array.length values); grown
  end

let grow values size default =
  if Array.length values >= size then values
  else begin
    let grown = Array.make (max size (2 * Array.length values)) default in
    Array.blit values 0 grown 0 (Array.length values); grown
  end

(* ------------------------------------------------------------- boxes *)

type size =
  | Px of float
  | Pct of float
  | Rel of (float -> float)
  | Grow
  | Fit
  | Text

type axis = Row | Column
type flags = int

let none = 0
let clickable = 1
let focusable = 2
let scroll = 4
let clip = 8
let blocking = 16
let add = Stdlib.( + )
let hit_flags = clickable lor focusable lor scroll lor blocking

type rect = float * float * float * float

type paint = {
  owner : ui;
  builder : Batch.Builder.t;
  mutable scale : float;
  mutable tx : float;
  mutable ty : float;
  mutable clip_rect : rect;
}

and painter = paint -> rect -> unit

and snapshot = {
  s_key : int; s_parent : int; s_flags : int; s_w : size; s_h : size;
  s_max_h : float; s_row : bool; s_padding : float; s_gap : float;
  s_at_x : float; s_at_y : float; s_xform : (float * float * float) option;
  s_text : string; s_text_size : int; s_scroll_step : float;
  s_hit : (rect -> rect) option; s_painters : painter list;
  s_overlays : painter list;
}

and cached_subtree = { stamp : int; boxes : snapshot array }

and ui = {
  mutable theme : Theme.t;
  font : Font.t option;
  font_size : int;
  (* retained, by slot *)
  table : Table.t;
  mutable slot_key : int array;
  mutable free : int list;
  mutable next_slot : int;
  mutable touched : int array;
  mutable rx : float array; mutable ry : float array;
  mutable rw : float array; mutable rh : float array;
  mutable hx : float array; mutable hy : float array;
  mutable hw : float array; mutable hh : float array;
  mutable scroll_y : float array;
  mutable state_values : int array;
  mutable text_values : string option array;
  mutable press_time : float array;
  mutable press_x : float array; mutable press_y : float array;
  mutable caches : cached_subtree option array;
  (* per-frame boxes *)
  mutable count : int;
  mutable b_key : int array; mutable b_slot : int array;
  mutable b_parent : int array; mutable b_first : int array;
  mutable b_last : int array; mutable b_next : int array;
  mutable b_flags : int array;
  mutable b_w : size array; mutable b_h : size array;
  mutable b_max_h : float array;
  mutable b_row : bool array;
  mutable b_padding : float array; mutable b_gap : float array;
  mutable b_at_x : float array; mutable b_at_y : float array;
  mutable b_xform : (float * float * float) option array;
  mutable b_text : string array; mutable b_text_size : int array;
  mutable b_scroll_step : float array;
  mutable b_hit : (rect -> rect) option array;
  mutable b_painters : painter list array;
  mutable b_overlays : painter list array;
  (* layout results, in each box's own space *)
  mutable l_x : float array; mutable l_y : float array;
  mutable l_w : float array; mutable l_h : float array;
  mutable l_content : float array; mutable l_gutter : float array;
  mutable l_scale : float array; mutable l_tx : float array;
  mutable l_ty : float array;
  (* build state *)
  mutable parents : int list;
  mutable seeds : int list;
  mutable building : bool;
  mutable frame_number : int;
  mutable density : int;
  mutable kit_row_height : int;
  mutable kit_padding : int;
  (* input *)
  mutable pointer : float * float;
  mutable hot : int;
  mutable active : int;
  mutable active_button : Input.mouse_button;
  mutable active_press : float * float;
  mutable focus : int;
  mutable composition : string;
  mutable command_down : bool;
  mutable shift_down : bool;
  mutable edit_focus : int;
  mutable edit_value : string;
  mutable edit_caret : int;
  mutable edit_anchor : int;
  mutable requested_cursor : [`Horizontal_resize|`Vertical_resize] option;
  (* this frame's raw events and logical size, for modal dismissal *)
  mutable frame_events : Event.t list;
  mutable view_w : float;
  mutable view_h : float;
  (* last laid-out height per modal key, kept while the modal is closed *)
  modal_heights : (int, float) Hashtbl.t;
  signals : accumulator Int_table.t;
  (* previous frame's hit list, in paint order *)
  mutable hit_count : int;
  mutable hit_keys : int array; mutable hit_flags_of : int array;
  mutable hit_x : float array; mutable hit_y : float array;
  mutable hit_w : float array; mutable hit_h : float array;
  (* output *)
  batch_builder : Batch.Builder.t;
  mutable regions : Scene.t;
  mutable scene : Scene.t;
  atlas : atlas;
  mutable destroyed : bool;
}

and accumulator = {
  mutable pressed : bool;
  mutable released : bool;
  mutable clicked : bool;
  mutable double_clicked : bool;
  mutable moved : bool;
  mutable drag_x : float;
  mutable drag_y : float;
  mutable press_point : float * float;
  mutable release_point : float * float;
  mutable button : Input.mouse_button option;
  mutable scroll_x : float;
  mutable scroll_y_steps : float;
  mutable keys : Event.t list;
}

(* ------------------------------------------------------ glyph atlas *)

and atlas = {
  width : int;
  mutable height : int;
  mutable pixels : bytes;
  glyphs : glyph Int_table.t;
  mutable shelf_x : int;
  mutable shelf_y : int;
  mutable shelf_h : int;
  mutable dirty : bool;
  mutable image : Image.t option;
  mutable fonts : (Font.t * int * int) list;
  mutable next_font : int;
}

and glyph = { gx : int; gy : int; gw : int; gh : int; advance : int }

type t = ui

let atlas_width = 1024
let atlas_max_height = 4096

let create_atlas () = {
  width = atlas_width; height = 256;
  pixels = Bytes.make (atlas_width * 256 * 4) '\000';
  glyphs = Int_table.create 512; shelf_x = 0; shelf_y = 0; shelf_h = 0;
  dirty = false; image = None; fonts = []; next_font = 1 }

let font_id atlas font =
  let generation = Font.Private.generation font in
  match List.find_opt (fun (candidate, _, _) -> candidate == font) atlas.fonts with
  | Some (_, id, known) when known = generation -> id
  | Some (_, id, _) ->
      (* A mutated font (style, hinting) rasterizes differently: new glyph ids. *)
      Int_table.filter_map_inplace (fun key glyph ->
        if key lsr 26 = id then None else Some glyph) atlas.glyphs;
      atlas.fonts <- (font, id, generation)
        :: List.filter (fun (candidate, _, _) -> candidate != font) atlas.fonts;
      id
  | None ->
      let id = atlas.next_font in
      atlas.next_font <- add id 1;
      atlas.fonts <- (font, id, generation) :: atlas.fonts;
      id

let reset_atlas atlas =
  Int_table.reset atlas.glyphs;
  Bytes.fill atlas.pixels 0 (Bytes.length atlas.pixels) '\000';
  atlas.shelf_x <- 0; atlas.shelf_y <- 0; atlas.shelf_h <- 0;
  atlas.dirty <- true

(* ponytail: a single shelf-packed page that doubles in height up to 4096
   rows; when that fills, the atlas is cleared and glyphs re-rasterize. *)
let reserve atlas width height =
  let padded_w = add width 1 and padded_h = add height 1 in
  if padded_w > atlas.width then None else begin
    if atlas.shelf_x + padded_w > atlas.width then begin
      atlas.shelf_y <- add atlas.shelf_y atlas.shelf_h;
      atlas.shelf_x <- 0; atlas.shelf_h <- 0
    end;
    if atlas.shelf_y + padded_h > atlas.height then begin
      let height = ref atlas.height in
      while atlas.shelf_y + padded_h > !height && !height < atlas_max_height do
        height := 2 * !height done;
      if atlas.shelf_y + padded_h > !height then reset_atlas atlas
      else begin
        let pixels = Bytes.make (atlas.width * !height * 4) '\000' in
        Bytes.blit atlas.pixels 0 pixels 0 (Bytes.length atlas.pixels);
        atlas.pixels <- pixels; atlas.height <- !height
      end
    end;
    let x = atlas.shelf_x and y = atlas.shelf_y in
    atlas.shelf_x <- add x padded_w;
    atlas.shelf_h <- max atlas.shelf_h padded_h;
    Some (x, y)
  end

let glyph atlas font ~density code =
  let key = ((font_id atlas font * 32 + density) lsl 21) lor code in
  match Int_table.find_opt atlas.glyphs key with
  | Some glyph -> Some glyph
  | None ->
      match Font.Private.glyph ~density font code with
      | Error _ -> None
      | Ok raster ->
          let glyph = if raster.glyph_width = 0 || raster.glyph_height = 0 then
              Some { gx = 0; gy = 0; gw = 0; gh = 0;
                advance = raster.glyph_advance }
            else match reserve atlas raster.glyph_width raster.glyph_height with
              | None -> None
              | Some (gx, gy) ->
                  for row = 0 to raster.glyph_height - 1 do
                    for column = 0 to raster.glyph_width - 1 do
                      let offset = (((add gy row) * atlas.width) + add gx column) * 4 in
                      Bytes.set_int32_le atlas.pixels offset 0x00ffffffl;
                      Bytes.set atlas.pixels (add offset 3)
                        (Bytes.get raster.glyph_alpha
                           ((row * raster.glyph_width) + column))
                    done
                  done;
                  atlas.dirty <- true;
                  Some { gx; gy; gw = raster.glyph_width; gh = raster.glyph_height;
                    advance = raster.glyph_advance } in
          Option.iter (Int_table.replace atlas.glyphs key) glyph;
          glyph

let publish_atlas atlas =
  if atlas.dirty then begin
    atlas.dirty <- false;
    let rgba = Bytes.copy atlas.pixels in
    match atlas.image with
    | Some image ->
        ignore (Prismel_next_resources.Image.replace (Image.Private.resource image)
          ~width:atlas.width ~height:atlas.height ~rgba)
    | None ->
        match Prismel_next_resources.Image.create ~width:atlas.width
            ~height:atlas.height ~rgba with
        | Ok resource -> atlas.image <- Some (Image.Private.of_resource resource)
        | Error _ -> ()
  end

let fallback_fonts = Hashtbl.create 4
let face ui size =
  match size with
  | None when Option.is_some ui.font -> ui.font
  | _ ->
      let size = Option.value size ~default:ui.font_size in
      match Theme.font size with
      | Some font -> Some font
      | None ->
          match Hashtbl.find_opt fallback_fonts size with
          | Some font -> Some font
          | None ->
              match Font.system ~size () with
              | Ok font -> Hashtbl.add fallback_fonts size font; Some font
              | Error _ -> None

let iter_code_points text visit =
  let length = String.length text in
  let rec loop index =
    if index < length then begin
      let decoded = String.get_utf_8_uchar text index in
      visit (Uchar.to_int (Uchar.utf_decode_uchar decoded));
      loop (add index (Uchar.utf_decode_length decoded))
    end in
  loop 0

let text_width_px ui ?size text =
  match face ui size with
  | None -> 0
  | Some font ->
      let total = ref 0 in
      iter_code_points text (fun code ->
        match glyph ui.atlas font ~density:ui.density code with
        | Some glyph -> total := add !total glyph.advance
        | None -> ());
      !total

(* ----------------------------------------------------------- create *)

let create ?(theme = Theme.default) ?font ?(font_size = Theme.font_size) () =
  if font_size <= 0 then invalid_arg "Ui.create: font_size must be positive";
  let capacity = 64 in
  { theme; font; font_size; table = Table.create ();
    slot_key = Array.make capacity 0; free = []; next_slot = 0;
    touched = Array.make capacity (-1);
    rx = Array.make capacity 0.; ry = Array.make capacity 0.;
    rw = Array.make capacity 0.; rh = Array.make capacity 0.;
    hx = Array.make capacity 0.; hy = Array.make capacity 0.;
    hw = Array.make capacity 0.; hh = Array.make capacity 0.;
    scroll_y = Array.make capacity 0.;
    state_values = Array.make capacity min_int;
    text_values = Array.make capacity None;
    press_time = Array.make capacity Float.neg_infinity;
    press_x = Array.make capacity 0.; press_y = Array.make capacity 0.;
    caches = Array.make capacity None;
    count = 0;
    b_key = Array.make capacity 0; b_slot = Array.make capacity 0;
    b_parent = Array.make capacity (-1); b_first = Array.make capacity (-1);
    b_last = Array.make capacity (-1); b_next = Array.make capacity (-1);
    b_flags = Array.make capacity 0;
    b_w = Array.make capacity Grow; b_h = Array.make capacity Grow;
    b_max_h = Array.make capacity Float.infinity;
    b_row = Array.make capacity false;
    b_padding = Array.make capacity 0.; b_gap = Array.make capacity 0.;
    b_at_x = Array.make capacity Float.nan; b_at_y = Array.make capacity Float.nan;
    b_xform = Array.make capacity None;
    b_text = Array.make capacity ""; b_text_size = Array.make capacity 0;
    b_scroll_step = Array.make capacity 0.;
    b_hit = Array.make capacity None;
    b_painters = Array.make capacity []; b_overlays = Array.make capacity [];
    l_x = Array.make capacity 0.; l_y = Array.make capacity 0.;
    l_w = Array.make capacity 0.; l_h = Array.make capacity 0.;
    l_content = Array.make capacity 0.; l_gutter = Array.make capacity 0.;
    l_scale = Array.make capacity 1.; l_tx = Array.make capacity 0.;
    l_ty = Array.make capacity 0.;
    parents = []; seeds = []; building = false; frame_number = 0; density = 1;
    kit_row_height = 24; kit_padding = 3;
    pointer = (Float.nan, Float.nan); hot = 0; active = 0;
    active_button = Input.LeftButton; active_press = (0., 0.); focus = 0; composition = "";
    command_down = false; shift_down = false;
    edit_focus = 0; edit_value = ""; edit_caret = 0; edit_anchor = 0;
    requested_cursor = None;
    frame_events = []; view_w = 0.; view_h = 0.; modal_heights = Hashtbl.create 4;
    signals = Int_table.create 16;
    hit_count = 0; hit_keys = [||]; hit_flags_of = [||];
    hit_x = [||]; hit_y = [||]; hit_w = [||]; hit_h = [||];
    batch_builder = Batch.Builder.create ~capacity:1024 ();
    regions = []; scene = []; atlas = create_atlas (); destroyed = false }

let destroy ui =
  if not ui.destroyed then begin
    ui.destroyed <- true;
    Option.iter Image.destroy ui.atlas.image;
    ui.atlas.image <- None;
    ui.scene <- []
  end

let theme ui = ui.theme
let set_theme ui theme = ui.theme <- theme
let font_size ui = ui.font_size
let scene ui = ui.scene
let row_height ui = ui.kit_row_height
let panel_padding ui = ui.kit_padding

(* ----------------------------------------------------- retained slots *)

let ensure_slot_capacity ui size =
  if size > Array.length ui.slot_key then begin
    ui.slot_key <- grow ui.slot_key size 0;
    ui.touched <- grow ui.touched size (-1);
    ui.rx <- grow_float ui.rx size 0.; ui.ry <- grow_float ui.ry size 0.;
    ui.rw <- grow_float ui.rw size 0.; ui.rh <- grow_float ui.rh size 0.;
    ui.hx <- grow_float ui.hx size 0.; ui.hy <- grow_float ui.hy size 0.;
    ui.hw <- grow_float ui.hw size 0.; ui.hh <- grow_float ui.hh size 0.;
    ui.scroll_y <- grow_float ui.scroll_y size 0.;
    ui.state_values <- grow ui.state_values size min_int;
    ui.text_values <- grow ui.text_values size None;
    ui.press_time <- grow_float ui.press_time size Float.neg_infinity;
    ui.press_x <- grow_float ui.press_x size 0.;
    ui.press_y <- grow_float ui.press_y size 0.;
    ui.caches <- grow ui.caches size None
  end

let slot_of ui key =
  let slot = Table.find ui.table key in
  if slot >= 0 then slot
  else begin
    let slot = match ui.free with
      | slot :: rest -> ui.free <- rest; slot
      | [] -> let slot = ui.next_slot in ui.next_slot <- add slot 1; slot in
    ensure_slot_capacity ui (add slot 1);
    ui.slot_key.(slot) <- key;
    ui.touched.(slot) <- ui.frame_number;
    ui.rx.(slot) <- 0.; ui.ry.(slot) <- 0.; ui.rw.(slot) <- 0.; ui.rh.(slot) <- 0.;
    ui.hx.(slot) <- 0.; ui.hy.(slot) <- 0.; ui.hw.(slot) <- 0.; ui.hh.(slot) <- 0.;
    ui.scroll_y.(slot) <- 0.; ui.state_values.(slot) <- min_int;
    ui.text_values.(slot) <- None; ui.press_time.(slot) <- Float.neg_infinity;
    ui.caches.(slot) <- None;
    Table.add ui.table key slot;
    slot
  end

let prune ui =
  for slot = 0 to ui.next_slot - 1 do
    let key = ui.slot_key.(slot) in
    if key <> 0 && ui.touched.(slot) < ui.frame_number then begin
      Table.remove ui.table key;
      ui.slot_key.(slot) <- 0;
      ui.text_values.(slot) <- None;
      ui.caches.(slot) <- None;
      ui.free <- slot :: ui.free;
      if ui.focus = key then begin
        ui.focus <- 0; ui.composition <- ""; ui.edit_focus <- 0
      end;
      if ui.active = key then ui.active <- 0
    end
  done

(* -------------------------------------------------------------- input *)

let contains (x, y, w, h) (px, py) = px >= x && py >= y && px < x +. w && py < y +. h

let accumulator ui key =
  match Int_table.find_opt ui.signals key with
  | Some value -> value
  | None ->
      let value = { pressed = false; released = false; clicked = false;
        double_clicked = false; moved = false; drag_x = 0.; drag_y = 0.;
        press_point = (0., 0.); release_point = (0., 0.); button = None;
        scroll_x = 0.; scroll_y_steps = 0.; keys = [] } in
      Int_table.replace ui.signals key value;
      value

let hit_index ui key =
  let rec search index =
    if index < 0 then -1
    else if ui.hit_keys.(index) = key then index
    else search (index - 1) in
  search (ui.hit_count - 1)

let hit_contains ui index point =
  contains (ui.hit_x.(index), ui.hit_y.(index), ui.hit_w.(index), ui.hit_h.(index))
    point

(* Topmost hit entry under [point]; [0] when none. *)
let topmost ui point =
  let rec search index =
    if index < 0 then 0
    else if hit_contains ui index point then ui.hit_keys.(index)
    else search (index - 1) in
  search (ui.hit_count - 1)

let flags_of_key ui key =
  let index = hit_index ui key in
  if index < 0 then 0 else ui.hit_flags_of.(index)

let scroll_target ui point =
  let rec search index =
    if index < 0 then 0
    else if not (hit_contains ui index point) then search (index - 1)
    else if ui.hit_flags_of.(index) land scroll <> 0 then ui.hit_keys.(index)
    else if ui.hit_flags_of.(index) land blocking <> 0 then 0
    else search (index - 1) in
  search (ui.hit_count - 1)

let route ui (frame : Frame.t) =
  Int_table.reset ui.signals;
  ui.requested_cursor <- None;
  ui.frame_events <- frame.events;
  ui.command_down <- List.mem Input.Meta frame.keys || List.mem Input.Ctrl frame.keys;
  ui.shift_down <- List.mem Input.Shift frame.keys;
  ui.view_w <- float frame.width; ui.view_h <- float frame.height;
  let set_pointer (x, y) = ui.pointer <- (float x, float y) in
  List.iter (fun (event : Event.t) -> match event with
    | Event.MouseMoved point ->
        let px, py = ui.pointer in
        set_pointer point;
        if ui.active <> 0 then begin
          let value = accumulator ui ui.active in
          let x, y = ui.pointer in
          if Float.is_finite px then begin
            value.drag_x <- value.drag_x +. (x -. px);
            value.drag_y <- value.drag_y +. (y -. py)
          end;
          value.moved <- true
        end
    | Event.MousePressed (button, point) ->
        set_pointer point;
        let target = topmost ui ui.pointer in
        let flags = flags_of_key ui target in
        if button = Input.LeftButton then begin
          let focus = if flags land focusable <> 0 then target else 0 in
          if focus <> ui.focus then begin
            ui.composition <- ""; ui.edit_focus <- 0
          end;
          ui.focus <- focus
        end;
        if flags land clickable <> 0 && ui.active = 0 then begin
          ui.active <- target; ui.active_button <- button;
          ui.active_press <- ui.pointer;
          let value = accumulator ui target in
          value.pressed <- true;
          value.press_point <- ui.pointer;
          value.button <- Some button;
          let slot = Table.find ui.table target in
          if slot >= 0 && button = Input.LeftButton then begin
            let x, y = ui.pointer in
            let dx = x -. ui.press_x.(slot) and dy = y -. ui.press_y.(slot) in
            if frame.time >= ui.press_time.(slot)
                && frame.time -. ui.press_time.(slot) <= 0.35
                && (dx *. dx) +. (dy *. dy) <= 25. then begin
              value.double_clicked <- true;
              ui.press_time.(slot) <- Float.neg_infinity
            end else ui.press_time.(slot) <- frame.time;
            ui.press_x.(slot) <- x; ui.press_y.(slot) <- y
          end
        end
    | Event.MouseReleased (button, point) ->
        set_pointer point;
        if ui.active <> 0 && button = ui.active_button then begin
          let value = accumulator ui ui.active in
          value.released <- true;
          value.release_point <- ui.pointer;
          value.press_point <- ui.active_press;
          value.button <- Some button;
          let index = hit_index ui ui.active in
          if button = Input.LeftButton && index >= 0
             && hit_contains ui index ui.pointer
             && hit_contains ui index ui.active_press
          then value.clicked <- true;
          ui.active <- 0
        end
    | Event.MouseScrolled (horizontal, vertical) ->
        let target = scroll_target ui ui.pointer in
        if target <> 0 then begin
          let value = accumulator ui target in
          value.scroll_x <- value.scroll_x +. horizontal;
          value.scroll_y_steps <- value.scroll_y_steps +. vertical
        end
    | Event.PointerCancelled button ->
        if ui.active <> 0 && button = ui.active_button then begin
          (accumulator ui ui.active).released <- true;
          ui.active <- 0
        end
    | Event.WindowFocusLost ->
        if ui.active <> 0 then (accumulator ui ui.active).released <- true;
        ui.active <- 0; ui.focus <- 0; ui.hot <- 0; ui.composition <- "";
        ui.edit_focus <- 0
    | Event.KeyPressed _ | Event.KeyReleased _ | Event.TextInput _
    | Event.TextEditing _ ->
        if ui.focus <> 0 then begin
          let value = accumulator ui ui.focus in
          value.keys <- event :: value.keys;
          (match event with
           | Event.TextEditing { text; _ } -> ui.composition <- text
           | Event.TextInput _ -> ui.composition <- ""
           | _ -> ())
        end
    | _ -> ()) frame.events;
  Int_table.iter (fun _ value -> value.keys <- List.rev value.keys) ui.signals;
  let mouse_x, mouse_y = frame.mouse in
  if not (Float.is_finite (fst ui.pointer)) then
    ui.pointer <- (float mouse_x, float mouse_y);
  ui.hot <- (if List.exists (function Event.WindowFocusLost -> true | _ -> false)
      frame.events then 0 else topmost ui ui.pointer)

let wants_pointer ui = ui.hot <> 0 || ui.active <> 0
let cursor ui = ui.requested_cursor
let request_cursor ui shape = ui.requested_cursor <- Some shape
let text_input_focused ui = ui.focus <> 0
let unfocus ui = ui.focus <- 0; ui.composition <- ""; ui.edit_focus <- 0

(* -------------------------------------------------------------- boxes *)

type box = { index : int; box_key : int; box_slot : int }

let key box = box.box_key

let ensure_box_capacity ui size =
  if size > Array.length ui.b_key then begin
    ui.b_key <- grow ui.b_key size 0; ui.b_slot <- grow ui.b_slot size 0;
    ui.b_parent <- grow ui.b_parent size (-1);
    ui.b_first <- grow ui.b_first size (-1);
    ui.b_last <- grow ui.b_last size (-1);
    ui.b_next <- grow ui.b_next size (-1);
    ui.b_flags <- grow ui.b_flags size 0;
    ui.b_w <- grow ui.b_w size Grow; ui.b_h <- grow ui.b_h size Grow;
    ui.b_max_h <- grow_float ui.b_max_h size Float.infinity;
    ui.b_row <- grow ui.b_row size false;
    ui.b_padding <- grow_float ui.b_padding size 0.;
    ui.b_gap <- grow_float ui.b_gap size 0.;
    ui.b_at_x <- grow_float ui.b_at_x size Float.nan;
    ui.b_at_y <- grow_float ui.b_at_y size Float.nan;
    ui.b_xform <- grow ui.b_xform size None;
    ui.b_text <- grow ui.b_text size "";
    ui.b_text_size <- grow ui.b_text_size size 0;
    ui.b_scroll_step <- grow_float ui.b_scroll_step size 0.;
    ui.b_hit <- grow ui.b_hit size None;
    ui.b_painters <- grow ui.b_painters size [];
    ui.b_overlays <- grow ui.b_overlays size [];
    ui.l_x <- grow_float ui.l_x size 0.; ui.l_y <- grow_float ui.l_y size 0.;
    ui.l_w <- grow_float ui.l_w size 0.; ui.l_h <- grow_float ui.l_h size 0.;
    ui.l_content <- grow_float ui.l_content size 0.;
    ui.l_gutter <- grow_float ui.l_gutter size 0.;
    ui.l_scale <- grow_float ui.l_scale size 1.;
    ui.l_tx <- grow_float ui.l_tx size 0.;
    ui.l_ty <- grow_float ui.l_ty size 0.
  end

let require_building ui =
  if not ui.building then invalid_arg "Ui: boxes must be built inside Ui.frame"

let current_parent ui = match ui.parents with parent :: _ -> parent | [] -> 0
let current_seed ui = match ui.seeds with seed :: _ -> seed | [] -> 0

(* Two boxes with one key in a frame get distinct, order-stable keys. *)
let unique_key ui key =
  let rec loop key attempt =
    let slot = Table.find ui.table key in
    if slot >= 0 && ui.touched.(slot) = ui.frame_number
    then loop (hash_range key "#dup" 0 4) (add attempt 1)
    else key in
  loop key 0

let append_box ui ~key ~parent =
  let index = ui.count in
  ensure_box_capacity ui (add index 1);
  ui.count <- add index 1;
  let slot = slot_of ui key in
  ui.touched.(slot) <- ui.frame_number;
  ui.b_key.(index) <- key; ui.b_slot.(index) <- slot;
  ui.b_parent.(index) <- parent; ui.b_first.(index) <- -1;
  ui.b_last.(index) <- -1; ui.b_next.(index) <- -1;
  if parent >= 0 then begin
    if ui.b_last.(parent) < 0 then ui.b_first.(parent) <- index
    else ui.b_next.(ui.b_last.(parent)) <- index;
    ui.b_last.(parent) <- index
  end;
  index

let set_box ui index ~flags ~w ~h ~max_h ~row ~padding ~gap ~at_x ~at_y ~xform
    ~text ~text_size ~scroll_step ~hit =
  ui.b_flags.(index) <- flags; ui.b_w.(index) <- w; ui.b_h.(index) <- h;
  ui.b_max_h.(index) <- max_h; ui.b_row.(index) <- row;
  ui.b_padding.(index) <- padding; ui.b_gap.(index) <- gap;
  ui.b_at_x.(index) <- at_x; ui.b_at_y.(index) <- at_y;
  ui.b_xform.(index) <- xform; ui.b_text.(index) <- text;
  ui.b_text_size.(index) <- text_size; ui.b_scroll_step.(index) <- scroll_step;
  ui.b_hit.(index) <- hit; ui.b_painters.(index) <- [];
  ui.b_overlays.(index) <- []

let box ui ?(flags = none) ?(w = Grow) ?(h = Fit) ?(max_h = Float.infinity)
    ?(axis = Column) ?(padding = 0.) ?(gap = 0.) ?at ?xform ?(text = "")
    ?(text_size = 0) ?(scroll_step = 24.) ?hit label =
  require_building ui;
  let key = unique_key ui (key_of (current_seed ui) label) in
  let index = append_box ui ~key ~parent:(current_parent ui) in
  let at_x, at_y = match at with Some (x, y) -> x, y | None -> Float.nan, Float.nan in
  set_box ui index ~flags ~w ~h ~max_h ~row:(axis = Row) ~padding ~gap ~at_x ~at_y
    ~xform ~text ~text_size ~scroll_step ~hit;
  { index; box_key = key; box_slot = ui.b_slot.(index) }

let within ui box f =
  require_building ui;
  let parents = ui.parents and seeds = ui.seeds in
  ui.parents <- box.index :: parents;
  ui.seeds <- box.box_key :: seeds;
  Fun.protect ~finally:(fun () -> ui.parents <- parents; ui.seeds <- seeds) f

let scope ui label f =
  require_building ui;
  let seeds = ui.seeds in
  ui.seeds <- key_of (current_seed ui) label :: seeds;
  Fun.protect ~finally:(fun () -> ui.seeds <- seeds) f

let rect ui box = ui.rx.(box.box_slot), ui.ry.(box.box_slot),
  ui.rw.(box.box_slot), ui.rh.(box.box_slot)
let hit_rect ui box = ui.hx.(box.box_slot), ui.hy.(box.box_slot),
  ui.hw.(box.box_slot), ui.hh.(box.box_slot)

type signal = {
  hovered : bool;
  pressed : bool;
  held : bool;
  released : bool;
  clicked : bool;
  double_clicked : bool;
  dragging : bool;
  drag : float * float;
  pointer : float * float;
  press_point : float * float;
  release_point : float * float;
  button : Input.mouse_button option;
  scroll : float * float;
  keys : Event.t list;
}

let signal ui box =
  let key = box.box_key in
  let held = ui.active = key in
  match Int_table.find_opt ui.signals key with
  | None ->
      { hovered = ui.hot = key; pressed = false; held; released = false;
        clicked = false; double_clicked = false; dragging = false;
        drag = (0., 0.); pointer = ui.pointer;
        press_point = (if held then ui.active_press
          else (ui.press_x.(box.box_slot), ui.press_y.(box.box_slot)));
        release_point = ui.pointer;
        button = (if held then Some ui.active_button else None);
        scroll = (0., 0.); keys = [] }
  | Some value ->
      { hovered = ui.hot = key; pressed = value.pressed; held;
        released = value.released; clicked = value.clicked;
        double_clicked = value.double_clicked;
        dragging = value.moved && (held || value.released);
        drag = (value.drag_x, value.drag_y); pointer = ui.pointer;
        press_point = (if value.pressed || value.released then value.press_point
          else if held then ui.active_press
          else (ui.press_x.(box.box_slot), ui.press_y.(box.box_slot)));
        release_point = value.release_point;
        button = (match value.button with
          | Some _ as button -> button
          | None -> if held then Some ui.active_button else None);
        scroll = (value.scroll_x, value.scroll_y_steps);
        keys = value.keys }

let focused ui box = ui.focus = box.box_key
let focus ui box =
  if ui.focus <> box.box_key then begin
    ui.composition <- ""; ui.edit_focus <- 0
  end;
  ui.focus <- box.box_key
let active ui box = ui.active = box.box_key

let scroll_offset ui box = ui.scroll_y.(box.box_slot)
let set_scroll_offset ui box value = ui.scroll_y.(box.box_slot) <- value

let state ui box ~default =
  let value = ui.state_values.(box.box_slot) in
  if value = min_int then default else value
let set_state ui box value = ui.state_values.(box.box_slot) <- value
let text_state ui box = ui.text_values.(box.box_slot)
let set_text_state ui box value = ui.text_values.(box.box_slot) <- value

let draw ui box painter =
  ui.b_painters.(box.index) <- painter :: ui.b_painters.(box.index)
let draw_over ui box painter =
  ui.b_overlays.(box.index) <- painter :: ui.b_overlays.(box.index)

(* ------------------------------------------------------------- cached *)

let snapshot_box ui index parent_offset =
  { s_key = ui.b_key.(index);
    s_parent = (if ui.b_parent.(index) < 0 then -1
      else ui.b_parent.(index) - parent_offset);
    s_flags = ui.b_flags.(index); s_w = ui.b_w.(index); s_h = ui.b_h.(index);
    s_max_h = ui.b_max_h.(index); s_row = ui.b_row.(index);
    s_padding = ui.b_padding.(index); s_gap = ui.b_gap.(index);
    s_at_x = ui.b_at_x.(index); s_at_y = ui.b_at_y.(index);
    s_xform = ui.b_xform.(index); s_text = ui.b_text.(index);
    s_text_size = ui.b_text_size.(index);
    s_scroll_step = ui.b_scroll_step.(index); s_hit = ui.b_hit.(index);
    s_painters = ui.b_painters.(index); s_overlays = ui.b_overlays.(index) }

let cached ui ~key:label ~stamp f =
  let container = box ui ~w:Grow ~h:Fit label in
  let slot = container.box_slot in
  match ui.caches.(slot) with
  | Some cache when cache.stamp = stamp ->
      (* Replay: parents inside the subtree are relative to the container. *)
      Array.iter (fun (entry : snapshot) ->
        let parent = if entry.s_parent < 0 then container.index
          else add container.index entry.s_parent in
        let index = append_box ui ~key:entry.s_key ~parent in
        set_box ui index ~flags:entry.s_flags ~w:entry.s_w ~h:entry.s_h
          ~max_h:entry.s_max_h ~row:entry.s_row ~padding:entry.s_padding
          ~gap:entry.s_gap ~at_x:entry.s_at_x ~at_y:entry.s_at_y
          ~xform:entry.s_xform ~text:entry.s_text ~text_size:entry.s_text_size
          ~scroll_step:entry.s_scroll_step ~hit:entry.s_hit;
        ui.b_painters.(index) <- entry.s_painters;
        ui.b_overlays.(index) <- entry.s_overlays) cache.boxes
  | Some _ | None ->
      let first = ui.count in
      within ui container f;
      let boxes = Array.init (ui.count - first) (fun offset ->
        let index = add first offset in
        let entry = snapshot_box ui index container.index in
        if ui.b_parent.(index) = container.index
        then { entry with s_parent = -1 } else entry) in
      ui.caches.(slot) <- Some { stamp; boxes }

(* ------------------------------------------------------------- layout *)

let children ui index visit =
  let child = ref ui.b_first.(index) in
  while !child >= 0 do visit !child; child := ui.b_next.(!child) done

let flow ui index = Float.is_nan ui.b_at_x.(index)

let text_extent ui index row =
  let text = ui.b_text.(index) in
  if text = "" then 0.
  else if row then
    float (text_width_px ui ?size:(if ui.b_text_size.(index) > 0
      then Some ui.b_text_size.(index) else None) text) /. float ui.density
  else float (if ui.b_text_size.(index) > 0 then ui.b_text_size.(index)
    else ui.font_size) *. 1.3

(* Bottom-up: fixed, text, and fit sizes. Children follow their parent in
   build order, so a reverse sweep sees every child first. *)
let intrinsic ui =
  for index = ui.count - 1 downto 0 do
    let padding = ui.b_padding.(index) and gap = ui.b_gap.(index)
    and row = ui.b_row.(index) in
    let along = ref 0. and across = ref 0. and flow_count = ref 0 in
    children ui index (fun child ->
      if flow ui child then begin
        incr flow_count;
        let cw = ui.l_w.(child) and ch = ui.l_h.(child) in
        if row then (along := !along +. cw; across := Float.max !across ch)
        else (along := !along +. ch; across := Float.max !across cw)
      end);
    let gaps = gap *. float (max 0 (!flow_count - 1)) in
    let content_w = (if row then !along +. gaps else !across) +. (2. *. padding)
    and content_h = (if row then !across else !along +. gaps) +. (2. *. padding) in
    ui.l_content.(index) <- content_h;
    let resolve kind content horizontal = match kind with
      | Px value -> value
      | Fit -> content
      | Text -> text_extent ui index horizontal +. (2. *. padding)
      | Pct _ | Rel _ | Grow -> 0. in
    ui.l_w.(index) <- resolve ui.b_w.(index) content_w true;
    ui.l_h.(index) <- Float.min ui.b_max_h.(index)
        (resolve ui.b_h.(index) content_h false)
  done

(* Top-down: relative sizes, grow shares, scroll gutters, and positions. *)
let arrange ui =
  ui.l_x.(0) <- 0.; ui.l_y.(0) <- 0.;
  ui.l_scale.(0) <- 1.; ui.l_tx.(0) <- 0.; ui.l_ty.(0) <- 0.;
  for index = 0 to ui.count - 1 do
    let padding = ui.b_padding.(index) and row = ui.b_row.(index) in
    let scrolls = ui.b_flags.(index) land scroll <> 0 in
    let max_scroll = Float.max 0. (ui.l_content.(index) -. ui.l_h.(index)) in
    let gutter = if scrolls && max_scroll > 0. then 10. else 0. in
    ui.l_gutter.(index) <- gutter;
    let slot = ui.b_slot.(index) in
    if scrolls then
      ui.scroll_y.(slot) <- Float.max 0. (Float.min max_scroll ui.scroll_y.(slot));
    (* Children live in this box's space, or in its canvas. *)
    let canvas = ui.b_xform.(index) in
    let child_scale, child_tx, child_ty, origin_x, origin_y, unit = match canvas with
      | None -> ui.l_scale.(index), ui.l_tx.(index), ui.l_ty.(index),
          ui.l_x.(index), ui.l_y.(index), 1.
      | Some (scale, tx, ty) ->
          ui.l_scale.(index) *. scale,
          ui.l_tx.(index) +. (ui.l_scale.(index) *. (ui.l_x.(index) +. tx)),
          ui.l_ty.(index) +. (ui.l_scale.(index) *. (ui.l_y.(index) +. ty)),
          0., 0., scale in
    let inner_w = (ui.l_w.(index) -. (2. *. padding) -. gutter) /. unit
    and inner_h = (ui.l_h.(index) -. (2. *. padding)) /. unit in
    let relative kind inner current = match kind with
      | Pct fraction -> inner *. fraction
      | Rel f -> f inner
      | Px _ | Fit | Text | Grow -> current in
    let fixed = ref 0. and grow_count = ref 0 and flow_count = ref 0 in
    children ui index (fun child ->
      ui.l_scale.(child) <- child_scale;
      ui.l_tx.(child) <- child_tx; ui.l_ty.(child) <- child_ty;
      ui.l_w.(child) <- relative ui.b_w.(child) inner_w ui.l_w.(child);
      ui.l_h.(child) <- Float.min ui.b_max_h.(child)
        (relative ui.b_h.(child) inner_h ui.l_h.(child));
      if flow ui child then begin
        incr flow_count;
        let kind = if row then ui.b_w.(child) else ui.b_h.(child) in
        if kind = Grow then incr grow_count
        else fixed := !fixed +. (if row then ui.l_w.(child) else ui.l_h.(child))
      end);
    let gaps = ui.b_gap.(index) *. float (max 0 (!flow_count - 1)) in
    let share = if !grow_count = 0 then 0.
      else Float.max 0. (((if row then inner_w else inner_h) -. !fixed -. gaps)
        /. float !grow_count) in
    let cursor = ref (padding /. unit) in
    let scroll_offset = if scrolls then ui.scroll_y.(slot) else 0. in
    children ui index (fun child ->
      if row then begin
        if ui.b_w.(child) = Grow && flow ui child then ui.l_w.(child) <- share;
        if ui.b_h.(child) = Grow then
          ui.l_h.(child) <- Float.min ui.b_max_h.(child) inner_h
      end else begin
        if ui.b_h.(child) = Grow && flow ui child then
          ui.l_h.(child) <- Float.min ui.b_max_h.(child) share;
        if ui.b_w.(child) = Grow then ui.l_w.(child) <- inner_w
      end;
      if flow ui child then begin
        if row then begin
          ui.l_x.(child) <- origin_x +. !cursor;
          ui.l_y.(child) <- origin_y +. (padding /. unit) -. scroll_offset;
          cursor := !cursor +. ui.l_w.(child) +. ui.b_gap.(index)
        end else begin
          ui.l_x.(child) <- origin_x +. (padding /. unit);
          ui.l_y.(child) <- origin_y +. !cursor -. scroll_offset;
          cursor := !cursor +. ui.l_h.(child) +. ui.b_gap.(index)
        end
      end else begin
        ui.l_x.(child) <- origin_x +. ui.b_at_x.(child);
        ui.l_y.(child) <- origin_y +. ui.b_at_y.(child)
      end)
  done

let screen ui index =
  let scale = ui.l_scale.(index) in
  (ui.l_x.(index) *. scale) +. ui.l_tx.(index),
  (ui.l_y.(index) *. scale) +. ui.l_ty.(index),
  ui.l_w.(index) *. scale, ui.l_h.(index) *. scale

let intersect (ax, ay, aw, ah) (bx, by, bw, bh) =
  let x = Float.max ax bx and y = Float.max ay by in
  let right = Float.min (ax +. aw) (bx +. bw)
  and bottom = Float.min (ay +. ah) (by +. bh) in
  x, y, Float.max 0. (right -. x), Float.max 0. (bottom -. y)

(* ----------------------------------------------------------- painting *)

let packed (color : Color.t) =
  Int32.logor (Int32.shift_left (Int32.of_int color.r) 24)
    (Int32.logor (Int32.shift_left (Int32.of_int color.g) 16)
       (Int32.logor (Int32.shift_left (Int32.of_int color.b) 8)
          (Int32.of_int color.a)))

module Paint = struct
  type t = paint

  let prepare paint =
    Batch.Builder.set_xform paint.builder
      { Batch.scale = paint.scale; tx = paint.tx; ty = paint.ty };
    let x, y, w, h = paint.clip_rect in
    Batch.Builder.set_clip paint.builder
      (Some { Batch.x; y; width = w; height = h })

  let fill paint ~x ~y ~w ~h ?(radius = 0.) color =
    prepare paint;
    Batch.Builder.rect paint.builder ~x ~y ~width:w ~height:h
      ~color:(packed color) ~radius ()

  let stroke paint ~x ~y ~w ~h ?(width = 1.) ?(radius = 0.) color =
    prepare paint;
    Batch.Builder.rect paint.builder ~x ~y ~width:w ~height:h
      ~border_color:(packed color) ~border:width ~radius ()

  let rect paint ~x ~y ~w ~h ?fill:fill_color ?stroke:stroke_color ?radius () =
    let fill_color = match fill_color, stroke_color with
      | None, None -> Some Color.white | _ -> fill_color in
    Option.iter (fill paint ~x ~y ~w ~h ?radius) fill_color;
    Option.iter (stroke paint ~x ~y ~w ~h ?radius) stroke_color

  let wire paint p0 p1 p2 p3 ?(width = 1.) color =
    prepare paint;
    Batch.Builder.wire paint.builder p0 p1 p2 p3 ~width ~color:(packed color)

  let line paint ~from_:(x0, y0) ~to_:(x1, y1) ?(width = 1.) color =
    let half = width /. 2. in
    if x0 = x1 then
      fill paint ~x:(x0 -. half) ~y:(Float.min y0 y1) ~w:width
        ~h:(Float.abs (y1 -. y0)) color
    else if y0 = y1 then
      fill paint ~x:(Float.min x0 x1) ~y:(y0 -. half) ~w:(Float.abs (x1 -. x0))
        ~h:width color
    else
      wire paint (x0, y0)
        (x0 +. ((x1 -. x0) /. 3.), y0 +. ((y1 -. y0) /. 3.))
        (x0 +. (2. *. (x1 -. x0) /. 3.), y0 +. (2. *. (y1 -. y0) /. 3.))
        (x1, y1) ~width color

  let circle paint ~at:(cx, cy) ~radius ?fill:fill_color ?stroke:stroke_color () =
    prepare paint;
    let fill_color = match fill_color, stroke_color with
      | None, None -> Some Color.white | _ -> fill_color in
    Batch.Builder.rect paint.builder ~x:(cx -. radius) ~y:(cy -. radius)
      ~width:(2. *. radius) ~height:(2. *. radius)
      ~color:(Option.fold ~none:0l ~some:packed fill_color)
      ~border_color:(Option.fold ~none:0l ~some:packed stroke_color)
      ~border:(if Option.is_some stroke_color then 1. else 0.)
      ~radius ~anti_alias:true ()

  let arc paint ~at:(cx, cy) ~radius ~from_ ~to_ ?(width = 1.) color =
    let span = to_ -. from_ in
    let segments = max 1 (int_of_float (Float.ceil (Float.abs span /. (Float.pi /. 2.)))) in
    let step = span /. float segments in
    let k = 4. /. 3. *. Float.tan (step /. 4.) *. radius in
    for segment = 0 to segments - 1 do
      let a0 = from_ +. (step *. float segment) in
      let a1 = a0 +. step in
      let x0 = cx +. (radius *. cos a0) and y0 = cy +. (radius *. sin a0)
      and x3 = cx +. (radius *. cos a1) and y3 = cy +. (radius *. sin a1) in
      wire paint (x0, y0) (x0 -. (k *. sin a0), y0 +. (k *. cos a0))
        (x3 +. (k *. sin a1), y3 -. (k *. cos a1)) (x3, y3) ~width color
    done

  let grid paint ~x ~y ~w ~h ~origin:(ox, oy) ~spacing ?(dot = 1.) color =
    prepare paint;
    Batch.Builder.grid paint.builder ~x ~y ~width:w ~height:h ~origin_x:ox
      ~origin_y:oy ~spacing ~dot ~color:(packed color)

  let text paint ~at:(x, y) ?size ?color text =
    let ui = paint.owner in
    if text <> "" then match face ui size with
      | None -> ()
      | Some font ->
          prepare paint;
          let color = packed (Option.value color ~default:ui.theme.foreground) in
          let density = float ui.density and scale = paint.scale in
          (* Snap the run's origin to a physical pixel so each glyph texel
             lands on exactly one backing pixel, as whole-string text does. *)
          let snap value = Float.round (value *. density) /. density in
          let screen_x = snap ((x *. scale) +. paint.tx)
          and screen_y = snap ((y *. scale) +. paint.ty) in
          let pen = ref 0 in
          iter_code_points text (fun code ->
            match glyph ui.atlas font ~density:ui.density code with
            | None -> ()
            | Some glyph ->
                if glyph.gw > 0 then begin
                  let gx = screen_x +. (float !pen /. density)
                  and gw = float glyph.gw /. density
                  and gh = float glyph.gh /. density in
                  Batch.Builder.textured paint.builder ~texture:1
                    ~x:((gx -. paint.tx) /. scale)
                    ~y:((screen_y -. paint.ty) /. scale)
                    ~width:(gw /. scale) ~height:(gh /. scale)
                    ~u0:(float glyph.gx) ~v0:(float glyph.gy)
                    ~u1:(float (add glyph.gx glyph.gw))
                    ~v1:(float (add glyph.gy glyph.gh)) ~color
                end;
                pen := add !pen glyph.advance)

  let text_width paint ?size text =
    float (text_width_px paint.owner ?size text) /. float paint.owner.density

  let input_region paint ?(cursor=0.) ~x ~y ~w ~h ~focused () =
    let sx = (x *. paint.scale) +. paint.tx and sy = (y *. paint.scale) +. paint.ty in
    paint.owner.regions <- Scene.text_input_region
        ~at:(int_of_float sx, int_of_float sy)
        ~w:(int_of_float (w *. paint.scale)) ~h:(int_of_float (h *. paint.scale))
        ~focused ~cursor:(int_of_float (Float.round (cursor *. paint.scale))) ()
        :: paint.owner.regions
end

let record_hit ui index (x, y, w, h) =
  let position = ui.hit_count in
  if position >= Array.length ui.hit_keys then begin
    let size = max 64 (2 * Array.length ui.hit_keys) in
    ui.hit_keys <- grow ui.hit_keys size 0;
    ui.hit_flags_of <- grow ui.hit_flags_of size 0;
    ui.hit_x <- grow_float ui.hit_x size 0.; ui.hit_y <- grow_float ui.hit_y size 0.;
    ui.hit_w <- grow_float ui.hit_w size 0.; ui.hit_h <- grow_float ui.hit_h size 0.
  end;
  ui.hit_keys.(position) <- ui.b_key.(index);
  ui.hit_flags_of.(position) <- ui.b_flags.(index);
  ui.hit_x.(position) <- x; ui.hit_y.(position) <- y;
  ui.hit_w.(position) <- w; ui.hit_h.(position) <- h;
  ui.hit_count <- add position 1

let paint_all ui (frame : Frame.t) =
  let builder = ui.batch_builder in
  Batch.Builder.reset builder;
  ui.regions <- [];
  ui.hit_count <- 0;
  let paint = { owner = ui; builder; scale = 1.; tx = 0.; ty = 0.;
    clip_rect = (0., 0., float frame.width, float frame.height) } in
  let run painters index clip_rect =
    if painters <> [] then begin
      paint.scale <- ui.l_scale.(index); paint.tx <- ui.l_tx.(index);
      paint.ty <- ui.l_ty.(index); paint.clip_rect <- clip_rect;
      let local = ui.l_x.(index), ui.l_y.(index), ui.l_w.(index), ui.l_h.(index) in
      List.iter (fun painter -> painter paint local) (List.rev painters)
    end in
  let rec visit index clip_rect =
    let screen_rect = screen ui index in
    let slot = ui.b_slot.(index) in
    let x, y, w, h = screen_rect in
    ui.rx.(slot) <- x; ui.ry.(slot) <- y; ui.rw.(slot) <- w; ui.rh.(slot) <- h;
    let hit = match ui.b_hit.(index) with
      | None -> screen_rect
      | Some f ->
          let hx, hy, hw, hh = f (ui.l_x.(index), ui.l_y.(index),
            ui.l_w.(index), ui.l_h.(index)) in
          let scale = ui.l_scale.(index) in
          (hx *. scale) +. ui.l_tx.(index), (hy *. scale) +. ui.l_ty.(index),
          hw *. scale, hh *. scale in
    let clipped_hit = intersect hit clip_rect in
    let hx, hy, hw, hh = clipped_hit in
    ui.hx.(slot) <- hx; ui.hy.(slot) <- hy; ui.hw.(slot) <- hw; ui.hh.(slot) <- hh;
    let visible = let _, _, vw, vh = intersect screen_rect clip_rect in
      vw > 0. && vh > 0. in
    if ui.b_flags.(index) land hit_flags <> 0 && hw > 0. && hh > 0. then
      record_hit ui index clipped_hit;
    if visible || ui.b_xform.(index) <> None then begin
      run ui.b_painters.(index) index clip_rect;
      let child_clip = if ui.b_flags.(index) land clip <> 0 then
          let padding = ui.b_padding.(index) *. ui.l_scale.(index) in
          intersect clip_rect (x +. padding, y +. padding,
            Float.max 0. (w -. (2. *. padding)), Float.max 0. (h -. (2. *. padding)))
        else clip_rect in
      children ui index (fun child -> visit child child_clip);
      run ui.b_overlays.(index) index clip_rect
    end else
      (* Culled: keep retained rectangles current for [rect] queries. *)
      let rec retain index = children ui index (fun child ->
        let x, y, w, h = screen ui child in
        let slot = ui.b_slot.(child) in
        ui.rx.(slot) <- x; ui.ry.(slot) <- y; ui.rw.(slot) <- w; ui.rh.(slot) <- h;
        ui.hw.(slot) <- 0.; ui.hh.(slot) <- 0.;
        retain child) in
      retain index in
  visit 0 paint.clip_rect;
  Batch.Builder.publish builder

(* -------------------------------------------------------------- frame *)

let apply_scroll ui =
  for index = 0 to ui.count - 1 do
    if ui.b_flags.(index) land scroll <> 0 then
      match Int_table.find_opt ui.signals ui.b_key.(index) with
      | Some value when value.scroll_y_steps <> 0. ->
          let slot = ui.b_slot.(index) in
          ui.scroll_y.(slot) <- ui.scroll_y.(slot)
            -. (value.scroll_y_steps *. ui.b_scroll_step.(index))
      | Some _ | None -> ()
  done

let frame ui (frame : Frame.t) f =
  if ui.destroyed then invalid_arg "Ui.frame: the UI was destroyed";
  if ui.building then invalid_arg "Ui.frame: frames cannot nest";
  if not (Float.is_finite frame.time) then invalid_arg "Ui.frame: time must be finite";
  let scale_x, scale_y = frame.pixel_scale in
  ui.density <- max 1 (int_of_float (Float.round (Float.max scale_x scale_y)));
  ui.frame_number <- add ui.frame_number 1;
  route ui frame;
  ui.count <- 0;
  ui.building <- true;
  ui.parents <- []; ui.seeds <- [];
  let root = append_box ui ~key:0x2c1b3c6d ~parent:(-1) in
  set_box ui root ~flags:none ~w:(Px (float frame.width)) ~h:(Px (float frame.height))
    ~max_h:Float.infinity ~row:false ~padding:0. ~gap:0. ~at_x:0. ~at_y:0.
    ~xform:None ~text:"" ~text_size:0 ~scroll_step:0. ~hit:None;
  ui.parents <- [root]; ui.seeds <- [0x2c1b3c6d];
  let result = Fun.protect ~finally:(fun () -> ui.building <- false)
      (fun () -> f ui) in
  ui.parents <- []; ui.seeds <- [];
  apply_scroll ui;
  intrinsic ui;
  arrange ui;
  let batch = paint_all ui frame in
  prune ui;
  if ui.focus <> 0 && Table.find ui.table ui.focus < 0 then begin
    ui.focus <- 0; ui.edit_focus <- 0
  end;
  publish_atlas ui.atlas;
  let images = match ui.atlas.image with
    | Some image when Batch.textures batch <> [] -> [1, image]
    | Some _ | None -> [] in
  let batch = if images = [] && Batch.textures batch <> [] then Batch.empty else batch in
  ui.scene <- (if Batch.count batch = 0 then List.rev ui.regions
    else Scene.Private.ui ~images batch :: List.rev ui.regions);
  result

(* ------------------------------------------------------ layout helpers *)

let row ui ?(w = Grow) ?(h = Fit) ?(gap = 0.) ?(padding = 0.) label f =
  within ui (box ui ~w ~h ~axis:Row ~gap ~padding label) f

let col ui ?(w = Grow) ?(h = Fit) ?(gap = 0.) ?(padding = 0.) label f =
  within ui (box ui ~w ~h ~axis:Column ~gap ~padding label) f

let splitter ui ?(axis = Row) ?(thickness = 6.) label =
  let w, h = match axis with Row -> Px thickness, Grow | Column -> Grow, Px thickness in
  let divider = box ui ~flags:(clickable lor blocking) ~w ~h label in
  let theme = ui.theme in
  draw ui divider (fun paint (x, y, w, h) -> Paint.fill paint ~x ~y ~w ~h theme.foreground);
  let signal = signal ui divider in
  if signal.hovered || signal.held then
    request_cursor ui (match axis with Row -> `Horizontal_resize
      | Column -> `Vertical_resize);
  let dx, dy = signal.drag in
  if signal.held || signal.released then (match axis with Row -> dx | Column -> dy)
  else 0.

(* --------------------------------------------------------- kit widgets *)

let kit_row ui ?(flags = clickable lor blocking) ?hit label =
  box ui ~flags ~w:Grow ~h:(Px (float ui.kit_row_height)) ?hit label

let ints (x, y, w, h) = int_of_float x, int_of_float y, int_of_float w, int_of_float h
let floats (x, y, w, h) = float x, float y, float w, float h

(* Old PXUI geometry, reproduced exactly from a row rectangle. *)
let label_y ui y h = y + max 5 ((h - ui.font_size - 3) / 2)
let value_column w =
  let desired = min 140 (max 120 (w / 3)) in
  min desired (w / 2)
let value_control (x, y, w, h) =
  let label = value_column w in
  x + label, y + 3, max 1 (w - label), max 1 (h - 6)
let button_control (x, y, w, h) = x, y + 3, w, max 1 (h - 6)
let toggle_control (x, y, w, _) =
  let width = min 40 w in x + w - width, y + 3, width, 18
let control_hit shape rect = floats (shape (ints rect))

let position (x, _, w, _) fraction =
  x + int_of_float ((Float.max 0. (Float.min 1. fraction)
    *. float (max 1 (w - 1))) +. 0.5)

let compact_float value =
  if abs_float value >= 1000. || (value <> 0. && abs_float value < 0.01)
  then Printf.sprintf "%.2g" value
  else Printf.sprintf "%.3g" value

let fraction_at (x, _, w, _) pointer_x =
  Float.max 0. (Float.min 1. ((pointer_x -. float x) /. float (max 1 (w - 1))))

let fill paint (x, y, w, h) color =
  Paint.fill paint ~x:(float x) ~y:(float y) ~w:(float w) ~h:(float h) color
let framed paint (x, y, w, h) ~fill:color ~stroke =
  Paint.rect paint ~x:(float x) ~y:(float y) ~w:(float w) ~h:(float h)
    ~fill:color ~stroke ()
let kit_text paint ?color x y text =
  Paint.text paint ~at:(float x, float y) ?color text
let kit_line paint ~from_:(x0, y0) ~to_:(x1, y1) ?width color =
  Paint.line paint ~from_:(float x0, float y0) ~to_:(float x1, float y1) ?width color

let hover_row paint ui (x, y, w, h) =
  fill paint (x, y + 2, w, max 1 (h - 4))
    (Color.with_alpha (Theme.hover_fill ui.theme) 150)

let panel_with ?stroke ui ?(x = 12.) ?(y = 12.) ?(width = 280.) ?max_height
    ?(row_height = 24) ?(padding = 3) label f =
  if row_height < 24 then invalid_arg "Ui.panel: row_height must be at least 24";
  if padding < 0 then invalid_arg "Ui.panel: padding must be non-negative";
  let width = Float.max 180. width in
  let max_h = match max_height with
    | Some height -> Float.max height (float (add row_height (2 * padding)))
    | None -> Float.infinity in
  let panel = box ui ~flags:(scroll lor clip lor blocking) ~w:(Px width) ~h:Fit ~max_h
      ~axis:Column ~padding:(float padding) ~at:(x, y)
      ~scroll_step:(float row_height) label in
  let theme = ui.theme and index = panel.index in
  draw ui panel (fun paint (x, y, w, h) -> Paint.fill paint ~x ~y ~w ~h theme.panel);
  draw_over ui panel (fun paint rect ->
    Option.iter (fun color -> let x, y, w, h = rect in
      Paint.stroke paint ~x ~y ~w ~h ~width:1. color) stroke;
    let x, y, width, height = ints rect in
    let content = int_of_float ui.l_content.(index) in
    let maximum = max 0 (content - height) in
    if maximum > 0 then begin
      let track_x = x + width - padding - 5 and track_y = y + padding
      and track_height = max 1 (height - (2 * padding)) in
      let thumb_height = min track_height
          (max 20 (track_height * height / max 1 content)) in
      let travel = track_height - thumb_height in
      let scroll_y = int_of_float ui.scroll_y.(panel.box_slot) in
      let thumb_y = track_y + (scroll_y * travel / maximum) in
      Paint.fill paint ~x:(float track_x) ~y:(float track_y) ~w:4.
        ~h:(float track_height) ~radius:2. (Color.with_alpha theme.track 180);
      Paint.fill paint ~x:(float track_x) ~y:(float thumb_y) ~w:4.
        ~h:(float thumb_height) ~radius:2. (Color.with_alpha theme.accent 210)
    end);
  let previous_row = ui.kit_row_height and previous_padding = ui.kit_padding in
  ui.kit_row_height <- row_height; ui.kit_padding <- padding;
  Fun.protect ~finally:(fun () ->
    ui.kit_row_height <- previous_row; ui.kit_padding <- previous_padding)
    (fun () -> within ui panel f)

let panel ui = panel_with ui

(* A centered panel from last frame's height. Esc, window focus loss, or a
   press outside it dismisses it: the builder is skipped and [None] returned,
   so the host drops its open state. *)
let modal ui ?(width = 320.) label f =
  let key = key_of (current_seed ui) label in
  let slot = Table.find ui.table key in
  let rect = if slot >= 0 then ui.rx.(slot), ui.ry.(slot), ui.rw.(slot), ui.rh.(slot)
    else 0., 0., 0., 0. in
  if slot >= 0 then Hashtbl.replace ui.modal_heights key ui.rh.(slot);
  let height = Option.value ~default:0. (Hashtbl.find_opt ui.modal_heights key) in
  let dismissed = List.exists (function
    | Event.KeyPressed Input.Escape | Event.WindowFocusLost -> true
    | Event.MousePressed (_, (px, py)) ->
        slot >= 0 && not (contains rect (float px, float py))
    | _ -> false) ui.frame_events in
  if dismissed then None else
    let x = Float.round (Float.max 0. ((ui.view_w -. width) /. 2.))
    and y = Float.round (Float.max 0. ((ui.view_h -. height) /. 2.)) in
    Some (panel_with ~stroke:ui.theme.accent ui ~x ~y ~width
      ~max_height:(Float.max 48. (ui.view_h -. 32.)) label f)

let label ui text =
  let row = kit_row ui ~flags:none text in
  let theme = ui.theme and shown = display text in
  draw ui row (fun paint rect ->
    let x, y, w, h = ints rect in
    fill paint (x, y + 1, w, max 1 (h - 2)) theme.foreground;
    kit_text paint ~color:theme.input (x + 8) (label_y ui y h) shown)

let button ui text =
  let row = kit_row ui ~hit:(control_hit button_control) text in
  let signal = signal ui row in
  let theme = ui.theme and shown = display text in
  let pressed = signal.held in
  let hovered = signal.hovered in
  draw ui row (fun paint rect ->
    let (_, y, _, h) as bounds = ints rect in
    let control = button_control bounds in
    let cx, _, _, _ = control in
    if hovered then hover_row paint ui bounds;
    fill paint control (if pressed then theme.accent
      else if hovered then Color.blend theme.foreground theme.accent ~pct:0.4
      else theme.foreground);
    kit_text paint ~color:theme.input (cx + 12) (label_y ui y h) shown);
  signal.clicked

let toggle ui text value =
  let row = kit_row ui ~hit:(control_hit toggle_control) text in
  let signal = signal ui row in
  let value = if signal.clicked then not value else value in
  let theme = ui.theme and shown = display text in
  let pressed = signal.held and hovered = signal.hovered in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = toggle_control bounds in
    if hovered then hover_row paint ui bounds;
    let track = if value then Color.blend theme.accent theme.input ~pct:0.28
      else if hovered then Color.lighten theme.control 0.08 else theme.control in
    let knob_x = if value then cx + cw - 10 else cx + 9 in
    kit_text paint ~color:(if value then theme.foreground else Theme.muted theme)
      x (label_y ui y h) shown;
    framed paint control ~fill:track
      ~stroke:(if hovered || pressed then theme.accent else Theme.border theme);
    fill paint (knob_x - 6, cy + (ch / 2) - 6, 12, 12)
      (if value then theme.accent else Theme.muted theme));
  value

let previous_utf8 text index =
  let rec seek index =
    if index <= 0 then 0
    else if Char.code text.[index] land 0xc0 <> 0x80 then index
    else seek (index - 1) in
  if index <= 0 then 0 else seek (index - 1)

let next_utf8 text index =
  let length = String.length text in
  let rec seek index =
    if index >= length then length
    else if Char.code text.[index] land 0xc0 <> 0x80 then index
    else seek (index + 1) in
  if index >= length then length else seek (index + 1)

let text_caret_at ui text x =
  match face ui None with
  | None -> String.length text
  | Some font ->
      let length = String.length text and density = float ui.density in
      let rec seek index width =
        if index >= length then length else
          let decoded = String.get_utf_8_uchar text index in
          let code = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
          let advance = match glyph ui.atlas font ~density:ui.density code with
            | Some glyph -> float glyph.advance /. density
            | None -> 0. in
          if x < width +. (advance /. 2.) then index
          else seek (index + Uchar.utf_decode_length decoded) (width +. advance) in
      seek 0 0.

let numeric_character = function
  | '0' .. '9' | '+' | '-' | '.' | 'e' | 'E' -> true
  | _ -> false

let clipboard_command ui = function
  | Event.KeyPressed (Input.KeyChar key) when ui.command_down ->
      Some (Char.lowercase_ascii key)
  | _ -> None

type text_edit = { mutable text : string; mutable caret : int; mutable anchor : int }

let load_text_edit ui key text =
  if ui.edit_focus <> key || ui.edit_value <> text then begin
    ui.edit_focus <- key; ui.edit_value <- text;
    ui.edit_caret <- String.length text; ui.edit_anchor <- ui.edit_caret
  end;
  { text; caret = ui.edit_caret; anchor = ui.edit_anchor }

let save_text_edit ui edit =
  ui.edit_value <- edit.text;
  ui.edit_caret <- edit.caret;
  ui.edit_anchor <- edit.anchor

let text_selection edit =
  min edit.caret edit.anchor, max edit.caret edit.anchor

let replace_text edit inserted =
  let start, stop = text_selection edit in
  edit.text <- String.sub edit.text 0 start ^ inserted ^
    String.sub edit.text stop (String.length edit.text - stop);
  edit.caret <- start + String.length inserted;
  edit.anchor <- edit.caret

let point_text_caret ui edit signal ~x =
  let at (px, _) = text_caret_at ui edit.text (max 0. (px -. x)) in
  if signal.pressed then begin
    let caret = at signal.press_point in
    edit.caret <- caret;
    if not ui.shift_down then edit.anchor <- caret
  end;
  if signal.dragging then edit.caret <- at signal.pointer

let edit_text_event ui edit ~accept event =
  let selected () = edit.caret <> edit.anchor in
  let move target =
    edit.caret <- target;
    if not ui.shift_down then edit.anchor <- target in
  match event with
  | event when clipboard_command ui event = Some 'a' ->
      edit.anchor <- 0; edit.caret <- String.length edit.text; false
  | event when clipboard_command ui event = Some 'c' ->
      let start, stop = text_selection edit in
      ignore (Clipboard.set_text (if selected () then
        String.sub edit.text start (stop - start) else edit.text)); false
  | event when clipboard_command ui event = Some 'x' ->
      let start, stop = text_selection edit in
      let copied = if selected () then
        String.sub edit.text start (stop - start) else edit.text in
      if Clipboard.set_text copied = Ok () then begin
        if selected () then replace_text edit "" else begin
          edit.text <- ""; edit.caret <- 0; edit.anchor <- 0
        end;
        true
      end else false
  | event when clipboard_command ui event = Some 'v' ->
      (match Clipboard.get_text () with
       | Ok text when accept text -> replace_text edit text; true
       | Ok _ | Error _ -> false)
  | Event.TextInput text when accept text -> replace_text edit text; true
  | Event.KeyPressed Input.Backspace ->
      if not (selected ()) then edit.anchor <- previous_utf8 edit.text edit.caret;
      replace_text edit ""; true
  | Event.KeyPressed Input.Delete ->
      if not (selected ()) then edit.anchor <- next_utf8 edit.text edit.caret;
      replace_text edit ""; true
  | Event.KeyPressed Input.ArrowLeft ->
      move (if ui.command_down then 0 else if selected () && not ui.shift_down
        then fst (text_selection edit) else previous_utf8 edit.text edit.caret);
      false
  | Event.KeyPressed Input.ArrowRight ->
      move (if ui.command_down then String.length edit.text
        else if selected () && not ui.shift_down then snd (text_selection edit)
        else next_utf8 edit.text edit.caret);
      false
  | Event.KeyPressed Input.Home -> move 0; false
  | Event.KeyPressed Input.End -> move (String.length edit.text); false
  | _ -> false

let paint_text_edit paint ~control:(cx, cy, cw, ch) ~y ~composition edit =
  let theme = paint.owner.theme in
  let width text = Paint.text_width paint text /. paint.scale in
  let before = String.sub edit.text 0 edit.caret in
  let caret_x = float (cx + 8) +. width before in
  Paint.input_region paint ~x:(float cx) ~y:(float cy) ~w:(float cw)
    ~h:(float ch) ~focused:true ~cursor:(caret_x -. float cx) ();
  if edit.caret <> edit.anchor then begin
    let start, stop = text_selection edit in
    Paint.fill paint
      ~x:(float (cx + 8) +. width (String.sub edit.text 0 start))
      ~y:(float (cy + 2))
      ~w:(width (String.sub edit.text start (stop - start)))
      ~h:(float (max 1 (ch - 4))) (Color.with_alpha theme.accent 100)
  end;
  if composition = "" then kit_text paint (cx + 8) y edit.text
  else begin
    kit_text paint (cx + 8) y before;
    Paint.text paint ~at:(caret_x, float y) composition;
    Paint.text paint ~at:(caret_x +. width composition, float y)
      (String.sub edit.text edit.caret
        (String.length edit.text - edit.caret))
  end;
  Paint.line paint ~from_:(caret_x, float (cy + 2))
    ~to_:(caret_x, float (cy + ch - 2)) ~width:1. theme.accent

(* Numeric label editing shared by float and integer sliders. The retained
   state records validity; [parse] validates the edit buffer. *)
let numeric_editor ui row signal ~current ~parse =
  let bounds = ints (rect ui row) in
  let control = value_control bounds in
  let inside_control point = contains (floats control) point in
  let editing = text_state ui row in
  let state = state ui row ~default:1 in
  let set text ~valid =
    set_text_state ui row (Some text);
    set_state ui row (if valid then 1 else 0) in
  let finish () = set_text_state ui row None; set_state ui row 1 in
  match editing with
  | Some text when not (focused ui row) || (signal.pressed
      && not (inside_control signal.press_point)) ->
      (* Focus moved away: commit a valid value, drop an invalid one. *)
      finish ();
      if focused ui row then unfocus ui;
      (match parse text with Some value -> Some value | None -> None), false
  | Some text ->
      let edit = load_text_edit ui row.box_key text in
      let committed = ref None and state = ref state
      and cancelled = ref false in
      let (cx, _, _, _) = control in
      point_text_caret ui edit signal ~x:(float (cx + 8));
      List.iter (fun (event : Event.t) -> match event with
        | Event.KeyPressed Input.Enter ->
            (match parse edit.text with
             | Some value -> committed := Some value
             | None -> state := 0)
        | Event.KeyPressed Input.Escape -> cancelled := true
        | event ->
            if edit_text_event ui edit
                ~accept:(String.for_all numeric_character) event then
              state := if parse edit.text <> None then 1 else 0) signal.keys;
      if !cancelled then (finish (); unfocus ui; None, false)
      else (match !committed with
        | Some value -> finish (); unfocus ui; Some value, false
        | None ->
            save_text_edit ui edit;
            set edit.text ~valid:(!state land 1 <> 0);
            None, true)
  | None ->
      if signal.double_clicked && not (inside_control signal.press_point) then begin
        let text = current () in
        set text ~valid:true;
        focus ui row;
        ui.edit_focus <- row.box_key; ui.edit_value <- text;
        ui.edit_caret <- String.length text; ui.edit_anchor <- 0;
        None, true
      end else None, false

let slider_row ui text ~draw_value ~value_text ~fraction_of ~from_fraction ~parse
    ~current value =
  let row = kit_row ui text in
  let signal = signal ui row in
  let bounds = ints (rect ui row) in
  let control = value_control bounds in
  let in_control point = contains (floats control) point in
  let typed, editing = numeric_editor ui row signal ~current:(fun () -> current value)
      ~parse in
  (* Only an open numeric editor takes keyboard focus. *)
  if editing then ui.b_flags.(row.index) <- clickable lor focusable lor blocking;
  let dragging = not editing && (signal.held || signal.released)
    && in_control signal.press_point in
  let value = match typed with
    | Some typed -> typed
    | None when dragging ->
        let x = if signal.released then fst signal.release_point
          else fst signal.pointer in
        from_fraction value (fraction_at control x)
    | None -> value in
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered && in_control signal.pointer in
  let pressed = dragging && signal.held in
  let edit = text_state ui row and valid = state ui row ~default:1 land 1 <> 0 in
  let composition = ui.composition and focused = focused ui row in
  let edit_caret = ui.edit_caret and edit_anchor = ui.edit_anchor in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    if hovered then hover_row paint ui bounds;
    match edit with
    | Some text ->
        kit_text paint ~color:theme.accent x (label_y ui y h) shown;
        framed paint control ~fill:theme.input
          ~stroke:(if valid then theme.accent else Theme.invalid);
        if focused then paint_text_edit paint ~control ~y:(label_y ui y h)
          ~composition { text; caret = edit_caret; anchor = edit_anchor }
        else kit_text paint (cx + 8) (label_y ui y h) text
    | None ->
        let marker = position control (fraction_of value) in
        let fill_width = max 1 (marker - cx + 1) in
        kit_text paint x (label_y ui y h) shown;
        framed paint (cx, cy + 4, cw, max 1 (ch - 8)) ~fill:theme.track
          ~stroke:(Theme.border theme);
        fill paint (cx, cy + 4, fill_width, max 1 (ch - 8))
          (Color.with_alpha theme.accent (if pressed then 220 else 175));
        kit_line paint ~from_:(marker, cy + 2) ~to_:(marker, cy + ch - 2)
          ~width:2. theme.foreground;
        if draw_value then kit_text paint (cx + 6) (cy + 6) (value_text value));
  value

let slider ui text ~range:(low, high) value =
  if not (Float.is_finite low && Float.is_finite high) || high <= low then
    invalid_arg "Ui.slider: range must be finite and increasing";
  if not (Float.is_finite value) then invalid_arg "Ui.slider: value must be finite";
  slider_row ui text ~draw_value:true ~value_text:compact_float
    ~fraction_of:(fun value -> (value -. low) /. (high -. low))
    ~from_fraction:(fun _ fraction -> low +. (fraction *. (high -. low)))
    ~parse:(fun text ->
      match float_of_string_opt text with
      | Some value when Float.is_finite value -> Some value
      | Some _ | None -> None)
    ~current:(Printf.sprintf "%.17g") value

let int_slider ui text ~range:(low, high) value =
  if high <= low then invalid_arg "Ui.int_slider: range must be increasing";
  slider_row ui text ~draw_value:true ~value_text:string_of_int
    ~fraction_of:(fun value -> float (value - low) /. float (high - low))
    ~from_fraction:(fun _ fraction ->
      max low (min high (low + int_of_float ((fraction *. float (high - low)) +. 0.5))))
    ~parse:int_of_string_opt ~current:string_of_int value

let text_field ui text value =
  let row = kit_row ui ~flags:(clickable lor focusable lor blocking)
      ~hit:(control_hit value_control) text in
  let signal = signal ui row in
  let focused = focused ui row in
  let edit = if focused then load_text_edit ui row.box_key value else
    let end_ = String.length value in
    { text = value; caret = end_; anchor = end_ } in
  if focused then begin
    let (cx, _, _, _) = value_control (ints (rect ui row)) in
    point_text_caret ui edit signal ~x:(float (cx + 8));
    List.iter (fun event -> ignore (edit_text_event ui edit
      ~accept:(fun _ -> true) event)) signal.keys;
    save_text_edit ui edit
  end;
  let value = edit.text in
  let theme = ui.theme and shown = display text and composition = ui.composition in
  let hovered = signal.hovered in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    if hovered then hover_row paint ui bounds;
    kit_text paint ~color:(if focused then theme.foreground else Theme.muted theme)
      x (label_y ui y h) shown;
    framed paint control ~fill:(if hovered then Theme.hover_fill theme else theme.input)
      ~stroke:(if focused then theme.accent else Theme.border theme);
    if focused then paint_text_edit paint ~control ~y:(label_y ui y h)
      ~composition edit
    else begin
      Paint.input_region paint ~x:(float cx) ~y:(float cy) ~w:(float cw)
        ~h:(float ch) ~focused:false ();
      kit_text paint (cx + 8) (label_y ui y h) value
    end);
  value

let choice ui text options selected =
  let options = Array.of_list options in
  let count = Array.length options in
  if count = 0 then invalid_arg "Ui.choice: options must not be empty";
  if selected < 0 || selected >= count then
    invalid_arg "Ui.choice: selected index is out of bounds";
  let row = kit_row ui ~hit:(control_hit value_control) text in
  let signal = signal ui row in
  let selected =
    if not signal.clicked then selected else
      let cx, _, cw, _ = value_control (ints (rect ui row)) in
      let direction = if fst signal.release_point < float (cx + (cw / 2)) then -1 else 1 in
      (selected + direction + count) mod count in
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered and pressed = signal.held in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, _, cw, _) as control = value_control bounds in
    if hovered then hover_row paint ui bounds;
    kit_text paint x (label_y ui y h) shown;
    framed paint control
      ~fill:(if pressed then Theme.pressed_fill theme
        else if hovered then Theme.hover_fill theme else theme.input)
      ~stroke:(if hovered || pressed then theme.accent else Theme.border theme);
    kit_text paint ~color:theme.accent (cx + 7) (label_y ui y h) "‹";
    kit_text paint (cx + 21) (label_y ui y h) options.(selected);
    kit_text paint ~color:theme.accent (cx + cw - 13) (label_y ui y h) "›");
  selected

let range_slider ui text ~range:(low, high) (lower, upper) =
  if high <= low then invalid_arg "Ui.range_slider: range must be increasing";
  let clamp value = Float.max low (Float.min high value) in
  let lower = clamp lower and upper = clamp upper in
  let lower, upper = Float.min lower upper, Float.max lower upper in
  let row = kit_row ui ~hit:(control_hit value_control) text in
  let signal = signal ui row in
  let control = value_control (ints (rect ui row)) in
  let fraction value = (value -. low) /. (high -. low) in
  (* The nearer handle is captured on press and kept for the drag. *)
  let handle =
    if signal.pressed then begin
      let x = fst signal.press_point in
      let low_x = float (position control (fraction lower))
      and high_x = float (position control (fraction upper)) in
      let handle = if Float.abs (x -. low_x) <= Float.abs (x -. high_x) then 0 else 1 in
      set_state ui row handle; handle
    end else state ui row ~default:0 in
  let lower, upper =
    if signal.held || signal.released then
      let x = if signal.released then fst signal.release_point else fst signal.pointer in
      let value = low +. (fraction_at control x *. (high -. low)) in
      if handle = 0 then Float.min value upper, upper
      else lower, Float.max value lower
    else lower, upper in
  let theme = ui.theme and shown = display text and hovered = signal.hovered in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    let low_x = position control (fraction lower)
    and high_x = position control (fraction upper) in
    if hovered then hover_row paint ui bounds;
    kit_text paint x (label_y ui y h) shown;
    framed paint (cx, cy + 7, cw, max 1 (ch - 14)) ~fill:theme.track
      ~stroke:(Theme.border theme);
    fill paint (low_x, cy + 7, max 1 (high_x - low_x + 1), max 1 (ch - 14))
      (Color.with_alpha theme.accent 185);
    kit_line paint ~from_:(low_x, cy + 3) ~to_:(low_x, cy + ch - 3) ~width:2.
      theme.foreground;
    kit_line paint ~from_:(high_x, cy + 3) ~to_:(high_x, cy + ch - 3) ~width:2.
      theme.foreground;
    kit_text paint (cx + 5) (cy + 6) (compact_float lower ^ " — " ^ compact_float upper));
  lower, upper

let xy ui text ~x_range:(x_min, x_max) ~y_range:(y_min, y_max) (px, py) =
  if x_max <= x_min || y_max <= y_min then invalid_arg "Ui.xy: ranges must increase";
  let clamp low high value = Float.max low (Float.min high value) in
  let px = clamp x_min x_max px and py = clamp y_min y_max py in
  let row = kit_row ui ~hit:(control_hit value_control) text in
  let signal = signal ui row in
  let (_, cy, _, ch) as control = value_control (ints (rect ui row)) in
  let px, py =
    if signal.held || signal.released then
      let x, y = if signal.released then signal.release_point else signal.pointer in
      let fy = Float.max 0. (Float.min 1. ((y -. float cy) /. float (max 1 (ch - 1)))) in
      x_min +. (fraction_at control x *. (x_max -. x_min)),
      y_min +. (fy *. (y_max -. y_min))
    else px, py in
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered and pressed = signal.held in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    let knob_x = position control ((px -. x_min) /. (x_max -. x_min)) in
    let knob_y = cy + int_of_float (((py -. y_min) /. (y_max -. y_min)
      *. float (max 1 (ch - 1))) +. 0.5) in
    if hovered then hover_row paint ui bounds;
    kit_text paint x (label_y ui y h) shown;
    framed paint control ~fill:(if hovered then Theme.hover_fill theme else theme.input)
      ~stroke:(Theme.border theme);
    kit_line paint ~from_:(cx + (cw / 2), cy + 3) ~to_:(cx + (cw / 2), cy + ch - 3)
      (Theme.faint_border theme);
    kit_line paint ~from_:(cx + 3, cy + (ch / 2)) ~to_:(cx + cw - 3, cy + (ch / 2))
      (Theme.faint_border theme);
    Paint.circle paint ~at:(float knob_x, float knob_y)
      ~radius:(if pressed then 6. else 5.) ~fill:theme.accent
      ~stroke:theme.foreground ());
  px, py

type pick = [ `None | `Pick of int | `Delete of int | `Submit | `Back | `Cancel ]

(* ponytail: case-insensitive subsequence match, no scoring; swap for
   fzf-style ranking if lists grow long. *)
let fuzzy_match ~query text =
  let query = String.lowercase_ascii query and text = String.lowercase_ascii text in
  let length = String.length text in
  let rec walk at index =
    index = String.length query
    || (at < length && walk (at + 1) (if text.[at] = query.[index] then index + 1 else index)) in
  walk 0 0

(* A focused search row over a windowed list. The cursor (search box state)
   and an armed delete row (list box state) are retained; the host keeps the
   query and applies the result. *)
let picker ui ?(limit = 10) label ~query rows_of =
  let rows = ref (rows_of query) in
  let count () = Array.length !rows in
  let search = kit_row ui ~flags:(clickable lor focusable lor blocking) label in
  focus ui search;
  let list = box ui ~w:Grow ~h:Fit ~axis:Column (label ^ "##rows") in
  let search_signal = signal ui search in
  let keys = search_signal.keys in
  let clamp cursor = if count () = 0 then 0 else max 0 (min (count () - 1) cursor) in
  let cursor = ref (clamp (state ui search ~default:0))
  and armed = ref (state ui list ~default:(-1)) and query = ref query
  and result = ref `None in
  let edit = load_text_edit ui search.box_key !query in
  let (sx, _, _, _) = ints (rect ui search) in
  point_text_caret ui edit search_signal ~x:(float (sx + 8));
  let set_query text = query := text; rows := rows_of text; cursor := 0; armed := -1 in
  List.iter (fun (event : Event.t) -> let count = count () in
    if !result = `None then match event with
    | Event.KeyPressed Input.Backspace when edit.text = "" -> result := `Back
    | Event.KeyPressed Input.ArrowLeft when edit.text = "" -> result := `Back
    | Event.KeyPressed Input.ArrowDown when count > 0 ->
        cursor := (!cursor + 1) mod count; armed := -1
    | Event.KeyPressed Input.ArrowUp when count > 0 ->
        cursor := (!cursor + count - 1) mod count; armed := -1
    | Event.KeyPressed Input.Enter ->
        result := if count > 0 then `Pick !cursor else `Submit
    | Event.KeyPressed Input.Delete when count > 0 &&
        edit.caret = edit.anchor ->
        if !armed = !cursor then (result := `Delete !cursor; armed := -1)
        else armed := !cursor
    | Event.KeyPressed Input.Escape -> result := `Cancel
    | event ->
        ignore (edit_text_event ui edit ~accept:(fun _ -> true) event);
        if edit.text <> !query then set_query edit.text) keys;
  save_text_edit ui edit;
  let count = count () and rows = !rows in
  let length = min limit count in
  let start = if length = count then 0
    else max 0 (min (count - length) (!cursor - (length / 2))) in
  let theme = ui.theme and composition = ui.composition in
  let placeholder = display label in
  draw ui search (fun paint rect ->
    let (x, y, w, h) = ints rect in
    let control = x, y + 3, w, max 1 (h - 6) in
    let cx, _, _, _ = control in
    framed paint control ~fill:theme.input ~stroke:theme.accent;
    if edit.text = "" then
      kit_text paint ~color:(Theme.muted theme) (cx + 8)
        (label_y ui y h) placeholder;
    paint_text_edit paint ~control ~y:(label_y ui y h) ~composition edit);
  within ui list (fun () ->
    for visible = 0 to length - 1 do
      let index = start + visible in
      let row = kit_row ui ~flags:(clickable lor blocking)
          (Printf.sprintf "row###%d" visible) in
      let row_signal = signal ui row in
      if !result = `None && row_signal.clicked then result := `Pick index;
      let current = index = !cursor and hovered = row_signal.hovered in
      let doomed = index = !armed in
      let text, detail = rows.(index) in
      draw ui row (fun paint rect ->
        let (x, y, w, h) as bounds = ints rect in
        if current || doomed then
          fill paint (x, y + 1, w, max 1 (h - 2))
            (if doomed then Theme.invalid else theme.foreground)
        else if hovered then hover_row paint ui bounds;
        let color = if current || doomed then theme.input else theme.foreground in
        kit_text paint ~color (x + 8) (label_y ui y h) text;
        let detail_width = int_of_float (Paint.text_width paint detail) in
        kit_text paint ~color:(if current || doomed then theme.input else Theme.muted theme)
          (x + w - detail_width - 8) (label_y ui y h) detail)
    done);
  set_state ui search !cursor; set_state ui list !armed;
  !query, !result

let context_clicked (signal : signal) =
  let (px, py), (rx, ry) = signal.press_point, signal.release_point in
  signal.released && signal.button = Some Input.RightButton
  && ((px -. rx) *. (px -. rx)) +. ((py -. ry) *. (py -. ry)) < 16.

(* A floating kit menu at [at], kept inside the frame. The host holds whether
   it is open; rows commit on press and release inside, disabled rows are
   inert, and Escape, focus loss, or a press outside dismiss it. *)
let context_menu ui ~at:(x, y) label items =
  let width = 200. and row_height = float ui.kit_row_height in
  let height = (float (List.length items) *. row_height) +. 6. in
  let x = Float.max 0. (Float.min x (ui.view_w -. width))
  and y = Float.max 0. (Float.min y (ui.view_h -. height)) in
  let slot = Table.find ui.table (key_of (current_seed ui) label) in
  let rect = if slot >= 0 then ui.rx.(slot), ui.ry.(slot), ui.rw.(slot), ui.rh.(slot)
    else x, y, width, height in
  let dismissed = List.exists (function
    | Event.KeyPressed Input.Escape | Event.WindowFocusLost -> true
    | Event.MousePressed (_, (px, py)) -> not (contains rect (float px, float py))
    | _ -> false) ui.frame_events in
  if dismissed then `Dismiss else
    let picked = panel_with ~stroke:ui.theme.accent ui ~x ~y ~width label (fun () ->
      List.mapi (fun index (text, enabled) ->
        let row = kit_row ui ~flags:(if enabled then clickable lor blocking else blocking)
            text in
        let signal = signal ui row in
        let theme = ui.theme and shown = display text in
        draw ui row (fun paint rect ->
          let (_, y, _, h) as bounds = ints rect in
          let rx, _, _, _ = bounds in
          if enabled && signal.hovered then hover_row paint ui bounds;
          kit_text paint ~color:(if enabled then theme.foreground else Theme.muted theme)
            (rx + 8) (label_y ui y h) shown);
        if enabled && signal.clicked then Some index else None) items
      |> List.find_map Fun.id) in
    match picked with Some index -> `Pick index | None -> `Open

let accordion ui ?(expanded = false) ?set_expanded text f =
  let row = kit_row ui text in
  let signal = signal ui row in
  let open_ = state ui row ~default:(if expanded then 1 else 0) = 1 in
  let open_ = match set_expanded with Some forced -> forced | None -> open_ in
  let open_ = if signal.clicked then not open_ else open_ in
  set_state ui row (if open_ then 1 else 0);
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered and pressed = signal.held in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let bx, by, bw, bh = bounds in
    if hovered then hover_row paint ui bounds;
    fill paint (bx, by + 1, bw, max 1 (bh - 2))
      (if pressed || hovered then theme.accent else theme.foreground);
    kit_text paint ~color:theme.input (x + 9) (label_y ui y h)
      (if open_ then "-" else "+");
    kit_text paint ~color:theme.input (x + 27) (label_y ui y h) shown);
  if open_ then Some (f ()) else None

let expanded ui text =
  let key = key_of (current_seed ui) text in
  let slot = Table.find ui.table key in
  if slot < 0 || ui.state_values.(slot) = min_int then None
  else Some (ui.state_values.(slot) = 1)

let ( + ) left right = left lor right
