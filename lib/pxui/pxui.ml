type change =
  | Clicked of string
  | Toggled of string * bool
  | Slid of string * float
  | Int_slid of string * int
  | Text_changed of string * string
  | Selected of string * string
  | Ranged of string * float * float
  | Moved2 of string * float * float

type widget =
  | Label of string
  | Accordion of { name : string; label : string; expanded : bool }
  | Accordion_end
  | Button of { name : string; label : string }
  | Toggle of { name : string; label : string; value : bool }
  | Slider of {
      name : string;
      label : string;
      min : float;
      max : float;
      value : float;
    }
  | Int_slider of {
      name : string;
      label : string;
      min : int;
      max : int;
      value : int;
    }
  | Text_field of { name : string; label : string; value : string }
  | Choice of {
      name : string;
      label : string;
      options : string array;
      selected : int;
    }
  | Range of {
      name : string;
      label : string;
      min : float;
      max : float;
      low : float;
      high : float;
    }
  | Xy of {
      name : string;
      label : string;
      x_min : float;
      x_max : float;
      y_min : float;
      y_max : float;
      x : float;
      y : float;
    }

module Stable_store = struct
  type id = int64

  type 'a t = {
    mutable generations : int array;
    mutable occupied : bytes;
    mutable free_next : int array;
    mutable payloads : 'a option array;
    mutable free_head : int;
    mutable next_slot : int;
    mutable live : int;
  }

  let minimum_capacity = 8
  let create ?(capacity = minimum_capacity) () =
    let capacity = max minimum_capacity capacity in
    { generations = Array.make capacity 1;
      occupied = Bytes.make capacity '\000';
      free_next = Array.make capacity (-1);
      payloads = Array.make capacity None;
      free_head = -1; next_slot = 0; live = 0 }

  let capacity store = Array.length store.generations
  let length store = store.live
  let slot id = Int64.to_int (Int64.logand id 0xffff_ffffL)
  let generation id = Int64.to_int (Int64.shift_right_logical id 32)
  let make_id slot generation =
    Int64.logor (Int64.shift_left (Int64.of_int generation) 32)
      (Int64.of_int slot)

  let grow store =
    let old_capacity = capacity store in
    let new_capacity = old_capacity * 2 in
    let extend old initial =
      let fresh = Array.make new_capacity initial in
      Array.blit old 0 fresh 0 old_capacity;
      fresh in
    store.generations <- extend store.generations 1;
    let occupied = Bytes.make new_capacity '\000' in
    Bytes.blit store.occupied 0 occupied 0 old_capacity;
    store.occupied <- occupied;
    store.free_next <- extend store.free_next (-1);
    store.payloads <- extend store.payloads None

  let add store payload =
    let slot =
      if store.free_head >= 0 then begin
        let slot = store.free_head in
        store.free_head <- Array.unsafe_get store.free_next slot;
        Array.unsafe_set store.free_next slot (-1);
        slot
      end else begin
        if store.next_slot = capacity store then grow store;
        let slot = store.next_slot in
        store.next_slot <- slot + 1;
        slot
      end in
    Bytes.unsafe_set store.occupied slot '\001';
    Array.unsafe_set store.payloads slot (Some payload);
    store.live <- store.live + 1;
    make_id slot (Array.unsafe_get store.generations slot)

  let valid store id =
    let slot = slot id in
    slot >= 0 && slot < store.next_slot
    && Bytes.unsafe_get store.occupied slot = '\001'
    && Array.unsafe_get store.generations slot = generation id

  let get store id =
    if valid store id then Array.unsafe_get store.payloads (slot id) else None

  let set store id payload =
    if not (valid store id) then false
    else begin
      Array.unsafe_set store.payloads (slot id) (Some payload);
      true
    end

  let remove store id =
    if not (valid store id) then false
    else begin
      let slot = slot id in
      Array.unsafe_set store.payloads slot None;
      Bytes.unsafe_set store.occupied slot '\000';
      let generation = Array.unsafe_get store.generations slot in
      Array.unsafe_set store.generations slot
        (if generation = Int32.to_int Int32.max_int then 1 else generation + 1);
      Array.unsafe_set store.free_next slot store.free_head;
      store.free_head <- slot;
      store.live <- store.live - 1;
      true
    end
end

type id_queue = {
  mutable queued_ids : Stable_store.id array;
  mutable queued_length : int;
  mutable queued_members : bytes;
}

let make_id_queue capacity =
  { queued_ids = Array.make (max 8 capacity) 0L; queued_length = 0;
    queued_members = Bytes.make capacity '\000' }

type widget_runtime = {
  slots : widget Stable_store.t;
  mutable names : (string, Stable_store.id) Hashtbl.t;
  mutable order : Stable_store.id array;
  mutable order_length : int;
  mutable visible_order : Stable_store.id array;
  mutable visible_length : int;
  mutable kinds : bytes;
  mutable parents : int array;
  mutable first_children : int array;
  mutable next_siblings : int array;
  mutable depths : int array;
  mutable z_orders : int array;
  mutable flags : bytes;
  mutable dirty : bytes;
  mutable row_x : int array;
  mutable row_y : int array;
  mutable row_width : int array;
  mutable row_height : int array;
  mutable control_x : int array;
  mutable control_y : int array;
  mutable control_width : int array;
  mutable control_height : int array;
  mutable float_values : float array;
  mutable float_values2 : float array;
  mutable int_values : int array;
  mutable text_values : string option array;
  mutable labels : string option array;
  mutable paint_builders : Scene_command.Display_list.Builder.t option array;
  mutable paint_nodes : Prismel.Scene.node option array;
  mutable paint_text : Prismel.Font.Private.retained_text list array;
  mutable paint_segment_ids : int64 array;
  mutable paint_segment_versions : int64 array;
  mutable paint_source_bytes : int array;
  paint_cache_slots : int array;
  mutable paint_cache_next : int;
  mutable paint_cache_count : int;
  mutable paint_cache_bytes : int;
  mutable display_list_builds : int;
  mutable display_list_reuses : int;
  mutable display_list_evictions : int;
  panel_builder : Scene_command.Display_list.Builder.t;
  panel_segment_id : int64;
  mutable panel_segment_version : int64;
  mutable panel_node : Prismel.Scene.node option;
  scrollbar_builder : Scene_command.Display_list.Builder.t;
  scrollbar_segment_id : int64;
  mutable scrollbar_segment_version : int64;
  mutable scrollbar_node : Prismel.Scene.node option;
  mutable scrollbar_valid : bool;
  mutable composed_scene : Prismel.Scene.t option;
  mutable composed_layout_generation : int64;
  mutable composed_paint_generation : int64;
  mutable composed_scroll_y : int;
  mutable paint_density : int;
  mutable paint_font : Prismel.Font.t option;
  mutable paint_font_generation : int;
  mutable paint_font_size : int;
  mutable paint_theme_signature : int64;
  mutable spec_widgets : widget array;
  mutable structure_generation : int64;
  mutable layout_generation : int64;
  mutable paint_generation : int64;
  mutable mutations : int;
  mutable created : int;
  mutable removed : int;
  mutable focus_id : Stable_store.id option;
  mutable active_id : Stable_store.id option;
  mutable hover_id : Stable_store.id option;
  mutable numeric_edit_id : Stable_store.id option;
  mutable numeric_edit_text : string;
  mutable numeric_edit_valid : bool;
  mutable composition_text : string;
  reconcile_queue : id_queue;
  style_queue : id_queue;
  layout_queue : id_queue;
  prepaint_queue : id_queue;
  text_queue : id_queue;
  paint_queue : id_queue;
  compose_queue : id_queue;
  accessibility_queue : id_queue;
  mutable visible : bool;
  mutable phase : int;
  mutable reconcile_visits : int;
  mutable style_visits : int;
  mutable layout_visits : int;
  mutable prepaint_visits : int;
  mutable text_visits : int;
  mutable paint_visits : int;
  mutable compose_visits : int;
  mutable accessibility_visits : int;
  mutable panel_x : int;
  mutable panel_y : int;
  mutable panel_width : int;
  mutable panel_row_height : int;
  mutable panel_padding : int;
  mutable panel_max_height : int option;
  mutable panel_frame_max_height : int option;
  mutable panel_scroll_y : int;
  mutable content_height : int;
  mutable panel_height : int;
  mutable max_scroll : int;
  mutable layout_visible_count : int;
  mutable layout_first_visible : int;
  mutable layout_last_visible : int;
  mutable layout_visited : int;
  mutable committed_layout_generation : int64;
  mutable dead : bool;
}

type theme = {
  panel : Prismel.Color.t;
  foreground : Prismel.Color.t;
  control : Prismel.Color.t;
  input : Prismel.Color.t;
  track : Prismel.Color.t;
  accent : Prismel.Color.t;
}

let default_theme = {
  panel = Prismel.Color.rgba 10 14 20 244;
  foreground = Prismel.Color.rgb 228 236 242;
  control = Prismel.Color.rgb 29 39 49;
  input = Prismel.Color.rgb 17 24 32;
  track = Prismel.Color.rgb 48 61 72;
  accent = Prismel.Color.rgb 36 218 181;
}

let fresh_display_segment_id=Scene_command.Display_list.fresh_id

type range_handle = Low | High

type active =
  | Armed of int
  | Drag_slider of int
  | Drag_range of int * range_handle
  | Drag_xy of int

type numeric_edit = {
  index : int;
  text : string;
  valid : bool;
  replace_on_input : bool;
}

type bounds = { x : int; y : int; w : int; h : int }

type layout = {
  index : int;
  row : bounds;
  control : bounds;
}

type displayed = {
  source_index : int;
  row_index : int;
  widget : widget;
}

type layout_snapshot = {
  displayed : displayed array;
  layouts : layout option array;
  content_height : int;
  panel_height : int;
  max_scroll : int;
}

type t = {
  x : int;
  y : int;
  width : int;
  row_height : int;
  padding : int;
  theme : theme;
  font : Prismel.Font.t option;
  font_size : int;
  (* The host owns [max_height]. Reusable controls may additionally fit the
     canvas to the current frame without overwriting that authoritative cap. *)
  frame_max_height : int option;
  max_height : int option;
  mutable scroll_y : int;
  mutable widget_count : int;
  (* Reverse display order keeps both functional and compatibility builders O(1). *)
  mutable widgets : widget list;
  mutable ordered_cache : widget array option;
  mutable runtime_cache : widget_runtime option;
  mutable layout_cache : layout_snapshot option;
  mutable focus : string option;
  mutable composition : string;
  mutable pointer : (int * int) option;
  mutable hover : int option;
  mutable active : active option;
  mutable numeric_edit : numeric_edit option;
  mutable last_label_press : (int * (int * int) * float) option;
  mutable scene_cache : (t * Prismel.Scene.t) option;
}

let create ?(x = 12) ?(y = 12) ?(width = 280) ?(row_height = 32)
    ?(padding = 8) ?(theme = default_theme) ?font ?(font_size = 13)
    ?max_height () =
  if row_height < 28 then invalid_arg "Pxui.create: row_height must be at least 28";
  if padding < 0 then invalid_arg "Pxui.create: padding must be non-negative";
  if font_size <= 0 then invalid_arg "Pxui.create: font_size must be positive";
  let width = Stdlib.max 180 width in
  if width - (2 * padding) < 64 then
    invalid_arg "Pxui.create: padding leaves too little control width";
  Option.iter (fun height ->
    if height < row_height + (2 * padding) then
      invalid_arg "Pxui.create: max_height is too small for one row")
    max_height;
  {
    x;
    y;
    width;
    row_height;
    padding;
    theme;
    font;
    font_size;
    frame_max_height = None;
    max_height;
    scroll_y = 0;
    widget_count = 0;
    widgets = [];
    ordered_cache = None;
    runtime_cache = None;
    layout_cache = None;
    focus = None;
    composition = "";
    pointer = None;
    hover = None;
    active = None;
    numeric_edit = None;
    last_label_press = None;
    scene_cache = None;
  }

let append canvas widget =
  canvas.widgets <- widget :: canvas.widgets;
  canvas.widget_count <- canvas.widget_count + 1;
  canvas.ordered_cache <- None;
  canvas.runtime_cache <- None;
  canvas.layout_cache <- None

let with_widget canvas widget =
  { canvas with
    widget_count = canvas.widget_count + 1;
    widgets = widget :: canvas.widgets;
    ordered_cache = None;
    runtime_cache = None;
    layout_cache = None;
  }

let ordered_widget_array canvas =
  match canvas.ordered_cache with
  | Some widgets -> widgets
  | None ->
      let widgets = Array.of_list (List.rev canvas.widgets) in
      canvas.ordered_cache <- Some widgets;
      widgets

let ordered_widgets canvas = Array.to_list (ordered_widget_array canvas)

let widget_name = function
  | Accordion value -> Some value.name
  | Button value -> Some value.name
  | Toggle value -> Some value.name
  | Slider value -> Some value.name
  | Int_slider value -> Some value.name
  | Text_field value -> Some value.name
  | Choice value -> Some value.name
  | Range value -> Some value.name
  | Xy value -> Some value.name
  | Label _ | Accordion_end -> None

let widget_kind = function
  | Label _ -> 0
  | Accordion _ -> 1
  | Accordion_end -> 2
  | Button _ -> 3
  | Toggle _ -> 4
  | Slider _ -> 5
  | Int_slider _ -> 6
  | Text_field _ -> 7
  | Choice _ -> 8
  | Range _ -> 9
  | Xy _ -> 10

let widget_label = function
  | Label text -> Some text
  | Accordion value -> Some value.label
  | Button value -> Some value.label
  | Toggle value -> Some value.label
  | Slider value -> Some value.label
  | Int_slider value -> Some value.label
  | Text_field value -> Some value.label
  | Choice value -> Some value.label
  | Range value -> Some value.label
  | Xy value -> Some value.label
  | Accordion_end -> None

let widget_float_values = function
  | Slider value -> value.value, 0.
  | Range value -> value.low, value.high
  | Xy value -> value.x, value.y
  | _ -> 0., 0.

let widget_int_value = function
  | Int_slider value -> value.value
  | Choice value -> value.selected
  | Accordion value -> if value.expanded then 1 else 0
  | Toggle value -> if value.value then 1 else 0
  | _ -> 0

let widget_text_value = function
  | Text_field value -> Some value.value
  | _ -> None

let same_widget left right = match left, right with
  | Label left, Label right -> String.equal left right
  | Accordion left, Accordion right -> left.name = right.name
      && left.label = right.label && left.expanded = right.expanded
  | Accordion_end, Accordion_end -> true
  | Button left, Button right -> left.name = right.name && left.label = right.label
  | Toggle left, Toggle right -> left.name = right.name
      && left.label = right.label && left.value = right.value
  | Slider left, Slider right -> left.name = right.name
      && left.label = right.label && left.min = right.min && left.max = right.max
      && left.value = right.value
  | Int_slider left, Int_slider right -> left.name = right.name
      && left.label = right.label && left.min = right.min && left.max = right.max
      && left.value = right.value
  | Text_field left, Text_field right -> left.name = right.name
      && left.label = right.label && left.value = right.value
  | Choice left, Choice right -> left.name = right.name
      && left.label = right.label && left.options = right.options
      && left.selected = right.selected
  | Range left, Range right -> left.name = right.name
      && left.label = right.label && left.min = right.min && left.max = right.max
      && left.low = right.low && left.high = right.high
  | Xy left, Xy right -> left.name = right.name && left.label = right.label
      && left.x_min = right.x_min && left.x_max = right.x_max
      && left.y_min = right.y_min && left.y_max = right.y_max
      && left.x = right.x && left.y = right.y
  | _ -> false

let make_widget_runtime capacity =
  let slots = Stable_store.create ~capacity () in
  let capacity = Stable_store.capacity slots in
  { slots; names = Hashtbl.create (max 8 capacity);
    order = Array.make capacity 0L; order_length = 0;
    visible_order = Array.make capacity 0L; visible_length = 0;
    kinds = Bytes.make capacity '\000';
    parents = Array.make capacity (-1);
    first_children = Array.make capacity (-1);
    next_siblings = Array.make capacity (-1);
    depths = Array.make capacity 0; z_orders = Array.make capacity 0;
    flags = Bytes.make capacity '\000'; dirty = Bytes.make capacity '\000';
    row_x = Array.make capacity 0; row_y = Array.make capacity 0;
    row_width = Array.make capacity 0; row_height = Array.make capacity 0;
    control_x = Array.make capacity 0; control_y = Array.make capacity 0;
    control_width = Array.make capacity 0; control_height = Array.make capacity 0;
    float_values = Array.make capacity 0.;
    float_values2 = Array.make capacity 0.; int_values = Array.make capacity 0;
    text_values = Array.make capacity None; labels = Array.make capacity None;
    paint_builders = Array.make capacity None;
    paint_nodes = Array.make capacity None;
    paint_text = Array.make capacity [];
    paint_segment_ids = Array.make capacity 0L;
    paint_segment_versions = Array.make capacity 0L;
    paint_source_bytes = Array.make capacity 0;
    paint_cache_slots = Array.make 256 (-1); paint_cache_next = 0;
    paint_cache_count = 0; paint_cache_bytes = 0;
    display_list_builds = 0; display_list_reuses = 0;
    display_list_evictions = 0;
    panel_builder = Scene_command.Display_list.Builder.create ~capacity:8 ();
    panel_segment_id = fresh_display_segment_id ();
    panel_segment_version = 0L; panel_node = None;
    scrollbar_builder = Scene_command.Display_list.Builder.create ~capacity:4 ();
    scrollbar_segment_id = fresh_display_segment_id ();
    scrollbar_segment_version = 0L; scrollbar_node = None;
    scrollbar_valid = false;
    composed_scene = None; composed_layout_generation = -1L;
    composed_paint_generation = -1L; composed_scroll_y = -1;
    paint_density = 0; paint_font = None; paint_font_generation = 0;
    paint_font_size = 0; paint_theme_signature = 0L;
    spec_widgets = [||]; structure_generation = 0L; layout_generation = 0L;
    paint_generation = 0L; mutations = 0; created = 0; removed = 0;
    focus_id = None; active_id = None; hover_id = None;
    numeric_edit_id = None; numeric_edit_text = "";
    numeric_edit_valid = true; composition_text = "";
    reconcile_queue = make_id_queue capacity;
    style_queue = make_id_queue capacity;
    layout_queue = make_id_queue capacity;
    prepaint_queue = make_id_queue capacity;
    text_queue = make_id_queue capacity;
    paint_queue = make_id_queue capacity;
    compose_queue = make_id_queue capacity;
    accessibility_queue = make_id_queue capacity;
    visible = true; phase = 0;
    reconcile_visits = 0; style_visits = 0; layout_visits = 0;
    prepaint_visits = 0; text_visits = 0; paint_visits = 0;
    compose_visits = 0; accessibility_visits = 0;
    panel_x = 0; panel_y = 0; panel_width = 280; panel_row_height = 32;
    panel_padding = 8; panel_max_height = None;
    panel_frame_max_height = None; panel_scroll_y = 0;
    content_height = 0; panel_height = 0; max_scroll = 0;
    layout_visible_count = 0; layout_first_visible = 0;
    layout_last_visible = 0; layout_visited = 0;
    committed_layout_generation = 0L; dead = false }

