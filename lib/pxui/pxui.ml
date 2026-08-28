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
  canvas.ordered_cache <- None

let with_widget canvas widget =
  { canvas with
    widget_count = canvas.widget_count + 1;
    widgets = widget :: canvas.widgets;
    ordered_cache = None;
  }

let ordered_widget_array canvas =
  match canvas.ordered_cache with
  | Some widgets -> widgets
  | None ->
      let widgets = Array.of_list (List.rev canvas.widgets) in
      canvas.ordered_cache <- Some widgets;
      widgets

let ordered_widgets canvas = Array.to_list (ordered_widget_array canvas)

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

let displayed_widgets canvas =
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

let content_height canvas =
  (Array.length (displayed_widgets canvas) * canvas.row_height)
  + (2 * canvas.padding)

let panel_height canvas =
  let height = content_height canvas in
  let height = Option.fold ~none:height ~some:(min height) canvas.max_height in
  Option.fold ~none:height ~some:(min height) canvas.frame_max_height

let max_scroll canvas = max 0 (content_height canvas - panel_height canvas)

let clamp_scroll canvas =
  let scroll_y = clamp 0 (max_scroll canvas) canvas.scroll_y in
  if scroll_y = canvas.scroll_y then canvas else { canvas with scroll_y }

let scrollable canvas = max_scroll canvas > 0

let row_y (canvas : t) index =
  canvas.y + canvas.padding + (index * canvas.row_height) - canvas.scroll_y

let contains bounds (x, y) =
  x >= bounds.x && x < bounds.x + bounds.w
  && y >= bounds.y && y < bounds.y + bounds.h

let layout (canvas : t) displayed =
  let index = displayed.source_index and widget = displayed.widget in
  let inner_x = canvas.x + canvas.padding in
  let scrollbar_gutter = if scrollable canvas then 10 else 0 in
  let inner_width = Stdlib.max 1
      (canvas.width - (2 * canvas.padding) - scrollbar_gutter) in
  let y = row_y canvas displayed.row_index in
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

let position bounds fraction =
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
  let canvas = clamp_scroll { canvas with widgets; ordered_cache = None } in
  match canvas.numeric_edit with
  | Some edit when not (Array.exists
      (fun displayed -> displayed.source_index = edit.index)
      (displayed_widgets canvas)) ->
      { canvas with numeric_edit = None; composition = "" }
  | Some _ | None -> canvas

let update_at index transform count widgets =
  let stored_index = count - index - 1 in
  List.mapi (fun current widget ->
    if current = stored_index then transform widget else widget) widgets

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
      clamp_scroll { canvas with scroll_y; active = None }, []
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
  let widgets = ordered_widget_array canvas in
  let index = ref 0 and result = ref None in
  while !index < Array.length widgets && Option.is_none !result do
    result := extract name widgets.(!index);
    incr index
  done;
  !result

let toggle_value canvas name =
  find_map name
    (fun expected -> function
      | Toggle toggle when toggle.name = expected -> Some toggle.value
      | _ -> None)
    canvas

let set_toggle_value canvas name value =
  let widgets = List.map (function
    | Toggle toggle when toggle.name = name -> Toggle { toggle with value }
    | widget -> widget) canvas.widgets in
  { canvas with widgets; ordered_cache = None }

let slider_value canvas name =
  find_map name
    (fun expected -> function
      | Slider slider when slider.name = expected -> Some slider.value
      | _ -> None)
    canvas

let set_slider_value canvas name value =
  if not (Float.is_finite value) then
    invalid_arg "Pxui.set_slider_value: value must be finite";
  let widgets = List.map (function
    | Slider slider when slider.name = name ->
        Slider { slider with value }
    | widget -> widget) canvas.widgets in
  { canvas with widgets; ordered_cache = None }

let int_slider_value canvas name =
  find_map name
    (fun expected -> function
      | Int_slider slider when slider.name = expected -> Some slider.value
      | _ -> None)
    canvas

let set_int_slider_value canvas name value =
  let widgets = List.map (function
    | Int_slider slider when slider.name = name ->
        Int_slider { slider with value }
    | widget -> widget) canvas.widgets in
  { canvas with widgets; ordered_cache = None }

let text_value canvas name =
  find_map name
    (fun expected -> function
      | Text_field field when field.name = expected -> Some field.value
      | _ -> None)
    canvas

let set_text_value canvas name value =
  let widgets = List.map (function
    | Text_field field when field.name = name -> Text_field { field with value }
    | widget -> widget) canvas.widgets in
  { canvas with widgets; ordered_cache = None }

let choice_value canvas name =
  find_map name
    (fun expected -> function
      | Choice choice when choice.name = expected ->
          Some choice.options.(choice.selected)
      | _ -> None)
    canvas

let set_choice_value canvas name value =
  let widgets = List.map (function
    | Choice choice when choice.name = name ->
        (match Array.find_index (( = ) value) choice.options with
         | Some selected -> Choice { choice with selected }
         | None -> invalid_arg (Printf.sprintf
             "Pxui.set_choice_value: %S is not an option for %S" value name))
    | widget -> widget) canvas.widgets in
  { canvas with widgets; ordered_cache = None }

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
  let widgets = List.map (function
    | Accordion accordion when accordion.name = name ->
        Accordion { accordion with expanded }
    | widget -> widget) canvas.widgets in
  replace_widgets { canvas with active = None } widgets

let with_position ~x ~y (canvas : t) =
  if x = canvas.x && y = canvas.y then canvas
  else { canvas with x; y; active = None; hover = None }

let with_width width (canvas : t) =
  if width <= 0 then invalid_arg "Pxui.with_width: width must be positive";
  if width = canvas.width then canvas
  else { canvas with width; active = None; hover = None }

let with_max_height max_height (canvas : t) =
  Option.iter (fun height ->
    if height < canvas.row_height + (2 * canvas.padding) then
      invalid_arg "Pxui.with_max_height: height is too small for one row")
    max_height;
  if max_height = canvas.max_height then canvas
  else clamp_scroll { canvas with max_height; active = None; hover = None }

let with_frame_max_height frame_max_height (canvas : t) =
  Option.iter (fun height ->
    if height < canvas.row_height + (2 * canvas.padding) then
      invalid_arg "Pxui: frame height is too small for one row")
    frame_max_height;
  if frame_max_height = canvas.frame_max_height then canvas
  else
    let previous_height = panel_height canvas in
    let updated = clamp_scroll { canvas with frame_max_height } in
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
    let ui = set_slider_value ui (name control "fov")
        (Prismel.Easy_camera.fov_y camera *. 180. /. Float.pi) in
    let ui = set_slider_value ui (name control "distance")
        (Prismel.Easy_camera.distance camera) in
    let ui = set_slider_value ui (name control "near")
        (Prismel.Easy_camera.near camera) in
    let ui = set_slider_value ui (name control "far")
        (Prismel.Easy_camera.far camera) in
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
    let center = Prismel.Easy_camera2.center camera in
    let ui = set_slider_value ui (name control "center-x") center.x
      |> fun ui -> set_slider_value ui (name control "center-y") center.y
      |> fun ui -> set_slider_value ui (name control "zoom")
           (Prismel.Easy_camera2.zoom camera)
      |> fun ui -> set_slider_value ui (name control "rotation")
           (Prismel.Easy_camera2.rotation camera *. 180. /. Float.pi) in
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
            canvas with widgets; ordered_cache = None; composition = "";
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
