open Rays

module Int_table = Hashtbl.Make (Int)
module Batch = Scene.Private.Ui_batch

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

(* Index of [marker] in [text], or [-1]; no closure or substring per call. *)
let rec marker_at text marker at offset =
  offset = String.length marker
  || (String.unsafe_get text (at + offset) = String.unsafe_get marker offset
      && marker_at text marker at (offset + 1))
let rec marker_from text marker index =
  if index + String.length marker > String.length text then -1
  else if marker_at text marker index 0 then index
  else marker_from text marker (index + 1)
let find_marker text marker =
  if String.contains text '#' then marker_from text marker 0 else -1

let key_of seed text =
  let index = find_marker text "###" in
  (* the id after ### replaces the label's hash, under the same parent: two panels that build
     the same widget keep separate state *)
  if index >= 0 then hash_range seed text (index + 3) (String.length text)
  else hash_range seed text 0 (String.length text)

let display text =
  let index = find_marker text "##" in
  if index >= 0 then String.sub text 0 index else text

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
(* Kit controls enter keyboard mode through Tab; pointer editing retains the
   existing host shortcut behavior. Text-entry rows also focus on a press. *)
let tab_only = 32
let tab_stop = focusable lor tab_only
(* a multiline editor keeps Tab for itself (two spaces) instead of moving the focus *)
let keep_tab = 64
(* a press on such a box leaves the keyboard focus where it is (a completion row under an editor) *)
let keep_focus = 128
let add = Stdlib.( + )
let hit_flags = clickable lor focusable lor scroll lor blocking

type rect = float * float * float * float