let ensure_runtime_capacity runtime =
  let capacity = Stable_store.capacity runtime.slots in
  let old_capacity = Bytes.length runtime.kinds in
  if capacity > old_capacity then begin
    let extend_array old initial =
      let values = Array.make capacity initial in
      Array.blit old 0 values 0 old_capacity;
      values in
    let extend_bytes old =
      let values = Bytes.make capacity '\000' in
      Bytes.blit old 0 values 0 old_capacity;
      values in
    let extend_queue queue =
      let members = Bytes.make capacity '\000' in
      Bytes.blit queue.queued_members 0 members 0 old_capacity;
      queue.queued_members <- members in
    runtime.order <- extend_array runtime.order 0L;
    runtime.visible_order <- extend_array runtime.visible_order 0L;
    runtime.kinds <- extend_bytes runtime.kinds;
    runtime.parents <- extend_array runtime.parents (-1);
    runtime.first_children <- extend_array runtime.first_children (-1);
    runtime.next_siblings <- extend_array runtime.next_siblings (-1);
    runtime.depths <- extend_array runtime.depths 0;
    runtime.z_orders <- extend_array runtime.z_orders 0;
    runtime.flags <- extend_bytes runtime.flags;
    runtime.dirty <- extend_bytes runtime.dirty;
    runtime.row_x <- extend_array runtime.row_x 0;
    runtime.row_y <- extend_array runtime.row_y 0;
    runtime.row_width <- extend_array runtime.row_width 0;
    runtime.row_height <- extend_array runtime.row_height 0;
    runtime.control_x <- extend_array runtime.control_x 0;
    runtime.control_y <- extend_array runtime.control_y 0;
    runtime.control_width <- extend_array runtime.control_width 0;
    runtime.control_height <- extend_array runtime.control_height 0;
    runtime.float_values <- extend_array runtime.float_values 0.;
    runtime.float_values2 <- extend_array runtime.float_values2 0.;
    runtime.int_values <- extend_array runtime.int_values 0;
    runtime.text_values <- extend_array runtime.text_values None;
    runtime.labels <- extend_array runtime.labels None;
    runtime.paint_builders <- extend_array runtime.paint_builders None;
    runtime.paint_nodes <- extend_array runtime.paint_nodes None;
    runtime.paint_text <- extend_array runtime.paint_text [];
    runtime.paint_segment_ids <- extend_array runtime.paint_segment_ids 0L;
    runtime.paint_segment_versions <- extend_array runtime.paint_segment_versions 0L;
    runtime.paint_source_bytes <- extend_array runtime.paint_source_bytes 0;
    List.iter extend_queue
      [ runtime.reconcile_queue; runtime.style_queue; runtime.layout_queue;
        runtime.prepaint_queue; runtime.text_queue; runtime.paint_queue;
        runtime.compose_queue; runtime.accessibility_queue ]
  end

let clear_runtime_paint_slot runtime slot =
  if Array.unsafe_get runtime.paint_nodes slot <> None then begin
    runtime.paint_cache_count <- max 0 (runtime.paint_cache_count - 1);
    runtime.paint_cache_bytes <- max 0
      (runtime.paint_cache_bytes
       - Array.unsafe_get runtime.paint_source_bytes slot)
  end;
  List.iter Prismel.Font.Private.release_retained
    (Array.unsafe_get runtime.paint_text slot);
  Array.unsafe_set runtime.paint_text slot [];
  Array.unsafe_set runtime.paint_nodes slot None;
  Option.iter Scene_command.Display_list.Builder.reset
    (Array.unsafe_get runtime.paint_builders slot);
  Array.unsafe_set runtime.paint_builders slot None;
  Array.unsafe_set runtime.paint_segment_ids slot 0L;
  Array.unsafe_set runtime.paint_segment_versions slot 0L;
  Array.unsafe_set runtime.paint_source_bytes slot 0;
  runtime.composed_scene <- None


let enqueue_id queue id =
  let slot = Stable_store.slot id in
  if Bytes.unsafe_get queue.queued_members slot = '\000' then begin
    if queue.queued_length = Array.length queue.queued_ids then begin
      let grown = Array.make (queue.queued_length * 2) 0L in
      Array.blit queue.queued_ids 0 grown 0 queue.queued_length;
      queue.queued_ids <- grown
    end;
    Array.unsafe_set queue.queued_ids queue.queued_length id;
    queue.queued_length <- queue.queued_length + 1;
    Bytes.unsafe_set queue.queued_members slot '\001'
  end

let dirty_structure = 1
let dirty_layout = 2
let dirty_hitboxes = 4
let dirty_text = 8
let dirty_paint = 16
let dirty_compose = 32
let dirty_accessibility = 64

let mark_runtime_dirty runtime id effects =
  let slot = Stable_store.slot id in
  let previous = Char.code (Bytes.unsafe_get runtime.dirty slot) in
  Bytes.unsafe_set runtime.dirty slot (Char.chr (previous lor effects));
  if effects land dirty_paint <> 0 then begin
    let flags = Char.code (Bytes.unsafe_get runtime.flags slot) land 0xfd in
    Bytes.unsafe_set runtime.flags slot (Char.chr flags)
  end;
  if effects land dirty_structure <> 0 then begin
    enqueue_id runtime.reconcile_queue id;
    enqueue_id runtime.style_queue id
  end;
  if effects land dirty_layout <> 0 then enqueue_id runtime.layout_queue id;
  if effects land (dirty_layout lor dirty_hitboxes) <> 0 then
    enqueue_id runtime.prepaint_queue id;
  if effects land dirty_text <> 0 then enqueue_id runtime.text_queue id;
  if effects land dirty_paint <> 0 then enqueue_id runtime.paint_queue id;
  if effects land dirty_compose <> 0 then enqueue_id runtime.compose_queue id;
  if effects land dirty_accessibility <> 0 then
    enqueue_id runtime.accessibility_queue id

let widget_dirty_effects previous widget = match previous, widget with
  | Accordion before, Accordion after when before.expanded <> after.expanded ->
      dirty_structure lor dirty_layout lor dirty_hitboxes lor dirty_text
      lor dirty_paint lor dirty_compose lor dirty_accessibility
  | _ -> dirty_text lor dirty_paint lor dirty_accessibility

let set_runtime_widget runtime id widget =
  let slot = Stable_store.slot id in
  Bytes.unsafe_set runtime.kinds slot (Char.chr (widget_kind widget));
  Array.unsafe_set runtime.labels slot (widget_label widget);
  let first, second = widget_float_values widget in
  Array.unsafe_set runtime.float_values slot first;
  Array.unsafe_set runtime.float_values2 slot second;
  Array.unsafe_set runtime.int_values slot (widget_int_value widget);
  Array.unsafe_set runtime.text_values slot (widget_text_value widget)

let rebuild_runtime_hierarchy runtime =
  let capacity = Bytes.length runtime.kinds in
  Array.fill runtime.parents 0 capacity (-1);
  Array.fill runtime.first_children 0 capacity (-1);
  Array.fill runtime.next_siblings 0 capacity (-1);
  let stack = Array.make (max 1 runtime.order_length) (-1) in
  let stack_length = ref 0 in
  let last_children = Array.make capacity (-1) in
  for index = 0 to runtime.order_length - 1 do
    let id = Array.unsafe_get runtime.order index in
    let slot = Stable_store.slot id in
    let parent = if !stack_length = 0 then -1
      else Array.unsafe_get stack (!stack_length - 1) in
    Array.unsafe_set runtime.parents slot parent;
    Array.unsafe_set runtime.depths slot !stack_length;
    Array.unsafe_set runtime.z_orders slot index;
    if parent >= 0 then begin
      let previous = Array.unsafe_get last_children parent in
      if previous < 0 then Array.unsafe_set runtime.first_children parent slot
      else Array.unsafe_set runtime.next_siblings previous slot;
      Array.unsafe_set last_children parent slot
    end;
    match Char.code (Bytes.unsafe_get runtime.kinds slot) with
    | 1 ->
        Array.unsafe_set stack !stack_length slot;
        incr stack_length
    | 2 when !stack_length > 0 -> decr stack_length
    | _ -> ()
  done

let rebuild_runtime_visible_order runtime =
  runtime.visible_length <- 0;
  let hidden_depth = ref 0 in
  for index = 0 to runtime.order_length - 1 do
    let id = Array.unsafe_get runtime.order index in
    let slot = Stable_store.slot id in
    let kind = Char.code (Bytes.unsafe_get runtime.kinds slot) in
    if kind = 1 then begin
      if !hidden_depth = 0 then begin
        Array.unsafe_set runtime.visible_order runtime.visible_length id;
        runtime.visible_length <- runtime.visible_length + 1;
        if Array.unsafe_get runtime.int_values slot = 0 then hidden_depth := 1
      end else incr hidden_depth
    end else if kind = 2 then begin
      if !hidden_depth > 0 then decr hidden_depth
    end else if !hidden_depth = 0 then begin
      Array.unsafe_set runtime.visible_order runtime.visible_length id;
      runtime.visible_length <- runtime.visible_length + 1
    end
  done

let populate_widget_runtime runtime widgets =
  runtime.spec_widgets <- widgets;
  runtime.order_length <- 0;
  Array.iter (fun widget ->
    let id = Stable_store.add runtime.slots widget in
    ensure_runtime_capacity runtime;
    Array.unsafe_set runtime.order runtime.order_length id;
    runtime.order_length <- runtime.order_length + 1;
    set_runtime_widget runtime id widget;
    mark_runtime_dirty runtime id
      (dirty_structure lor dirty_layout lor dirty_hitboxes lor dirty_text
       lor dirty_paint lor dirty_compose lor dirty_accessibility);
    Option.iter (fun name ->
      if not (Hashtbl.mem runtime.names name) then Hashtbl.add runtime.names name id)
      (widget_name widget);
    runtime.created <- runtime.created + 1) widgets;
  runtime.structure_generation <- Int64.succ runtime.structure_generation;
  runtime.layout_generation <- Int64.succ runtime.layout_generation;
  runtime.paint_generation <- Int64.succ runtime.paint_generation;
  rebuild_runtime_hierarchy runtime;
  rebuild_runtime_visible_order runtime

let widget_runtime canvas =
  match canvas.runtime_cache with
  | Some runtime -> runtime
  | None ->
      let widgets = ordered_widget_array canvas in
      let runtime = make_widget_runtime (Array.length widgets) in
      populate_widget_runtime runtime widgets;
      canvas.runtime_cache <- Some runtime;
      runtime

let reconcile_widget_runtime runtime widgets =
  if widgets == runtime.spec_widgets then 0
  else begin
    let old_order = runtime.order and old_length = runtime.order_length in
    let old_widgets = runtime.spec_widgets in
    let used = ref (Bytes.make (Stable_store.capacity runtime.slots) '\000') in
    let next_order = ref (Array.make (max 8 (Array.length widgets)) 0L) in
    let next_names = Hashtbl.create (max 8 (Array.length widgets)) in
    let changed = ref 0 and created = ref 0
    and structural_value_change = ref false in
    let ensure_order index =
      if index = Array.length !next_order then begin
        let grown = Array.make (index * 2) 0L in
        Array.blit !next_order 0 grown 0 index;
        next_order := grown
      end in
    Array.iteri (fun index widget ->
      let kind = widget_kind widget in
      let candidate = match widget_name widget with
        | Some name -> Hashtbl.find_opt runtime.names name
        | None when index < old_length && index < Array.length old_widgets
            && Option.is_none (widget_name (Array.unsafe_get old_widgets index)) ->
            Some (Array.unsafe_get old_order index)
        | None -> None in
      let candidate = match candidate with
        | Some id when Stable_store.valid runtime.slots id ->
            let slot = Stable_store.slot id in
            if slot < Bytes.length !used
                && Bytes.unsafe_get !used slot = '\000'
                && Char.code (Bytes.unsafe_get runtime.kinds slot) = kind
            then Some id else None
        | Some _ | None -> None in
      let id = match candidate with
        | Some id ->
            let slot = Stable_store.slot id in
            Bytes.unsafe_set !used slot '\001';
            let previous = Option.get (Stable_store.get runtime.slots id) in
            if not (same_widget previous widget) then begin
              let effects = widget_dirty_effects previous widget in
              ignore (Stable_store.set runtime.slots id widget);
              set_runtime_widget runtime id widget;
              mark_runtime_dirty runtime id effects;
              if effects land dirty_structure <> 0 then
                structural_value_change := true;
              incr changed;
              runtime.mutations <- runtime.mutations + 1
            end;
            id
        | None ->
            let id = Stable_store.add runtime.slots widget in
            ensure_runtime_capacity runtime;
            let slot = Stable_store.slot id in
            if slot >= Bytes.length !used then begin
              let grown = Bytes.make (Stable_store.capacity runtime.slots) '\000' in
              Bytes.blit !used 0 grown 0 (Bytes.length !used);
              used := grown
            end;
            Bytes.unsafe_set !used slot '\001';
            set_runtime_widget runtime id widget;
            mark_runtime_dirty runtime id
              (dirty_structure lor dirty_layout lor dirty_hitboxes lor dirty_text
               lor dirty_paint lor dirty_compose lor dirty_accessibility);
            incr created;
            runtime.created <- runtime.created + 1;
            runtime.mutations <- runtime.mutations + 1;
            id in
      ensure_order index;
      Array.unsafe_set !next_order index id;
      Option.iter (fun name ->
        if not (Hashtbl.mem next_names name) then Hashtbl.add next_names name id)
        (widget_name widget)) widgets;
    let removed = ref 0 in
    for index = 0 to old_length - 1 do
      let id = Array.unsafe_get old_order index in
      let slot = Stable_store.slot id in
      let retained = slot < Bytes.length !used
        && Bytes.unsafe_get !used slot = '\001' in
      if Stable_store.valid runtime.slots id && not retained then begin
        ignore (Stable_store.remove runtime.slots id);
        clear_runtime_paint_slot runtime slot;
        Array.unsafe_set runtime.labels slot None;
        Array.unsafe_set runtime.text_values slot None;
        Bytes.unsafe_set runtime.dirty slot '\000';
        List.iter (fun queue ->
          Bytes.unsafe_set queue.queued_members slot '\000')
          [ runtime.reconcile_queue; runtime.style_queue; runtime.layout_queue;
            runtime.prepaint_queue; runtime.text_queue; runtime.paint_queue;
            runtime.compose_queue; runtime.accessibility_queue ];
        incr removed;
        runtime.removed <- runtime.removed + 1;
        runtime.mutations <- runtime.mutations + 1
      end
    done;
    let structure_changed = !created > 0 || !removed > 0
      || !structural_value_change
      || old_length <> Array.length widgets
      || let rec differs index = index < Array.length widgets
          && (Array.unsafe_get old_order index <> Array.unsafe_get !next_order index
              || differs (index + 1)) in differs 0 in
    runtime.order <- !next_order;
    runtime.order_length <- Array.length widgets;
    runtime.names <- next_names;
    runtime.spec_widgets <- widgets;
    if structure_changed then begin
      runtime.structure_generation <- Int64.succ runtime.structure_generation;
      runtime.layout_generation <- Int64.succ runtime.layout_generation
    end;
    if structure_changed || !changed > 0 then
      runtime.paint_generation <- Int64.succ runtime.paint_generation;
    Option.iter (fun id -> if not (Stable_store.valid runtime.slots id) then
      runtime.focus_id <- None) runtime.focus_id;
    Option.iter (fun id -> if not (Stable_store.valid runtime.slots id) then
      runtime.active_id <- None) runtime.active_id;
    rebuild_runtime_hierarchy runtime;
    rebuild_runtime_visible_order runtime;
    !changed + !created + !removed
  end

let widget_at canvas index =
  if index < 0 || index >= canvas.widget_count then None
  else Some (ordered_widget_array canvas).(index)

let label ~text canvas = with_widget canvas (Label text)
let accordion ~name ~label ~expanded contents canvas =
  let canvas = with_widget canvas (Accordion { name; label; expanded }) in
  let canvas = contents canvas in
  with_widget canvas Accordion_end
let button ~name ~label canvas = with_widget canvas (Button { name; label })
let toggle ~name ~label ~value canvas =
  with_widget canvas (Toggle { name; label; value })
let text_field ~name ~label ~value canvas =
  with_widget canvas (Text_field { name; label; value })
let choice ~name ~label ~options ~selected canvas =
  let options = Array.of_list options in
  if Array.length options = 0 then
    invalid_arg "Pxui.choice: options must not be empty";
  if selected < 0 || selected >= Array.length options then
    invalid_arg "Pxui.choice: selected index is out of bounds";
  with_widget canvas (Choice { name; label; options; selected })

let add_label canvas ~text = append canvas (Label text)
let add_button canvas ~name ~label = append canvas (Button { name; label })
let add_toggle canvas ~name ~label ~value =
  append canvas (Toggle { name; label; value })
let add_text_field canvas ~name ~label ~value =
  append canvas (Text_field { name; label; value })

let clamp low high value = max low (min high value)

let validate_float_slider where ~min ~max ~value =
  if not (Float.is_finite min && Float.is_finite max) || max <= min then
    invalid_arg (where ^ ": max must be finite and greater than min");
  if not (Float.is_finite value) then
    invalid_arg (where ^ ": value must be finite")

let range ~name ~label ~min ~max ~low ~high canvas =
  if max <= min then invalid_arg "Pxui.range: max must be greater than min";
  let low = clamp min max low and high = clamp min max high in
  let low, high = Float.min low high, Float.max low high in
  with_widget canvas (Range { name; label; min; max; low; high })

let xy ~name ~label ~x_range:(x_min, x_max) ~y_range:(y_min, y_max)
    ~value:(x, y) canvas =
  if x_max <= x_min || y_max <= y_min then
    invalid_arg "Pxui.xy: ranges must increase";
  with_widget canvas
    (Xy {
      name;
      label;
      x_min;
      x_max;
      y_min;
      y_max;
      x = clamp x_min x_max x;
      y = clamp y_min y_max y;
    })

let add_slider canvas ~name ~label ~min ~max ~value =
  validate_float_slider "Pxui.add_slider" ~min ~max ~value;
  append canvas (Slider { name; label; min; max; value })

let add_int_slider canvas ~name ~label ~min ~max ~value =
  if max <= min then
    invalid_arg "Pxui.add_int_slider: max must be greater than min";
  append canvas (Int_slider { name; label; min; max; value })

let slider ~name ~label ~min ~max ~value canvas =
  validate_float_slider "Pxui.slider" ~min ~max ~value;
  with_widget canvas (Slider { name; label; min; max; value })

let int_slider ~name ~label ~min ~max ~value canvas =
  if max <= min then
    invalid_arg "Pxui.int_slider: max must be greater than min";
  with_widget canvas (Int_slider { name; label; min; max; value })

let compute_displayed_widgets canvas =
  let widgets = ordered_widget_array canvas in
  let hidden_depth = ref 0 and row_index = ref 0 and reversed = ref [] in
  Array.iteri (fun source_index widget ->
    match widget with
    | Accordion accordion ->
        if !hidden_depth = 0 then begin
          reversed := { source_index; row_index = !row_index; widget } :: !reversed;
          incr row_index;
          if not accordion.expanded then hidden_depth := 1
        end else incr hidden_depth
    | Accordion_end ->
        if !hidden_depth > 0 then decr hidden_depth
    | _ when !hidden_depth = 0 ->
        reversed := { source_index; row_index = !row_index; widget } :: !reversed;
        incr row_index
    | _ -> ()) widgets;
  Array.of_list (List.rev !reversed)

let raw_layout (canvas : t) ~scrollable displayed =
  let index = displayed.source_index and widget = displayed.widget in
  let inner_x = canvas.x + canvas.padding in
  let scrollbar_gutter = if scrollable then 10 else 0 in
  let inner_width = Stdlib.max 1
      (canvas.width - (2 * canvas.padding) - scrollbar_gutter) in
  let y = canvas.y + canvas.padding + (displayed.row_index * canvas.row_height)
      - canvas.scroll_y in
  let row = { x = inner_x; y; w = inner_width; h = canvas.row_height } in
  let desired_label_width = min 96 (max 72 (inner_width / 3)) in
  let label_width = min desired_label_width (inner_width / 2) in
  let value_x = inner_x + label_width in
  let value_width = Stdlib.max 1 (inner_width - label_width) in
  let control =
    match widget with
    | Label _ | Accordion _ -> row
    | Accordion_end -> assert false
    | Button _ ->
        { x = inner_x; y = y + 3; w = inner_width;
          h = Stdlib.max 1 (canvas.row_height - 6) }
    | Toggle _ ->
        let toggle_width = min 40 inner_width in
        { x = inner_x + inner_width - toggle_width;
          y = y + 7; w = toggle_width; h = 18 }
    | Slider _ | Int_slider _ | Text_field _ | Choice _ | Range _ | Xy _ ->
        { x = value_x; y = y + 3; w = value_width;
          h = Stdlib.max 1 (canvas.row_height - 6) }
  in
  { index; row; control }

let compute_layout_snapshot canvas =
  let displayed = compute_displayed_widgets canvas in
  let content_height =
    (Array.length displayed * canvas.row_height) + (2 * canvas.padding) in
  let panel_height =
    let height = Option.fold ~none:content_height ~some:(min content_height)
        canvas.max_height in
    Option.fold ~none:height ~some:(min height) canvas.frame_max_height in
  let max_scroll = max 0 (content_height - panel_height) in
  let scrollable = max_scroll > 0 in
  let layouts = Array.make canvas.widget_count None in
  Array.iter (fun displayed ->
    layouts.(displayed.source_index) <-
      Some (raw_layout canvas ~scrollable displayed)) displayed;
  { displayed; layouts; content_height; panel_height; max_scroll }

let layout_snapshot canvas = match canvas.layout_cache with
  | Some snapshot -> snapshot
  | None ->
      let snapshot = compute_layout_snapshot canvas in
      canvas.layout_cache <- Some snapshot;
      snapshot

let displayed_widgets canvas = (layout_snapshot canvas).displayed
let content_height canvas = (layout_snapshot canvas).content_height
let panel_height canvas = (layout_snapshot canvas).panel_height
let max_scroll canvas = (layout_snapshot canvas).max_scroll

let clamp_scroll canvas =
  let scroll_y = clamp 0 (max_scroll canvas) canvas.scroll_y in
  if scroll_y = canvas.scroll_y then canvas
  else { canvas with scroll_y; layout_cache = None }

let contains (bounds : bounds) (x, y) =
  x >= bounds.x && x < bounds.x + bounds.w
  && y >= bounds.y && y < bounds.y + bounds.h

let layout (canvas : t) displayed =
  match (layout_snapshot canvas).layouts.(displayed.source_index) with
  | Some layout -> layout
  | None -> invalid_arg "Pxui.layout: widget is not visible"

let text_node (canvas : t) ?color ?size x y text =
  let color = Option.value ~default:canvas.theme.foreground color in
  match canvas.font with
  | Some font -> Prismel.Scene.font_text font ~at:(x, y) ~color text
  | None ->
      Prismel.Scene.text ~at:(x, y) ~color
        ~size:(Option.value ~default:canvas.font_size size) text

let compact_float value =
  if abs_float value >= 1000. || (value <> 0. && abs_float value < 0.01)
  then Printf.sprintf "%.2g" value
  else Printf.sprintf "%.3g" value

let numeric_text = function
  | Slider slider -> Printf.sprintf "%.17g" slider.value
  | Int_slider slider -> string_of_int slider.value
  | _ -> invalid_arg "PXUI numeric editor requires a slider"

let numeric_text_valid widget text =
  match widget with
  | Slider _ ->
      (try Float.is_finite (float_of_string text) with Failure _ -> false)
  | Int_slider _ ->
      (try ignore (int_of_string text); true with Failure _ -> false)
  | _ -> false

let active_index (canvas : t) index =
  match canvas.active with
  | Some (Armed active)
  | Some (Drag_slider active)
  | Some (Drag_range (active, _))
  | Some (Drag_xy active) -> active = index
  | None -> false

let position (bounds : bounds) fraction =
  bounds.x
  + int_of_float
      ((clamp 0. 1. fraction
        *. float_of_int (Stdlib.max 1 (bounds.w - 1))) +. 0.5)

let widget_scene (canvas : t) layout widget =
  let open Prismel in
  let open Scene in
  let theme = canvas.theme in
  let muted = Color.blend theme.foreground theme.panel ~pct:0.48 in
  let border = Color.with_alpha theme.foreground 34 in
  let faint_border = Color.with_alpha theme.foreground 20 in
  let hover_fill = Color.lighten theme.input 0.075 in
  let pressed_fill = Color.blend theme.control theme.accent ~pct:0.18 in
  let hovered = canvas.hover = Some layout.index in
  let pressed = active_index canvas layout.index in
  let label_y = layout.row.y + max 5 ((layout.row.h - canvas.font_size - 3) / 2) in
  let row_hover =
    if hovered then
      [rounded_rect ~at:(layout.row.x, layout.row.y + 2)
         ~w:layout.row.w ~h:(Stdlib.max 1 (layout.row.h - 4)) ~radius:5
         ~fill:(Color.with_alpha hover_fill 150) ()]
    else []
  in
  let numeric_editor label =
    match canvas.numeric_edit with
    | Some edit when edit.index = layout.index ->
        let shown = edit.text ^ canvas.composition ^ "│" in
        Some [
          text_node canvas ~color:theme.accent layout.row.x label_y label;
          rounded_rect ~at:(layout.control.x, layout.control.y)
            ~w:layout.control.w ~h:layout.control.h ~radius:4
            ~fill:theme.input
            ~stroke:(if edit.valid then theme.accent
              else Prismel.Color.hex_exn "#fb7185") ();
          text_node canvas (layout.control.x + 8) label_y shown;
        ]
    | Some _ | None -> None
  in
  row_hover @
  match widget with
  | Label text ->
      [
        rect ~at:(layout.row.x, layout.row.y + 7) ~w:3
          ~h:(Stdlib.max 1 (layout.row.h - 14)) ~fill:theme.accent ();
        text_node canvas ~color:theme.foreground
          ~size:(Stdlib.max 1 (canvas.font_size - 1))
          (layout.row.x + 10) label_y text;
        line
          ~from_:(layout.row.x + 10, layout.row.y + layout.row.h - 2)
          ~to_:(layout.row.x + layout.row.w, layout.row.y + layout.row.h - 2)
          ~color:faint_border ();
      ]
  | Accordion { label; expanded; _ } ->
      let fill =
        if pressed then pressed_fill
        else if hovered then Color.lighten theme.control 0.08
        else theme.control in
      [
        rounded_rect ~at:(layout.control.x, layout.control.y + 2)
          ~w:layout.control.w ~h:(Stdlib.max 1 (layout.control.h - 4))
          ~radius:5 ~fill
          ~stroke:(if hovered || pressed then theme.accent else border) ();
        text_node canvas ~color:theme.accent ~size:11
          (layout.control.x + 9) label_y (if expanded then "▾" else "▸");
        text_node canvas (layout.control.x + 27) label_y label;
      ]
  | Accordion_end -> []
  | Button { label; _ } ->
      let fill =
        if pressed then pressed_fill
        else if hovered then Color.lighten theme.control 0.08
        else theme.control
      in
      [
        rounded_rect ~at:(layout.control.x, layout.control.y)
          ~w:layout.control.w ~h:layout.control.h ~radius:5
          ~fill ~stroke:(if hovered || pressed then theme.accent else border) ();
        rect ~at:(layout.control.x + 1, layout.control.y + 6) ~w:2
          ~h:(Stdlib.max 1 (layout.control.h - 12)) ~fill:theme.accent ();
        text_node canvas (layout.control.x + 12) label_y label;
      ]
  | Toggle { label; value; _ } ->
      let track =
        if value then Color.blend theme.accent theme.input ~pct:0.28
        else if hovered then Color.lighten theme.control 0.08
        else theme.control
      in
      let knob_x =
        if value then layout.control.x + layout.control.w - 10
        else layout.control.x + 9
      in
      [
        text_node canvas ~color:(if value then theme.foreground else muted)
          layout.row.x label_y label;
        rounded_rect ~at:(layout.control.x, layout.control.y)
          ~w:layout.control.w ~h:layout.control.h ~radius:9
          ~fill:track
          ~stroke:(if hovered || pressed then theme.accent else border) ();
        circle ~at:(knob_x, layout.control.y + (layout.control.h / 2))
          ~radius:6
          ~fill:(if value then theme.accent else muted) ();
      ]
  | Slider { label; min; max; value; _ } ->
      (match numeric_editor label with
       | Some scene -> scene
       | None ->
           let fraction = (value -. min) /. (max -. min) in
           let marker = position layout.control fraction in
           let fill_width = Stdlib.max 1 (marker - layout.control.x + 1) in
           [
             text_node canvas layout.row.x label_y label;
             rounded_rect ~at:(layout.control.x, layout.control.y + 4)
               ~w:layout.control.w
               ~h:(Stdlib.max 1 (layout.control.h - 8)) ~radius:4
               ~fill:theme.track ~stroke:border ();
             rounded_rect ~at:(layout.control.x, layout.control.y + 4)
               ~w:fill_width
               ~h:(Stdlib.max 1 (layout.control.h - 8)) ~radius:4
               ~fill:(Color.with_alpha theme.accent
                 (if pressed then 220 else 175)) ();
             line ~from_:(marker, layout.control.y + 2)
               ~to_:(marker, layout.control.y + layout.control.h - 2)
               ~color:theme.foreground ~width:2 ();
             text_node canvas ~size:11
               (layout.control.x + 6) (layout.control.y + 6)
               (compact_float value);
           ])
  | Int_slider { label; min; max; value; _ } ->
      (match numeric_editor label with
       | Some scene -> scene
       | None ->
           let fraction = float_of_int (value - min)
             /. float_of_int (max - min) in
           let marker = position layout.control fraction in
           let fill_width = Stdlib.max 1 (marker - layout.control.x + 1) in
           [
             text_node canvas layout.row.x label_y label;
             rounded_rect ~at:(layout.control.x, layout.control.y + 4)
               ~w:layout.control.w
               ~h:(Stdlib.max 1 (layout.control.h - 8)) ~radius:4
               ~fill:theme.track ~stroke:border ();
             rounded_rect ~at:(layout.control.x, layout.control.y + 4)
               ~w:fill_width
               ~h:(Stdlib.max 1 (layout.control.h - 8)) ~radius:4
               ~fill:(Color.with_alpha theme.accent
                 (if pressed then 220 else 175)) ();
             line ~from_:(marker, layout.control.y + 2)
               ~to_:(marker, layout.control.y + layout.control.h - 2)
               ~color:theme.foreground ~width:2 ();
             text_node canvas ~size:11
               (layout.control.x + 6) (layout.control.y + 6)
               (string_of_int value);
           ])
  | Text_field { name; label; value } ->
      let focused = canvas.focus = Some name in
      let shown =
        if focused then value ^ canvas.composition ^ "│" else value
      in
      [
        text_node canvas ~color:(if focused then theme.foreground else muted)
          layout.row.x label_y label;
        rounded_rect ~at:(layout.control.x, layout.control.y)
          ~w:layout.control.w ~h:layout.control.h ~radius:4
          ~fill:(if hovered then hover_fill else theme.input)
          ~stroke:(if focused then theme.accent else border) ();
        text_node canvas (layout.control.x + 8) label_y shown;
      ]
  | Choice { label; options; selected; _ } ->
      [
        text_node canvas layout.row.x label_y label;
        rounded_rect ~at:(layout.control.x, layout.control.y)
          ~w:layout.control.w ~h:layout.control.h ~radius:4
          ~fill:(if pressed then pressed_fill
            else if hovered then hover_fill else theme.input)
          ~stroke:(if hovered || pressed then theme.accent else border) ();
        text_node canvas ~color:theme.accent ~size:11
          (layout.control.x + 7) label_y "‹";
        text_node canvas (layout.control.x + 21) label_y
          options.(selected);
        text_node canvas ~color:theme.accent ~size:11
          (layout.control.x + layout.control.w - 13) label_y "›";
      ]
  | Range { label; min; max; low; high; _ } ->
      let low_x = position layout.control ((low -. min) /. (max -. min)) in
      let high_x = position layout.control ((high -. min) /. (max -. min)) in
      [
        text_node canvas layout.row.x label_y label;
        rounded_rect ~at:(layout.control.x, layout.control.y + 7)
          ~w:layout.control.w
          ~h:(Stdlib.max 1 (layout.control.h - 14)) ~radius:3
          ~fill:theme.track ~stroke:border ();
        rect ~at:(low_x, layout.control.y + 7)
          ~w:(Stdlib.max 1 (high_x - low_x + 1))
          ~h:(Stdlib.max 1 (layout.control.h - 14))
          ~fill:(Color.with_alpha theme.accent 185) ();
        line ~from_:(low_x, layout.control.y + 3)
          ~to_:(low_x, layout.control.y + layout.control.h - 3)
          ~color:theme.foreground ~width:2 ();
        line ~from_:(high_x, layout.control.y + 3)
          ~to_:(high_x, layout.control.y + layout.control.h - 3)
          ~color:theme.foreground ~width:2 ();
        text_node canvas ~size:10
          (layout.control.x + 5) (layout.control.y + 6)
          (compact_float low ^ " — " ^ compact_float high);
      ]
  | Xy { label; x_min; x_max; y_min; y_max; x; y; _ } ->
      let px = position layout.control ((x -. x_min) /. (x_max -. x_min)) in
      let py =
        layout.control.y
        + int_of_float
            (((y -. y_min) /. (y_max -. y_min)
              *. float_of_int (Stdlib.max 1 (layout.control.h - 1))) +. 0.5)
      in
      [
        text_node canvas layout.row.x label_y label;
        rounded_rect ~at:(layout.control.x, layout.control.y)
          ~w:layout.control.w ~h:layout.control.h ~radius:4
          ~fill:(if hovered then hover_fill else theme.input) ~stroke:border ();
        line
          ~from_:(layout.control.x + (layout.control.w / 2), layout.control.y + 3)
          ~to_:(layout.control.x + (layout.control.w / 2),
            layout.control.y + layout.control.h - 3)
          ~color:faint_border ();
        line
          ~from_:(layout.control.x + 3, layout.control.y + (layout.control.h / 2))
          ~to_:(layout.control.x + layout.control.w - 3,
            layout.control.y + (layout.control.h / 2))
          ~color:faint_border ();
        circle ~at:(px, py) ~radius:(if pressed then 6 else 5)
          ~fill:theme.accent ~stroke:theme.foreground ();
      ]

let scene_uncached (canvas : t) =
  let displayed = displayed_widgets canvas in
  let height = panel_height canvas in
  let open Prismel in
  let border = Color.with_alpha canvas.theme.foreground 34 in
  let glow = Color.with_alpha canvas.theme.accent 56 in
  let input_regions =
    Array.to_list
      (Array.map (fun displayed -> match displayed.widget with
        | Text_field field ->
            let bounds = (layout canvas displayed).control in
            Some (Scene.text_input_region ~at:(bounds.x, bounds.y)
              ~w:bounds.w ~h:bounds.h
              ~focused:(canvas.focus = Some field.name) ())
        | (Slider _ | Int_slider _) ->
            (match canvas.numeric_edit with
             | Some edit when edit.index = displayed.source_index ->
                 let bounds = (layout canvas displayed).control in
                 Some (Scene.text_input_region ~at:(bounds.x, bounds.y)
                   ~w:bounds.w ~h:bounds.h ~focused:true ())
             | Some _ | None -> None)
        | _ -> None) displayed)
    |> List.filter_map Fun.id
  in
  let panel = Scene.[
    rounded_rect ~at:(canvas.x + 4, canvas.y + 5)
      ~w:canvas.width ~h:height ~radius:8
      ~fill:(Color.rgba 0 0 0 105) ();
    rounded_rect ~at:(canvas.x, canvas.y)
      ~w:canvas.width ~h:height ~radius:8
      ~fill:canvas.theme.panel ~stroke:border ();
    line ~from_:(canvas.x + 12, canvas.y + 1)
      ~to_:(canvas.x + canvas.width - 12, canvas.y + 1)
      ~color:glow ();
  ] in
  let widgets = input_regions
    @ (Array.to_list
         (Array.map
            (fun displayed ->
              widget_scene canvas (layout canvas displayed) displayed.widget)
            displayed)
       |> List.concat) in
  let content = Scene.[clip
      ~at:(canvas.x + canvas.padding, canvas.y + canvas.padding)
      ~w:(Stdlib.max 1 (canvas.width - (2 * canvas.padding)))
      ~h:(Stdlib.max 1 (height - (2 * canvas.padding))) widgets] in
  let scrollbar =
    let maximum = max_scroll canvas in
    if maximum = 0 then []
    else
      let track_x = canvas.x + canvas.width - canvas.padding - 5
      and track_y = canvas.y + canvas.padding
      and track_height = Stdlib.max 1 (height - (2 * canvas.padding)) in
      let thumb_height = Stdlib.max 20
          (track_height * height / Stdlib.max 1 (content_height canvas))
        |> min track_height in
      let travel = track_height - thumb_height in
      let thumb_y = track_y +
        if maximum = 0 then 0 else canvas.scroll_y * travel / maximum in
      Scene.[
        rounded_rect ~at:(track_x, track_y) ~w:4 ~h:track_height ~radius:2
          ~fill:(Color.with_alpha canvas.theme.track 180) ();
        rounded_rect ~at:(track_x, thumb_y) ~w:4 ~h:thumb_height ~radius:2
          ~fill:(Color.with_alpha canvas.theme.accent 210) ();
      ]
  in
  panel @ content @ scrollbar