(* What a carry holds, and how it was picked up: by pressing a box and moving past the dead
   zone (the box's key), or by a key (no pointer capture). *)
type payload = { kind : string; value : string }
type origin = From_pointer of int | From_key
type drop = Hover of payload | Dropped of payload

(* The dead zone of a carry started by the pointer, in points. *)
let carry_dead_zone = 4.

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
  mutable font_size : int;
  (* owned kit faces by size; [None] caches a failed load *)
  faces : Font.t option Int_table.t;
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
  mutable scroll_raw : float array;
  mutable scroll_visual : float array;
  mutable scroll_event_time : float array;
  mutable scroll_frame_time : float array;
  mutable state_values : int array;
  mutable text_values : string option array;
  mutable press_time : float array;
  mutable press_x : float array; mutable press_y : float array;
  mutable press_count : int array;  (* consecutive left presses within 0.35 s and 5 points *)
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
  mutable overlays : int list;  (* popup boxes this frame, newest first *)
  mutable foreground : (int * int) list;  (* floating panels, below modal popups *)
  mutable seeds : int list;
  mutable building : bool;
  mutable frame_number : int;
  mutable density : int;
  mutable kit_row_height : int;
  mutable kit_padding : int;
  mutable closed_section : int;  (* the last closed section header: the next one follows it closely *)
  (* input *)
  mutable pointer : float * float;
  mutable hot : int;
  mutable hover_rest : (string * (float * float) * float * int) option;
  mutable active : int option;  (* Some 0: unconsumed background gesture *)
  mutable active_button : Input.mouse_button;
  mutable active_press : float * float;
  mutable active_keys : Input.key list;
  mutable focus : int;
  mutable keyboard_focus : bool;
  mutable composition : string;
  mutable previous_keys : Input.key list;
  mutable edit_focus : int;
  mutable edit_value : string;
  mutable edit_caret : int;
  mutable edit_anchor : int;
  mutable edit_scroll_x : float;
  (* the focused text's undo and redo stacks (text, caret, anchor), and the caret after the
     last typed character so consecutive typing undoes as one step *)
  mutable edit_undo : (string * int * int) list;
  mutable edit_redo : (string * int * int) list;
  mutable edit_group : int;
  (* a double or triple click's selection unit, extended by the drag that follows it *)
  mutable edit_unit : (int * int * int) option;
  mutable scrub_origin : (int * string) option;
  (* the carry: the payload in flight, and the one released this frame with the box that was
     hot at the release *)
  mutable payload : (payload * origin) option;
  mutable dropped : (payload * int) option;
  (* the box whose press was carried until the host cancelled: it does not carry again before
     the next press *)
  mutable carry_latch : int option;
  (* the undo or redo key the focused text declined this frame because its own stack was empty *)
  mutable passed_undo : [`Undo | `Redo] option;
  mutable requested_cursor : [`Horizontal_resize|`Vertical_resize|`Text] option;
  (* this frame's raw events and logical size, for modal dismissal *)
  mutable frame_events : Event.t list;
  mutable input_frame : Frame.t option;
  mutable routed_events : (int * Event.t * (float * float)) list;
  mutable cancelled : Input.mouse_button list;
  mutable modal_key : int option;
  mutable modal_in_frame : bool;
  mutable view_w : float;
  mutable view_h : float;
  (* last laid-out height per modal key, kept while the modal is closed *)
  modal_heights : (int, float * int) Hashtbl.t;
  signals : accumulator Int_table.t;
  (* previous frame's hit list, in paint order *)
  mutable hit_count : int;
  (* the hit entry [chain_key] and its ancestors, kept between questions about one key (the
     hovered box is asked about by every card of a canvas); [0]: not known *)
  mutable chain_key : int; mutable chain : int list;
  mutable hit_keys : int array; mutable hit_parent : int array;
  mutable hit_flags_of : int array;
  mutable hit_x : float array; mutable hit_y : float array;
  mutable hit_w : float array; mutable hit_h : float array;
  (* output *)
  batch_builder : Batch.Builder.t;
  mutable regions : Scene.t;
  mutable scene_layers : (int * Scene.t) list;
  mutable scene : Scene.t;
  atlas : atlas;
  mutable destroyed : bool;
}

and accumulator = {
  mutable pressed : bool;
  mutable subtree_press : int option;
  mutable released : bool;
  mutable clicked : bool;
  mutable double_clicked : bool;
  mutable clicks : int;
  mutable moved : bool;
  mutable drag_x : float;
  mutable drag_y : float;
  mutable press_point : float * float;
  mutable release_point : float * float;
  mutable button : Input.mouse_button option;
  mutable scroll_x : float;
  mutable scroll_y_steps : float;
  mutable pinch : float;  (* product of this frame's pinch factors *)
  mutable keys : (Event.t * Input.key list) list;
  mutable press_keys : Input.key list;
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
    match Image.upload_rgba ?into:atlas.image ~width:atlas.width
        ~height:atlas.height ~rgba:atlas.pixels () with
    | Ok image -> atlas.image <- Some image; atlas.dirty <- false
    | Error _ -> ()
  end

(* The kit face: [RAYS_UI_FONT], else Pragmasevka found from the working
   directory or the executable upward. *)
let kit_font_path = lazy (
  match Sys.getenv_opt "RAYS_UI_FONT" with
  | Some path -> Some path
  | None ->
      let relative = Filename.concat "assets"
          (Filename.concat "fonts" "Pragmasevka-Regular.ttf") in
      let rec upward directory =
        let candidate = Filename.concat directory relative in
        if Sys.file_exists candidate then Some candidate
        else let parent = Filename.dirname directory in
          if parent = directory then None else upward parent in
      match upward (Sys.getcwd ()) with
      | Some _ as found -> found
      | None -> upward (Filename.dirname (Sys.executable_name)))

let face ui size =
  match size with
  | None when Option.is_some ui.font -> ui.font
  | _ ->
      let size = Option.value size ~default:ui.font_size in
      match Int_table.find_opt ui.faces size with
      | Some face -> face
      | None ->
          let loaded = match Lazy.force kit_font_path with
            | Some path -> Font.load path size
            | None -> Error (`Msg "no kit font") in
          let face = match loaded with
            | Ok font -> Some font
            | Error _ -> Result.to_option (Font.system ~size ()) in
          Int_table.replace ui.faces size face;
          face

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
  { theme; font; font_size; faces = Int_table.create 4; table = Table.create ();
    slot_key = Array.make capacity 0; free = []; next_slot = 0;
    touched = Array.make capacity (-1);
    rx = Array.make capacity 0.; ry = Array.make capacity 0.;
    rw = Array.make capacity 0.; rh = Array.make capacity 0.;
    hx = Array.make capacity 0.; hy = Array.make capacity 0.;
    hw = Array.make capacity 0.; hh = Array.make capacity 0.;
    scroll_y = Array.make capacity 0.;
    scroll_raw = Array.make capacity 0.; scroll_visual = Array.make capacity 0.;
    scroll_event_time = Array.make capacity Float.neg_infinity;
    scroll_frame_time = Array.make capacity 0.;
    state_values = Array.make capacity min_int;
    text_values = Array.make capacity None;
    press_time = Array.make capacity Float.neg_infinity;
    press_x = Array.make capacity 0.; press_y = Array.make capacity 0.;
    press_count = Array.make capacity 0;
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
    parents = []; overlays = []; foreground = []; seeds = []; building = false; frame_number = 0; density = 1;
    kit_row_height = 24; kit_padding = 0; closed_section = -1;
    pointer = (Float.nan, Float.nan); hot = 0; hover_rest = None; active = None;
    active_button = Input.LeftButton; active_press = (0., 0.); focus = 0;
    keyboard_focus = false; composition = "";
    previous_keys = []; active_keys = [];
    edit_focus = 0; edit_value = ""; edit_caret = 0; edit_anchor = 0;
    edit_scroll_x = 0.;
    edit_undo = []; edit_redo = []; edit_group = -1; edit_unit = None;
    scrub_origin = None; payload = None; dropped = None; carry_latch = None;
    passed_undo = None;
    requested_cursor = None;
    frame_events = []; input_frame = None; routed_events = []; cancelled = [];
    modal_key = None; modal_in_frame = false;
    view_w = 0.; view_h = 0.; modal_heights = Hashtbl.create 4;
    signals = Int_table.create 16;
    hit_count = 0; chain_key = 0; chain = []; hit_keys = [||]; hit_parent = [||]; hit_flags_of = [||];
    hit_x = [||]; hit_y = [||]; hit_w = [||]; hit_h = [||];
    batch_builder = Batch.Builder.create ~capacity:1024 ();
    regions = []; scene_layers = []; scene = []; atlas = create_atlas (); destroyed = false }

let destroy ui =
  if not ui.destroyed then begin
    ui.destroyed <- true;
    Option.iter Image.destroy ui.atlas.image;
    ui.atlas.image <- None;
    Int_table.iter (fun _ face -> Option.iter Font.destroy face) ui.faces;
    Int_table.reset ui.faces;
    ui.atlas.fonts <- [];
    ui.scene <- []
  end

let theme ui = ui.theme
let set_theme ui theme = ui.theme <- theme
let font_size ui = ui.font_size
(* the kit text size and, with it, the row height (24 at 11 points); set between frames *)
let set_font_size ui size =
  if size <= 0 then invalid_arg "Ui.set_font_size: size must be positive";
  ui.font_size <- size; ui.kit_row_height <- max 24 (size + 11)
let scene ?under ui = match under with
  | None -> ui.scene
  | Some under -> List.concat_map (fun (key, layer) -> under key @ layer) ui.scene_layers
      @ List.rev ui.regions
let row_height ui = ui.kit_row_height
let view_size ui = ui.view_w, ui.view_h
let text_line_height ui = ui.font_size + (ui.font_size + 1) / 2
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
    ui.scroll_raw <- grow_float ui.scroll_raw size 0.;
    ui.scroll_visual <- grow_float ui.scroll_visual size 0.;
    ui.scroll_event_time <- grow_float ui.scroll_event_time size Float.neg_infinity;
    ui.scroll_frame_time <- grow_float ui.scroll_frame_time size 0.;
    ui.state_values <- grow ui.state_values size min_int;
    ui.text_values <- grow ui.text_values size None;
    ui.press_time <- grow_float ui.press_time size Float.neg_infinity;
    ui.press_x <- grow_float ui.press_x size 0.;
    ui.press_y <- grow_float ui.press_y size 0.;
    ui.press_count <- grow ui.press_count size 0;
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
    ui.scroll_raw.(slot) <- 0.; ui.scroll_visual.(slot) <- 0.;
    ui.scroll_event_time.(slot) <- Float.neg_infinity;
    ui.scroll_frame_time.(slot) <- 0.;
    ui.text_values.(slot) <- None; ui.press_time.(slot) <- Float.neg_infinity;
    ui.press_count.(slot) <- 0;
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
      if ui.active = Some key then begin
        ui.cancelled <- ui.active_button :: ui.cancelled; ui.active <- None
      end;
      (* the box that holds a carry's pointer is gone: the carry goes with it *)
      (match ui.payload with
       | Some (_, From_pointer owner) when owner = key -> ui.payload <- None
       | _ -> ());
      if ui.hot = key then ui.hot <- 0
    end
  done

(* -------------------------------------------------------------- input *)

let contains (x, y, w, h) (px, py) = px >= x && py >= y && px < x +. w && py < y +. h
let command_modifiers keys = List.mem Input.Meta keys || List.mem Input.Ctrl keys

let accumulator ui key =
  match Int_table.find_opt ui.signals key with
  | Some value -> value
  | None ->
      let value = { pressed = false; subtree_press = None;
        released = false; clicked = false;
        double_clicked = false; clicks = 0; moved = false; drag_x = 0.; drag_y = 0.;
        press_point = (0., 0.); release_point = (0., 0.); button = None;
        scroll_x = 0.; scroll_y_steps = 0.; pinch = 1.; keys = [];
        press_keys = if ui.active = Some key then ui.active_keys else [] } in
      Int_table.replace ui.signals key value;
      value

let hit_index ui key =
  let rec search index =
    if index < 0 then -1
    else if ui.hit_keys.(index) = key then index
    else search (index - 1) in
  search (ui.hit_count - 1)

let rec hit_ancestors ui key f =
  if key <> 0 then begin
    f key;
    let index = hit_index ui key in
    if index >= 0 then hit_ancestors ui ui.hit_parent.(index) f
  end

(* [key] is [ancestor] or under it in the hit list.  The chain of a key is walked once (each step
   scans the list) and kept until the list is rebuilt. *)
let hit_within ui key ancestor =
  key = ancestor || (key <> 0 && begin
    if ui.chain_key <> key then begin
      let chain = ref [] in
      hit_ancestors ui key (fun k -> chain := k :: !chain);
      ui.chain_key <- key; ui.chain <- !chain
    end;
    List.mem ancestor ui.chain end)

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

let last_press_within ui (frame : Frame.t) roots =
  List.fold_left (fun last -> function
    | Event.MousePressed (_, point) ->
        let found = ref None in
        hit_ancestors ui (topmost ui point) (fun key ->
          if !found = None && List.mem key roots then found := Some key);
        (match !found with Some _ as root -> root | None -> last)
    | _ -> last) None frame.events

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

let traverse_focus ui ~shift =
  let eligible index = ui.hit_flags_of.(index) land focusable <> 0
    && Option.fold ~none:true ~some:(fun modal ->
      hit_within ui ui.hit_keys.(index) modal) ui.modal_key in
  let current = hit_index ui ui.focus in
  let direction = if shift then -1 else 1 in
  let start = if current >= 0 then current
    else if direction < 0 then 0 else ui.hit_count - 1 in
  let rec seek distance =
    if distance > ui.hit_count then () else
      let index = (start + (direction * distance) + ui.hit_count) mod ui.hit_count in
      if eligible index then begin
        ui.focus <- ui.hit_keys.(index); ui.keyboard_focus <- true;
        ui.composition <- ""; ui.edit_focus <- 0
      end else seek (distance + 1) in
  seek 1

let route ui (frame : Frame.t) =
  Int_table.reset ui.signals;
  ui.requested_cursor <- None;
  ui.frame_events <- frame.events;
  ui.input_frame <- Some frame;
  ui.routed_events <- []; ui.cancelled <- [];
  ui.dropped <- None;
  let released_carry = ref false in
  ui.passed_undo <- None;
  ui.modal_in_frame <- ui.modal_key <> None;
  let modifiers = ref (Event.Private.keys_before ~previous:ui.previous_keys
    ~held:frame.keys frame.events) in
  ui.previous_keys <- frame.keys;
  ui.view_w <- float frame.width; ui.view_h <- float frame.height;
  let set_pointer point = ui.pointer <- point in
  let modal_target target = match ui.modal_key with
    | Some modal when not (hit_within ui target modal) -> modal
    | _ -> target in
  let pointer_target point =
    match ui.active with Some target -> target | None -> modal_target (topmost ui point) in
  List.iteri (fun event_index (event : Event.t) ->
    modifiers := Event.Private.keys_after !modifiers event;
    let command = command_modifiers !modifiers in
    (match event with
     | Event.KeyPressed Input.Tab when not command ->
         if flags_of_key ui ui.focus land keep_tab = 0 then
           traverse_focus ui ~shift:(List.mem Input.Shift !modifiers)
     | _ -> ());
    let owner, delta = match event with
      | Event.MouseMoved ((x, y) as point) ->
          pointer_target point,
          (if Float.is_finite (fst ui.pointer) then x -. fst ui.pointer, y -. snd ui.pointer
           else 0., 0.)
      | MousePressed (_, point) | MouseReleased (_, point) -> pointer_target point, (0., 0.)
      | MouseScrolled _ | MousePinched _ ->
          let target = match ui.active with Some target -> target
            | None -> let scroll = scroll_target ui ui.pointer in
                modal_target (if scroll <> 0 then scroll else topmost ui ui.pointer) in
          target, (0., 0.)
      | KeyPressed Input.Tab when not command ->
          (if ui.focus = 0 then 0x2c1b3c6d else ui.focus), (0., 0.)
      | KeyPressed _ | KeyReleased _ | TextInput _ | TextEditing _ ->
          ui.focus, (0., 0.)
      | _ -> 0, (0., 0.) in
    ui.routed_events <- (owner, event, delta) :: ui.routed_events;
    match event with
    | Event.MouseMoved point ->
        let px, py = ui.pointer in
        set_pointer point;
        Option.iter (fun active ->
          let value = accumulator ui active in
          let x, y = ui.pointer in
          if Float.is_finite px then begin
            value.drag_x <- value.drag_x +. (x -. px);
            value.drag_y <- value.drag_y +. (y -. py)
          end;
          value.moved <- true
        ) ui.active
    (* a carry started from a key: a left press is the put, on what is under it, and nothing
       else sees the press *)
    | Event.MousePressed (Input.LeftButton, point)
      when (match ui.payload with Some (_, From_key) -> true | _ -> false) ->
        set_pointer point;
        (match ui.payload with
         | Some (payload, _) -> ui.dropped <- Some (payload, topmost ui point)
         | None -> ());
        ui.payload <- None;
        ui.routed_events <- (match ui.routed_events with
          | (_, event, delta) :: rest -> (-1, event, delta) :: rest | [] -> [])
    | Event.MousePressed (button, point) ->
        set_pointer point;
        let target = owner in
        hit_ancestors ui target (fun key ->
          (accumulator ui key).subtree_press <- Some event_index);
        let flags = flags_of_key ui target in
        if button = Input.LeftButton then begin
          let focus = if flags land keep_focus <> 0 then ui.focus
            else if flags land focusable <> 0 && flags land tab_only = 0 then target else 0 in
          if focus <> ui.focus then begin
            ui.composition <- ""; ui.edit_focus <- 0
          end;
          ui.focus <- focus;
          ui.keyboard_focus <- false
        end;
        if (target = 0 || flags land clickable <> 0) && ui.active = None then begin
          ui.active <- Some target; ui.active_button <- button;
          ui.active_press <- ui.pointer;
          ui.active_keys <- !modifiers;
          let value = accumulator ui target in
          value.pressed <- true;
          value.press_point <- ui.pointer;
          value.press_keys <- !modifiers;
          value.button <- Some button;
          let slot = Table.find ui.table target in
          if slot >= 0 && button = Input.LeftButton then begin
            let x, y = ui.pointer in
            let dx = x -. ui.press_x.(slot) and dy = y -. ui.press_y.(slot) in
            (* the second press within 0.35 s and 5 points is a double click, the third a
               triple; the fourth starts over *)
            let count = if frame.time >= ui.press_time.(slot)
                && frame.time -. ui.press_time.(slot) <= 0.35
                && (dx *. dx) +. (dy *. dy) <= 25. && ui.press_count.(slot) < 3
              then ui.press_count.(slot) + 1 else 1 in
            ui.press_count.(slot) <- count;
            value.clicks <- count;
            value.double_clicked <- count = 2;
            ui.press_time.(slot) <- frame.time;
            ui.press_x.(slot) <- x; ui.press_y.(slot) <- y
          end
        end
    | Event.MouseReleased (button, point) ->
        set_pointer point;
        (match ui.active with
        | Some active when button = ui.active_button ->
          (match ui.payload with
           | Some (_, From_pointer owner) when owner = active && button = Input.LeftButton ->
               released_carry := true
           | _ -> ());
          let value = accumulator ui active in
          value.released <- true;
          value.release_point <- ui.pointer;
          value.press_point <- ui.active_press;
          value.press_keys <- ui.active_keys;
          value.button <- Some button;
          let index = hit_index ui active in
          if button = Input.LeftButton && index >= 0
             && hit_contains ui index ui.pointer
             && hit_contains ui index ui.active_press
          then value.clicked <- true;
          ui.active <- None
        | _ -> ())
    | Event.MouseScrolled (horizontal, vertical) ->
        let target = modal_target (scroll_target ui ui.pointer) in
        if target <> 0 then begin
          let value = accumulator ui target in
          value.scroll_x <- value.scroll_x +. horizontal;
          value.scroll_y_steps <- value.scroll_y_steps +. vertical
        end
    (* a trackpad pinch goes where the wheel goes *)
    | Event.MousePinched scale ->
        let target = modal_target (scroll_target ui ui.pointer) in
        if target <> 0 then begin
          let value = accumulator ui target in
          value.pinch <- value.pinch *. scale
        end
    (* Cancellation ends capture without a release: no click, no commit. *)
    | Event.PointerCancelled button ->
        if button = ui.active_button then ui.active <- None;
        (match ui.payload with
         | Some (_, From_pointer _) when button = Input.LeftButton ->
             ui.payload <- None; released_carry := false
         | _ -> ())
    | Event.WindowFocusLost ->
        ui.payload <- None; released_carry := false;
        ui.active <- None; ui.focus <- 0; ui.hot <- 0; ui.composition <- "";
        ui.edit_focus <- 0; ui.keyboard_focus <- false
    | Event.KeyPressed _ | Event.KeyReleased _ | Event.TextInput _
    | Event.TextEditing _ ->
        if ui.focus <> 0 then begin
          let value = accumulator ui ui.focus in
          value.keys <- (event, !modifiers) :: value.keys;
          (match event with
           | Event.KeyPressed (Input.Enter | Space | KeyChar ' ')
               when not command -> value.clicked <- true
           | _ -> ());
          (match event with
           | Event.TextEditing { text; _ } -> ui.composition <- text
           | Event.TextInput _ -> ui.composition <- ""
           | Event.KeyPressed Input.Escape when flags_of_key ui ui.focus land tab_only <> 0 ->
               ui.focus <- 0; ui.keyboard_focus <- false; ui.edit_focus <- 0
           | _ -> ())
        end
    | _ -> ()) frame.events;
  ui.routed_events <- List.rev ui.routed_events;
  Int_table.iter (fun _ value -> value.keys <- List.rev value.keys) ui.signals;
  let mouse_x, mouse_y = frame.mouse in
  if not (Float.is_finite (fst ui.pointer)) then
    ui.pointer <- (mouse_x, mouse_y);
  ui.hot <- (if List.exists (function Event.WindowFocusLost -> true | _ -> false)
      frame.events then 0 else topmost ui ui.pointer);
  if ui.active = None then ui.carry_latch <- None;
  (* released: what the carry was put on is what was hot at the release *)
  if !released_carry then begin
    (match ui.payload with
     | Some (payload, _) -> ui.dropped <- Some (payload, ui.hot)
     | None -> ());
    ui.payload <- None
  end

let wants_pointer ui = ui.hot <> 0 || Option.fold ~none:false ~some:(( <> ) 0) ui.active
let cursor ui = ui.requested_cursor
let request_cursor ui shape = ui.requested_cursor <- Some shape
let text_input_focused ui = ui.focus <> 0
let passed_undo ui = ui.passed_undo

(* [label] cut to [limit] points wide ([width] measures text) with an ellipsis, on a character boundary *)
let ellipsis ~width ~limit label =
  let rec cut s =
    if s = "" then "" else begin
      let n = ref (String.length s - 1) in
      while !n > 0 && Char.code s.[!n] land 0xC0 = 0x80 do decr n done;
      let s = String.sub s 0 !n in
      if width (s ^ "…") <= limit then s ^ "…" else cut s
    end in
  if width label <= limit then label else cut label
let key_pressed ui key =
  List.exists (function Event.KeyPressed k -> k = key | _ -> false) ui.frame_events
let unfocus ui = ui.focus <- 0; ui.composition <- ""; ui.edit_focus <- 0;
  ui.keyboard_focus <- false

let dismiss_popup ui =
  ui.modal_key <- None;
  unfocus ui;
  if ui.active <> None then begin
    ui.cancelled <- ui.active_button :: ui.cancelled; ui.active <- None
  end

(* Event ownership is recorded before release/cancellation clears capture.
   A viewport passes its exact root key: child widgets retain their events. *)
let input ?(owner = 0) ui =
  let frame = match ui.input_frame with Some frame -> frame
    | None -> invalid_arg "Ui.input: no frame has completed" in
  let accepts target = not ui.modal_in_frame && (target = 0 || target = owner) in
  let events, delta, complete = List.fold_left (fun (events, (dx, dy), complete)
      (target, event, (mx, my)) -> match event with
    | Event.WindowFocusLost | PointerCancelled _ -> event :: events, (dx, dy), complete
    | _ when accepts target -> event :: events, (dx +. mx, dy +. my), complete
    | MouseReleased (button, _) ->
        Event.PointerCancelled button :: events, (dx, dy), false
    | _ -> events, (dx, dy), false) ([], (0., 0.), true) ui.routed_events in
  let held = Option.fold ~none:false ~some:accepts ui.active in
  let pointer = held || (ui.active = None && frame.mouse_buttons = [] && accepts ui.hot) in
  let cancelled = ui.cancelled @ (if ui.modal_in_frame then frame.mouse_buttons else []) in
  { frame with events = List.rev events @ List.map (fun button -> Event.PointerCancelled button) cancelled;
    keys = if ui.modal_in_frame || ui.focus <> 0 then [] else frame.keys;
    mouse_buttons = if held then frame.mouse_buttons else [];
    mouse_delta = if not pointer then 0., 0.
      else if complete then frame.mouse_delta else delta }

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

(* Integer-derived child keys: no label string per frame. *)
let int_key seed n =
  let hash = (seed lxor (n * 0x1e3779b97f4a7c15)) * fnv_prime in
  let hash = hash lxor (hash lsr 29) in
  if hash = 0 || hash = 1 then hash + 2 else hash

let box_keyed ui ?(flags = none) ?(w = Grow) ?(h = Fit) ?(max_h = Float.infinity)
    ?(axis = Column) ?(padding = 0.) ?(gap = 0.) ?at ?xform ?(text = "")
    ?(text_size = 0) ?(scroll_step = 24.) ?hit key =
  require_building ui;
  let key = unique_key ui key in
  let index = append_box ui ~key ~parent:(current_parent ui) in
  let at_x, at_y = match at with Some (x, y) -> x, y | None -> Float.nan, Float.nan in
  set_box ui index ~flags ~w ~h ~max_h ~row:(axis = Row) ~padding ~gap ~at_x ~at_y
    ~xform ~text ~text_size ~scroll_step ~hit;
  { index; box_key = key; box_slot = ui.b_slot.(index) }

let box ui ?flags ?w ?h ?max_h ?axis ?padding ?gap ?at ?xform ?text ?text_size
    ?scroll_step ?hit label =
  require_building ui;
  box_keyed ui ?flags ?w ?h ?max_h ?axis ?padding ?gap ?at ?xform ?text
    ?text_size ?scroll_step ?hit (key_of (current_seed ui) label)

let set_at ui box ~at:(x, y) =
  require_building ui;
  ui.b_at_x.(box.index) <- x;
  ui.b_at_y.(box.index) <- y

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
  subtree_press : int option;
  held : bool;
  released : bool;
  clicked : bool;
  double_clicked : bool;
  clicks : int;
  dragging : bool;
  drag : float * float;
  pointer : float * float;
  press_point : float * float;
  release_point : float * float;
  button : Input.mouse_button option;
  scroll : float * float;
  pinch : float;
  keys : Event.t list;
}

let signal ui box =
  let key = box.box_key in
  let held = ui.active = Some key in
  match Int_table.find_opt ui.signals key with
  | None ->
      { hovered = ui.hot = key; pressed = false; subtree_press = None;
        held; released = false;
        clicked = false; double_clicked = false; clicks = 0; dragging = false;
        drag = (0., 0.); pointer = ui.pointer;
        press_point = (if held then ui.active_press
          else (ui.press_x.(box.box_slot), ui.press_y.(box.box_slot)));
        release_point = ui.pointer;
        button = (if held then Some ui.active_button else None);
        scroll = (0., 0.); pinch = 1.; keys = [] }
  | Some value ->
      { hovered = ui.hot = key; pressed = value.pressed;
        subtree_press = value.subtree_press; held;
        released = value.released; clicked = value.clicked;
        double_clicked = value.double_clicked; clicks = value.clicks;
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
        pinch = value.pinch;
        keys = List.map fst value.keys }

let key_events ui box = match Int_table.find_opt ui.signals box.box_key with
  | None -> [] | Some value -> value.keys

let press_keys ui box = match Int_table.find_opt ui.signals box.box_key with
  | None -> if ui.active = Some box.box_key then ui.active_keys else []
  | Some value -> value.press_keys

let press_shift ui box = List.mem Input.Shift (press_keys ui box)

let focused ui box = ui.focus = box.box_key
let focus ui box =
  if ui.focus <> box.box_key then begin
    ui.composition <- ""; ui.edit_focus <- 0
  end;
  ui.focus <- box.box_key
let active ui box = ui.active = Some box.box_key
let hovered_within ui box = hit_within ui ui.hot box.box_key

(* ------------------------------------------------------------- carry *)

let carrying ui = Option.map fst ui.payload

let carry ui ?from ~kind ~value () =
  match from with
  | None ->
      (match ui.payload with
       | Some (held, From_key) when held.kind = kind && held.value = value -> ()
       | _ -> ui.payload <- Some ({ kind; value }, From_key))
  | Some box ->
      if ui.payload = None && ui.active = Some box.box_key && ui.carry_latch <> ui.active
         && ui.active_button = Input.LeftButton then begin
        let px, py = ui.active_press and x, y = ui.pointer in
        if Float.hypot (x -. px) (y -. py) >= carry_dead_zone then
          ui.payload <- Some ({ kind; value }, From_pointer box.box_key)
      end

let cancel_carry ui =
  if ui.payload <> None then ui.carry_latch <- ui.active;
  ui.payload <- None

let drop_target ui box =
  match ui.dropped, ui.payload with
  | Some (payload, hot), _ ->
      if hot <> 0 && hit_within ui hot box.box_key then Some (Dropped payload) else None
  | None, Some (payload, _) ->
      if ui.hot <> 0 && hit_within ui ui.hot box.box_key then Some (Hover payload) else None
  | None, None -> None

let scroll_offset ui box = ui.scroll_y.(box.box_slot)
let scroll_position ui box =
  ui.scroll_y.(box.box_slot) +. ui.scroll_visual.(box.box_slot)
let set_scroll_offset ui box value =
  ui.scroll_y.(box.box_slot) <- value;
  ui.scroll_raw.(box.box_slot) <- 0.;
  ui.scroll_visual.(box.box_slot) <- 0.

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

let to_front ui ?(order = 0) box =
  require_building ui;
  if ui.b_parent.(box.index) <> 0 then invalid_arg "Ui.to_front: expected a root box";
  ui.foreground <- (order, box.index) :: ui.foreground

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
    let scroll_offset = if scrolls then ui.scroll_y.(slot) +. ui.scroll_visual.(slot) else 0. in
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

  let text paint ~at:(x, y) ?size ?(tracking = 0.) ?color text =
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
          let pen = ref 0 and tracking = int_of_float (Float.round (tracking *. density)) in
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
                pen := add (add !pen glyph.advance) tracking)

  let text_width paint ?size text =
    float (text_width_px paint.owner ?size text) /. float paint.owner.density

  (* The label style: upper case, two points under the body, one point of tracking. *)
  let label_size paint = max 8 (paint.owner.font_size - 2)
  let cap paint ~at ?color label =
    text paint ~at ~size:(label_size paint) ~tracking:1.
      ~color:(Option.value color ~default:(Theme.ink_2 paint.owner.theme)) (String.uppercase_ascii label)
  let cap_width paint label =
    let label = String.uppercase_ascii label in
    let count = ref 0 in
    iter_code_points label (fun _ -> incr count);
    text_width paint ~size:(label_size paint) label +. float !count

  let chevron paint ~at:(cx, cy) direction color =
    let a, b = match direction with
      | `Down -> (-3.5, -2.), (3.5, -2.) | `Up -> (-3.5, 2.), (3.5, 2.)
      | `Right -> (-2., -3.5), (-2., 3.5) | `Left -> (2., -3.5), (2., 3.5) in
    let tip = match direction with
      | `Down -> 0., 1.5 | `Up -> 0., -1.5 | `Right -> 1.5, 0. | `Left -> -1.5, 0. in
    let p (dx, dy) = cx +. dx, cy +. dy in
    line paint ~from_:(p a) ~to_:(p tip) color; line paint ~from_:(p tip) ~to_:(p b) color

  (* Selection: four corner brackets [offset] outside the rectangle. *)
  let brackets paint ~x ~y ~w ~h ?(offset = 4.) ?(length = 8.) ?(width = 2.) color =
    let x = x -. offset and y = y -. offset and w = w +. (2. *. offset) and h = h +. (2. *. offset) in
    List.iter (fun (cx, cy, sx, sy) ->
      fill paint ~x:(if sx > 0. then cx else cx -. length) ~y:(if sy > 0. then cy else cy -. width)
        ~w:length ~h:width color;
      fill paint ~x:(if sx > 0. then cx else cx -. width) ~y:(if sy > 0. then cy else cy -. length)
        ~w:width ~h:length color)
      [ x, y, 1., 1.; x +. w, y, -1., 1.; x, y +. h, 1., -1.; x +. w, y +. h, -1., -1. ]

  let dashed paint ~from_:(x0, y0) ~to_:(x1, y1) ?(width = 1.) color =
    let length = Float.hypot (x1 -. x0) (y1 -. y0) in
    let steps = int_of_float (Float.ceil (length /. 7.)) in
    for step = 0 to steps - 1 do
      let a = float step *. 7. /. length and b = Float.min 1. ((float step *. 7. +. 4.) /. length) in
      line paint ~from_:(x0 +. ((x1 -. x0) *. a), y0 +. ((y1 -. y0) *. a))
        ~to_:(x0 +. ((x1 -. x0) *. b), y0 +. ((y1 -. y0) *. b)) ~width color
    done

  let dashed_rect paint ~x ~y ~w ~h color =
    dashed paint ~from_:(x, y) ~to_:(x +. w, y) color; dashed paint ~from_:(x, y +. h) ~to_:(x +. w, y +. h) color;
    dashed paint ~from_:(x, y) ~to_:(x, y +. h) color; dashed paint ~from_:(x +. w, y) ~to_:(x +. w, y +. h) color

  (* Empty: a hairline box crossed corner to corner. *)
  let cross paint ~x ~y ~w ~h color =
    stroke paint ~x ~y ~w ~h color;
    line paint ~from_:(x, y) ~to_:(x +. w, y +. h) color;
    line paint ~from_:(x, y +. h) ~to_:(x +. w, y) color

  (* Bypassed, stale, cooking: diagonal hairlines every 5 points, clipped to the rectangle. *)
  let hatch paint ~x ~y ~w ~h color =
    let previous = paint.clip_rect in
    paint.clip_rect <- intersect previous
      ((x *. paint.scale) +. paint.tx, (y *. paint.scale) +. paint.ty, w *. paint.scale, h *. paint.scale);
    let offset = ref (-. h) in
    while !offset < w do
      line paint ~from_:(x +. !offset, y +. h) ~to_:(x +. !offset +. h, y) color;
      offset := !offset +. 7.
    done;
    paint.clip_rect <- previous

  let input_region paint ?(cursor=0.) ~x ~y ~w ~h ~focused () =
    let sx = (x *. paint.scale) +. paint.tx and sy = (y *. paint.scale) +. paint.ty in
    paint.owner.regions <- Scene.text_input_region
        ~at:(int_of_float sx, int_of_float sy)
        ~w:(int_of_float (w *. paint.scale)) ~h:(int_of_float (h *. paint.scale))
        ~focused ~cursor:(max 0 (int_of_float (Float.round (cursor *. paint.scale)))) ()
        :: paint.owner.regions
end

let record_hit ui index parent (x, y, w, h) =
  let position = ui.hit_count in
  if position >= Array.length ui.hit_keys then begin
    let size = max 64 (2 * Array.length ui.hit_keys) in
    ui.hit_keys <- grow ui.hit_keys size 0;
    ui.hit_parent <- grow ui.hit_parent size 0;
    ui.hit_flags_of <- grow ui.hit_flags_of size 0;
    ui.hit_x <- grow_float ui.hit_x size 0.; ui.hit_y <- grow_float ui.hit_y size 0.;
    ui.hit_w <- grow_float ui.hit_w size 0.; ui.hit_h <- grow_float ui.hit_h size 0.
  end;
  ui.hit_keys.(position) <- ui.b_key.(index);
  ui.hit_parent.(position) <- parent;
  ui.hit_flags_of.(position) <- ui.b_flags.(index);
  ui.hit_x.(position) <- x; ui.hit_y.(position) <- y;
  ui.hit_w.(position) <- w; ui.hit_h.(position) <- h;
  ui.chain_key <- 0;
  ui.hit_count <- add position 1

let paint_all ui (frame : Frame.t) =
  let builder = ui.batch_builder in
  Batch.Builder.reset builder;
  ui.regions <- [];
  ui.hit_count <- 0; ui.chain_key <- 0;
  let paint = { owner = ui; builder; scale = 1.; tx = 0.; ty = 0.;
    clip_rect = (0., 0., float frame.width, float frame.height) } in
  let layers = ref [] and key = ref 0 in
  let flush () = layers := (!key, Batch.Builder.publish builder) :: !layers;
    Batch.Builder.reset builder in
  let run painters index clip_rect =
    if painters <> [] then begin
      paint.scale <- ui.l_scale.(index); paint.tx <- ui.l_tx.(index);
      paint.ty <- ui.l_ty.(index); paint.clip_rect <- clip_rect;
      let local = ui.l_x.(index), ui.l_y.(index), ui.l_w.(index), ui.l_h.(index) in
      (* [draw] prepends; paint oldest first without reversing a copy. *)
      let rec in_order = function
        | [] -> ()
        | painter :: earlier -> in_order earlier; painter paint local in
      in_order painters
    end in
  let rec visit index clip_rect parent_hit =
    if ui.b_parent.(index) = 0 && List.exists (fun (_, root) -> root = index) ui.foreground then begin
      flush (); key := ui.b_key.(index)
    end;
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
    let has_hit = ui.b_flags.(index) land hit_flags <> 0 && hw > 0. && hh > 0. in
    if has_hit then record_hit ui index parent_hit clipped_hit;
    if visible || ui.b_xform.(index) <> None then begin
      run ui.b_painters.(index) index clip_rect;
      let child_clip = if ui.b_flags.(index) land clip <> 0 then
          let padding = ui.b_padding.(index) *. ui.l_scale.(index) in
          intersect clip_rect (x +. padding, y +. padding,
            Float.max 0. (w -. (2. *. padding)), Float.max 0. (h -. (2. *. padding)))
        else clip_rect in
      let parent_hit = if has_hit then ui.b_key.(index) else parent_hit in
      children ui index (fun child -> visit child child_clip parent_hit);
      run ui.b_overlays.(index) index clip_rect;
      if ui.keyboard_focus && ui.focus = ui.b_key.(index) then begin
        paint.scale <- ui.l_scale.(index); paint.tx <- ui.l_tx.(index);
        paint.ty <- ui.l_ty.(index); paint.clip_rect <- clip_rect;
        Paint.stroke paint ~x:(ui.l_x.(index) +. 1.) ~y:(ui.l_y.(index) +. 1.)
          ~w:(Float.max 0. (ui.l_w.(index) -. 2.))
          ~h:(Float.max 0. (ui.l_h.(index) -. 2.)) ui.theme.accent
      end
    end else
      (* Culled: keep retained rectangles current for [rect] queries. *)
      let rec retain index = children ui index (fun child ->
        let x, y, w, h = screen ui child in
        let slot = ui.b_slot.(child) in
        ui.rx.(slot) <- x; ui.ry.(slot) <- y; ui.rw.(slot) <- w; ui.rh.(slot) <- h;
        ui.hw.(slot) <- 0.; ui.hh.(slot) <- 0.;
        retain child) in
      retain index in
  visit 0 paint.clip_rect 0;
  flush (); List.rev !layers

(* -------------------------------------------------------------- frame *)

let apply_scroll ui time =
  for index = 0 to ui.count - 1 do
    if ui.b_flags.(index) land scroll <> 0 then begin
      let slot = ui.b_slot.(index) in
      let max_scroll = Float.max 0. (ui.l_content.(index) -. ui.l_h.(index)) in
      let clamp x = Float.max 0. (Float.min max_scroll x) in
      let wheel = match Int_table.find_opt ui.signals ui.b_key.(index) with
        | Some value -> value.scroll_y_steps
        | None -> 0. in
      if wheel <> 0. then begin
        let next = ui.scroll_y.(slot) +. ui.scroll_raw.(slot)
          -. (wheel *. ui.b_scroll_step.(index)) in
        let bounded = clamp next in
        let raw = next -. bounded in
        let height = ui.l_h.(index) in
        ui.scroll_y.(slot) <- bounded;
        ui.scroll_raw.(slot) <- raw;
        ui.scroll_visual.(slot) <-
          if height <= 0. then 0. else
          0.05 *. raw /. (1. +. 0.05 *. Float.abs raw /. height);
        ui.scroll_event_time.(slot) <- time
      end else if ui.scroll_visual.(slot) <> 0.
          && time -. ui.scroll_event_time.(slot) > 0.08 then begin
        let dt = Float.max 0. (time -. ui.scroll_frame_time.(slot)) in
        let visual = ui.scroll_visual.(slot) *. Float.exp (-. dt /. 0.084) in
        ui.scroll_visual.(slot) <- if Float.abs visual < 0.25 then 0. else visual;
        let height = ui.l_h.(index) in
        ui.scroll_raw.(slot) <-
          if height <= 0. || ui.scroll_visual.(slot) = 0. then 0. else
          ui.scroll_visual.(slot) /.
            (0.05 *. (1. -. Float.abs ui.scroll_visual.(slot) /. height))
      end;
      ui.scroll_frame_time.(slot) <- time
    end
  done

(* The payload in flight follows the pointer as a small label above everything. Idle frames
   (nothing carried) build and paint nothing. *)
let carry_ghost ui =
  match ui.payload with
  | Some (payload, _) when Float.is_finite (fst ui.pointer) ->
      let px, py = ui.pointer in
      let width = float (text_width_px ui payload.value) /. float ui.density +. 16. in
      let parents = ui.parents and seeds = ui.seeds in
      ui.parents <- [0]; ui.seeds <- [0x2c1b3c6d];
      Fun.protect ~finally:(fun () -> ui.parents <- parents; ui.seeds <- seeds) (fun () ->
        let ghost = box ui ~w:(Px width) ~h:(Px 22.) ~at:(px +. 14., py +. 14.) "ui-carry-ghost" in
        let theme = ui.theme in
        draw_over ui ghost (fun paint (x, y, w, h) ->
          Paint.rect paint ~x ~y ~w ~h ~fill:theme.accent ~radius:3. ();
          Paint.text paint ~at:(x +. 8., y +. 5.) ~color:theme.input payload.value);
        ui.foreground <- (max_int, ghost.index) :: ui.foreground)
  | _ -> ()

let frame ui (frame : Frame.t) f =
  if ui.destroyed then invalid_arg "Ui.frame: the UI was destroyed";
  if ui.building then invalid_arg "Ui.frame: frames cannot nest";
  if not (Float.is_finite frame.time) then invalid_arg "Ui.frame: time must be finite";
  let scale_x, scale_y = frame.pixel_scale in
  ui.density <- max 1 (int_of_float (Float.round (Float.max scale_x scale_y)));
  ui.frame_number <- add ui.frame_number 1;
  route ui frame;
  ui.modal_key <- None;
  ui.count <- 0;
  ui.building <- true;
  ui.parents <- []; ui.seeds <- [];
  let root = append_box ui ~key:0x2c1b3c6d ~parent:(-1) in
  set_box ui root ~flags:none ~w:(Px (float frame.width)) ~h:(Px (float frame.height))
    ~max_h:Float.infinity ~row:false ~padding:0. ~gap:0. ~at_x:0. ~at_y:0.
    ~xform:None ~text:"" ~text_size:0 ~scroll_step:0. ~hit:None;
  ui.parents <- [root]; ui.seeds <- [0x2c1b3c6d];
  let result = Fun.protect ~finally:(fun () -> ui.building <- false)
      (fun () -> let result = f ui in carry_ghost ui; result) in
  ui.parents <- []; ui.seeds <- [];
  (* Move popups to the end of the root's children, oldest first. *)
  List.iter (fun index ->
    if ui.b_parent.(index) = 0 && ui.b_last.(0) <> index then begin
      let rec unlink previous child =
        if child >= 0 then
          if child = index then begin
            (if previous < 0 then ui.b_first.(0) <- ui.b_next.(index)
             else ui.b_next.(previous) <- ui.b_next.(index))
          end else unlink child ui.b_next.(child) in
      unlink (-1) ui.b_first.(0);
      ui.b_next.(ui.b_last.(0)) <- index; ui.b_next.(index) <- -1;
      ui.b_last.(0) <- index
    end) (List.stable_sort (fun (a, _) (b, _) -> Int.compare a b) (List.rev ui.foreground)
      |> List.map snd |> fun foreground -> foreground @ List.rev ui.overlays);
  ui.overlays <- [];
  intrinsic ui;
  apply_scroll ui frame.time;
  arrange ui;
  let layers = paint_all ui frame in
  ui.foreground <- [];
  prune ui;
  if ui.focus <> 0 && Table.find ui.table ui.focus < 0 then begin
    ui.focus <- 0; ui.edit_focus <- 0
  end;
  publish_atlas ui.atlas;
  ui.scene_layers <- List.map (fun (key, batch) ->
    let images = match ui.atlas.image with
      | Some image when Batch.textures batch <> [] -> [1, image]
      | Some _ | None -> [] in
    let batch = if images = [] && Batch.textures batch <> [] then Batch.empty else batch in
    key, (if Batch.count batch = 0 then [] else [Scene.Private.ui ~images batch])) layers;
  ui.scene <- List.concat_map snd ui.scene_layers @ List.rev ui.regions;
  result

(* ------------------------------------------------------ layout helpers *)

let hover_delay ui ~key =
  let time = match ui.input_frame with Some frame -> frame.time | None -> 0. in
  if ui.active <> None || ui.modal_in_frame
      || List.exists (function Event.WindowFocusLost -> true | _ -> false)
      ui.frame_events then (ui.hover_rest <- None; false)
  else match ui.hover_rest with
    | Some (previous, pointer, start, seen) when previous = key && pointer = ui.pointer
        && (seen = ui.frame_number || seen = ui.frame_number - 1) && time >= start ->
        ui.hover_rest <- Some (key, pointer, start, ui.frame_number);
        time -. start >= 0.380
    | _ -> ui.hover_rest <- Some (key, ui.pointer, time, ui.frame_number); false

let tooltip ui ~key ~text =
  if hover_delay ui ~key then begin
    let width = Float.min 400. (Float.max 40. (ui.view_w -. 16.)) in
    let columns = max 1 (int_of_float ((width -. 16.) /. 7.)) in
    let lines, last = List.fold_left (fun (lines, line) word ->
      if line = "" then lines, word
      else if String.length line + String.length word + 1 <= columns then
        lines, line ^ " " ^ word
      else line :: lines, word) ([], "") (String.split_on_char ' ' text) in
    let lines = List.rev (last :: lines) in
    let height = 4. +. (16. *. float (List.length lines)) in
    let px, py = ui.pointer in
    let x = Float.max 8. (Float.min (px +. 12.) (ui.view_w -. width -. 8.)) in
    let y = if py +. height +. 24. <= ui.view_h then py +. 20.
      else Float.max 8. (py -. height -. 8.) in
    let parents = ui.parents and seeds = ui.seeds in
    ui.parents <- [0]; ui.seeds <- [0x2c1b3c6d];
    Fun.protect ~finally:(fun () -> ui.parents <- parents; ui.seeds <- seeds) (fun () ->
      let tip = box ui ~w:(Px width) ~h:(Px height) ~at:(x, y) "ui-tooltip" in
      ui.overlays <- tip.index :: ui.overlays;
      draw ui tip (fun paint (x, y, w, h) ->
        Paint.rect paint ~x ~y ~w ~h ~fill:ui.theme.input ~stroke:(Theme.edge ui.theme) ();
        List.iteri (fun i line -> Paint.text paint ~color:ui.theme.foreground
          ~at:(x +. 8., y +. 2. +. (16. *. float i)) line) lines))
  end

let row ui ?(w = Grow) ?(h = Fit) ?(gap = 0.) ?(padding = 0.) label f =
  within ui (box ui ~w ~h ~axis:Row ~gap ~padding label) f

let col ui ?(w = Grow) ?(h = Fit) ?(gap = 0.) ?(padding = 0.) label f =
  within ui (box ui ~w ~h ~axis:Column ~gap ~padding label) f

let splitter ui ?(axis = Row) ?(thickness = 6.) label =
  let w, h = match axis with Row -> Px thickness, Grow | Column -> Grow, Px thickness in
  let divider = box ui ~flags:(clickable lor blocking) ~w ~h label in
  let theme = ui.theme in
  let signal = signal ui divider in
  (* a hairline in a wider drag target; accent while dragged *)
  draw ui divider (fun paint (x, y, w, h) ->
    let color = if signal.held then theme.accent else Theme.edge theme in
    if axis = Row then Paint.fill paint ~x:(x +. Float.floor (w /. 2.)) ~y ~w:1. ~h color
    else Paint.fill paint ~x ~y:(y +. Float.floor (h /. 2.)) ~w ~h:1. color);
  if signal.hovered || signal.held then
    request_cursor ui (match axis with Row -> `Horizontal_resize
      | Column -> `Vertical_resize);
  let dx, dy = signal.drag in
  if signal.held || signal.released then (match axis with Row -> dx | Column -> dy)
  else 0.

(* --------------------------------------------------------- kit widgets *)

let kit_row ui ?(flags = clickable lor focusable lor blocking lor tab_only) ?hit label =
  box ui ~flags ~w:Grow ~h:(Px (float ui.kit_row_height)) ?hit label

let ints (x, y, w, h) = int_of_float x, int_of_float y, int_of_float w, int_of_float h
let floats (x, y, w, h) = float x, float y, float w, float h

(* Kit rev 3 geometry from a row rectangle: 12 points at each side, a label column of 112
   (half of a narrow row), then the 20-point control. *)
let side = 12
let label_y ui y h = y + max 4 ((h - ui.font_size - 3) / 2)
let value_column w = min 112 (max 0 ((w - (2 * side) - 8) / 2))
let value_control (x, y, w, h) =
  let cx = x + side + value_column w + 8 in
  cx, y + 2, max 1 (x + w - side - cx), max 1 (h - 4)
let toggle_control (x, y, w, h) = x + w - side - 28, y + ((h - 14) / 2), 28, 14
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

let hover_row paint ui bounds = fill paint bounds (Theme.faint_border ui.theme)
(* a field is a value on a hairline: accent while it holds the keyboard *)
let underline paint (cx, cy, cw, ch) color = fill paint (cx, cy + ch - 1, cw, 1) color
let paint_switch paint (theme : Theme.t) ~x ~y value =
  Paint.rect paint ~x ~y ~w:28. ~h:14. ~fill:(if value then theme.input else theme.track)
    ~stroke:(Theme.border theme) ();
  Paint.fill paint ~x:(x +. (if value then 17. else 3.)) ~y:(y +. 3.) ~w:8. ~h:8.
    (if value then theme.accent else Theme.ink_3 theme)
let cap_y ui y h = y +. Float.floor ((h -. float (max 8 (ui.font_size - 2)) -. 3.) /. 2.)
(* a section header: a label in ink-3 and a chevron, under 16 points of space *)
let paint_section paint ui (x, y, w, h) label ~open_ ~hovered =
  if hovered then Paint.fill paint ~x ~y ~w ~h (Theme.faint_border ui.theme);
  Paint.cap paint ~at:(x +. float side, cap_y ui y h) ~color:(Theme.ink_3 ui.theme) label;
  Paint.chevron paint ~at:(x +. w -. float side -. 4., y +. (h /. 2.))
    (if open_ then `Down else `Right) (Theme.ink_2 ui.theme)
(* the space above a section header: 4 at the top of its parent, none after a closed one *)
let section_gap ui =
  let last = ui.b_last.(current_parent ui) in
  if last < 0 then 4 else if last = ui.closed_section then 0 else 16

let panel_with ?stroke ui ?(x = 12.) ?(y = 12.) ?(width = 280.) ?height ?max_height
    ?(row_height = 24) ?(padding = 0) label f =
  if row_height < 24 then invalid_arg "Ui.panel: row_height must be at least 24";
  if padding < 0 then invalid_arg "Ui.panel: padding must be non-negative";
  let width = Float.max 180. width in
  let max_h = match max_height with
    | Some height -> Float.max height (float (add row_height (2 * padding)))
    | None -> Float.infinity in
  let panel = box ui ~flags:(scroll lor clip lor blocking) ~w:(Px width)
      ~h:(Option.fold ~none:Fit ~some:(fun height -> Px height) height) ~max_h
      ~axis:Column ~padding:(float padding) ~at:(x, y)
      ~scroll_step:(float row_height) label in
  let theme = ui.theme and index = panel.index in
  draw ui panel (fun paint (x, y, w, h) ->
    (* a floating sheet (a menu, a window) is the input white; a docked panel is the ground *)
    Paint.fill paint ~x ~y ~w ~h (if Option.is_some stroke then theme.input else theme.panel));
  draw_over ui panel (fun paint rect ->
    Option.iter (fun color -> let x, y, w, h = rect in
      Paint.stroke paint ~x ~y ~w ~h ~width:1. color) stroke;
    let x, y, width, height = ints rect in
    let content = int_of_float ui.l_content.(index) in
    let maximum = max 0 (content - height) in
    if maximum > 0 then begin
      let track_x = x + width - 6 and track_y = y + padding
      and track_height = max 1 (height - (2 * padding)) in
      let thumb_height = min track_height
          (max 20 (track_height * height / max 1 content)) in
      let travel = track_height - thumb_height in
      let scroll_y = int_of_float ui.scroll_y.(panel.box_slot) in
      let thumb_y = track_y + (scroll_y * travel / maximum) in
      (* no track, no arrows: a 4-point thumb *)
      Paint.fill paint ~x:(float track_x) ~y:(float thumb_y) ~w:4.
        ~h:(float thumb_height) (Theme.border theme)
    end);
  let previous_row = ui.kit_row_height and previous_padding = ui.kit_padding in
  ui.kit_row_height <- row_height; ui.kit_padding <- padding;
  Fun.protect ~finally:(fun () ->
    ui.kit_row_height <- previous_row; ui.kit_padding <- previous_padding)
    (fun () -> within ui panel f)

let panel ui = panel_with ui

let inspector_width ui =
  let rec find index =
    if index <= 0 then 280. else
    match ui.b_w.(index) with
    | Px width -> width
    | _ -> find ui.b_parent.(index) in
  find (current_parent ui)

let inspector_fit paint ~size ~width text =
  if Paint.text_width paint ~size text <= width then text else
  let rec shorten length =
    if length <= 0 then "…" else
    let shown = String.sub text 0 length ^ "…" in
    if Paint.text_width paint ~size shown <= width then shown else
    let previous = ref (length - 1) in
    while !previous > 0 && Char.code text.[!previous] land 0xc0 = 0x80 do
      decr previous
    done;
    shorten !previous in
  shorten (String.length text)

let inspector_row ui ?width ~key ~label () =
  let width = Option.value width ~default:(inspector_width ui) in
  let row_h = float ui.kit_row_height in
  (* 12, a 6-point slot for the pin dot, 8, the label, 8, the control, 12 *)
  let label_x = 26. in
  let label_w = Float.max 64. (Float.min 98. (width *. 0.26)) in
  let value_x = label_x +. label_w +. 8. in
  let stacked = float (String.length label) *. (float ui.font_size *. 0.55) > label_w in
  let control_x, control_y, control_width, height =
    if stacked then label_x, row_h +. 2., width -. label_x -. 12., 2. *. row_h
    else value_x, 2., Float.max 40. (width -. value_x -. 12.), row_h in
  let row = box ui ~w:Grow ~h:(Px height) key in
  let theme = ui.theme and hovered = hovered_within ui row in
  draw ui row (fun paint (x, y, w, h) ->
    if hovered then Paint.fill paint ~x ~y ~w ~h (Theme.faint_border theme);
    Paint.text paint ~at:(x +. label_x, y +. float (label_y ui 0 ui.kit_row_height))
      ~color:(Theme.ink_2 theme)
      (inspector_fit paint ~size:ui.font_size
         ~width:(if stacked then width -. label_x -. 12. else label_w) label));
  row, control_x, control_y, control_width

let inspector_section ui ~key ?(expanded = false) ?set_expanded label f =
  let gap = float (section_gap ui) in
  let title = box ui ~flags:(clickable lor tab_stop) ~w:Grow
      ~h:(Px (gap +. float ui.kit_row_height)) key in
  let open_ = state ui title ~default:(if expanded then 1 else 0) <> 0 in
  let open_ = Option.value set_expanded ~default:open_ in
  let signal = signal ui title in
  let open_ = if signal.clicked then not open_ else open_ in
  set_state ui title (if open_ then 1 else 0);
  if not open_ then ui.closed_section <- title.index;
  draw ui title (fun paint (x, y, w, h) ->
    paint_section paint ui (x, y +. gap, w, h -. gap) label ~open_ ~hovered:signal.hovered);
  if open_ then Some (f ()) else None

let inspector_toggle_value ui ~key ~at:(x, y) value =
  let control = box ui ~flags:(clickable lor tab_stop) ~at:(x, y)
      ~w:(Px 28.) ~h:(Px 20.) key in
  let value = if (signal ui control).clicked then not value else value in
  draw ui control (fun paint (x, y, _, _) -> paint_switch paint ui.theme ~x ~y:(y +. 3.) value);
  value

(* A switch row: the label takes the row, the switch sits at its end. *)
let inspector_toggle ui ~key ~label value =
  let width = inspector_width ui in
  let row = box ui ~w:Grow ~h:(Px (float ui.kit_row_height)) key in
  let theme = ui.theme and hovered = hovered_within ui row in
  draw ui row (fun paint (x, y, w, h) ->
    if hovered then Paint.fill paint ~x ~y ~w ~h (Theme.faint_border theme);
    Paint.text paint ~at:(x +. 26., y +. float (label_y ui 0 ui.kit_row_height))
      ~color:(Theme.ink_2 theme) (inspector_fit paint ~size:ui.font_size ~width:(width -. 78.) label));
  within ui row (fun () -> inspector_toggle_value ui
    ~key:(key ^ "-value") ~at:(width -. 40., 2.) value)

(* The selected thing's name at the display size, once per panel, over one line of detail. *)
let inspector_header ui ~key ~title ~detail =
  let display = ui.font_size * Theme.display_size / Theme.font_size in
  let line = float (display + 8) in
  let header = box ui ~flags:clip ~w:Grow ~h:(Px (12. +. line +. float ui.kit_row_height +. 8.)) key in
  draw ui header (fun paint (x, y, w, h) ->
    Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. (Theme.edge ui.theme);
    Paint.text paint ~at:(x +. float side, y +. 12.) ~size:display
      ~color:ui.theme.foreground
      (inspector_fit paint ~size:display ~width:(w -. 24.) title);
    Paint.text paint ~at:(x +. float side, y +. 12. +. line +. float (label_y ui 0 ui.kit_row_height))
      ~color:(Theme.ink_2 ui.theme)
      (inspector_fit paint ~size:ui.font_size ~width:(w -. 24.) detail));
  header

(* A text button on a row of its own. *)
let inspector_button ui ~key label =
  let row = box ui ~flags:(clickable lor tab_stop) ~w:Grow ~h:(Px (float ui.kit_row_height)) key in
  let signal = signal ui row in
  draw ui row (fun paint (x, y, w, h) ->
    let shown = inspector_fit paint ~size:ui.font_size ~width:(w -. 24.) label in
    if signal.held || signal.hovered then
      Paint.fill paint ~x:(x +. 6.) ~y:(y +. 2.) ~w:(Paint.text_width paint shown +. 12.) ~h:(h -. 4.)
        (if signal.held then Theme.pressed_fill ui.theme else Theme.hover_fill ui.theme);
    Paint.text paint ~at:(x +. float side, y +. float (label_y ui 0 ui.kit_row_height))
      ~color:ui.theme.foreground shown);
  signal.clicked

let inspector_readout ui ?width ~key ~label value =
  let row, control_x, control_y, control_width =
    inspector_row ui ?width ~key ~label () in
  draw ui row (fun paint (x, y, _, _) ->
    let shown = inspector_fit paint ~size:ui.font_size ~width:control_width value in
    Paint.text paint
      ~at:(x +. control_x +. control_width -. Paint.text_width paint shown,
           y +. control_y -. 2. +. float (label_y ui 0 ui.kit_row_height))
      ~color:ui.theme.foreground shown)

let inspector_message ui ~key message =
  let row = box ui ~w:Grow ~h:(Px (float ui.kit_row_height)) key in
  draw ui row (fun paint (x, y, w, h) ->
    Paint.circle paint ~at:(x +. 15., y +. (h /. 2.)) ~radius:3. ~fill:ui.theme.accent ();
    Paint.text paint ~at:(x +. 26., y +. float (label_y ui 0 ui.kit_row_height))
      ~color:(Theme.ink_2 ui.theme)
      (inspector_fit paint ~size:ui.font_size ~width:(w -. 38.) message))

let popup ui ?stroke ?max_height ?(dismiss_initial = true)
    ~at:(x, y) ~width ~height label f =
  let key = key_of (current_seed ui) label in
  (* Build a popup before the body it shields. Previous popups arbitrate in
     [route]; this also shields a newly opened/dismissed popup's frame. *)
  ui.modal_in_frame <- true;
  Int_table.filter_map_inplace (fun target signal ->
    if hit_within ui target key then Some signal else None) ui.signals;
  if Option.fold ~none:false ~some:(fun active -> not (hit_within ui active key)) ui.active then begin
    ui.cancelled <- ui.active_button :: ui.cancelled; ui.active <- None
  end;
  if ui.focus <> 0 && not (hit_within ui ui.focus key) then unfocus ui;
  let slot = Table.find ui.table key in
  let rect = if slot >= 0 then ui.rx.(slot), ui.ry.(slot), ui.rw.(slot), ui.rh.(slot)
    else x, y, width, height in
  let dismissed = List.exists (function
    | Event.KeyPressed Input.Escape | Event.WindowFocusLost -> true
    | Event.MousePressed (_, point) ->
        (slot >= 0 || dismiss_initial) && not (contains rect point)
    | _ -> false) ui.frame_events in
  if dismissed then None else begin
    (* Popups live at the root wherever they are built, so a pane's hit
       area never clips them, and are moved last so they paint on top. *)
    let parents = ui.parents in
    ui.parents <- [0];
    let index = ui.count in
    Fun.protect ~finally:(fun () -> ui.parents <- parents) (fun () ->
      let result = panel_with ?stroke ?max_height ui ~x ~y ~width label f in
      ui.overlays <- index :: ui.overlays;
      ui.modal_key <- Some key;
      Some result)
  end

(* A centered panel from last frame's height. *)
let modal ui ?(width = 320.) label f =
  let key = key_of (current_seed ui) label in
  let slot = Table.find ui.table key in
  if slot >= 0 then begin
    if not (Hashtbl.mem ui.modal_heights key) && Hashtbl.length ui.modal_heights >= 32 then begin
      (* ponytail: scan at most 32 heights on insertion; use LRU if this
         small working set ever needs a larger capacity. *)
      let oldest = Hashtbl.fold (fun key (_, seen) oldest -> match oldest with
        | Some (_, previous) when previous <= seen -> oldest
        | _ -> Some (key, seen)) ui.modal_heights None in
      Option.iter (fun (key, _) -> Hashtbl.remove ui.modal_heights key) oldest
    end;
    Hashtbl.replace ui.modal_heights key (ui.rh.(slot), ui.frame_number)
  end;
  let height = Option.fold ~none:0. ~some:fst (Hashtbl.find_opt ui.modal_heights key) in
  let x = Float.round (Float.max 0. ((ui.view_w -. width) /. 2.))
  and y = Float.round (Float.max 0. ((ui.view_h -. height) /. 2.)) in
  popup ui ~stroke:(Theme.border ui.theme) ~dismiss_initial:false ~at:(x, y)
    ~width ~height ~max_height:(Float.max 48. (ui.view_h -. 32.)) label f

let label ui text =
  let row = kit_row ui ~flags:none text in
  let theme = ui.theme and shown = display text in
  draw ui row (fun paint (x, y, _, h) ->
    Paint.cap paint ~at:(x +. float side, cap_y ui y h) ~color:theme.foreground shown)

(* A button is its text: a fill on hover and press, an accent underline with the keyboard. *)
let button ui text =
  let shown = display text in
  let width = (float (text_width_px ui shown) /. float (max 1 ui.density)) +. 12. in
  let extent (x, y, w, h) = x +. 6., y +. 2., Float.max 1. (Float.min width (w -. 12.)), h -. 4. in
  let row = kit_row ui ~hit:extent text in
  let signal = signal ui row in
  let theme = ui.theme and focus = focused ui row in
  draw ui row (fun paint rect ->
    let _, y, _, h = ints rect in
    let (cx, _, _, _) as control = ints (extent rect) in
    if signal.held then fill paint control (Theme.pressed_fill theme)
    else if signal.hovered then fill paint control (Theme.hover_fill theme);
    if focus then underline paint control theme.accent;
    kit_text paint (cx + 6) (label_y ui y h) shown);
  signal.clicked

let toggle ui text value =
  let row = kit_row ui ~hit:(control_hit toggle_control) text in
  let signal = signal ui row in
  let value = if signal.clicked then not value else value in
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let cx, cy, _, _ = toggle_control bounds in
    if hovered then hover_row paint ui bounds;
    kit_text paint (x + side) (label_y ui y h) shown;
    paint_switch paint theme ~x:(float cx) ~y:(float cy) value);
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

let text_caret_at ui ?size text x =
  match face ui size with
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

let clipboard_command ~command = function
  | Event.KeyPressed (Input.KeyChar key) when command ->
      Some (Char.lowercase_ascii key)
  | _ -> None

type text_edit = { mutable text : string; mutable caret : int; mutable anchor : int }

let load_text_edit ui key text =
  if ui.edit_focus <> key || ui.edit_value <> text then begin
    ui.edit_focus <- key; ui.edit_value <- text;
    ui.edit_caret <- String.length text; ui.edit_anchor <- ui.edit_caret;
    ui.edit_scroll_x <- 0.;
    ui.edit_undo <- []; ui.edit_redo <- []; ui.edit_group <- -1; ui.edit_unit <- None
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

(* Words as macOS counts them: letters, digits, underscores and every non-ASCII byte. *)
let word_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
  | c -> Char.code c >= 128

(* Option-Left: back over the separators, then over the word *)
let word_left text i =
  let i = ref i in
  while !i > 0 && not (word_char text.[!i - 1]) do decr i done;
  while !i > 0 && word_char text.[!i - 1] do decr i done;
  !i

(* Option-Right: over the separators, then to the end of the word *)
let word_right text i =
  let n = String.length text in
  let i = ref i in
  while !i < n && not (word_char text.[!i]) do incr i done;
  while !i < n && word_char text.[!i] do incr i done;
  !i

let line_start text i =
  let i = ref i in
  while !i > 0 && text.[!i - 1] <> '\n' do decr i done;
  !i

let line_end text i =
  let n = String.length text in
  let i = ref i in
  while !i < n && text.[!i] <> '\n' do incr i done;
  !i

(* what a double click selects at [i]: the word there, else the run of blanks, else the one
   punctuation character; nothing on a line break *)
let word_at text i =
  let n = String.length text in
  let class_of c = if word_char c then 1 else if c = ' ' || c = '\t' then 2
    else if c = '\n' || c = '\r' then 0 else 3 in
  let pick = if i < n && class_of text.[i] <> 0 then Some i
    else if i > 0 && class_of text.[i - 1] <> 0 then Some (i - 1) else None in
  match pick with
  | None -> i, i
  | Some p when class_of text.[p] = 3 -> p, p + 1
  | Some p ->
      let k = class_of text.[p] in
      let a = ref p and b = ref (p + 1) in
      while !a > 0 && class_of text.[!a - 1] = k do decr a done;
      while !b < n && class_of text.[!b] = k do incr b done;
      !a, !b

(* ---- undo inside the focused text: snapshots before each change, consecutive typing as one *)

let rec bounded n = function x :: rest when n > 0 -> x :: bounded (n - 1) rest | _ -> []

let remember ui edit ~typing =
  if not (typing && edit.caret = edit.anchor && ui.edit_group = edit.caret) then begin
    ui.edit_undo <- bounded 200 ((edit.text, edit.caret, edit.anchor) :: ui.edit_undo);
    ui.edit_redo <- []
  end;
  ui.edit_group <- -1

let undo_text ui edit ~redo =
  match if redo then ui.edit_redo else ui.edit_undo with
  | [] -> false
  | (text, caret, anchor) :: rest ->
      let now = edit.text, edit.caret, edit.anchor in
      if redo then (ui.edit_redo <- rest; ui.edit_undo <- now :: ui.edit_undo)
      else (ui.edit_undo <- rest; ui.edit_redo <- now :: ui.edit_redo);
      edit.text <- text; edit.caret <- caret; edit.anchor <- anchor;
      ui.edit_group <- -1;
      true

(* an exhausted stack hands the key to the host's own undo ([passed_undo]) *)
let pass_undo ui edit ~redo =
  undo_text ui edit ~redo || (ui.passed_undo <- Some (if redo then `Redo else `Undo); false)

(* A press places the caret (Shift extends the selection), a double click selects the word
   there, a triple click the [line_of] range; the drag that follows extends by the same unit. *)
let press_select ui edit ~shift ~clicks ~line_of at =
  if clicks < 2 then begin
    edit.caret <- at;
    if not shift then edit.anchor <- at;
    ui.edit_unit <- None
  end else begin
    let a, b = if clicks = 2 then word_at edit.text at else line_of at in
    edit.anchor <- a; edit.caret <- b;
    ui.edit_unit <- Some (a, b, clicks)
  end

let drag_select ui edit ~line_of at =
  match ui.edit_unit with
  | None -> edit.caret <- at
  | Some (a, b, clicks) ->
      let c, d = if clicks = 2 then word_at edit.text at else line_of at in
      if c < a then (edit.anchor <- b; edit.caret <- c)
      else (edit.anchor <- a; edit.caret <- max b d)

let point_text_caret ui ?size edit signal ~shift ~x ~right =
  let at (px, _) = text_caret_at ui ?size edit.text
    (Float.max 0. (Float.min right px -. x +. ui.edit_scroll_x)) in
  let line_of _ = 0, String.length edit.text in
  if signal.pressed then
    press_select ui edit ~shift ~clicks:signal.clicks ~line_of (at signal.press_point);
  if signal.dragging || (signal.held && signal.pointer <> signal.press_point) then begin
    let px = fst signal.pointer in
    if px < x then ui.edit_scroll_x <- Float.max 0.
      (ui.edit_scroll_x -. Float.max 1. (Float.min 24. ((x -. px) *. 0.25)))
    else if px > right then ui.edit_scroll_x <- ui.edit_scroll_x +.
      Float.max 1. (Float.min 24. ((px -. right) *. 0.25));
    drag_select ui edit ~line_of (at signal.pointer)
  end

(* The keys every text widget shares, as macOS binds them: Command-A/C/X/V, Command-Z and
   Shift-Command-Z (or Command-Y) undo and redo, Option-arrows move by words, Command-arrows
   and Home/End by lines, Option-Backspace/Delete take a word, Command-Backspace/Delete the
   line to the caret.  Returns whether the text changed. *)
let edit_text_event ui edit ~accept ~modifiers event =
  let command = command_modifiers modifiers
  and shift = List.mem Input.Shift modifiers
  and alt = List.mem Input.Alt modifiers in
  let selected () = edit.caret <> edit.anchor in
  let move target =
    edit.caret <- target;
    if not shift then edit.anchor <- target in
  (* the selection, else from the caret to [target] *)
  let delete_to target =
    if (not (selected ())) && target = edit.caret then false else begin
      remember ui edit ~typing:false;
      if not (selected ()) then edit.anchor <- target;
      replace_text edit ""; true
    end in
  match event with
  | event when clipboard_command ~command event = Some 'a' ->
      edit.anchor <- 0; edit.caret <- String.length edit.text; false
  | event when clipboard_command ~command event = Some 'c' ->
      let start, stop = text_selection edit in
      ignore (Clipboard.set_text (if selected () then
        String.sub edit.text start (stop - start) else edit.text)); false
  | event when clipboard_command ~command event = Some 'x' ->
      let start, stop = text_selection edit in
      let copied = if selected () then
        String.sub edit.text start (stop - start) else edit.text in
      if Clipboard.set_text copied = Ok () then begin
        remember ui edit ~typing:false;
        if selected () then replace_text edit "" else begin
          edit.text <- ""; edit.caret <- 0; edit.anchor <- 0
        end;
        true
      end else false
  | event when clipboard_command ~command event = Some 'v' ->
      (match Clipboard.get_text () with
       | Ok text when accept text -> remember ui edit ~typing:false; replace_text edit text; true
       | Ok _ | Error _ -> false)
  | event when clipboard_command ~command event = Some 'z' -> pass_undo ui edit ~redo:shift
  | event when clipboard_command ~command event = Some 'y' -> pass_undo ui edit ~redo:true
  | Event.TextInput text when accept text ->
      let typing = not (String.exists (function ' ' | '\t' | '\n' -> true | _ -> false) text) in
      remember ui edit ~typing;
      replace_text edit text;
      if typing then ui.edit_group <- edit.caret;
      true
  | Event.KeyPressed Input.Backspace ->
      delete_to (if command then line_start edit.text edit.caret
        else if alt then word_left edit.text edit.caret
        else previous_utf8 edit.text edit.caret)
  | Event.KeyPressed Input.Delete ->
      delete_to (if command then line_end edit.text edit.caret
        else if alt then word_right edit.text edit.caret
        else next_utf8 edit.text edit.caret)
  | Event.KeyPressed Input.ArrowLeft ->
      move (if command then line_start edit.text edit.caret
        else if alt then word_left edit.text edit.caret
        else if selected () && not shift then fst (text_selection edit)
        else previous_utf8 edit.text edit.caret);
      false
  | Event.KeyPressed Input.ArrowRight ->
      move (if command then line_end edit.text edit.caret
        else if alt then word_right edit.text edit.caret
        else if selected () && not shift then snd (text_selection edit)
        else next_utf8 edit.text edit.caret);
      false
  | Event.KeyPressed Input.Home -> move (line_start edit.text edit.caret); false
  | Event.KeyPressed Input.End -> move (line_end edit.text edit.caret); false
  | _ -> false

let paint_text_edit paint ?size ~control:(cx, cy, cw, ch) ~y ~composition edit =
  let ui = paint.owner in
  let theme = ui.theme in
  let width text = Paint.text_width paint ?size text /. paint.scale in
  let before = String.sub edit.text 0 edit.caret in
  let visible = float (max 1 (cw - 4)) in
  let scroll = Float.max 0. (Float.min ui.edit_scroll_x
    (Float.max 0. (width edit.text -. visible))) in
  let caret_width = width before in
  let scroll = if caret_width < scroll then caret_width
    else if caret_width -. scroll > visible then caret_width -. visible
    else scroll in
  ui.edit_scroll_x <- scroll;
  let text_x = float (cx + 2) -. scroll in
  let caret_x = text_x +. caret_width in
  Paint.input_region paint ~x:(float cx) ~y:(float cy) ~w:(float cw)
    ~h:(float ch) ~focused:true ~cursor:(caret_x -. float cx) ();
  let previous_clip = paint.clip_rect in
  paint.clip_rect <- intersect previous_clip
    ((float cx *. paint.scale) +. paint.tx,
     (float cy *. paint.scale) +. paint.ty,
     float cw *. paint.scale, float ch *. paint.scale);
  if edit.caret <> edit.anchor then begin
    let start, stop = text_selection edit in
    Paint.fill paint
      ~x:(text_x +. width (String.sub edit.text 0 start))
      ~y:(float (cy + 2))
      ~w:(width (String.sub edit.text start (stop - start)))
      ~h:(float (max 1 (ch - 4))) (Theme.tint theme)
  end;
  if composition = "" then Paint.text paint ?size ~at:(text_x, float y) edit.text
  else begin
    Paint.text paint ?size ~at:(text_x, float y) before;
    Paint.text paint ?size ~at:(caret_x, float y) composition;
    Paint.text paint ?size ~at:(caret_x +. width composition, float y)
      (String.sub edit.text edit.caret
        (String.length edit.text - edit.caret))
  end;
  Paint.line paint ~from_:(caret_x, float (cy + 3))
    ~to_:(caret_x, float (cy + ch - 3)) ~width:1. theme.accent;
  paint.clip_rect <- previous_clip

(* Numeric label editing shared by float and integer sliders. The retained
   state records validity; [parse] validates the edit buffer. *)
let rec numeric_editor ?size ?control ?(click_to_edit = false)
    ?(edit_request = false) ?(alt_to_edit = false)
    ?(accept = String.for_all numeric_character) ui row signal ~keys ~current ~parse =
  let enter = function
    | Event.KeyPressed Input.Enter, modifiers -> not (command_modifiers modifiers)
    | _ -> false in
  let bounds = ints (rect ui row) in
  let control_bounds = Option.value ~default:(value_control bounds) control in
  let control = control_bounds in
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
      let (cx, _, cw, _) = control in
      point_text_caret ui ?size edit signal ~shift:(press_shift ui row)
        ~x:(float (cx + 2)) ~right:(float (cx + cw - 2));
      List.iter (fun ((event : Event.t), modifiers) -> match event with
        | Event.KeyPressed Input.Enter when not (command_modifiers modifiers) ->
            (match parse edit.text with
             | Some value -> committed := Some value
             | None -> state := 0)
        | Event.KeyPressed Input.Escape -> cancelled := true
        | event ->
            if edit_text_event ui edit ~modifiers
                ~accept event then
              state := if parse edit.text <> None then 1 else 0) keys;
      if !cancelled then (finish (); unfocus ui; None, false)
      else (match !committed with
        | Some value -> finish (); unfocus ui; Some value, false
        | None ->
            save_text_edit ui edit;
            set edit.text ~valid:(!state land 1 <> 0);
            None, true)
  | None ->
      let click = click_to_edit && signal.clicked
        && abs_float (fst signal.release_point -. fst signal.press_point) < 4.
        && abs_float (snd signal.release_point -. snd signal.press_point) < 4. in
      if edit_request || (alt_to_edit && signal.clicked
          && List.mem Input.Alt (press_keys ui row)) || click
          || (signal.double_clicked && not (inside_control signal.press_point))
          || (focused ui row && List.exists enter keys) then begin
        let text = current () in
        set text ~valid:true;
        focus ui row;
        ui.edit_focus <- row.box_key; ui.edit_value <- text;
        ui.edit_caret <- String.length text; ui.edit_anchor <- 0;
        ui.edit_scroll_x <- 0.;
        let rec after_enter = function
          | event :: rest when enter event -> rest
          | _ :: rest -> after_enter rest | [] -> [] in
        let keys = if signal.double_clicked || signal.clicked then keys else after_enter keys in
        numeric_editor ?size ~control:control_bounds ~click_to_edit ~accept ui row
          { signal with keys = List.map fst keys; pressed = false;
            clicked = false; double_clicked = false } ~keys ~current ~parse
      end else None, false

let value_field ui ~at ~w ~h ?size ?display ?fraction ?slide ?scrub ?(left = false)
    ?(edit = false) ~valid label value =
  let box = box ui ~flags:(clickable lor tab_stop lor blocking lor clip)
    ~at ~w:(Px w) ~h:(Px h) label in
  let signal = signal ui box in
  let bounds = ints (rect ui box) in
  let slider = Option.is_some slide || Option.is_some scrub in
  let typed, editing = numeric_editor ?size ~control:bounds
    ~click_to_edit:(not slider) ~edit_request:edit ~alt_to_edit:slider
    ~accept:(fun _ -> true) ui box signal ~keys:(key_events ui box)
    ~current:(fun () -> value) ~parse:(fun text -> if valid text then Some text else None) in
  if editing then ui.b_flags.(box.index) <- clickable lor focusable lor blocking lor clip;
  let origin = if signal.pressed then begin
      ui.scrub_origin <- Some (box.box_key, value); value
    end else match ui.scrub_origin with
      | Some (key, origin) when key = box.box_key -> origin | _ -> value in
  let value = match typed with
    | Some text -> text
    | None when not editing && (signal.pressed || signal.held || signal.released)
        && signal.button = Some Input.LeftButton
        && not (List.mem Input.Alt (press_keys ui box)) ->
        let pointer = if signal.released then signal.release_point else signal.pointer in
        (match slide, scrub with
         | Some slide, _ -> slide (fraction_at bounds (fst pointer))
         | None, Some scrub -> scrub origin (fst pointer -. fst signal.press_point)
             (List.mem Input.Shift (press_keys ui box))
         | None, None -> value)
    | _ -> value in
  if not signal.held && Option.fold ~none:false
      ~some:(fun (key, _) -> key = box.box_key) ui.scrub_origin then ui.scrub_origin <- None;
  let buffer = text_state ui box in
  let edit = if editing && focused ui box then
      load_text_edit ui box.box_key (Option.value ~default:value buffer)
    else { text = value; caret = 0; anchor = 0 } in
  let composition = ui.composition and focus = focused ui box in
  let display = if typed <> None || signal.held || signal.released then value
    else Option.value ~default:value display in
  let invalid = state ui box ~default:1 land 1 = 0 in
  draw ui box (fun paint rect ->
    let (x, y, w, h) as bounds = ints rect in
    let previous_clip = paint.clip_rect in
    paint.clip_rect <- intersect previous_clip
      ((float x *. paint.scale) +. paint.tx, (float y *. paint.scale) +. paint.ty,
       float w *. paint.scale, float h *. paint.scale);
    underline paint bounds (if invalid then Theme.invalid
      else if editing then ui.theme.accent else Theme.edge ui.theme);
    let text_y = y + max 1 ((h - Option.value ~default:ui.font_size size - 3) / 2) in
    if editing && focus then paint_text_edit paint ?size ~control:bounds ~y:text_y ~composition edit
    else begin
      (* the 2-point line under the value is its position in the soft range *)
      Option.iter (fun f -> Paint.fill paint ~x:(float x) ~y:(float (y + h - 2))
        ~w:(float w *. Float.max 0. (Float.min 1. f)) ~h:2. (Theme.ink_2 ui.theme)) fraction;
      let width = Paint.text_width paint ?size display in
      Paint.text paint ?size ~at:((if left then float (x + 2)
        else float (x + w - 2) -. width), float text_y) display
    end;
    paint.clip_rect <- previous_clip);
  value, editing

let keyboard_fraction keys ~step value =
  List.fold_left (fun value (event, modifiers) ->
    let step = step *. (if List.mem Input.Shift modifiers then 10. else 1.) in
    match event with
    | Event.KeyPressed (Input.ArrowLeft | ArrowDown) ->
        Float.max 0. (value -. step)
    | Event.KeyPressed (Input.ArrowRight | ArrowUp) ->
        Float.min 1. (value +. step)
    | Event.KeyPressed Input.Home -> 0.
    | Event.KeyPressed Input.End -> 1.
    | _ -> value) value keys

let slider_row ui text ~draw_value ~value_text ~fraction_of ~from_fraction ~step ~parse
    ~current value =
  let row = kit_row ui text in
  let signal = signal ui row in
  let bounds = ints (rect ui row) in
  let control = value_control bounds in
  let in_control point = contains (floats control) point in
  let typed, editing = numeric_editor ui row signal ~keys:(key_events ui row)
      ~current:(fun () -> current value)
      ~parse in
  if editing then ui.b_flags.(row.index) <- clickable lor focusable lor blocking;
  let dragging = not editing && (signal.held || signal.released)
    && in_control signal.press_point in
  let value = match typed with
    | Some typed -> typed
    | None when dragging ->
        let x = if signal.released then fst signal.release_point
          else fst signal.pointer in
        from_fraction value (fraction_at control x)
    | None when not editing ->
        let fraction = fraction_of value in
        let adjusted = keyboard_fraction (key_events ui row) ~step fraction in
        if adjusted = fraction then value else from_fraction value adjusted
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
    kit_text paint ~color:(Theme.ink_2 theme) (x + side) (label_y ui y h) shown;
    match edit with
    | Some text ->
        underline paint control (if valid then theme.accent else Theme.invalid);
        if focused then paint_text_edit paint ~control ~y:(label_y ui y h)
          ~composition { text; caret = edit_caret; anchor = edit_anchor }
        else kit_text paint (cx + 2) (label_y ui y h) text
    | None ->
        let marker = position control (fraction_of value) in
        underline paint control (Theme.edge theme);
        fill paint (cx, cy + ch - 2, max 1 (marker - cx + 1), 2)
          (if pressed then theme.foreground else Theme.ink_2 theme);
        if draw_value then begin
          let text = value_text value in
          Paint.text paint ~at:(float (cx + cw - 2) -. Paint.text_width paint text,
            float (label_y ui y h)) text
        end);
  value

let slider ui text ~range:(low, high) value =
  if not (Float.is_finite low && Float.is_finite high) || high <= low then
    invalid_arg "Ui.slider: range must be finite and increasing";
  if not (Float.is_finite value) then invalid_arg "Ui.slider: value must be finite";
  slider_row ui text ~draw_value:true ~value_text:compact_float ~step:0.01
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
    ~step:(1. /. float (high - low))
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
    let (cx, _, cw, _) = value_control (ints (rect ui row)) in
    point_text_caret ui edit signal ~shift:(press_shift ui row)
      ~x:(float (cx + 2)) ~right:(float (cx + cw - 2));
    List.iter (fun (event, modifiers) -> ignore (edit_text_event ui edit ~modifiers
      ~accept:(fun _ -> true) event)) (key_events ui row);
    save_text_edit ui edit
  end;
  let value = edit.text in
  let theme = ui.theme and shown = display text and composition = ui.composition in
  let hovered = signal.hovered in
  (* the I-beam over the value, as in any text field *)
  (let (px, py) = ui.pointer in
   let (cx, cy, cw, ch) = value_control (ints (rect ui row)) in
   if hovered && px >= float cx && px < float (cx + cw)
      && py >= float cy && py < float (cy + ch) then request_cursor ui `Text);
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    if hovered then hover_row paint ui bounds;
    kit_text paint ~color:(Theme.ink_2 theme) (x + side) (label_y ui y h) shown;
    underline paint control (if focused then theme.accent else Theme.edge theme);
    if focused then paint_text_edit paint ~control ~y:(label_y ui y h)
      ~composition edit
    else begin
      Paint.input_region paint ~x:(float cx) ~y:(float cy) ~w:(float cw)
        ~h:(float ch) ~focused:false ();
      kit_text paint (cx + 2) (label_y ui y h) value
    end);
  value

(* Multiline text: the same focus, IME composition, clipboard and edit
   events as [text_field] ([edit_text_event], the [ui.edit_*] retained
   state); added are Enter, Tab (two spaces), the vertical keys and row-scoped Home/End,
   and the pointer maps to (row, column).  With [wrap] a long line continues on the next row
   (DepartureMono is monospaced: a row holds as many characters as fit).  ponytail: rows are
   found per frame (O(text)), only visible rows are drawn. *)
let text_width ui ?size text =
  match face ui size with
  | None -> 0.
  | Some font ->
      let density = float ui.density in
      let rec sum index width =
        if index >= String.length text then width else
          let decoded = String.get_utf_8_uchar text index in
          let advance = match glyph ui.atlas font ~density:ui.density
              (Uchar.to_int (Uchar.utf_decode_uchar decoded)) with
            | Some glyph -> float glyph.advance /. density | None -> 0. in
          sum (index + Uchar.utf_decode_length decoded) (width +. advance) in
      sum 0 0.

(* The rows of a text: (start, stop, logical line) with [stop] exclusive and before the newline.
   Without [cols] a row is a line; with it a line continues every [cols] characters. *)
let text_rows ?cols text =
  let n = String.length text in
  let rows = ref [] in
  let rec line start logical =
    let stop = match String.index_from_opt text start '\n' with Some i -> i | None -> n in
    let rec chunk from = match cols with
      | None -> rows := (from, stop, logical) :: !rows
      | Some cols ->
          let rec advance i k =
            if k = 0 || i >= stop then i
            else advance (i + Uchar.utf_decode_length (String.get_utf_8_uchar text i)) (k - 1) in
          let upto = advance from (max 1 cols) in
          if upto >= stop then rows := (from, stop, logical) :: !rows
          else (rows := (from, upto, logical) :: !rows; chunk upto) in
    chunk start;
    if stop < n then line (stop + 1) (logical + 1) in
  line 0 0;
  Array.of_list (List.rev !rows)

(* the row holding byte [index] *)
let row_at rows index =
  let start i = let s, _, _ = rows.(i) in s in
  let rec seek low high =
    if low >= high then low else
      let middle = (low + high + 1) / 2 in
      if start middle <= index then seek middle high else seek low (middle - 1) in
  seek 0 (Array.length rows - 1)

let context_clicked (signal : signal) =
  let (px, py), (rx, ry) = signal.press_point, signal.release_point in
  signal.released && signal.button = Some Input.RightButton
  && ((px -. rx) *. (px -. rx)) +. ((py -. ry) *. (py -. ry)) < 16.

(* What a code editor knows about its text: colours by byte span, matching bracket pairs, the
   indentation of a new line, the brackets typed in pairs, ranked completions for the token at
   the caret, a description of the token under the pointer, and the numeric literals a drag
   changes.  A host supplies it; the widget stays language-free. *)
type completion = {
  replace : int * int;  (* the byte span [insert] replaces *)
  insert : string;
  label : string;  (* the row *)
  detail : string;  (* the row's right column: a type, a category *)
  doc : string;  (* one line under the rows while the row is selected *)
}

type language = {
  colorize : string -> (int * int * Color.t) list;  (* sorted, non-overlapping byte spans *)
  brackets : string -> (int * int) list;  (* (open, close) byte positions of matched pairs *)
  indent : string -> int -> string;  (* the indentation of a line broken at this byte *)
  pairs : (char * char) list;  (* typing the first inserts both; the second skips over itself *)
  complete : string -> int -> completion list;  (* ranked, for the token ending at the caret *)
  describe : string -> int -> (int * int * string) option;  (* the token at a byte and its doc *)
  number_at : string -> int -> (int * int) option;  (* the numeric literal at a byte *)
  rewrite : (string -> int -> string * int) option;
  (* [rewrite text caret] after an edit: the text as the language keeps it (parinfer), and
     where [caret] lands in it *)
}

(* A box at the root, laid out and painted after every pane (like a tooltip), so a popup under
   a caret is never clipped by its pane. *)
let overlay_box ui ?flags ~at ~w ~h label =
  let parents = ui.parents and seeds = ui.seeds in
  ui.parents <- [0]; ui.seeds <- [0x2c1b3c6d];
  Fun.protect ~finally:(fun () -> ui.parents <- parents; ui.seeds <- seeds) (fun () ->
    let overlay = box ui ?flags ~w:(Px w) ~h:(Px h) ~at label in
    ui.overlays <- overlay.index :: ui.overlays;
    overlay)

(* A number literal dragged [dx] points: a float moves a tenth of its last decimal place per
   point (Shift: ten times that) and keeps one more decimal; an integer moves one per five
   points (Shift: one per point). *)
let scrubbed literal dx ~coarse =
  match String.index_opt literal '.', int_of_string_opt literal with
  | None, Some v -> string_of_int (v + int_of_float (Float.round (dx /. (if coarse then 1. else 5.))))
  | Some dot, _ ->
      let decimals = String.length literal - dot - 1 in
      let step = (10. ** float (- (decimals + 1))) *. (if coarse then 10. else 1.) in
      let v = (match float_of_string_opt literal with Some v -> v | None -> 0.) +. (dx *. step) in
      let s = Printf.sprintf "%.*f" (decimals + 1) v in
      let n = ref (String.length s) in
      while !n > 0 && s.[!n - 1] = '0' do decr n done;
      if !n > 0 && s.[!n - 1] = '.' then String.sub s 0 (!n + 1) else String.sub s 0 !n
  | None, None -> literal

let text_area_submit ui ~at ~w ~h ?(readonly = false) ?(wrap = false) ?(errors = []) ?(spans = [])
    ?reveal ?language ?on_context ?on_scrub ?on_click ?on_caret ?on_drop ?(chips = []) label text =
  (* a line of code is one and a half times its text, as code editors set it (17 points at 11,
     20 at 13): the 24-point row is a control's, twice the text *)
  let row = float (text_line_height ui) in
  let body = box ui
      ~flags:(clickable lor focusable lor blocking lor scroll lor clip
              lor (if readonly then 0 else keep_tab))
      ~at ~w:(Px w) ~h:(Px h) ~scroll_step:row label in
  let char_w = text_width ui "0" in
  let columns_of count =
    if not wrap then None
    else
      let gutter = 16. +. char_w *. float (max 3 (String.length (string_of_int count))) in
      Some (int_of_float (Float.floor (Float.max 1. (w -. gutter -. 16.) /. Float.max 1. char_w))) in
  (* the gutter width follows the number of logical lines, the wrap width follows the gutter *)
  let rows_of text =
    let logical = 1 + String.fold_left (fun n c -> if c = '\n' then n + 1 else n) 0 text in
    text_rows ?cols:(columns_of logical) text in
  let rows = rows_of text in
  let count = Array.length rows in
  let logical_count rows = let _, _, l = rows.(Array.length rows - 1) in l + 1 in
  let start_of rows i = let s, _, _ = rows.(i) in s in
  let stop_of rows i = let _, e, _ = rows.(i) in e in
  let row_text text rows i = String.sub text (start_of rows i) (stop_of rows i - start_of rows i) in
  (* the content box scrolls; two empty boxes keep the completion popup's and the number
     scrub's state between frames *)
  let content, suggest, scrub = within ui body (fun () ->
    let content = box ui ~w:(Px w) ~h:(Px (float count *. row)) (label ^ "-content") in
    let suggest = box ui ~w:(Px 0.) ~h:(Px 0.) ~at:(0., 0.) (label ^ "-suggest") in
    let scrub = box ui ~w:(Px 0.) ~h:(Px 0.) ~at:(0., 0.) (label ^ "-scrub") in
    content, suggest, scrub) in
  let signal_of = signal in
  let signal = signal ui body in
  (* the I-beam over text; a number under the pointer asks for the scrub
     cursor further down, and the last request wins *)
  if signal.hovered then request_cursor ui `Text;
  let focused = focused ui body in
  let gutter = 16. +. char_w *. float (max 3 (String.length (string_of_int (logical_count rows)))) in
  let bx, by, bw, bh = rect ui body in
  let horizontal = ref (float (state ui body ~default:0)) in
  (* the byte at a point; [strict] answers only over the row's glyphs *)
  let point_in ?(strict = false) text rows (px, py) =
    let count = Array.length rows in
    let line = max 0 (min (count - 1)
      (int_of_float (Float.floor ((py -. by +. scroll_position ui body) /. row)))) in
    let x = px -. bx -. gutter -. 4. +. !horizontal in
    let line_text = row_text text rows line in
    if strict && (x < 0. || x > text_width ui line_text || py < by || py > by +. bh) then None
    else Some (start_of rows line + text_caret_at ui line_text (Float.max 0. x)) in
  let point_at point = Option.get (point_in text rows point) in
  let edit = if focused then load_text_edit ui body.box_key text
    else { text; caret = String.length text; anchor = String.length text } in
  let moved = ref false and submitted = ref false in
  (match on_context with
   | Some f when context_clicked signal -> f signal.release_point
   | _ -> ());
  (* a press on a number arms a scrub (its state is the start + 1, negated once dragging); three
     points sideways make it one, three points down a selection as before *)
  let scrub_state = state ui scrub ~default:0 in
  let scrubbing = ref None in
  (match language with
   | Some l when not readonly && signal.pressed && signal.button = Some Input.LeftButton ->
       (match l.number_at text (point_at signal.press_point) with
        | Some (a, b) -> set_state ui scrub (a + 1); set_text_state ui scrub (Some (String.sub text a (b - a)))
        | None -> set_state ui scrub 0)
   | Some _ when scrub_state <> 0 && signal.held ->
       let dx = fst signal.pointer -. fst signal.press_point
       and dy = snd signal.pointer -. snd signal.press_point in
       if scrub_state < 0 || (Float.abs dx >= 3. && Float.abs dx >= Float.abs dy) then begin
         let start = abs scrub_state - 1 in
         set_state ui scrub (- (start + 1));
         scrubbing := Some (start, Option.value ~default:"" (text_state ui scrub), dx)
       end else if Float.abs dy >= 3. then set_state ui scrub 0
   | _ when scrub_state <> 0 && not signal.held ->
       set_state ui scrub 0;
       if scrub_state < 0 then Option.iter (fun f -> f `Done) on_scrub
   | _ -> ());
  (* the completion popup: its state is (token start + 1) * 256 + the selected row; the rows are
     built before the keys so a click on one is seen this frame *)
  let open_ = if focused then state ui suggest ~default:0 else (set_state ui suggest 0; 0) in
  let items = match language with
    | Some l when open_ <> 0 && not readonly -> Array.of_list (l.complete edit.text edit.caret)
    | _ -> [||] in
  let shown = min 8 (Array.length items) in
  let selected = ref (min (open_ land 255) (max 0 (Array.length items - 1))) in
  let first = max 0 (!selected - shown + 1) in
  let closed = ref false in
  let accept (c : completion) =
    remember ui edit ~typing:false;
    let a, b = c.replace in
    let a = max 0 (min a (String.length edit.text)) and b = max 0 (min b (String.length edit.text)) in
    edit.text <- String.sub edit.text 0 a ^ c.insert ^ String.sub edit.text b (String.length edit.text - b);
    edit.caret <- a + String.length c.insert; edit.anchor <- edit.caret;
    set_state ui suggest 0; closed := true in
  let popup = if shown = 0 then None else begin
    let doc = items.(!selected).doc in
    let width = Array.fold_left (fun w (c : completion) ->
      Float.max w (text_width ui c.label +. text_width ui c.detail +. 44.)) 220. items in
    let width = Float.min width (Float.max 120. (ui.view_w -. 16.)) in
    let height = (float (shown * ui.kit_row_height)) +. (if doc = "" then 4. else 22.) in
    let container = overlay_box ui ~flags:blocking ~at:(0., 0.) ~w:width ~h:height (label ^ "-completions") in
    let boxes = within ui container (fun () ->
      List.init shown (fun i ->
        kit_row ui ~flags:(clickable lor blocking lor keep_focus) (Printf.sprintf "row-%d" i))) in
    List.iteri (fun i r -> if (signal_of ui r).clicked then accept items.(first + i)) boxes;
    Some (container, boxes, width, height)
  end in
  if focused then begin
    let caret0 = edit.caret in
    (* a triple click takes the logical line with its break *)
    let line_of at =
      let s = line_start edit.text at and e = line_end edit.text at in
      s, (if e < String.length edit.text then e + 1 else e) in
    if signal.pressed && signal.button = Some Input.LeftButton then
      begin
        press_select ui edit ~shift:(press_shift ui body) ~clicks:signal.clicks ~line_of
          (point_at signal.press_point);
        (* a double click on true / false flips it, as dragging flips a number *)
        if signal.clicks = 2 && language <> None && not readonly then begin
          let a, b = text_selection edit in
          let flipped = match String.sub edit.text a (b - a) with
            | "true" -> Some "false" | "false" -> Some "true" | _ -> None in
          Option.iter (fun word ->
            remember ui edit ~typing:false;
            replace_text edit word; edit.anchor <- a; edit.caret <- a + String.length word) flipped
        end
      end
    else if !scrubbing = None && scrub_state = 0
        && (signal.dragging || (signal.held && signal.pointer <> signal.press_point)) then
      drag_select ui edit ~line_of (point_at signal.pointer);
    let typed = ref false and changed = ref false in
    let page = max 1 (int_of_float (bh /. row) - 1) in
    List.iter (fun ((event : Event.t), modifiers) ->
      let command = command_modifiers modifiers and shift = List.mem Input.Shift modifiers in
      let rows = rows_of edit.text in
      let count = Array.length rows in
      let x_of line index = text_width ui
        (String.sub edit.text (start_of rows line) (index - start_of rows line)) in
      let line = row_at rows edit.caret in
      let move target = edit.caret <- target; if not shift then edit.anchor <- target in
      let vertical step =
        let target = line + step in
        if target < 0 then move 0
        else if target >= count then move (String.length edit.text)
        else move (start_of rows target
          + text_caret_at ui (row_text edit.text rows target) (x_of line edit.caret)) in
      let listing = shown > 0 && not !closed in
      let change () = changed := true; remember ui edit ~typing:false in
      (match event with
      | Event.KeyPressed Input.Enter when command -> submitted := true
      (* the completion popup takes Up, Down, Tab, Enter and Escape while it is open *)
      | Event.KeyPressed ((Input.ArrowUp | Input.ArrowDown) as key) when listing ->
          let n = Array.length items in
          selected := (!selected + (if key = Input.ArrowUp then n - 1 else 1)) mod n
      | Event.KeyPressed (Input.Tab | Input.Enter) when listing && not readonly -> accept items.(!selected)
      | Event.KeyPressed Input.Escape when open_ <> 0 && not !closed -> set_state ui suggest 0; closed := true
      | Event.KeyPressed Input.Escape -> unfocus ui
      | Event.KeyPressed Input.Enter ->
          if not readonly then begin
            let indent = match language with
              | Some l -> l.indent edit.text (fst (text_selection edit)) | None -> "" in
            change (); replace_text edit ("\n" ^ indent)
          end
      (* brackets come in pairs: an opener wraps the selection or inserts both, a closer typed
         before itself steps over it, Backspace between an empty pair takes both *)
      | Event.TextInput s when language <> None && String.length s = 1 && not readonly && not command ->
          let c = s.[0] and pairs = (Option.get language).pairs in
          let start, stop = text_selection edit in
          let next = if edit.caret < String.length edit.text then Some edit.text.[edit.caret] else None in
          (match List.assoc_opt c pairs with
           | Some close when start <> stop ->
               change ();
               replace_text edit (String.make 1 c ^ String.sub edit.text start (stop - start) ^ String.make 1 close);
               edit.anchor <- start + 1; edit.caret <- stop + 1
           | _ when List.exists (fun (_, close) -> close = c) pairs && next = Some c ->
               edit.caret <- edit.caret + 1; edit.anchor <- edit.caret
           | Some close ->
               change ();
               replace_text edit (String.make 1 c ^ String.make 1 close);
               edit.caret <- edit.caret - 1; edit.anchor <- edit.caret
           | None -> changed := edit_text_event ui edit ~accept:(fun _ -> true) ~modifiers event || !changed);
          typed := true
      | Event.KeyPressed Input.Backspace when language <> None && not readonly && not command
          && edit.caret = edit.anchor && edit.caret > 0 && edit.caret < String.length edit.text
          && List.mem (edit.text.[edit.caret - 1], edit.text.[edit.caret]) (Option.get language).pairs ->
          change (); edit.anchor <- edit.caret - 1; edit.caret <- edit.caret + 1; replace_text edit ""; typed := true
      (* Command-X / C with no selection take the caret's whole logical line, newline included *)
      | Event.KeyPressed (Input.KeyChar ('x' | 'X' | 'c' | 'C' as key)) when command && edit.caret = edit.anchor ->
          let s = match String.rindex_from_opt edit.text (max 0 (edit.caret - 1)) '\n' with
            | Some i when edit.caret > 0 -> i + 1 | _ -> 0 in
          let e = match String.index_from_opt edit.text edit.caret '\n' with
            | Some i -> i + 1 | None -> String.length edit.text in
          if Clipboard.set_text (String.sub edit.text s (e - s)) = Ok ()
             && (key = 'x' || key = 'X') && not readonly then begin
            change (); edit.anchor <- s; edit.caret <- e; replace_text edit ""; typed := true
          end
      | Event.KeyPressed Input.Tab when not command && not readonly ->
          if not shift then (change (); replace_text edit "  ")
          else begin
            (* Shift-Tab: up to two spaces leave the start of the line *)
            let line_start = line_start edit.text edit.caret in
            let spaces = if line_start < String.length edit.text && edit.text.[line_start] = ' '
              then (if line_start + 1 < String.length edit.text && edit.text.[line_start + 1] = ' ' then 2 else 1)
              else 0 in
            if spaces > 0 then begin
              change ();
              edit.text <- String.sub edit.text 0 line_start
                ^ String.sub edit.text (line_start + spaces) (String.length edit.text - line_start - spaces);
              edit.caret <- max line_start (edit.caret - spaces); edit.anchor <- edit.caret
            end
          end
      | Event.KeyPressed Input.ArrowUp when command -> move 0
      | Event.KeyPressed Input.ArrowDown when command -> move (String.length edit.text)
      | Event.KeyPressed Input.ArrowUp -> vertical (-1)
      | Event.KeyPressed Input.ArrowDown -> vertical 1
      | Event.KeyPressed Input.PageUp -> vertical (-page)
      | Event.KeyPressed Input.PageDown -> vertical page
      | Event.KeyPressed (Input.Home | Input.ArrowLeft) when command || event = Event.KeyPressed Input.Home ->
          move (start_of rows line)
      | Event.KeyPressed (Input.End | Input.ArrowRight) when command || event = Event.KeyPressed Input.End ->
          move (stop_of rows line)
      | event ->
          let before = edit.text, edit.caret, edit.anchor in
          if edit_text_event ui edit ~accept:(fun _ -> true) ~modifiers event then begin
            if readonly then begin
              let text, caret, anchor = before in
              edit.text <- text; edit.caret <- caret; edit.anchor <- anchor;
              ui.edit_undo <- []; ui.edit_redo <- []
            end else begin
              changed := true;
              (match event with
               | Event.TextInput _ | Event.KeyPressed (Input.Backspace | Input.Delete) -> typed := true
               | _ -> ())
            end
          end))
      (key_events ui body);
    (* a dragged number: the literal at the press follows the pointer (the caret sits after it) *)
    Option.iter (fun (start, literal, dx) ->
      if start <= String.length edit.text && literal <> "" then begin
        let stop = ref start in
        while !stop < String.length edit.text && numeric_character edit.text.[!stop] do incr stop done;
        let coarse = match ui.input_frame with
          | Some (frame : Frame.t) -> List.mem Input.Shift frame.keys | None -> false in
        let next = scrubbed literal dx ~coarse in
        edit.text <- String.sub edit.text 0 start ^ next
          ^ String.sub edit.text !stop (String.length edit.text - !stop);
        edit.caret <- start + String.length next; edit.anchor <- edit.caret;
        set_state ui suggest 0;
        Option.iter (fun f -> f `Live) on_scrub
      end) !scrubbing;
    (* typing opens the popup on the token at the caret (the selection starts over); a popup
       left open follows the caret and closes when the caret leaves its token *)
    (match language with
     | Some l when not readonly && (!typed || (open_ <> 0 && not !closed)) ->
         (match l.complete edit.text edit.caret with
          | c :: _ when !typed -> set_state ui suggest ((fst c.replace + 1) * 256)
          | c :: _ when fst c.replace = (open_ lsr 8) - 1 ->
              set_state ui suggest ((open_ lsr 8) * 256 + !selected)
          | _ -> set_state ui suggest 0)
     | _ -> ());
    (* the language's rewrite (parinfer) after this frame's edits; the anchor maps like the caret *)
    (match language with
     | Some { rewrite = Some rewrite; _ } when !changed && not readonly ->
         let text', caret' = rewrite edit.text edit.caret in
         let anchor' = if edit.anchor = edit.caret then caret' else snd (rewrite edit.text edit.anchor) in
         edit.text <- text'; edit.caret <- caret'; edit.anchor <- anchor'
     | _ -> ());
    save_text_edit ui edit;
    moved := edit.caret <> caret0 || edit.text != text || signal.pressed
  end;
  (* scrolling: the wheel, then whatever keeps the caret (or [reveal]) in view *)
  let final = edit.text in
  if focused then Option.iter (fun f -> f edit.caret) on_caret;
  (match on_click with
   | Some f when signal.clicked && signal.button = Some Input.LeftButton && scrub_state >= 0 ->
       Option.iter (fun byte -> f byte (command_modifiers (press_keys ui body)))
         (point_in ~strict:true text rows signal.release_point)
   | _ -> ());
  (* a payload in flight over the area: the byte under the pointer, hovering or released *)
  (match on_drop with
   | Some f ->
       Option.iter (fun drop -> Option.iter (fun byte -> f byte drop) (point_in text rows signal.pointer))
         (drop_target ui body)
   | None -> ());
  let rows = if final == text then rows else rows_of final in
  let count = Array.length rows in
  (* [reveal] scrolls once per (offset, length): the content box remembers it *)
  let revealed = match reveal with
    | Some index when bw > 0.
        && state ui content ~default:0 <> (index * 1_000_003) + String.length final + 1 ->
        set_state ui content ((index * 1_000_003) + String.length final + 1); Some index
    | _ -> None in
  let target = if !moved then Some edit.caret
    else Option.map (fun index -> min (String.length final) index) revealed in
  let longest = ref 0 in
  Array.iteri (fun i _ -> longest := max !longest (stop_of rows i - start_of rows i)) rows;
  let visible = Float.max 1. (bw -. gutter -. 16.) in
  let max_x = if wrap then 0. else Float.max 0. (float !longest *. char_w -. visible) in
  horizontal := Float.max 0. (Float.min max_x (!horizontal +. fst signal.scroll *. row));
  let vertical = ref (Float.max 0. (Float.min (Float.max 0. (float count *. row -. bh))
    (scroll_offset ui body))) in
  Option.iter (fun index ->
    let line = row_at rows index in
    let top = float line *. row in
    if top < !vertical then vertical := top
    else if top +. row > !vertical +. bh then vertical := top +. row -. bh;
    let x = text_width ui (String.sub final (start_of rows line) (min index (stop_of rows line) - start_of rows line)) in
    if x < !horizontal then horizontal := x
    else if x -. !horizontal > visible then horizontal := x -. visible) target;
  set_state ui body (int_of_float !horizontal);
  if !vertical <> scroll_offset ui body then set_scroll_offset ui body !vertical;
  (* painted where the shared elastic scroll puts the content, overshoot included *)
  let offset = scroll_position ui body and horizontal = !horizontal in
  let theme = ui.theme and composition = ui.composition in
  (* the language's colours and the bracket pair at the caret, once per frame *)
  let colors = match language with Some l -> l.colorize final | None -> [] in
  let matched = match language with
    | Some l when focused ->
        let c = edit.caret in
        List.find_opt (fun (o, k) -> o = c - 1 || k = c - 1 || o = c || k = c) (l.brackets final)
    | _ -> None in
  (* the pointer over a number invites a drag; over any other token it describes it after a rest *)
  let under_pointer = match language with
    | Some _ when signal.hovered && ui.active = None && not readonly ->
        point_in ~strict:true final rows signal.pointer
    | _ -> None in
  let hovered_number = match language, under_pointer, !scrubbing with
    | _, _, Some (start, _, _) ->
        let stop = ref start in
        while !stop < String.length final && numeric_character final.[!stop] do incr stop done;
        Some (start, !stop)
    | Some l, Some byte, None -> l.number_at final byte
    | _ -> None in
  if hovered_number <> None then request_cursor ui `Horizontal_resize;
  (match language, under_pointer with
   | Some l, Some byte when hovered_number = None && open_ = 0 ->
       Option.iter (fun (start, _, doc) ->
         if doc <> "" then tooltip ui ~key:(Printf.sprintf "%s#%d" label start) ~text:doc)
         (l.describe final byte)
   | _ -> ());
  (* the completion popup sits under the caret's row (above it near the bottom of the view) *)
  let text_x0 = bx +. gutter +. 4. -. horizontal in
  let x_at index =
    let line = row_at rows index in
    text_x0 +. text_width ui (String.sub final (start_of rows line) (index - start_of rows line)) in
  Option.iter (fun (container, rows_boxes, width, height) ->
    let caret_line = row_at rows edit.caret in
    let anchor = x_at (fst items.(!selected).replace) in
    let px = Float.max 8. (Float.min (anchor -. 8.) (ui.view_w -. width -. 8.)) in
    let below = by -. offset +. (float (caret_line + 1) *. row) in
    let py = if below +. height <= ui.view_h -. 8. then below
      else Float.max 8. (by -. offset +. (float caret_line *. row) -. height) in
    set_at ui container ~at:(px, py);
    let selected = !selected in
    draw ui container (fun paint (x, y, w, h) ->
      Paint.rect paint ~x ~y ~w ~h ~fill:theme.input ~stroke:(Theme.edge theme) ();
      let doc = items.(selected).doc in
      if doc <> "" then
        Paint.text paint ~color:(Theme.muted theme)
          ~at:(x +. 8., y +. h -. 18.) (display doc));
    List.iteri (fun i r ->
      let c = items.(first + i) and hovered = (signal_of ui r).hovered in
      draw ui r (fun paint rect ->
        let (rx, ry, rw, rh) as bounds = ints rect in
        if first + i = selected then fill paint bounds theme.control
        else if hovered then hover_row paint ui bounds;
        kit_text paint ~color:theme.foreground (rx + side) (label_y ui ry rh) c.label;
        let dw = int_of_float (text_width ui c.detail) in
        kit_text paint ~color:(Theme.muted theme) (rx + rw - dw - side) (label_y ui ry rh) c.detail)) rows_boxes)
    popup;
  draw ui body (fun paint (bx, by, bw, bh) ->
    let width text = Paint.text_width paint text /. paint.scale in
    Paint.fill paint ~x:bx ~y:by ~w:bw ~h:bh (if readonly then theme.panel else theme.input);
    let previous = paint.clip_rect in
    let clip x w = paint.clip_rect <- intersect previous
      ((x *. paint.scale) +. paint.tx, (by *. paint.scale) +. paint.ty,
       w *. paint.scale, bh *. paint.scale) in
    let text_x = bx +. gutter +. 4. -. horizontal in
    Paint.fill paint ~x:(bx +. gutter) ~y:by ~w:1. ~h:bh (Theme.faint_border theme);
    let small = Paint.label_size paint in
    let first = max 0 (int_of_float (Float.floor (offset /. row)))
    and last = min (count - 1) (int_of_float (Float.floor ((offset +. bh) /. row))) in
    let caret_line = row_at rows edit.caret in
    let selected = focused && edit.caret <> edit.anchor in
    let s0, s1 = text_selection edit in
    let band line (start, stop) color y =
      let ls = start_of rows line and le = stop_of rows line in
      (* a selection runs on past the end of a row that ends a line *)
      let newline = le < String.length final && final.[le] = '\n' in
      let start = max start ls and stop = min stop (if newline then le + 1 else le) in
      if start < stop || (start <= le && stop > le) then
        let x0 = width (String.sub final ls (min start le - ls)) in
        let x1 = if stop > le then width (String.sub final ls (le - ls)) +. char_w
          else width (String.sub final ls (stop - ls)) in
        Paint.fill paint ~x:(text_x +. x0) ~y ~w:(Float.max 1. (x1 -. x0)) ~h:row color in
    for line = first to last do
      let y = by -. offset +. float line *. row in
      let text_y = y +. float (max 0 ((text_line_height ui - ui.font_size - 3) / 2)) in
      let _, _, logical = rows.(line) in
      let starts_line = line = 0 || (let _, _, before = rows.(line - 1) in before <> logical) in
      clip bx bw;
      let wrong = List.mem (logical + 1) errors and current = focused && line = caret_line in
      if wrong then Paint.fill paint ~x:bx ~y ~w:bw ~h:row (Color.with_alpha Theme.invalid 18)
      else if current then Paint.fill paint ~x:bx ~y ~w:bw ~h:row (Theme.faint_border theme);
      if starts_line then begin
        let number = string_of_int (logical + 1) in
        let number_x = bx +. gutter -. 10. -. Paint.text_width paint ~size:small number in
        if wrong then Paint.fill paint ~x:(number_x -. 10.) ~y:(y +. (row /. 2.) -. 3.) ~w:6. ~h:6. Theme.invalid;
        Paint.text paint ~size:small ~at:(number_x, text_y +. 1.)
          ~color:(if wrong then Theme.invalid else if current then theme.foreground else Theme.ink_3 theme) number
      end;
      clip (bx +. gutter) (bw -. gutter);
      List.iter (fun span -> band line span (Theme.tint theme) y) spans;
      if selected then band line (s0, s1) (Theme.tint theme) y;
      (* the bracket pair at the caret: an accent outline *)
      Option.iter (fun (o, k) -> List.iter (fun b ->
        let ls = start_of rows line and le = stop_of rows line in
        if b >= ls && b < le then
          Paint.stroke paint ~x:(text_x +. width (String.sub final ls (b - ls))) ~y:(y +. 1.)
            ~w:char_w ~h:(row -. 2.) theme.accent) [ o; k ]) matched;
      (* a number under the pointer (or being dragged) wears an accent underline *)
      Option.iter (fun (a, b) ->
        let ls = start_of rows line and le = stop_of rows line in
        if a >= ls && a < le then begin
          let x0 = width (String.sub final ls (a - ls)) and x1 = width (String.sub final ls (min b le - ls)) in
          Paint.fill paint ~x:(text_x +. x0) ~y:(y +. row -. 4.) ~w:(Float.max 1. (x1 -. x0)) ~h:2.
            (if !scrubbing <> None then theme.accent else Color.with_alpha theme.accent 160)
        end) hovered_number;
      let ls = start_of rows line and le = stop_of rows line in
      (* a colour literal wears its colour as a bar under it *)
      List.iter (fun (a, b, color) ->
        if a >= ls && a < le && b <= String.length final then
          Paint.fill paint ~x:(text_x +. width (String.sub final ls (a - ls))) ~y:(y +. row -. 5.)
            ~w:(width (String.sub final a (min b le - a))) ~h:4. color) chips;
      let line_str = String.sub final ls (le - ls) in
      if focused && line = caret_line && composition <> "" then begin
        let before = String.sub final ls (edit.caret - ls) in
        let caret_x = text_x +. width before in
        Paint.text paint ~at:(text_x, text_y) ~color:theme.foreground before;
        Paint.text paint ~at:(caret_x, text_y) ~color:theme.foreground composition;
        Paint.text paint ~at:(caret_x +. width composition, text_y) ~color:theme.foreground
          (String.sub line_str (String.length before) (String.length line_str - String.length before))
      end else if colors = [] then Paint.text paint ~at:(text_x, text_y) ~color:theme.foreground line_str
      else begin
        (* the row in coloured runs, the gaps in the foreground colour; ponytail: every row scans
           the whole colour list (visible rows x tokens), fine for workspace-sized text *)
        let at a = text_x +. width (String.sub final ls (a - ls)) in
        let run a b color = if a < b then Paint.text paint ~at:(at a, text_y) ~color (String.sub final a (b - a)) in
        let pos = List.fold_left (fun pos (a, b, color) ->
          let a = max a ls and b = min b le in
          if a >= b || a < pos then pos else (run pos a theme.foreground; run a b color; b)) ls colors in
        run pos le theme.foreground
      end
    done;
    clip (bx +. gutter) (bw -. gutter);
    if focused then begin
      let y = by -. offset +. float caret_line *. row in
      let caret_x = text_x +. width (String.sub final (start_of rows caret_line)
        (edit.caret - start_of rows caret_line)) in
      Paint.input_region paint ~x:bx ~y ~w:bw ~h:row ~focused:true ~cursor:(caret_x -. bx) ();
      Paint.line paint ~from_:(caret_x, y +. 2.) ~to_:(caret_x, y +. row -. 2.) ~width:1. theme.accent
    end else Paint.input_region paint ~x:bx ~y:by ~w:bw ~h:bh ~focused:false ();
    paint.clip_rect <- previous);
  final, !submitted

let text_area ui ~at ~w ~h ?readonly ?errors ?spans ?reveal ?language label text =
  fst (text_area_submit ui ~at ~w ~h ?readonly ?errors ?spans ?reveal ?language label text)

let choice ui text options selected =
  let options = Array.of_list options in
  let count = Array.length options in
  if count = 0 then invalid_arg "Ui.choice: options must not be empty";
  if selected < 0 || selected >= count then
    invalid_arg "Ui.choice: selected index is out of bounds";
  let row = kit_row ui ~hit:(control_hit value_control) text in
  let signal = signal ui row in
  let selected =
    let direction = List.fold_left (fun direction -> function
      | Event.KeyPressed (Input.ArrowLeft | ArrowDown) -> direction - 1
      | Event.KeyPressed (Input.ArrowRight | ArrowUp) -> direction + 1
      | _ -> direction) 0 signal.keys in
    if direction <> 0 then ((selected + direction) mod count + count) mod count
    else if not signal.clicked then selected else
      let cx, _, cw, _ = value_control (ints (rect ui row)) in
      let direction = if signal.button <> None
        && fst signal.release_point < float (cx + (cw / 2)) then -1 else 1 in
      (selected + direction + count) mod count in
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered and pressed = signal.held in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    if hovered then hover_row paint ui bounds;
    kit_text paint ~color:(Theme.ink_2 theme) (x + side) (label_y ui y h) shown;
    underline paint control (if pressed then theme.accent else Theme.edge theme);
    kit_text paint (cx + 2) (label_y ui y h) options.(selected);
    Paint.chevron paint ~at:(float (cx + cw - 6), float cy +. (float ch /. 2.)) `Down theme.foreground);
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
    end else
      let handle = state ui row ~default:0 in
      let handle = if signal.clicked && signal.button = None then 1 - handle else handle in
      set_state ui row handle; handle in
  let lower, upper =
    if signal.held || signal.released then
      let x = if signal.released then fst signal.release_point else fst signal.pointer in
      let value = low +. (fraction_at control x *. (high -. low)) in
      if handle = 0 then Float.min value upper, upper
      else lower, Float.max value lower
    else
      let current = if handle = 0 then lower else upper in
      let fraction = fraction current in
      let adjusted = keyboard_fraction (key_events ui row) ~step:0.01 fraction in
      if adjusted = fraction then lower, upper else
        let value = low +. (adjusted *. (high -. low)) in
        if handle = 0 then Float.min value upper, upper
        else lower, Float.max value lower in
  let theme = ui.theme and shown = display text and hovered = signal.hovered in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    let low_x = position control (fraction lower)
    and high_x = position control (fraction upper) in
    if hovered then hover_row paint ui bounds;
    kit_text paint ~color:(Theme.ink_2 theme) (x + side) (label_y ui y h) shown;
    underline paint control (Theme.edge theme);
    fill paint (low_x, cy + ch - 2, max 1 (high_x - low_x + 1), 2) (Theme.ink_2 theme);
    kit_text paint (cx + 2) (label_y ui y h) (compact_float lower);
    let upper = compact_float upper in
    Paint.text paint ~at:(float (cx + cw - 2) -. Paint.text_width paint upper, float (label_y ui y h)) upper);
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
    else
      List.fold_left (fun (px, py) -> function
        | Event.KeyPressed Input.ArrowLeft -> clamp x_min x_max (px -. (x_max -. x_min) *. 0.01), py
        | Event.KeyPressed Input.ArrowRight -> clamp x_min x_max (px +. (x_max -. x_min) *. 0.01), py
        | Event.KeyPressed Input.ArrowUp -> px, clamp y_min y_max (py -. (y_max -. y_min) *. 0.01)
        | Event.KeyPressed Input.ArrowDown -> px, clamp y_min y_max (py +. (y_max -. y_min) *. 0.01)
        | _ -> px, py) (px, py) signal.keys in
  let theme = ui.theme and shown = display text in
  let hovered = signal.hovered and pressed = signal.held in
  draw ui row (fun paint rect ->
    let (x, y, _, h) as bounds = ints rect in
    let (cx, cy, cw, ch) as control = value_control bounds in
    let knob_x = position control ((px -. x_min) /. (x_max -. x_min)) in
    let knob_y = cy + int_of_float (((py -. y_min) /. (y_max -. y_min)
      *. float (max 1 (ch - 1))) +. 0.5) in
    if hovered then hover_row paint ui bounds;
    kit_text paint ~color:(Theme.ink_2 theme) (x + side) (label_y ui y h) shown;
    framed paint control ~fill:theme.input ~stroke:(Theme.border theme);
    kit_line paint ~from_:(cx + (cw / 2), cy + 1) ~to_:(cx + (cw / 2), cy + ch - 1)
      (Theme.faint_border theme);
    kit_line paint ~from_:(cx + 1, cy + (ch / 2)) ~to_:(cx + cw - 1, cy + (ch / 2))
      (Theme.faint_border theme);
    kit_line paint ~from_:(knob_x, cy + 1) ~to_:(knob_x, cy + ch - 1) (Theme.border theme);
    kit_line paint ~from_:(cx + 1, knob_y) ~to_:(cx + cw - 1, knob_y) (Theme.border theme);
    Paint.circle paint ~at:(float knob_x, float knob_y)
      ~radius:(if pressed then 5.5 else 4.5) ~fill:theme.accent
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
  if ui.focus = 0 || ui.rw.(search.box_slot) = 0. then focus ui search;
  let list = box_keyed ui ~w:Grow ~h:Fit ~axis:Column (int_key search.box_key 0) in
  let search_signal = signal ui search in
  if search_signal.hovered then request_cursor ui `Text;
  let keys = key_events ui search in
  let clamp cursor = if count () = 0 then 0 else max 0 (min (count () - 1) cursor) in
  let cursor = ref (clamp (state ui search ~default:0))
  and armed = ref (state ui list ~default:(-1)) and query = ref query
  and result = ref `None in
  let edit = load_text_edit ui search.box_key !query in
  let (sx, _, sw, _) = ints (rect ui search) in
  point_text_caret ui edit search_signal ~shift:(press_shift ui search)
    ~x:(float (sx + side + 2)) ~right:(float (sx + sw - side - 2));
  let set_query text = query := text; rows := rows_of text; cursor := 0; armed := -1 in
  List.iter (fun ((event : Event.t), modifiers) -> let count = count () in
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
        ignore (edit_text_event ui edit ~modifiers ~accept:(fun _ -> true) event);
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
    let control = x + side, y + 2, max 1 (w - (2 * side)), max 1 (h - 4) in
    let cx, _, _, _ = control in
    underline paint control theme.accent;
    if edit.text = "" then
      kit_text paint ~color:(Theme.ink_3 theme) (cx + 2)
        (label_y ui y h) placeholder;
    paint_text_edit paint ~control ~y:(label_y ui y h) ~composition edit);
  within ui list (fun () ->
    for visible = 0 to length - 1 do
      let index = start + visible in
      let row = box_keyed ui ~flags:(clickable lor focusable lor blocking) ~w:Grow
          ~h:(Px (float ui.kit_row_height)) (int_key list.box_key visible) in
      let row_signal = signal ui row in
      if !result = `None && row_signal.clicked then result := `Pick index;
      let current = index = !cursor and hovered = row_signal.hovered in
      let doomed = index = !armed in
      let text, detail = rows.(index) in
      draw ui row (fun paint rect ->
        let (x, y, w, h) as bounds = ints rect in
        (* the keyboard cursor is the control fill; a row armed for deletion reads in the error colour *)
        if doomed then fill paint bounds (Theme.pressed_fill theme)
        else if current then fill paint bounds theme.control
        else if hovered then hover_row paint ui bounds;
        kit_text paint ~color:(if doomed then Theme.invalid else theme.foreground)
          (x + side) (label_y ui y h) text;
        let detail_width = int_of_float (Paint.text_width paint detail) in
        kit_text paint ~color:(Theme.muted theme)
          (x + w - detail_width - side) (label_y ui y h) detail)
    done);
  set_state ui search !cursor; set_state ui list !armed;
  !query, !result

(* A floating kit menu at [at], kept inside the frame. The host holds whether
   it is open; rows commit on press and release inside, disabled rows are
   inert, and Escape, focus loss, or a press outside dismiss it. *)
let context_menu ui ~at:(x, y) ?width ?selected ?(swatches = []) label items =
  (* the width follows the longest row; an empty label is a separator line *)
  let row_height = float ui.kit_row_height and gap = 9. in
  let swatch_pad = if List.exists Option.is_some swatches then 14. else 0. in
  let width = List.fold_left (fun w (text, _) -> Float.max w (text_width ui text +. 36. +. swatch_pad))
    (Option.value ~default:150. width) items |> Float.min ui.view_w in
  let height = List.fold_left (fun h (text, _) -> h +. (if text = "" then gap else row_height)) 12. items in
  let x = Float.max 0. (Float.min x (ui.view_w -. width))
  and y = Float.max 0. (Float.min y (ui.view_h -. height)) in
  let pad name = ignore (box ui ~flags:blocking ~w:Grow ~h:(Px 6.) name) in
  match popup ui ~stroke:(Theme.edge ui.theme) ~at:(x, y) ~width ~height label (fun () ->
      pad "menu-top";
      let picked = List.mapi (fun index (text, enabled) ->
        if text = "" then begin
          let line = box ui ~flags:blocking ~w:Grow ~h:(Px gap) (Printf.sprintf "separator-%d" index) in
          draw ui line (fun paint (x, y, w, _) ->
            Paint.fill paint ~x ~y:(y +. 4.) ~w ~h:1. (Theme.edge ui.theme));
          None
        end else begin
          let row = kit_row ui ~flags:(if enabled then clickable lor focusable lor blocking lor tab_only else blocking)
              text in
          let signal = signal ui row in
          let theme = ui.theme and shown = display text in
          draw ui row (fun paint rect ->
            let (_, y, _, h) as bounds = ints rect in
            let rx, _, _, _ = bounds in
            if enabled && signal.hovered then fill paint bounds theme.control;
            (* the current choice: a 6-point accent square before the label *)
            if selected = Some index then
              Paint.fill paint ~x:(float rx +. float side) ~y:(float y +. (float h /. 2.) -. 3.) ~w:6. ~h:6. theme.accent;
            let lead = if selected = None then 0 else 14 in
            Option.iter (fun color ->
              Paint.rect paint ~x:(float (rx + side + lead)) ~y:(float y +. float h /. 2. -. 4.)
                ~w:8. ~h:8. ~fill:color ~stroke:(Theme.edge theme) ())
              (Option.join (List.nth_opt swatches index));
            kit_text paint ~color:(if enabled then theme.foreground else Theme.ink_3 theme)
              (rx + side + lead + int_of_float swatch_pad) (label_y ui y h) shown);
          if enabled && signal.clicked then Some index else None
        end) items
      |> List.find_map Fun.id in
      pad "menu-bottom";
      picked) with
  | None -> dismiss_popup ui; `Dismiss
  | Some (Some index) -> dismiss_popup ui; `Pick index
  | Some None -> `Open

let accordion ui ?(expanded = false) ?set_expanded text f =
  let gap = section_gap ui in
  let row = box ui ~flags:(clickable lor focusable lor blocking lor tab_only) ~w:Grow
      ~h:(Px (float (ui.kit_row_height + gap))) text in
  let signal = signal ui row in
  let open_ = state ui row ~default:(if expanded then 1 else 0) = 1 in
  let open_ = match set_expanded with Some forced -> forced | None -> open_ in
  let open_ = if signal.clicked then not open_ else open_ in
  set_state ui row (if open_ then 1 else 0);
  if not open_ then ui.closed_section <- row.index;
  let shown = display text and hovered = signal.hovered in
  draw ui row (fun paint (x, y, w, h) ->
    paint_section paint ui (x, y +. float gap, w, h -. float gap) shown ~open_ ~hovered);
  if open_ then Some (f ()) else None

let expanded ui text =
  let key = key_of (current_seed ui) text in
  let slot = Table.find ui.table key in
  if slot < 0 || ui.state_values.(slot) = min_int then None
  else Some (ui.state_values.(slot) = 1)

let ( + ) left right = left lor right