let same_scene_state (left:t) (right:t) =
  left.x=right.x&&left.y=right.y&&left.width=right.width&&
  left.row_height=right.row_height&&left.padding=right.padding&&
  left.theme=right.theme&&left.font==right.font&&left.font_size=right.font_size&&
  left.frame_max_height=right.frame_max_height&&left.max_height=right.max_height&&
  left.scroll_y=right.scroll_y&&left.widgets==right.widgets&&
  left.focus=right.focus&&left.composition=right.composition&&
  left.hover=right.hover&&left.active=right.active&&left.numeric_edit=right.numeric_edit

let scene (canvas:t) = match canvas.scene_cache with
  |Some(snapshot,scene)when same_scene_state snapshot canvas->scene
  |_->
      let scene=scene_uncached canvas in
      (* Query memoization is already part of [t] through [ordered_cache].
         Retain exactly one immutable render-state snapshot and its pure Scene;
         physical widget-list identity makes functional and compatibility
         updates invalidate without polymorphic comparison or callbacks. *)
      canvas.scene_cache<-Some({canvas with scene_cache=None},scene);scene

let draw canvas = Prismel.Scene.render (scene canvas)

let hit_index (canvas : t) point =
  if not (contains { x = canvas.x; y = canvas.y; w = canvas.width;
      h = panel_height canvas } point) then None
  else
    let displayed = displayed_widgets canvas in
    let index = ref 0 and hit = ref None in
    while !index < Array.length displayed && Option.is_none !hit do
      let item = displayed.(!index) in
      (match item.widget with
       | Label _ | Accordion_end -> ()
       | _ ->
           if contains (layout canvas item).control point then
             hit := Some item.source_index);
      incr index
    done;
    !hit

let layout_at (canvas : t) index =
  let displayed = displayed_widgets canvas in
  match Array.find_opt (fun item -> item.source_index = index) displayed with
  | Some item -> layout canvas item
  | None -> invalid_arg "PXUI widget index outside visible layout"

let replace_widgets canvas widgets =
  let canvas = clamp_scroll
      { canvas with widgets; ordered_cache = None; runtime_cache = None;
        layout_cache = None } in
  match canvas.numeric_edit with
  | Some edit when not (Array.exists
      (fun displayed -> displayed.source_index = edit.index)
      (displayed_widgets canvas)) ->
      { canvas with numeric_edit = None; composition = "" }
  | Some _ | None -> canvas

let update_at index transform count widgets =
  let stored_index = count - index - 1 in
  let rec loop current = function
    | [] -> []
    | widget :: rest when current = stored_index -> transform widget :: rest
    | widget :: rest -> widget :: loop (current + 1) rest
  in
  loop 0 widgets

let slider_at (canvas : t) index x =
  let layout = layout_at canvas index in
  let fraction =
    clamp 0. 1.
      (float_of_int (x - layout.control.x)
       /. float_of_int (Stdlib.max 1 (layout.control.w - 1)))
  in
  let change = ref None in
  let widgets =
    update_at index
      (function
        | Slider slider ->
            let value = slider.min +. fraction *. (slider.max -. slider.min) in
            if value <> slider.value then change := Some (Slid (slider.name, value));
            Slider { slider with value }
        | Int_slider slider ->
            let span = slider.max - slider.min in
            let value = slider.min
              + int_of_float ((fraction *. float_of_int span) +. 0.5)
              |> clamp slider.min slider.max in
            if value <> slider.value then
              change := Some (Int_slid (slider.name, value));
            Int_slider { slider with value }
        | widget -> widget)
      canvas.widget_count canvas.widgets
  in
  replace_widgets canvas widgets, Option.to_list !change

let range_at (canvas : t) index handle x =
  let layout = layout_at canvas index in
  let fraction =
    clamp 0. 1.
      (float_of_int (x - layout.control.x)
       /. float_of_int (Stdlib.max 1 (layout.control.w - 1)))
  in
  let change = ref None in
  let widgets =
    update_at index
      (function
        | Range range ->
            let value = range.min +. fraction *. (range.max -. range.min) in
            let low, high =
              match handle with
              | Low -> Float.min value range.high, range.high
              | High -> range.low, Float.max value range.low
            in
            if low <> range.low || high <> range.high then
              change := Some (Ranged (range.name, low, high));
            Range { range with low; high }
        | widget -> widget)
      canvas.widget_count canvas.widgets
  in
  replace_widgets canvas widgets, Option.to_list !change

let xy_at (canvas : t) index x y =
  let layout = layout_at canvas index in
  let x_fraction =
    clamp 0. 1.
      (float_of_int (x - layout.control.x)
       /. float_of_int (Stdlib.max 1 (layout.control.w - 1)))
  in
  let y_fraction =
    clamp 0. 1.
      (float_of_int (y - layout.control.y)
       /. float_of_int (Stdlib.max 1 (layout.control.h - 1)))
  in
  let change = ref None in
  let widgets =
    update_at index
      (function
        | Xy point ->
            let px = point.x_min +. x_fraction *. (point.x_max -. point.x_min) in
            let py = point.y_min +. y_fraction *. (point.y_max -. point.y_min) in
            if px <> point.x || py <> point.y then
              change := Some (Moved2 (point.name, px, py));
            Xy { point with x = px; y = py }
        | widget -> widget)
      canvas.widget_count canvas.widgets
  in
  replace_widgets canvas widgets, Option.to_list !change

let focused_text_field canvas x y =
  match hit_index canvas (x, y) with
  | Some index ->
      (match widget_at canvas index with
       | Some (Text_field field) -> Some field.name
       | _ -> None)
  | None -> None

let map_focused canvas transform =
  match canvas.focus with
  | None -> canvas, []
  | Some focused ->
      let change = ref None in
      let widgets =
        List.map
          (function
            | Text_field field when field.name = focused ->
                let value = transform field.value in
                change := Some (Text_changed (field.name, value));
                Text_field { field with value }
            | widget -> widget)
          canvas.widgets
      in
      replace_widgets canvas widgets, Option.to_list !change

let drop_last_utf8 text =
  let rec find index =
    if index <= 0 then 0
    else if Char.code text.[index] land 0xc0 <> 0x80 then index
    else find (index - 1)
  in
  if text = "" then text
  else String.sub text 0 (find (String.length text - 1))

let range_handle_at canvas index x =
  let layout = layout_at canvas index in
  match widget_at canvas index with
  | Some (Range range) ->
      let low_x =
        position layout.control
          ((range.low -. range.min) /. (range.max -. range.min))
      in
      let high_x =
        position layout.control
          ((range.high -. range.min) /. (range.max -. range.min))
      in
      if abs (x - low_x) <= abs (x - high_x) then Low else High
  | _ -> Low

let numeric_label_index (canvas : t) point =
  if not (contains { x = canvas.x; y = canvas.y; w = canvas.width;
      h = panel_height canvas } point) then None
  else
    displayed_widgets canvas
    |> Array.find_map (fun displayed ->
      match displayed.widget with
      | Slider _ | Int_slider _ ->
          let geometry = layout canvas displayed in
          if contains geometry.row point && not (contains geometry.control point)
          then Some displayed.source_index else None
      | _ -> None)

let numeric_control_contains (canvas : t) (edit : numeric_edit) point =
  contains (layout_at canvas edit.index).control point

let clear_numeric_edit canvas =
  { canvas with numeric_edit = None; composition = "" }

let commit_numeric_edit ~keep_invalid canvas =
  match canvas.numeric_edit with
  | None -> canvas, []
  | Some edit ->
      (match widget_at canvas edit.index with
       | Some widget when numeric_text_valid widget edit.text ->
           let change = ref None in
           let widgets = update_at edit.index (function
             | Slider slider ->
                 let value = float_of_string edit.text in
                 if value <> slider.value then
                   change := Some (Slid (slider.name, value));
                 Slider { slider with value }
             | Int_slider slider ->
                 let value = int_of_string edit.text in
                 if value <> slider.value then
                   change := Some (Int_slid (slider.name, value));
                 Int_slider { slider with value }
             | widget -> widget)
             canvas.widget_count canvas.widgets in
           clear_numeric_edit (replace_widgets canvas widgets),
           Option.to_list !change
       | Some _ | None when keep_invalid ->
          { canvas with numeric_edit = Some {
              edit with valid = false; replace_on_input = false;
            } }, []
       | Some _ | None -> clear_numeric_edit canvas, [])

let set_numeric_text canvas text =
  match canvas.numeric_edit with
  | None -> canvas
  | Some edit ->
      let widget = Option.get (widget_at canvas edit.index) in
      { canvas with numeric_edit = Some {
          edit with
          text;
          valid = numeric_text_valid widget text;
          replace_on_input = false;
        } }

let numeric_character = function
  | '0' .. '9' | '+' | '-' | '.' | 'e' | 'E' -> true
  | _ -> false

let press ?time canvas ((x, y) as point) =
  let canvas, committed, editor_consumed = match canvas.numeric_edit with
    | Some edit when numeric_control_contains canvas edit point ->
        { canvas with last_label_press = None }, [], true
    | Some _ ->
        let canvas, changes = commit_numeric_edit ~keep_invalid:false canvas in
        canvas, changes, false
    | None -> canvas, [], false in
  if editor_consumed then
    { canvas with pointer = Some point; active = None }, committed
  else match numeric_label_index canvas point, time with
  | Some index, Some now ->
      let is_double = match canvas.last_label_press with
        | Some (previous, (px, py), previous_time) ->
            previous = index && now >= previous_time && now -. previous_time <= 0.35
            && ((x - px) * (x - px)) + ((y - py) * (y - py)) <= 25
        | None -> false in
      let canvas = { canvas with pointer = Some point; hover = Some index;
        active = None; focus = None; composition = "" } in
      if is_double then
        let widget = Option.get (widget_at canvas index) in
        { canvas with
          numeric_edit = Some {
            index;
            text = numeric_text widget;
            valid = true;
            replace_on_input = true;
          };
          last_label_press = None;
        }, committed
      else { canvas with last_label_press = Some (index, point, now) }, committed
  | Some _, None ->
      { canvas with
        pointer = Some point;
        active = None;
        last_label_press = None;
      }, committed
  | None, _ ->
  let index = hit_index canvas (x, y) in
  let base = {
    canvas with
    pointer = Some (x, y);
    hover = index;
    focus = focused_text_field canvas x y;
    composition = "";
    active = None;
    last_label_press = None;
  } in
  match index with
  | None -> base, committed
  | Some index ->
      (match widget_at canvas index with
       | Some (Accordion _ | Button _ | Toggle _ | Choice _) ->
           { base with active = Some (Armed index) }, committed
       | Some (Slider _ | Int_slider _) ->
           let base = { base with active = Some (Drag_slider index) } in
           let canvas, changes = slider_at base index x in
           canvas, committed @ changes
       | Some (Range _) ->
           let handle = range_handle_at canvas index x in
           let base = { base with active = Some (Drag_range (index, handle)) } in
           let canvas, changes = range_at base index handle x in
           canvas, committed @ changes
       | Some (Xy _) ->
           let base = { base with active = Some (Drag_xy index) } in
           let canvas, changes = xy_at base index x y in
           canvas, committed @ changes
       | Some (Text_field _ | Label _ | Accordion_end) | None ->
           base, committed)

let move canvas (x, y) =
  let canvas = {
    canvas with
    pointer = Some (x, y);
    hover = hit_index canvas (x, y);
  } in
  match canvas.active with
  | Some (Drag_slider index) -> slider_at canvas index x
  | Some (Drag_range (index, handle)) -> range_at canvas index handle x
  | Some (Drag_xy index) -> xy_at canvas index x y
  | Some (Armed _) | None -> canvas, []

let release_armed canvas index (x, y) =
  let target = layout_at canvas index in
  if not (contains target.control (x, y)) then canvas, []
  else
    let change = ref None in
    let widgets =
      update_at index
        (function
          | Button button as widget ->
              change := Some (Clicked button.name);
              widget
          | Accordion accordion ->
              let expanded = not accordion.expanded in
              change := Some (Toggled (accordion.name, expanded));
              Accordion { accordion with expanded }
          | Toggle toggle ->
              let value = not toggle.value in
              change := Some (Toggled (toggle.name, value));
              Toggle { toggle with value }
          | Choice choice ->
              let direction =
                if x < target.control.x + (target.control.w / 2)
                then -1 else 1
              in
              let count = Array.length choice.options in
              let selected = (choice.selected + direction + count) mod count in
              change := Some (Selected
                (choice.name, choice.options.(selected)));
              Choice { choice with selected }
          | widget -> widget)
        canvas.widget_count canvas.widgets
    in
    replace_widgets canvas widgets, Option.to_list !change

let release canvas (x, y) =
  let canvas = {
    canvas with
    pointer = Some (x, y);
    hover = hit_index canvas (x, y);
  } in
  let updated, changes =
    match canvas.active with
    | Some (Armed index) -> release_armed canvas index (x, y)
    | Some (Drag_slider index) -> slider_at canvas index x
    | Some (Drag_range (index, handle)) -> range_at canvas index handle x
    | Some (Drag_xy index) -> xy_at canvas index x y
    | None -> canvas, []
  in
  { updated with active = None }, changes

let update_one ?time canvas event =
  match event with
  | Prismel.Event.MousePressed (Prismel.Input.LeftButton, (x, y)) ->
      press ?time canvas (x, y)
  | Prismel.Event.MouseMoved (x, y) ->
      move canvas (x, y)
  | Prismel.Event.MouseReleased (Prismel.Input.LeftButton, (x, y)) ->
      release canvas (x, y)
  | Prismel.Event.MouseScrolled (_, vertical)
      when (match canvas.pointer with
        | Some point -> contains
            { x = canvas.x; y = canvas.y; w = canvas.width;
              h = panel_height canvas } point
        | None -> false) ->
      let scroll_y = canvas.scroll_y - (vertical * canvas.row_height) in
      clamp_scroll { canvas with scroll_y; active = None; layout_cache = None }, []
  | Prismel.Event.PointerCancelled Prismel.Input.LeftButton ->
      { canvas with active = None }, []
  | Prismel.Event.TextInput text ->
      (match canvas.numeric_edit with
       | Some edit when String.for_all numeric_character text ->
           let value = if edit.replace_on_input then text else edit.text ^ text in
           { (set_numeric_text canvas value) with composition = "" }, []
       | Some _ -> { canvas with composition = "" }, []
       | None ->
           let canvas, changes = map_focused canvas (fun value -> value ^ text) in
           { canvas with composition = "" }, changes)
  | Prismel.Event.TextEditing { text; _ } ->
      (match canvas.numeric_edit with
       | Some _ ->
           let composition =
             if String.for_all numeric_character text then text else ""
           in
           { canvas with composition }, []
       | None -> { canvas with composition = text }, [])
  | Prismel.Event.KeyPressed Prismel.Input.Backspace ->
      (match canvas.numeric_edit with
       | Some edit ->
           let value =
             if edit.replace_on_input then "" else drop_last_utf8 edit.text
           in
           { (set_numeric_text canvas value) with composition = "" }, []
       | None -> map_focused canvas drop_last_utf8)
  | Prismel.Event.KeyPressed Prismel.Input.Enter ->
      commit_numeric_edit ~keep_invalid:true canvas
  | Prismel.Event.KeyPressed Prismel.Input.Escape ->
      clear_numeric_edit canvas, []
  | Prismel.Event.WindowFocusLost ->
      { canvas with
        active = None;
        hover = None;
        focus = None;
        composition = "";
        numeric_edit = None;
        last_label_press = None;
      }, []
  | _ -> canvas, []

let update ?time canvas events =
  Option.iter (fun value ->
    if not (Float.is_finite value) then
      invalid_arg "Pxui.update: time must be finite") time;
  let canvas, changes = List.fold_left
    (fun (canvas, reversed_changes) event ->
      let canvas, next = update_one ?time canvas event in
      canvas, List.rev_append next reversed_changes)
    (canvas, []) events
  in
  canvas, List.rev changes

let update_frame canvas (frame : Prismel.Frame.t) =
  update ~time:frame.time canvas frame.events

let handle_event canvas = function
  | event ->
      let updated, changes = update_one canvas event in
  canvas.widgets <- updated.widgets;
  canvas.ordered_cache <- None;
  canvas.runtime_cache <- None;
  canvas.layout_cache <- None;
      canvas.focus <- updated.focus;
      canvas.composition <- updated.composition;
      canvas.pointer <- updated.pointer;
      canvas.hover <- updated.hover;
      canvas.active <- updated.active;
      canvas.numeric_edit <- updated.numeric_edit;
      canvas.last_label_press <- updated.last_label_press;
      canvas.scroll_y <- updated.scroll_y;
      changes

let find_map name extract canvas =
  let runtime = widget_runtime canvas in
  match Hashtbl.find_opt runtime.names name with
  | None -> None
  | Some id -> Option.bind (Stable_store.get runtime.slots id) (extract name)

type widget_update = Skip | Keep | Replace of widget

let update_widget canvas update =
  let rec loop reversed = function
    | [] -> canvas
    | widget :: rest ->
        (match update widget with
         | Skip -> loop (widget :: reversed) rest
         | Keep -> canvas
         | Replace widget ->
             let widgets = List.rev_append reversed (widget :: rest) in
             { canvas with widgets; ordered_cache = None; runtime_cache = None;
               layout_cache = None })
  in
  loop [] canvas.widgets

let toggle_value canvas name =
  find_map name
    (fun expected -> function
      | Toggle toggle when toggle.name = expected -> Some toggle.value
      | _ -> None)
    canvas

let set_toggle_value canvas name value =
  update_widget canvas (function
    | Toggle toggle when toggle.name = name ->
        if toggle.value = value then Keep
        else Replace (Toggle { toggle with value })
    | _ -> Skip)

let slider_value canvas name =
  find_map name
    (fun expected -> function
      | Slider slider when slider.name = expected -> Some slider.value
      | _ -> None)
    canvas

let set_slider_value canvas name value =
  if not (Float.is_finite value) then
    invalid_arg "Pxui.set_slider_value: value must be finite";
  update_widget canvas (function
    | Slider slider when slider.name = name ->
        if slider.value = value then Keep
        else Replace (Slider { slider with value })
    | _ -> Skip)

let int_slider_value canvas name =
  find_map name
    (fun expected -> function
      | Int_slider slider when slider.name = expected -> Some slider.value
      | _ -> None)
    canvas

let set_int_slider_value canvas name value =
  update_widget canvas (function
    | Int_slider slider when slider.name = name ->
        if slider.value = value then Keep
        else Replace (Int_slider { slider with value })
    | _ -> Skip)

let text_value canvas name =
  find_map name
    (fun expected -> function
      | Text_field field when field.name = expected -> Some field.value
      | _ -> None)
    canvas

let set_text_value canvas name value =
  update_widget canvas (function
    | Text_field field when field.name = name ->
        if field.value = value then Keep
        else Replace (Text_field { field with value })
    | _ -> Skip)

let choice_value canvas name =
  find_map name
    (fun expected -> function
      | Choice choice when choice.name = expected ->
          Some choice.options.(choice.selected)
      | _ -> None)
    canvas

let set_choice_value canvas name value =
  update_widget canvas (function
    | Choice choice when choice.name = name ->
        (match Array.find_index (( = ) value) choice.options with
         | Some selected when selected = choice.selected -> Keep
         | Some selected -> Replace (Choice { choice with selected })
         | None -> invalid_arg (Printf.sprintf
             "Pxui.set_choice_value: %S is not an option for %S" value name))
    | _ -> Skip)

let range_value canvas name =
  find_map name
    (fun expected -> function
      | Range range when range.name = expected -> Some (range.low, range.high)
      | _ -> None)
    canvas

let xy_value canvas name =
  find_map name
    (fun expected -> function
      | Xy point when point.name = expected -> Some (point.x, point.y)
      | _ -> None)
    canvas

let accordion_expanded canvas name =
  find_map name
    (fun expected -> function
      | Accordion accordion when accordion.name = expected ->
          Some accordion.expanded
      | _ -> None)
    canvas

let set_accordion_expanded canvas name expanded =
  let canvas = update_widget canvas (function
    | Accordion accordion when accordion.name = name ->
        if accordion.expanded = expanded then Keep
        else Replace (Accordion { accordion with expanded })
    | _ -> Skip) in
  if Option.is_none canvas.active then canvas else { canvas with active = None }

let with_position ~x ~y (canvas : t) =
  if x = canvas.x && y = canvas.y then canvas
  else { canvas with x; y; active = None; hover = None; layout_cache = None }

let with_width width (canvas : t) =
  if width <= 0 then invalid_arg "Pxui.with_width: width must be positive";
  if width = canvas.width then canvas
  else { canvas with width; active = None; hover = None; layout_cache = None }

let with_max_height max_height (canvas : t) =
  Option.iter (fun height ->
    if height < canvas.row_height + (2 * canvas.padding) then
      invalid_arg "Pxui.with_max_height: height is too small for one row")
    max_height;
  if max_height = canvas.max_height then canvas
  else clamp_scroll
      { canvas with max_height; active = None; hover = None; layout_cache = None }

let with_frame_max_height frame_max_height (canvas : t) =
  Option.iter (fun height ->
    if height < canvas.row_height + (2 * canvas.padding) then
      invalid_arg "Pxui: frame height is too small for one row")
    frame_max_height;
  if frame_max_height = canvas.frame_max_height then canvas
  else
    let previous_height = panel_height canvas in
    let updated = clamp_scroll { canvas with frame_max_height; layout_cache = None } in
    if panel_height updated = previous_height then updated
    else { updated with active = None; hover = None }

let bounds (canvas : t) =
  canvas.x, canvas.y, canvas.width, panel_height canvas

type canvas = t

module Camera_control = struct
  type render_request = {
    filename : string;
    factor : int;
  }

  type t = {
    prefix : string;
    ui_visible : bool;
  }

  let create ?(prefix = "camera") () =
    if prefix = "" then invalid_arg "Pxui.Camera_control: prefix is empty";
    { prefix; ui_visible = true }

  let name control suffix = control.prefix ^ "." ^ suffix

  let append control ~camera canvas =
    let degrees = Prismel.Easy_camera.fov_y camera *. 180. /. Float.pi in
    canvas
    |> accordion ~name:(name control "section") ~label:"Camera"
         ~expanded:false (fun canvas ->
           canvas
           |> slider ~name:(name control "fov") ~label:"FOV"
                ~min:15. ~max:120. ~value:degrees
           |> slider ~name:(name control "distance") ~label:"Distance"
                ~min:0.1 ~max:100. ~value:(Prismel.Easy_camera.distance camera)
           |> slider ~name:(name control "near") ~label:"Near clip"
                ~min:0.01 ~max:10. ~value:(Prismel.Easy_camera.near camera)
           |> slider ~name:(name control "far") ~label:"Far clip"
                ~min:10. ~max:5000. ~value:(Prismel.Easy_camera.far camera)
           |> toggle ~name:(name control "inertia") ~label:"Inertia"
                ~value:(Prismel.Easy_camera.inertia camera)
           |> button ~name:(name control "reset") ~label:"Reset camera")
    |> accordion ~name:(name control "render-section") ~label:"Render"
         ~expanded:false (fun canvas ->
           canvas
           |> choice ~name:(name control "factor") ~label:"Render factor"
                ~options:["1×"; "2×"; "3×"; "4×"] ~selected:1
           |> text_field ~name:(name control "filename") ~label:"Output"
                ~value:"prismel-render.png"
           |> button ~name:(name control "save") ~label:"Render / save PNG")

  let key_pressed character frame =
    Prismel.Frame.has_event (function
      | Prismel.Event.KeyPressed (Prismel.Input.KeyChar key) ->
          Char.lowercase_ascii key = character
      | _ -> false) frame

  let clicked expected changes =
    List.exists (function Clicked name -> name = expected | _ -> false) changes

  let slid expected changes =
    List.find_map (function
      | Slid (name, value) when name = expected -> Some value
      | _ -> None) changes

  let toggled expected changes =
    List.find_map (function
      | Toggled (name, value) when name = expected -> Some value
      | _ -> None) changes

  let value fallback = function Some value -> value | None -> fallback

  let render_factor control canvas =
    match choice_value canvas (name control "factor") with
    | Some "1×" -> 1 | Some "3×" -> 3 | Some "4×" -> 4
    | Some "2×" | Some _ | None -> 2

  let camera_area canvas frame =
    let x, _, width, _ = bounds canvas in
    let left_width = max 0 (x - 8)
    and right_x = x + width + 8 in
    let right_width = max 0 (frame.Prismel.Frame.width - right_x) in
    if right_width >= left_width then
      right_x, 0, right_width, frame.height
    else 0, 0, left_width, frame.height

  let update ?control_area ?(panel_visible = true) control ~ui ~camera frame =
    let minimum_height = ui.row_height + (2 * ui.padding) in
    let available_height = max minimum_height
        (frame.Prismel.Frame.height - ui.y - 8) in
    let ui = with_frame_max_height (Some available_height) ui in
    let h_pressed = key_pressed 'h' frame
    and c_pressed = key_pressed 'c' frame in
    let ui_was_visible = control.ui_visible in
    let control =
      if h_pressed then { control with ui_visible = not control.ui_visible }
      else if c_pressed && not control.ui_visible then
        { control with ui_visible = true }
      else control in
    let ui =
      if c_pressed then
        let section = name control "section" in
        let expanded = value false (accordion_expanded ui section) in
        set_accordion_expanded ui section
          (if h_pressed || not ui_was_visible then true else not expanded)
      else ui in
    let ui, changes =
      if control.ui_visible && panel_visible then update_frame ui frame
      else ui, [] in
    let current_fov = Prismel.Easy_camera.fov_y camera
    and current_distance = Prismel.Easy_camera.distance camera
    and current_near = Prismel.Easy_camera.near camera
    and current_far = Prismel.Easy_camera.far camera in
    let fov = value (current_fov *. 180. /. Float.pi)
        (slid (name control "fov") changes) *. Float.pi /. 180. in
    let fov = if fov > 0. && fov < Float.pi then fov else current_fov
    and distance =
      let candidate = value current_distance
          (slid (name control "distance") changes) in
      if candidate > 0. then candidate else current_distance
    and near =
      let candidate = value current_near
          (slid (name control "near") changes) in
      if candidate > 0. then candidate else current_near
    and far = value current_far
        (slid (name control "far") changes)
    and inertia = value (Prismel.Easy_camera.inertia camera)
        (toggled (name control "inertia") changes) in
    let far = max (near +. 0.01) far in
    let camera = camera
      |> Prismel.Easy_camera.with_fov_y fov
      |> Prismel.Easy_camera.with_distance distance
      |> Prismel.Easy_camera.with_clip ~near ~far
      |> Prismel.Easy_camera.with_inertia inertia
      |> Prismel.Easy_camera.with_translation_key (Some Prismel.Input.Space) in
    let camera = if clicked (name control "reset") changes
      then Prismel.Easy_camera.reset camera else camera in
    let area = match control_area with
      | Some area -> area
      | None when control.ui_visible -> camera_area ui frame
      | None -> 0, 0, frame.width, frame.height in
    let camera = Prismel.Easy_camera.with_control_area (Some area) camera
      |> Fun.flip Prismel.Easy_camera.update frame in
    let ui =
      if control.ui_visible && panel_visible then
        ui
        |> fun ui -> set_slider_value ui (name control "fov")
             (Prismel.Easy_camera.fov_y camera *. 180. /. Float.pi)
        |> fun ui -> set_slider_value ui (name control "distance")
             (Prismel.Easy_camera.distance camera)
        |> fun ui -> set_slider_value ui (name control "near")
             (Prismel.Easy_camera.near camera)
        |> fun ui -> set_slider_value ui (name control "far")
             (Prismel.Easy_camera.far camera)
      else ui in
    let requests = if clicked (name control "save") changes then
        let filename = value "prismel-render.png"
            (text_value ui (name control "filename")) in
        [{ filename; factor = render_factor control ui }]
      else [] in
    control, ui, camera, changes, requests

  let overlay control overlay =
    if control.ui_visible then overlay else Prismel.Scene.empty

  let scene control ui = overlay control (scene ui)

  let ui_visible control = control.ui_visible

  let save ?(background = Prismel.Color.black) request ~frame ~camera scene =
    ignore (background, frame, camera, scene);
    if request.factor <> 1 then
      Error "native framebuffer export supports render factor 1 only"
    else Prismel.Canvas.save_screen_png request.filename
end

module Camera2_control = struct
  type render_request = {
    filename : string;
    factor : int;
  }

  type t = {
    prefix : string;
    ui_visible : bool;
  }

  let create ?(prefix = "camera2") () =
    if prefix = "" then invalid_arg "Pxui.Camera2_control: prefix is empty";
    { prefix; ui_visible = true }

  let name control suffix = control.prefix ^ "." ^ suffix

  let append control ~camera canvas =
    let center = Prismel.Easy_camera2.center camera in
    let degrees = Prismel.Easy_camera2.rotation camera *. 180. /. Float.pi in
    canvas
    |> accordion ~name:(name control "section") ~label:"Camera"
         ~expanded:false (fun canvas ->
           canvas
           |> slider ~name:(name control "center-x") ~label:"Center X"
                ~min:(-1000.) ~max:1000. ~value:center.Prismel.Vec2.x
           |> slider ~name:(name control "center-y") ~label:"Center Y"
                ~min:(-1000.) ~max:1000. ~value:center.y
           |> slider ~name:(name control "zoom") ~label:"Zoom"
                ~min:0.05 ~max:20. ~value:(Prismel.Easy_camera2.zoom camera)
           |> slider ~name:(name control "rotation") ~label:"Rotation"
                ~min:(-180.) ~max:180. ~value:degrees
           |> toggle ~name:(name control "inertia") ~label:"Inertia"
                ~value:(Prismel.Easy_camera2.inertia camera)
           |> button ~name:(name control "reset") ~label:"Reset camera")
    |> accordion ~name:(name control "render-section") ~label:"Render"
         ~expanded:false (fun canvas ->
           canvas
           |> choice ~name:(name control "factor") ~label:"Render factor"
                ~options:["1×"; "2×"; "3×"; "4×"] ~selected:1
           |> text_field ~name:(name control "filename") ~label:"Output"
                ~value:"prismel-render.png"
           |> button ~name:(name control "save") ~label:"Render / save PNG")

  let key_pressed character frame =
    Prismel.Frame.has_event (function
      | Prismel.Event.KeyPressed (Prismel.Input.KeyChar key) ->
          Char.lowercase_ascii key = character
      | _ -> false) frame

  let clicked expected changes =
    List.exists (function Clicked name -> name = expected | _ -> false) changes

  let slid expected changes =
    List.find_map (function
      | Slid (name, value) when name = expected -> Some value
      | _ -> None) changes

  let toggled expected changes =
    List.find_map (function
      | Toggled (name, value) when name = expected -> Some value
      | _ -> None) changes

  let value fallback = function Some value -> value | None -> fallback

  let render_factor control canvas =
    match choice_value canvas (name control "factor") with
    | Some "1×" -> 1 | Some "3×" -> 3 | Some "4×" -> 4
    | Some "2×" | Some _ | None -> 2

  let camera_area canvas frame =
    let x, _, width, _ = bounds canvas in
    let left_width = max 0 (x - 8)
    and right_x = x + width + 8 in
    let right_width = max 0 (frame.Prismel.Frame.width - right_x) in
    if right_width >= left_width then right_x, 0, right_width, frame.height
    else 0, 0, left_width, frame.height

  let update ?control_area ?viewport ?(panel_visible = true) control ~ui ~camera frame =
    let minimum_height = ui.row_height + (2 * ui.padding) in
    let available_height = max minimum_height
        (frame.Prismel.Frame.height - ui.y - 8) in
    let ui = with_frame_max_height (Some available_height) ui in
    let h_pressed = key_pressed 'h' frame
    and c_pressed = key_pressed 'c' frame in
    let ui_was_visible = control.ui_visible in
    let control =
      if h_pressed then { control with ui_visible = not control.ui_visible }
      else if c_pressed && not control.ui_visible then
        { control with ui_visible = true }
      else control in
    let ui =
      if c_pressed then
        let section = name control "section" in
        let expanded = value false (accordion_expanded ui section) in
        set_accordion_expanded ui section
          (if h_pressed || not ui_was_visible then true else not expanded)
      else ui in
    let ui, changes = if control.ui_visible && panel_visible then update_frame ui frame
      else ui, [] in
    let current_center = Prismel.Easy_camera2.center camera in
    let center = Prismel.Vec2.create
        (value current_center.x (slid (name control "center-x") changes))
        (value current_center.y (slid (name control "center-y") changes)) in
    let zoom =
      let candidate = value (Prismel.Easy_camera2.zoom camera)
          (slid (name control "zoom") changes) in
      if candidate > 0. then candidate else Prismel.Easy_camera2.zoom camera in
    let rotation = value
        (Prismel.Easy_camera2.rotation camera *. 180. /. Float.pi)
        (slid (name control "rotation") changes) *. Float.pi /. 180. in
    let inertia = value (Prismel.Easy_camera2.inertia camera)
        (toggled (name control "inertia") changes) in
    let camera = camera
      |> Prismel.Easy_camera2.with_center center
      |> Prismel.Easy_camera2.with_zoom zoom
      |> Prismel.Easy_camera2.with_rotation rotation
      |> Prismel.Easy_camera2.with_inertia inertia
      |> Prismel.Easy_camera2.with_translation_key (Some Prismel.Input.Space)
      |> Prismel.Easy_camera2.with_viewport
           (Some (Option.value ~default:(0, 0, frame.width, frame.height)
                    viewport)) in
    let camera = if clicked (name control "reset") changes
      then Prismel.Easy_camera2.reset camera else camera in
    let area = match control_area with
      | Some area -> area
      | None when control.ui_visible -> camera_area ui frame
      | None -> 0, 0, frame.width, frame.height in
    let camera = Prismel.Easy_camera2.with_control_area (Some area) camera
      |> Fun.flip Prismel.Easy_camera2.update frame in
    let ui =
      if control.ui_visible && panel_visible then
        let center = Prismel.Easy_camera2.center camera in
        set_slider_value ui (name control "center-x") center.x
        |> fun ui -> set_slider_value ui (name control "center-y") center.y
        |> fun ui -> set_slider_value ui (name control "zoom")
             (Prismel.Easy_camera2.zoom camera)
        |> fun ui -> set_slider_value ui (name control "rotation")
             (Prismel.Easy_camera2.rotation camera *. 180. /. Float.pi)
      else ui in
    let requests = if clicked (name control "save") changes then
        let filename = value "prismel-render.png"
            (text_value ui (name control "filename")) in
        [{ filename; factor = render_factor control ui }]
      else [] in
    control, ui, camera, changes, requests

  let overlay control overlay =
    if control.ui_visible then overlay else Prismel.Scene.empty

  let scene control ui = overlay control (scene ui)
  let ui_visible control = control.ui_visible

  let save ?(background = Prismel.Color.black) request ~frame ~camera scene =
    ignore (background, frame, camera, scene);
    if request.factor <> 1 then
      Error "native framebuffer export supports render factor 1 only"
    else Prismel.Canvas.save_screen_png request.filename
end

let hex_of_string text =
  let digits = "0123456789abcdef" in
  let encoded = Bytes.create (String.length text * 2) in
  String.iteri
    (fun index character ->
      let byte = Char.code character in
      Bytes.set encoded (index * 2) digits.[byte lsr 4];
      Bytes.set encoded ((index * 2) + 1) digits.[byte land 0xf])
    text;
  Bytes.unsafe_to_string encoded

let string_of_hex encoded =
  let nibble = function
    | '0' .. '9' as c -> Ok (Char.code c - Char.code '0')
    | 'a' .. 'f' as c -> Ok (10 + Char.code c - Char.code 'a')
    | 'A' .. 'F' as c -> Ok (10 + Char.code c - Char.code 'A')
    | c -> Error (Printf.sprintf "invalid hexadecimal digit %C" c)
  in
  if String.length encoded mod 2 <> 0 then Error "odd hexadecimal value"
  else
    let decoded = Bytes.create (String.length encoded / 2) in
    let rec loop index =
      if index = Bytes.length decoded then Ok (Bytes.unsafe_to_string decoded)
      else
        match nibble encoded.[index * 2], nibble encoded.[(index * 2) + 1] with
        | Ok high, Ok low ->
            Bytes.set decoded index (Char.chr ((high lsl 4) lor low));
            loop (index + 1)
        | Error message, _ | _, Error message -> Error message
    in
    loop 0

let encode canvas =
  let line = function
    | Accordion { name; expanded; _ } ->
        Some (Printf.sprintf "A\t%s\t%d" (hex_of_string name)
          (if expanded then 1 else 0))
    | Toggle { name; value; _ } ->
        Some (Printf.sprintf "B\t%s\t%d" (hex_of_string name)
          (if value then 1 else 0))
    | Slider { name; value; _ } ->
        Some (Printf.sprintf "F\t%s\t%.17g" (hex_of_string name) value)
    | Int_slider { name; value; _ } ->
        Some (Printf.sprintf "I\t%s\t%d" (hex_of_string name) value)
    | Text_field { name; value; _ } ->
        Some (Printf.sprintf "S\t%s\t%s"
          (hex_of_string name) (hex_of_string value))
    | Choice { name; options; selected; _ } ->
        Some (Printf.sprintf "C\t%s\t%s"
          (hex_of_string name) (hex_of_string options.(selected)))
    | Range { name; low; high; _ } ->
        Some (Printf.sprintf "R\t%s\t%.17g,%.17g"
          (hex_of_string name) low high)
    | Xy { name; x; y; _ } ->
        Some (Printf.sprintf "P\t%s\t%.17g,%.17g"
          (hex_of_string name) x y)
    | Label _ | Button _ | Accordion_end -> None
  in
  "PXUI1\n"
  ^ String.concat "\n" (List.filter_map line (ordered_widgets canvas))
  ^ "\n"

type saved =
  | Saved_bool of bool
  | Saved_float of float
  | Saved_int of int
  | Saved_text of string
  | Saved_choice of string
  | Saved_pair of float * float

let decode canvas encoded =
  let lines = String.split_on_char '\n' encoded in
  match lines with
  | "PXUI1" :: entries ->
      let values = Hashtbl.create 16 in
      let rec parse line_number = function
        | [] -> Ok ()
        | "" :: rest -> parse (line_number + 1) rest
        | entry :: rest ->
            let error message =
              Error (Printf.sprintf "PXUI settings line %d: %s" line_number message)
            in
            (match String.split_on_char '\t' entry with
             | [kind; encoded_name; raw] ->
                 (match string_of_hex encoded_name with
                  | Error message -> error message
                  | Ok name ->
                      let value =
                        match kind with
                        | ("A" | "B") when raw = "0" -> Ok (Saved_bool false)
                        | ("A" | "B") when raw = "1" -> Ok (Saved_bool true)
                        | "F" ->
                            (try
                               let value = float_of_string raw in
                               if Float.is_finite value then
                                 Ok (Saved_float value)
                               else error "non-finite float"
                             with Failure _ -> error "invalid float")
                        | "I" ->
                            (try Ok (Saved_int (int_of_string raw))
                             with Failure _ -> error "invalid integer")
                        | "S" -> Result.map (fun s -> Saved_text s) (string_of_hex raw)
                        | "C" ->
                            Result.map (fun s -> Saved_choice s) (string_of_hex raw)
                        | ("R" | "P") ->
                            (match String.split_on_char ',' raw with
                             | [first; second] ->
                                 (try Ok (Saved_pair
                                   (float_of_string first, float_of_string second))
                                  with Failure _ -> error "invalid float pair")
                             | _ -> error "invalid float pair")
                        | _ -> error "unknown value kind"
                      in
                      Result.bind value (fun value ->
                        Hashtbl.replace values name value;
                        parse (line_number + 1) rest))
             | _ -> error "expected three tab-separated fields")
      in
      Result.bind (parse 2 entries) (fun () ->
        let error = ref None in
        let widgets =
          List.map
            (fun widget ->
              let mismatch name =
                error := Some (Printf.sprintf
                  "PXUI settings type mismatch for %S" name);
                widget
              in
              match widget with
              | Accordion accordion ->
                  (match Hashtbl.find_opt values accordion.name with
                   | None -> widget
                   | Some (Saved_bool expanded) ->
                       Accordion { accordion with expanded }
                   | Some _ -> mismatch accordion.name)
              | Toggle toggle ->
                  (match Hashtbl.find_opt values toggle.name with
                   | None -> widget
                   | Some (Saved_bool value) -> Toggle { toggle with value }
                   | Some _ -> mismatch toggle.name)
              | Slider slider ->
                  (match Hashtbl.find_opt values slider.name with
                   | None -> widget
                   | Some (Saved_float value) ->
                       Slider { slider with value }
                   | Some _ -> mismatch slider.name)
              | Int_slider slider ->
                  (match Hashtbl.find_opt values slider.name with
                   | None -> widget
                   | Some (Saved_int value) ->
                       Int_slider { slider with value }
                   | Some _ -> mismatch slider.name)
              | Text_field field ->
                  (match Hashtbl.find_opt values field.name with
                   | None -> widget
                   | Some (Saved_text value) -> Text_field { field with value }
                   | Some _ -> mismatch field.name)
              | Choice choice ->
                  (match Hashtbl.find_opt values choice.name with
                   | None -> widget
                   | Some (Saved_choice value) ->
                       (match
                          Array.find_index (fun option -> option = value)
                            choice.options
                        with
                        | Some selected -> Choice { choice with selected }
                        | None ->
                            error := Some (Printf.sprintf
                              "PXUI settings unknown choice %S for %S"
                              value choice.name);
                            widget)
                   | Some _ -> mismatch choice.name)
              | Range range ->
                  (match Hashtbl.find_opt values range.name with
                   | None -> widget
                   | Some (Saved_pair (low, high)) ->
                       Range { range with
                         low = clamp range.min range.max (Float.min low high);
                         high = clamp range.min range.max (Float.max low high);
                       }
                   | Some _ -> mismatch range.name)
              | Xy point ->
                  (match Hashtbl.find_opt values point.name with
                   | None -> widget
                   | Some (Saved_pair (x, y)) ->
                       Xy { point with
                         x = clamp point.x_min point.x_max x;
                         y = clamp point.y_min point.y_max y;
                       }
                   | Some _ -> mismatch point.name)
              | Label _ | Button _ | Accordion_end -> widget)
            canvas.widgets
        in
        match !error with
        | Some message -> Error message
        | None -> Ok {
            canvas with widgets; ordered_cache = None; runtime_cache = None;
            layout_cache = None;
            composition = "";
          })
  | _ -> Error "PXUI settings: unsupported or missing PXUI1 header"

let save canvas filename =
  try
    let channel = open_out_bin filename in
    Fun.protect
      ~finally:(fun () -> close_out channel)
      (fun () -> output_string channel (encode canvas));
    Ok ()
  with Sys_error message -> Error message

let load canvas filename =
  try
    let channel = open_in_bin filename in
    let encoded =
      Fun.protect
        ~finally:(fun () -> close_in channel)
        (fun () -> really_input_string channel (in_channel_length channel))
    in
    decode canvas encoded
  with Sys_error message -> Error message

let compatibility_scene = scene

module Private = struct
  module Store = Stable_store

  module Runtime = struct
    type id = Stable_store.id
    type nonrec t = widget_runtime
    type stats = {
      live : int;
      capacity : int;
      created : int;
      removed : int;
      mutations : int;
      structure_generation : int64;
      layout_generation : int64;
      paint_generation : int64;
      reconcile_visits : int;
      style_visits : int;
      layout_visits : int;
      prepaint_visits : int;
      text_visits : int;
      paint_visits : int;
      compose_visits : int;
      accessibility_visits : int;
      display_list_builds : int;
      display_list_reuses : int;
      display_list_evictions : int;
      display_list_entries : int;
      display_list_bytes : int;
    }

    let packed_color (color : Prismel.Color.t) =
      Int32.logor (Int32.shift_left (Int32.of_int color.r) 24)
        (Int32.logor (Int32.shift_left (Int32.of_int color.g) 16)
          (Int32.logor (Int32.shift_left (Int32.of_int color.b) 8)
            (Int32.of_int color.a)))

    let theme_signature (theme : theme) =
      let mix hash color = Int64.logxor
          (Int64.mul hash 0x100000001b3L)
          (Int64.of_int32 (packed_color color)) in
      let hash = mix 0xcbf29ce484222325L theme.panel in
      let hash = mix hash theme.foreground in
      let hash = mix hash theme.control in
      let hash = mix hash theme.input in
      let hash = mix hash theme.track in
      mix hash theme.accent

    let configure ?(initial = false) runtime canvas =
      let geometry_changed = runtime.panel_x <> canvas.x || runtime.panel_y <> canvas.y
        || runtime.panel_width <> canvas.width
        || runtime.panel_row_height <> canvas.row_height
        || runtime.panel_padding <> canvas.padding
        || runtime.panel_max_height <> canvas.max_height
        || runtime.panel_frame_max_height <> canvas.frame_max_height in
      let scroll_changed = runtime.panel_scroll_y <> canvas.scroll_y in
      let font_generation = Option.fold ~none:0
          ~some:Prismel.Font.Private.generation canvas.font in
      let theme_signature = theme_signature canvas.theme in
      let style_changed = runtime.paint_font != canvas.font
        || runtime.paint_font_generation <> font_generation
        || runtime.paint_font_size <> canvas.font_size
        || runtime.paint_theme_signature <> theme_signature in
      runtime.panel_x <- canvas.x; runtime.panel_y <- canvas.y;
      runtime.panel_width <- canvas.width;
      runtime.panel_row_height <- canvas.row_height;
      runtime.panel_padding <- canvas.padding;
      runtime.panel_max_height <- canvas.max_height;
      runtime.panel_frame_max_height <- canvas.frame_max_height;
      runtime.panel_scroll_y <- canvas.scroll_y;
      runtime.paint_font <- canvas.font;
      runtime.paint_font_generation <- font_generation;
      runtime.paint_font_size <- canvas.font_size;
      runtime.paint_theme_signature <- theme_signature;
      if geometry_changed && not initial then begin
        runtime.panel_node <- None;
        runtime.scrollbar_valid <- false;
        runtime.layout_generation <- Int64.succ runtime.layout_generation;
        for index = 0 to runtime.order_length - 1 do
          mark_runtime_dirty runtime (Array.unsafe_get runtime.order index)
            (dirty_layout lor dirty_hitboxes lor dirty_paint lor dirty_compose)
        done
      end else if scroll_changed && not initial then
        runtime.layout_generation <- Int64.succ runtime.layout_generation;
      if style_changed && not initial then begin
        runtime.panel_node <- None;
        runtime.scrollbar_node <- None;
        runtime.scrollbar_valid <- false;
        for index = 0 to runtime.order_length - 1 do
          mark_runtime_dirty runtime (Array.unsafe_get runtime.order index)
            (dirty_text lor dirty_paint)
        done
      end;
      let id_at_index index = if index < 0 || index >= runtime.order_length
        then None else Some (Array.unsafe_get runtime.order index) in
      let hover = Option.bind canvas.hover id_at_index in
      let active = match canvas.active with
        | Some (Armed index) | Some (Drag_slider index)
        | Some (Drag_range (index, _)) | Some (Drag_xy index) ->
            id_at_index index
        | None -> None in
      let focus = Option.bind canvas.focus
          (fun name -> Hashtbl.find_opt runtime.names name) in
      let numeric_id, numeric_text, numeric_valid = match canvas.numeric_edit with
        | None -> None, "", true
        | Some edit -> id_at_index edit.index, edit.text, edit.valid in
      let dirty_transition effects before after =
        if not initial && before <> after then begin
          Option.iter (fun id -> if Stable_store.valid runtime.slots id then
            mark_runtime_dirty runtime id effects) before;
          Option.iter (fun id -> if Stable_store.valid runtime.slots id then
            mark_runtime_dirty runtime id effects) after
        end in
      dirty_transition dirty_paint runtime.hover_id hover;
      dirty_transition dirty_paint runtime.active_id active;
      dirty_transition (dirty_text lor dirty_paint) runtime.focus_id focus;
      dirty_transition (dirty_text lor dirty_paint) runtime.numeric_edit_id numeric_id;
      if not initial && (runtime.numeric_edit_text <> numeric_text
          || runtime.numeric_edit_valid <> numeric_valid
          || runtime.composition_text <> canvas.composition) then
        Option.iter (fun id -> if Stable_store.valid runtime.slots id then
          mark_runtime_dirty runtime id (dirty_text lor dirty_paint))
          (match numeric_id with Some _ -> numeric_id | None -> focus);
      runtime.hover_id <- hover;
      runtime.active_id <- active;
      runtime.focus_id <- focus;
      runtime.numeric_edit_id <- numeric_id;
      runtime.numeric_edit_text <- numeric_text;
      runtime.numeric_edit_valid <- numeric_valid;
      runtime.composition_text <- canvas.composition

    let create canvas =
      let widgets = ordered_widget_array canvas in
      let runtime = make_widget_runtime (Array.length widgets) in
      populate_widget_runtime runtime widgets;
      configure ~initial:true runtime canvas;
      runtime

    let reconcile runtime canvas =
      if runtime.dead then invalid_arg "Pxui.Runtime.reconcile: destroyed runtime";
      let changes = reconcile_widget_runtime runtime (ordered_widget_array canvas) in
      configure runtime canvas;
      changes

    let find runtime name = Hashtbl.find_opt runtime.names name
    let valid runtime id = Stable_store.valid runtime.slots id
    let length runtime = runtime.order_length
    let id_at runtime index =
      if index < 0 || index >= runtime.order_length then None
      else Some (Array.unsafe_get runtime.order index)
    let parent runtime id =
      if not (valid runtime id) then None
      else
        let slot = Stable_store.slot id in
        let parent = Array.unsafe_get runtime.parents slot in
        if parent < 0 then None
        else Some (Stable_store.make_id parent
          (Array.unsafe_get runtime.slots.generations parent))
    let set_focus runtime = function
      | None ->
          if runtime.focus_id <> None then begin
            Option.iter (fun id -> mark_runtime_dirty runtime id
              (dirty_text lor dirty_paint)) runtime.focus_id;
            runtime.focus_id <- None
          end;
          true
      | Some id when valid runtime id ->
          if runtime.focus_id <> Some id then begin
            Option.iter (fun old -> mark_runtime_dirty runtime old
              (dirty_text lor dirty_paint)) runtime.focus_id;
            mark_runtime_dirty runtime id (dirty_text lor dirty_paint);
            runtime.focus_id <- Some id
          end;
          true
      | Some _ -> false
    let focus runtime = runtime.focus_id
    let set_active runtime = function
      | None ->
          if runtime.active_id <> None then begin
            Option.iter (fun id -> mark_runtime_dirty runtime id dirty_paint)
              runtime.active_id;
            runtime.active_id <- None
          end;
          true
      | Some id when valid runtime id ->
          if runtime.active_id <> Some id then begin
            Option.iter (fun old -> mark_runtime_dirty runtime old dirty_paint)
              runtime.active_id;
            mark_runtime_dirty runtime id dirty_paint;
            runtime.active_id <- Some id
          end;
          true
      | Some _ -> false
    let active runtime = runtime.active_id
    let dirty runtime id =
      if not (valid runtime id) then 0
      else Char.code (Bytes.unsafe_get runtime.dirty (Stable_store.slot id))
    let queues runtime =
      [ runtime.reconcile_queue; runtime.style_queue; runtime.layout_queue;
        runtime.prepaint_queue; runtime.text_queue; runtime.paint_queue;
        runtime.compose_queue; runtime.accessibility_queue ]
    let clear_dirty runtime =
      Bytes.fill runtime.dirty 0 (Bytes.length runtime.dirty) '\000';
      List.iter (fun queue ->
        queue.queued_length <- 0;
        Bytes.fill queue.queued_members 0
          (Bytes.length queue.queued_members) '\000') (queues runtime)
    let set_visible runtime visible = runtime.visible <- visible
    let visible runtime = runtime.visible
    let drain runtime phase queue effects =
      if runtime.phase <> 0 then
        invalid_arg "Pxui.Runtime: re-entrant pass execution";
      runtime.phase <- phase;
      let visited = ref 0 in
      for index = 0 to queue.queued_length - 1 do
        let id = Array.unsafe_get queue.queued_ids index in
        if Stable_store.valid runtime.slots id then begin
          let slot = Stable_store.slot id in
          if Bytes.unsafe_get queue.queued_members slot = '\001' then begin
            Bytes.unsafe_set queue.queued_members slot '\000';
            let dirty = Char.code (Bytes.unsafe_get runtime.dirty slot) in
            Bytes.unsafe_set runtime.dirty slot
              (Char.chr (dirty land (lnot effects) land 0xff));
            incr visited
          end
        end
      done;
      queue.queued_length <- 0;
      runtime.phase <- 0;
      !visited
    let commit_layout (runtime : t) =
      if not runtime.visible then 0
      else if runtime.layout_queue.queued_length = 0
          && runtime.prepaint_queue.queued_length = 0
          && runtime.committed_layout_generation = runtime.layout_generation then 0
      else begin
        let row_height = runtime.panel_row_height
        and padding = runtime.panel_padding in
        let content_height = runtime.visible_length * row_height + (2 * padding) in
        let capped = Option.fold ~none:content_height ~some:(min content_height)
            runtime.panel_max_height in
        let panel_height = Option.fold ~none:capped ~some:(min capped)
            runtime.panel_frame_max_height in
        let max_scroll = max 0 (content_height - panel_height) in
        runtime.panel_scroll_y <- max 0 (min max_scroll runtime.panel_scroll_y);
        runtime.content_height <- content_height;
        runtime.panel_height <- panel_height;
        runtime.max_scroll <- max_scroll;
        for index = 0 to runtime.order_length - 1 do
          let slot = Stable_store.slot (Array.unsafe_get runtime.order index) in
          let flags = Char.code (Bytes.unsafe_get runtime.flags slot) land 0xfe in
          Bytes.unsafe_set runtime.flags slot (Char.chr flags)
        done;
        let first = max 0 ((runtime.panel_scroll_y - padding) / row_height) in
        let last = min runtime.visible_length
            (((runtime.panel_scroll_y + panel_height) / row_height) + 2) in
        let scrollbar_gutter = if max_scroll > 0 then 10 else 0 in
        let inner_x = runtime.panel_x + padding in
        let inner_width = max 1
            (runtime.panel_width - (2 * padding) - scrollbar_gutter) in
        let desired_label_width = min 96 (max 72 (inner_width / 3)) in
        let label_width = min desired_label_width (inner_width / 2) in
        let value_x = inner_x + label_width in
        let value_width = max 1 (inner_width - label_width) in
        for row_index = first to last - 1 do
          let id = Array.unsafe_get runtime.visible_order row_index in
          let slot = Stable_store.slot id in
          let y = runtime.panel_y + padding + (row_index * row_height)
              - runtime.panel_scroll_y in
          Array.unsafe_set runtime.row_x slot inner_x;
          Array.unsafe_set runtime.row_y slot y;
          Array.unsafe_set runtime.row_width slot inner_width;
          Array.unsafe_set runtime.row_height slot row_height;
          let kind = Char.code (Bytes.unsafe_get runtime.kinds slot) in
          let x, cy, width, height = match kind with
            | 0 | 1 -> inner_x, y, inner_width, row_height
            | 3 -> inner_x, y + 3, inner_width, max 1 (row_height - 6)
            | 4 ->
                let width = min 40 inner_width in
                inner_x + inner_width - width, y + 7, width, 18
            | _ -> value_x, y + 3, value_width, max 1 (row_height - 6) in
          Array.unsafe_set runtime.control_x slot x;
          Array.unsafe_set runtime.control_y slot cy;
          Array.unsafe_set runtime.control_width slot width;
          Array.unsafe_set runtime.control_height slot height;
          let flags = Char.code (Bytes.unsafe_get runtime.flags slot) lor 1 in
          Bytes.unsafe_set runtime.flags slot (Char.chr flags);
          if flags land 2 = 0 then enqueue_id runtime.paint_queue id
        done;
        runtime.layout_visible_count <- max 0 (last - first);
        runtime.layout_first_visible <- first;
        runtime.layout_last_visible <- last;
        runtime.layout_visited <- runtime.layout_visited
          + runtime.layout_visible_count;
        runtime.committed_layout_generation <- runtime.layout_generation;
        ignore (drain runtime 3 runtime.layout_queue dirty_layout);
        ignore (drain runtime 4 runtime.prepaint_queue
          (dirty_layout lor dirty_hitboxes));
        runtime.layout_visible_count
      end
    let layout_metrics (runtime : t) =
      runtime.content_height, runtime.panel_height, runtime.max_scroll,
      runtime.layout_visible_count
    let bounds runtime id =
      if not (valid runtime id) then None
      else
        let slot = Stable_store.slot id in
        if Char.code (Bytes.unsafe_get runtime.flags slot) land 1 = 0 then None
        else Some
          (Array.unsafe_get runtime.row_x slot,
           Array.unsafe_get runtime.row_y slot,
           Array.unsafe_get runtime.row_width slot,
           Array.unsafe_get runtime.row_height slot,
           Array.unsafe_get runtime.control_x slot,
           Array.unsafe_get runtime.control_y slot,
           Array.unsafe_get runtime.control_width slot,
           Array.unsafe_get runtime.control_height slot)
    let hit_test runtime (x, y) =
      let found = ref None and index = ref (runtime.layout_last_visible - 1) in
      while !index >= runtime.layout_first_visible && Option.is_none !found do
        let id = Array.unsafe_get runtime.visible_order !index in
        let slot = Stable_store.slot id in
        let kind = Char.code (Bytes.unsafe_get runtime.kinds slot) in
        if kind <> 0 && kind <> 2 then begin
          let left = Array.unsafe_get runtime.control_x slot
          and top = Array.unsafe_get runtime.control_y slot
          and width = Array.unsafe_get runtime.control_width slot
          and height = Array.unsafe_get runtime.control_height slot in
          if x >= left && x < left + width && y >= top && y < top + height then
            found := Some id
        end;
        decr index
      done;
      !found
    let set_hover runtime hover =
      if hover <> runtime.hover_id then begin
        Option.iter (fun id -> if valid runtime id then
          mark_runtime_dirty runtime id dirty_paint) runtime.hover_id;
        Option.iter (fun id -> if valid runtime id then
          mark_runtime_dirty runtime id dirty_paint) hover;
        runtime.hover_id <- hover
      end
    let update_slider runtime id x =
      if not (valid runtime id) then None
      else
        let slot = Stable_store.slot id in
        let left = Array.unsafe_get runtime.control_x slot
        and width = max 1 (Array.unsafe_get runtime.control_width slot - 1) in
        let fraction = max 0. (min 1.
          (float_of_int (x - left) /. float_of_int width)) in
        match Stable_store.get runtime.slots id with
        | Some (Slider slider) ->
            let value = slider.min +. fraction *. (slider.max -. slider.min) in
            if value = slider.value then None
            else begin
              let widget = Slider { slider with value } in
              ignore (Stable_store.set runtime.slots id widget);
              Array.unsafe_set runtime.float_values slot value;
              mark_runtime_dirty runtime id
                (dirty_text lor dirty_paint lor dirty_accessibility);
              runtime.mutations <- runtime.mutations + 1;
              Some (Slid (slider.name, value))
            end
        | Some (Int_slider slider) ->
            let span = slider.max - slider.min in
            let value = slider.min
              + int_of_float (fraction *. float_of_int span +. 0.5)
              |> max slider.min |> min slider.max in
            if value = slider.value then None
            else begin
              let widget = Int_slider { slider with value } in
              ignore (Stable_store.set runtime.slots id widget);
              Array.unsafe_set runtime.int_values slot value;
              mark_runtime_dirty runtime id
                (dirty_text lor dirty_paint lor dirty_accessibility);
              runtime.mutations <- runtime.mutations + 1;
              Some (Int_slid (slider.name, value))
            end
        | Some _ | None -> None
    let update runtime events =
      if runtime.dead then invalid_arg "Pxui.Runtime.update: destroyed runtime";
      let reversed = ref [] in
      let emit = function None -> () | Some change -> reversed := change :: !reversed in
      List.iter (function
        | Prismel.Event.MousePressed (Prismel.Input.LeftButton, (x, y)) ->
            let hit = hit_test runtime (x, y) in
            set_hover runtime hit;
            ignore (set_active runtime hit);
            Option.iter (fun id -> emit (update_slider runtime id x)) hit
        | Prismel.Event.MouseMoved (x, y) ->
            set_hover runtime (hit_test runtime (x, y));
            Option.iter (fun id -> emit (update_slider runtime id x))
              runtime.active_id
        | Prismel.Event.MouseReleased (Prismel.Input.LeftButton, (x, y)) ->
            Option.iter (fun id -> emit (update_slider runtime id x))
              runtime.active_id;
            ignore (set_active runtime None);
            set_hover runtime (hit_test runtime (x, y))
        | Prismel.Event.PointerCancelled Prismel.Input.LeftButton
        | Prismel.Event.WindowFocusLost ->
            ignore (set_active runtime None);
            set_hover runtime None
        | _ -> ()) events;
      List.rev !reversed

    let add_geometries builder geometries =
      Array.iter (Scene_command.Display_list.Builder.geometry builder) geometries

    let add_rounded builder ~x ~y ~width ~height ~radius ~fill ~stroke =
      Scene_command.Display_list.Builder.push_transform builder
        { xx = 1.; xy = 0.; yx = 0.; yy = 1.; tx = float x; ty = float y };
      add_geometries builder
        (Scene_command.Shape2.rounded_rect ~width ~height ~radius
           ~fill:(Option.map packed_color fill)
           ~stroke:(Option.map packed_color stroke));
      Scene_command.Display_list.Builder.pop_transform builder

    let add_line builder ~from_ ~to_ ~width ~color =
      Scene_command.Display_list.Builder.geometry builder
        (Scene_command.Shape2.line ~from_ ~to_ ~width
           ~color:(packed_color color))

    let add_rect builder ~x ~y ~width ~height ~color =
      add_geometries builder (Scene_command.Shape2.rect ~x ~y ~width ~height
        ~fill:(Some (packed_color color)) ~stroke:None)

    let add_circle builder ~x ~y ~radius ~fill ~stroke =
      add_geometries builder (Scene_command.Shape2.ellipse ~center:(x, y)
        ~rx:radius ~ry:radius ~fill:(Option.map packed_color fill)
        ~stroke:(Option.map packed_color stroke))

    let add_text runtime canvas builder ~density ~x ~y ?size
        ~color text =
      let size = match canvas.font with Some font -> Prismel.Font.get_size font
        | None -> Option.value ~default:canvas.font_size size in
      match Prismel.Font.Private.retain_text ?font:canvas.font ~density ~size
          text (Prismel.Font.Solid color) with
      | Error _ -> Error ()
      | Ok handle ->
          let image = Prismel.Font.Private.retained_image handle in
          let width, height = Prismel.Image.get_size image in
          let resource_id = Prismel.Image.Private.identity image in
          let scale = float (max 1 density) in
          Scene_command.Display_list.Builder.image builder ~resource_id
            ~source:{ x = 0.; y = 0.; width = float width; height = float height }
            ~destination:{ x = float x; y = float y;
              width = float width /. scale; height = float height /. scale };
          ignore runtime;
          Ok (handle, image, resource_id)

    let paint_cache_byte_capacity = 64 * 1024 * 1024

    let evict_cold_paint runtime ~except =
      let capacity = Array.length runtime.paint_cache_slots in
      let rec search attempts =
        if attempts = capacity then false
        else
          let position = runtime.paint_cache_next in
          runtime.paint_cache_next <- (position + 1) mod capacity;
          let slot = Array.unsafe_get runtime.paint_cache_slots position in
          if slot < 0 || slot = except
              || slot >= Array.length runtime.paint_nodes
              || Array.unsafe_get runtime.paint_nodes slot = None
              || Char.code (Bytes.unsafe_get runtime.flags slot) land 1 <> 0
          then search (attempts + 1)
          else begin
            clear_runtime_paint_slot runtime slot;
            runtime.display_list_evictions <- runtime.display_list_evictions + 1;
            Array.unsafe_set runtime.paint_cache_slots position (-1);
            true
          end in
      search 0

    let reserve_paint_cache runtime slot bytes =
      if bytes > paint_cache_byte_capacity then false
      else
        let old_bytes = Array.unsafe_get runtime.paint_source_bytes slot in
        let existing = Array.unsafe_get runtime.paint_nodes slot <> None in
        let required_count () = runtime.paint_cache_count
          + if existing then 0 else 1 in
        let required_bytes () = runtime.paint_cache_bytes - old_bytes + bytes in
        let rec make_room () =
          if required_count () <= Array.length runtime.paint_cache_slots
              && required_bytes () <= paint_cache_byte_capacity then true
          else if evict_cold_paint runtime ~except:slot then make_room ()
          else false in
        if not (make_room ()) then false
        else if existing then begin
          runtime.paint_cache_bytes <- required_bytes ();
          true
        end else begin
          let capacity = Array.length runtime.paint_cache_slots in
          let rec find attempts =
            if attempts = capacity then None
            else
              let position = runtime.paint_cache_next in
              runtime.paint_cache_next <- (position + 1) mod capacity;
              let cached = Array.unsafe_get runtime.paint_cache_slots position in
              if cached < 0 || cached >= Array.length runtime.paint_nodes
                  || Array.unsafe_get runtime.paint_nodes cached = None
              then Some position else find (attempts + 1) in
          match find 0 with
          | None -> false
          | Some position ->
              Array.unsafe_set runtime.paint_cache_slots position slot;
              runtime.paint_cache_count <- runtime.paint_cache_count + 1;
              runtime.paint_cache_bytes <- runtime.paint_cache_bytes + bytes;
              true
        end

    let paint_widget (runtime : t) canvas ~density id =
      let slot = Stable_store.slot id in
      let builder = match Array.unsafe_get runtime.paint_builders slot with
        | Some builder -> builder
        | None ->
            let builder = Scene_command.Display_list.Builder.create ~capacity:16 () in
            Array.unsafe_set runtime.paint_builders slot (Some builder);
            builder in
      Scene_command.Display_list.Builder.reset builder;
      let row_width = Array.unsafe_get runtime.row_width slot
      and row_height = Array.unsafe_get runtime.row_height slot
      and control_x = Array.unsafe_get runtime.control_x slot
        - Array.unsafe_get runtime.row_x slot
      and control_y = Array.unsafe_get runtime.control_y slot
        - Array.unsafe_get runtime.row_y slot
      and control_width = Array.unsafe_get runtime.control_width slot
      and control_height = Array.unsafe_get runtime.control_height slot in
      let theme = canvas.theme in
      let border = Prismel.Color.with_alpha theme.foreground 34
      and faint_border = Prismel.Color.with_alpha theme.foreground 20
      and hover_fill = Prismel.Color.lighten theme.input 0.075
      and pressed_fill = Prismel.Color.blend theme.control theme.accent ~pct:0.18 in
      let hovered = runtime.hover_id = Some id
      and pressed = runtime.active_id = Some id in
      if hovered then add_rounded builder ~x:0 ~y:2 ~width:row_width
        ~height:(max 1 (row_height - 4)) ~radius:5
        ~fill:(Some (Prismel.Color.with_alpha hover_fill 150)) ~stroke:None;
      let label_y = max 5 ((row_height - canvas.font_size - 3) / 2) in
      let text = ref [] in
      let set_text_at x y ?size color value =
        match add_text runtime canvas builder ~density ~x ~y
            ?size ~color value with
        | Error () -> false
        | Ok asset -> text := asset :: !text; true in
      let set_text x ?size color value =
        set_text_at x label_y ?size color value in
      let muted = Prismel.Color.blend theme.foreground theme.panel ~pct:0.48 in
      let numeric_editor label =
        if runtime.numeric_edit_id <> Some id then None else
        let shown = runtime.numeric_edit_text ^ runtime.composition_text ^ "│" in
        let first = set_text 0 theme.accent label in
        add_rounded builder ~x:control_x ~y:control_y ~width:control_width
          ~height:control_height ~radius:4 ~fill:(Some theme.input)
          ~stroke:(Some (if runtime.numeric_edit_valid then theme.accent
            else Prismel.Color.hex_exn "#fb7185"));
        Some (first && set_text (control_x + 8) theme.foreground shown) in
      let painted = match Stable_store.get runtime.slots id with
        | Some (Label label) ->
            add_rect builder ~x:0 ~y:7 ~width:3
              ~height:(max 1 (row_height - 14)) ~color:theme.accent;
            let painted = set_text 10 ~size:(max 1 (canvas.font_size - 1))
                theme.foreground label in
            if painted then add_line builder ~from_:(10, row_height - 2)
              ~to_:(row_width, row_height - 2) ~width:1 ~color:faint_border;
            painted
        | Some (Button button) ->
            let fill = if pressed then pressed_fill
              else if hovered then Prismel.Color.lighten theme.control 0.08
              else theme.control in
            add_rounded builder ~x:control_x ~y:control_y
              ~width:control_width ~height:control_height ~radius:5
              ~fill:(Some fill)
              ~stroke:(Some (if hovered || pressed then theme.accent else border));
            add_rect builder ~x:(control_x + 1) ~y:(control_y + 6) ~width:2
              ~height:(max 1 (control_height - 12)) ~color:theme.accent;
            set_text (control_x + 12) theme.foreground button.label
        | Some (Accordion accordion) ->
            let fill = if pressed then pressed_fill
              else if hovered then Prismel.Color.lighten theme.control 0.08
              else theme.control in
            add_rounded builder ~x:control_x ~y:(control_y + 2)
              ~width:control_width ~height:(max 1 (control_height - 4))
              ~radius:5 ~fill:(Some fill)
              ~stroke:(Some (if hovered || pressed then theme.accent else border));
            set_text (control_x + 9) ~size:11 theme.accent
              (if accordion.expanded then "▾" else "▸")
            && set_text (control_x + 27) theme.foreground accordion.label
        | Some (Toggle toggle) ->
            let track = if toggle.value then
                Prismel.Color.blend theme.accent theme.input ~pct:0.28
              else if hovered then Prismel.Color.lighten theme.control 0.08
              else theme.control in
            let knob_x = if toggle.value then control_x + control_width - 10
              else control_x + 9 in
            let first = set_text 0
                (if toggle.value then theme.foreground else muted) toggle.label in
            add_rounded builder ~x:control_x ~y:control_y ~width:control_width
              ~height:control_height ~radius:9 ~fill:(Some track)
              ~stroke:(Some (if hovered || pressed then theme.accent else border));
            add_circle builder ~x:knob_x ~y:(control_y + (control_height / 2))
              ~radius:6
              ~fill:(Some (if toggle.value then theme.accent else muted))
              ~stroke:None;
            first
        | Some (Slider slider) ->
            (match numeric_editor slider.label with Some painted -> painted
             | None ->
                 let fraction = (slider.value -. slider.min)
                   /. (slider.max -. slider.min) in
                 let marker = position
                     { x = control_x; y = control_y; w = control_width;
                       h = control_height } fraction in
                 let fill_width = max 1 (marker - control_x + 1) in
                 let first = set_text 0 theme.foreground slider.label in
                 add_rounded builder ~x:control_x ~y:(control_y + 4)
                   ~width:control_width ~height:(max 1 (control_height - 8))
                   ~radius:4 ~fill:(Some theme.track) ~stroke:(Some border);
                 add_rounded builder ~x:control_x ~y:(control_y + 4)
                   ~width:fill_width ~height:(max 1 (control_height - 8))
                   ~radius:4
                   ~fill:(Some (Prismel.Color.with_alpha theme.accent
                     (if pressed then 220 else 175))) ~stroke:None;
                 add_line builder ~from_:(marker, control_y + 2)
                   ~to_:(marker, control_y + control_height - 2) ~width:2
                   ~color:theme.foreground;
                 first && set_text_at (control_x + 6) (control_y + 6)
                   ~size:11 theme.foreground (compact_float slider.value))
        | Some (Int_slider slider) ->
            (match numeric_editor slider.label with Some painted -> painted
             | None ->
                 let fraction = float_of_int (slider.value - slider.min)
                   /. float_of_int (slider.max - slider.min) in
                 let marker = position
                     { x = control_x; y = control_y; w = control_width;
                       h = control_height } fraction in
                 let fill_width = max 1 (marker - control_x + 1) in
                 let first = set_text 0 theme.foreground slider.label in
                 add_rounded builder ~x:control_x ~y:(control_y + 4)
                   ~width:control_width ~height:(max 1 (control_height - 8))
                   ~radius:4 ~fill:(Some theme.track) ~stroke:(Some border);
                 add_rounded builder ~x:control_x ~y:(control_y + 4)
                   ~width:fill_width ~height:(max 1 (control_height - 8))
                   ~radius:4
                   ~fill:(Some (Prismel.Color.with_alpha theme.accent
                     (if pressed then 220 else 175))) ~stroke:None;
                 add_line builder ~from_:(marker, control_y + 2)
                   ~to_:(marker, control_y + control_height - 2) ~width:2
                   ~color:theme.foreground;
                 first && set_text_at (control_x + 6) (control_y + 6)
                   ~size:11 theme.foreground (string_of_int slider.value))
        | Some (Text_field field) ->
            let focused = runtime.focus_id = Some id in
            let shown = if focused then
                field.value ^ runtime.composition_text ^ "│" else field.value in
            let first = set_text 0
                (if focused then theme.foreground else muted) field.label in
            add_rounded builder ~x:control_x ~y:control_y ~width:control_width
              ~height:control_height ~radius:4
              ~fill:(Some (if hovered then hover_fill else theme.input))
              ~stroke:(Some (if focused then theme.accent else border));
            first && set_text (control_x + 8) theme.foreground shown
        | Some (Choice choice) ->
            let first = set_text 0 theme.foreground choice.label in
            add_rounded builder ~x:control_x ~y:control_y ~width:control_width
              ~height:control_height ~radius:4
              ~fill:(Some (if pressed then pressed_fill
                else if hovered then hover_fill else theme.input))
              ~stroke:(Some (if hovered || pressed then theme.accent else border));
            first
            && set_text (control_x + 7) ~size:11 theme.accent "‹"
            && set_text (control_x + 21) theme.foreground
                 choice.options.(choice.selected)
            && set_text (control_x + control_width - 13) ~size:11
                 theme.accent "›"
        | Some (Range range) ->
            let low_x = position
                { x = control_x; y = control_y; w = control_width;
                  h = control_height }
                ((range.low -. range.min) /. (range.max -. range.min)) in
            let high_x = position
                { x = control_x; y = control_y; w = control_width;
                  h = control_height }
                ((range.high -. range.min) /. (range.max -. range.min)) in
            let first = set_text 0 theme.foreground range.label in
            add_rounded builder ~x:control_x ~y:(control_y + 7)
              ~width:control_width ~height:(max 1 (control_height - 14))
              ~radius:3 ~fill:(Some theme.track) ~stroke:(Some border);
            add_rect builder ~x:low_x ~y:(control_y + 7)
              ~width:(max 1 (high_x - low_x + 1))
              ~height:(max 1 (control_height - 14))
              ~color:(Prismel.Color.with_alpha theme.accent 185);
            add_line builder ~from_:(low_x, control_y + 3)
              ~to_:(low_x, control_y + control_height - 3) ~width:2
              ~color:theme.foreground;
            add_line builder ~from_:(high_x, control_y + 3)
              ~to_:(high_x, control_y + control_height - 3) ~width:2
              ~color:theme.foreground;
            first && set_text_at (control_x + 5) (control_y + 6) ~size:10
              theme.foreground
              (compact_float range.low ^ " — " ^ compact_float range.high)
        | Some (Xy point) ->
            let px = position
                { x = control_x; y = control_y; w = control_width;
                  h = control_height }
                ((point.x -. point.x_min) /. (point.x_max -. point.x_min)) in
            let py = control_y + int_of_float
                (((point.y -. point.y_min) /. (point.y_max -. point.y_min)
                  *. float (max 1 (control_height - 1))) +. 0.5) in
            let first = set_text 0 theme.foreground point.label in
            add_rounded builder ~x:control_x ~y:control_y ~width:control_width
              ~height:control_height ~radius:4
              ~fill:(Some (if hovered then hover_fill else theme.input))
              ~stroke:(Some border);
            add_line builder
              ~from_:(control_x + (control_width / 2), control_y + 3)
              ~to_:(control_x + (control_width / 2),
                control_y + control_height - 3) ~width:1 ~color:faint_border;
            add_line builder
              ~from_:(control_x + 3, control_y + (control_height / 2))
              ~to_:(control_x + control_width - 3,
                control_y + (control_height / 2)) ~width:1 ~color:faint_border;
            add_circle builder ~x:px ~y:py ~radius:(if pressed then 6 else 5)
              ~fill:(Some theme.accent) ~stroke:(Some theme.foreground);
            first
        | Some Accordion_end -> true
        | None -> false in
      if not painted then begin
        List.iter (fun (handle, _, _) ->
          Prismel.Font.Private.release_retained handle) !text;
        false
      end else
        let segment_id = match Array.unsafe_get runtime.paint_segment_ids slot with
          | 0L ->
              let id = fresh_display_segment_id () in
              Array.unsafe_set runtime.paint_segment_ids slot id; id
          | id -> id in
        let version = Int64.succ
            (Array.unsafe_get runtime.paint_segment_versions slot) in
        match Scene_command.Display_list.Builder.publish builder
            ~id:segment_id ~version with
        | Error _ ->
            List.iter (fun (handle, _, _) ->
              Prismel.Font.Private.release_retained handle) !text;
            false
        | Ok segment ->
            let images = List.map (fun (_, image, resource_id) ->
              resource_id, image) !text in
            let image_bytes = List.fold_left (fun total (_, image, _) ->
              let width, height = Prismel.Image.get_size image in
              total + (width * height * 4)) 0 !text in
            let source_bytes = Scene_command.Display_list.source_bytes segment
              + image_bytes in
            if not (reserve_paint_cache runtime slot source_bytes) then begin
              List.iter (fun (handle, _, _) ->
                Prismel.Font.Private.release_retained handle) !text;
              false
            end else begin
              let node = Prismel.Scene.display_list ~images segment in
              List.iter Prismel.Font.Private.release_retained
                (Array.unsafe_get runtime.paint_text slot);
              Array.unsafe_set runtime.paint_text slot
                (List.map (fun (handle, _, _) -> handle) !text);
              Array.unsafe_set runtime.paint_nodes slot (Some node);
              Array.unsafe_set runtime.paint_segment_versions slot version;
              Array.unsafe_set runtime.paint_source_bytes slot source_bytes;
              let flags = Char.code (Bytes.unsafe_get runtime.flags slot) lor 2 in
              Bytes.unsafe_set runtime.flags slot (Char.chr flags);
              true
            end

    let paint_panel (runtime : t) canvas =
      let builder = runtime.panel_builder in
      Scene_command.Display_list.Builder.reset builder;
      let height = runtime.panel_height and width = runtime.panel_width in
      let border = Prismel.Color.with_alpha canvas.theme.foreground 34
      and glow = Prismel.Color.with_alpha canvas.theme.accent 56 in
      add_rounded builder ~x:4 ~y:5 ~width ~height ~radius:8
        ~fill:(Some (Prismel.Color.rgba 0 0 0 105)) ~stroke:None;
      add_rounded builder ~x:0 ~y:0 ~width ~height ~radius:8
        ~fill:(Some canvas.theme.panel) ~stroke:(Some border);
      add_line builder ~from_:(12, 1) ~to_:(width - 12, 1) ~width:1 ~color:glow;
      let version = Int64.succ runtime.panel_segment_version in
      match Scene_command.Display_list.Builder.publish builder
          ~id:runtime.panel_segment_id ~version with
      | Error _ -> false
      | Ok segment ->
          runtime.panel_segment_version <- version;
          runtime.panel_node <- Some (Prismel.Scene.display_list segment);
          true

    let paint_scrollbar (runtime : t) canvas =
      if runtime.max_scroll = 0 then begin
        runtime.scrollbar_node <- None;
        runtime.scrollbar_valid <- true;
        true
      end else
        let builder = runtime.scrollbar_builder in
        Scene_command.Display_list.Builder.reset builder;
        let track_x = runtime.panel_width - runtime.panel_padding - 5
        and track_y = runtime.panel_padding
        and track_height = max 1
            (runtime.panel_height - (2 * runtime.panel_padding)) in
        let thumb_height = max 20
            (track_height * runtime.panel_height / max 1 runtime.content_height)
          |> min track_height in
        let travel = track_height - thumb_height in
        let thumb_y = track_y + runtime.panel_scroll_y * travel
            / max 1 runtime.max_scroll in
        add_rounded builder ~x:track_x ~y:track_y ~width:4
          ~height:track_height ~radius:2
          ~fill:(Some (Prismel.Color.with_alpha canvas.theme.track 180))
          ~stroke:None;
        add_rounded builder ~x:track_x ~y:thumb_y ~width:4
          ~height:thumb_height ~radius:2
          ~fill:(Some (Prismel.Color.with_alpha canvas.theme.accent 210))
          ~stroke:None;
        let version = Int64.succ runtime.scrollbar_segment_version in
        match Scene_command.Display_list.Builder.publish builder
            ~id:runtime.scrollbar_segment_id ~version with
        | Error _ -> false
        | Ok segment ->
            runtime.scrollbar_segment_version <- version;
            runtime.scrollbar_node <- Some (Prismel.Scene.display_list segment);
            runtime.scrollbar_valid <- true;
            true

    let retained_slice_supported (runtime : t) =
      ignore runtime;
      true

    let scene ?(density = 1) (runtime : t) canvas =
      if runtime.dead then invalid_arg "Pxui.Runtime.scene: destroyed runtime";
      if density <= 0 then invalid_arg "Pxui.Runtime.scene: invalid density";
      if not runtime.visible then []
      else if not (retained_slice_supported runtime) then compatibility_scene canvas
      else begin
        if runtime.paint_density <> density then begin
          runtime.paint_density <- density;
          runtime.panel_node <- None;
          runtime.scrollbar_node <- None;
          runtime.scrollbar_valid <- false;
          for index = 0 to runtime.order_length - 1 do
            let id = Array.unsafe_get runtime.order index in
            let slot = Stable_store.slot id in
            let flags = Char.code (Bytes.unsafe_get runtime.flags slot) land 0xfd in
            Bytes.unsafe_set runtime.flags slot (Char.chr flags)
          done
        end;
        let builds = ref 0 and reuses = ref 0 in
        if runtime.panel_node = None then begin
          if paint_panel runtime canvas then incr builds
        end else incr reuses;
        for index = runtime.layout_first_visible to runtime.layout_last_visible - 1 do
          let id = Array.unsafe_get runtime.visible_order index in
          let slot = Stable_store.slot id in
          if Char.code (Bytes.unsafe_get runtime.flags slot) land 2 = 0 then begin
            if paint_widget runtime canvas ~density id then incr builds
          end else incr reuses
        done;
        if ((not runtime.scrollbar_valid)
            || runtime.composed_scroll_y <> runtime.panel_scroll_y)
            && paint_scrollbar runtime canvas then incr builds
        else incr reuses;
        runtime.display_list_builds <- runtime.display_list_builds + !builds;
        runtime.display_list_reuses <- runtime.display_list_reuses + !reuses;
        if !builds > 0 then begin
          runtime.paint_generation <- Int64.succ runtime.paint_generation;
          runtime.composed_scene <- None
        end;
        match runtime.composed_scene with
        | Some scene when runtime.composed_layout_generation
              = runtime.committed_layout_generation
            && runtime.composed_paint_generation = runtime.paint_generation
            && runtime.composed_scroll_y = runtime.panel_scroll_y -> scene
        | _ ->
            let reversed = ref [] in
            for index = runtime.layout_first_visible
                to runtime.layout_last_visible - 1 do
              let id = Array.unsafe_get runtime.visible_order index in
              let slot = Stable_store.slot id in
              match Array.unsafe_get runtime.paint_nodes slot with
              | None -> ()
              | Some node ->
                  reversed := Prismel.Scene.translate
                    (Array.unsafe_get runtime.row_x slot)
                    (Array.unsafe_get runtime.row_y slot) [node] :: !reversed
            done;
            let widgets = List.rev !reversed in
            let regions = ref [] in
            for index = runtime.layout_first_visible
                to runtime.layout_last_visible - 1 do
              let id = Array.unsafe_get runtime.visible_order index in
              let slot = Stable_store.slot id in
              let focused = match Stable_store.get runtime.slots id with
                | Some (Text_field _) -> runtime.focus_id = Some id
                | Some (Slider _ | Int_slider _) ->
                    runtime.numeric_edit_id = Some id
                | Some _ | None -> false in
              if focused then regions := Prismel.Scene.text_input_region
                ~at:(Array.unsafe_get runtime.control_x slot,
                  Array.unsafe_get runtime.control_y slot)
                ~w:(Array.unsafe_get runtime.control_width slot)
                ~h:(Array.unsafe_get runtime.control_height slot)
                ~focused:true () :: !regions
            done;
            let widgets = List.rev_append !regions widgets in
            let content = Prismel.Scene.clip
                ~at:(runtime.panel_x + runtime.panel_padding,
                  runtime.panel_y + runtime.panel_padding)
                ~w:(max 1 (runtime.panel_width - (2 * runtime.panel_padding)))
                ~h:(max 1 (runtime.panel_height - (2 * runtime.panel_padding)))
                widgets in
            let scene = match runtime.panel_node, runtime.scrollbar_node with
              | Some panel, Some scrollbar ->
                  [Prismel.Scene.translate runtime.panel_x runtime.panel_y [panel];
                   content;
                   Prismel.Scene.translate runtime.panel_x runtime.panel_y
                     [scrollbar]]
              | Some panel, None ->
                  [Prismel.Scene.translate runtime.panel_x runtime.panel_y [panel];
                   content]
              | None, Some _ | None, None -> [content] in
            runtime.composed_scene <- Some scene;
            runtime.composed_layout_generation <-
              runtime.committed_layout_generation;
            runtime.composed_paint_generation <- runtime.paint_generation;
            runtime.composed_scroll_y <- runtime.panel_scroll_y;
            scene
      end

    let drain_paint runtime =
      if runtime.phase <> 0 then
        invalid_arg "Pxui.Runtime: re-entrant paint execution";
      runtime.phase <- 6;
      let visited = ref 0 in
      for index = 0 to runtime.paint_queue.queued_length - 1 do
        let id = Array.unsafe_get runtime.paint_queue.queued_ids index in
        if Stable_store.valid runtime.slots id then begin
          let slot = Stable_store.slot id in
          if Bytes.unsafe_get runtime.paint_queue.queued_members slot = '\001' then begin
            Bytes.unsafe_set runtime.paint_queue.queued_members slot '\000';
            let flags = Char.code (Bytes.unsafe_get runtime.flags slot) in
            if flags land 1 <> 0 then begin
              incr visited
            end;
            let dirty = Char.code (Bytes.unsafe_get runtime.dirty slot) in
            Bytes.unsafe_set runtime.dirty slot
              (Char.chr (dirty land (lnot dirty_paint) land 0xff))
          end
        end
      done;
      runtime.paint_queue.queued_length <- 0;
      runtime.phase <- 0;
      !visited
    let run_passes runtime =
      if runtime.dead then invalid_arg "Pxui.Runtime.run_passes: destroyed runtime"
      else if not runtime.visible then ()
      else begin
        runtime.reconcile_visits <- runtime.reconcile_visits
          + drain runtime 1 runtime.reconcile_queue dirty_structure;
        runtime.style_visits <- runtime.style_visits
          + drain runtime 2 runtime.style_queue dirty_structure;
        let visited = commit_layout runtime in
        runtime.layout_visits <- runtime.layout_visits + visited;
        runtime.prepaint_visits <- runtime.prepaint_visits + visited;
        runtime.text_visits <- runtime.text_visits
          + drain runtime 5 runtime.text_queue dirty_text;
        runtime.paint_visits <- runtime.paint_visits
          + drain_paint runtime;
        runtime.compose_visits <- runtime.compose_visits
          + drain runtime 7 runtime.compose_queue dirty_compose;
        runtime.accessibility_visits <- runtime.accessibility_visits
          + drain runtime 8 runtime.accessibility_queue dirty_accessibility
      end
    let pending runtime =
      runtime.reconcile_queue.queued_length,
      runtime.layout_queue.queued_length,
      runtime.prepaint_queue.queued_length,
      runtime.text_queue.queued_length,
      runtime.paint_queue.queued_length,
      runtime.compose_queue.queued_length
    let stats runtime =
      { live = Stable_store.length runtime.slots;
        capacity = Stable_store.capacity runtime.slots;
        created = runtime.created; removed = runtime.removed;
        mutations = runtime.mutations;
        structure_generation = runtime.structure_generation;
        layout_generation = runtime.layout_generation;
        paint_generation = runtime.paint_generation;
        reconcile_visits = runtime.reconcile_visits;
        style_visits = runtime.style_visits;
        layout_visits = runtime.layout_visits;
        prepaint_visits = runtime.prepaint_visits;
        text_visits = runtime.text_visits;
        paint_visits = runtime.paint_visits;
        compose_visits = runtime.compose_visits;
        accessibility_visits = runtime.accessibility_visits;
        display_list_builds = runtime.display_list_builds;
        display_list_reuses = runtime.display_list_reuses;
        display_list_evictions = runtime.display_list_evictions;
        display_list_entries = runtime.paint_cache_count;
        display_list_bytes = runtime.paint_cache_bytes }
    let destroy runtime =
      if not runtime.dead then begin
        for index = 0 to runtime.order_length - 1 do
          let id = Array.unsafe_get runtime.order index in
          clear_runtime_paint_slot runtime (Stable_store.slot id);
          ignore (Stable_store.remove runtime.slots id)
        done;
        runtime.order_length <- 0;
        runtime.visible_length <- 0;
        runtime.names <- Hashtbl.create 0;
        runtime.spec_widgets <- [||];
        Array.fill runtime.labels 0 (Array.length runtime.labels) None;
        Array.fill runtime.text_values 0 (Array.length runtime.text_values) None;
        runtime.panel_node <- None;
        runtime.scrollbar_node <- None;
        runtime.composed_scene <- None;
        Scene_command.Display_list.Builder.reset runtime.panel_builder;
        Scene_command.Display_list.Builder.reset runtime.scrollbar_builder;
        clear_dirty runtime;
        runtime.focus_id <- None;
        runtime.active_id <- None;
        runtime.dead <- true
      end
    let destroyed runtime = runtime.dead
  end
end

module Spec = struct
  type nonrec t = t
  let of_canvas value = value
end

module Runtime = Private.Runtime
