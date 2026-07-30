type change =
  | Clicked of string
  | Toggled of string * bool
  | Slid of string * float
  | Text_changed of string * string
  | Selected of string * string
  | Ranged of string * float * float
  | Moved2 of string * float * float

type widget =
  | Label of string
  | Button of { name : string; label : string }
  | Toggle of { name : string; label : string; value : bool }
  | Slider of {
      name : string;
      label : string;
      min : float;
      max : float;
      value : float;
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

type t = {
  x : int;
  y : int;
  width : int;
  row_height : int;
  padding : int;
  theme : theme;
  font : Prismel.Font.t option;
  font_size : int;
  mutable widgets : widget list;
  mutable focus : string option;
  mutable composition : string;
  mutable pointer : (int * int) option;
  mutable hover : int option;
  mutable active : active option;
}

let create ?(x = 12) ?(y = 12) ?(width = 280) ?(row_height = 32)
    ?(padding = 8) ?(theme = default_theme) ?font ?(font_size = 13) () =
  if row_height < 28 then invalid_arg "Pxui.create: row_height must be at least 28";
  if padding < 0 then invalid_arg "Pxui.create: padding must be non-negative";
  if font_size <= 0 then invalid_arg "Pxui.create: font_size must be positive";
  let width = Stdlib.max 180 width in
  if width - (2 * padding) < 64 then
    invalid_arg "Pxui.create: padding leaves too little control width";
  {
    x;
    y;
    width;
    row_height;
    padding;
    theme;
    font;
    font_size;
    widgets = [];
    focus = None;
    composition = "";
    pointer = None;
    hover = None;
    active = None;
  }

let append canvas widget =
  canvas.widgets <- canvas.widgets @ [widget]

let with_widget canvas widget =
  { canvas with widgets = canvas.widgets @ [widget] }

let label ~text canvas = with_widget canvas (Label text)
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
  if max <= min then invalid_arg "Pxui.add_slider: max must be greater than min";
  append canvas (Slider { name; label; min; max; value = clamp min max value })

let slider ~name ~label ~min ~max ~value canvas =
  if max <= min then invalid_arg "Pxui.slider: max must be greater than min";
  with_widget canvas
    (Slider { name; label; min; max; value = clamp min max value })

type bounds = { x : int; y : int; w : int; h : int }

type layout = {
  index : int;
  row : bounds;
  control : bounds;
}

let row_y (canvas : t) index =
  canvas.y + canvas.padding + (index * canvas.row_height)

let contains bounds (x, y) =
  x >= bounds.x && x < bounds.x + bounds.w
  && y >= bounds.y && y < bounds.y + bounds.h

let layout (canvas : t) index widget =
  let inner_x = canvas.x + canvas.padding in
  let inner_width = Stdlib.max 1 (canvas.width - (2 * canvas.padding)) in
  let y = row_y canvas index in
  let row = { x = inner_x; y; w = inner_width; h = canvas.row_height } in
  let desired_label_width = min 96 (max 72 (inner_width / 3)) in
  let label_width = min desired_label_width (inner_width / 2) in
  let value_x = inner_x + label_width in
  let value_width = Stdlib.max 1 (inner_width - label_width) in
  let control =
    match widget with
    | Label _ -> row
    | Button _ ->
        { x = inner_x; y = y + 3; w = inner_width;
          h = Stdlib.max 1 (canvas.row_height - 6) }
    | Toggle _ ->
        let toggle_width = min 40 inner_width in
        { x = inner_x + inner_width - toggle_width;
          y = y + 7; w = toggle_width; h = 18 }
    | Slider _ | Text_field _ | Choice _ | Range _ | Xy _ ->
        { x = value_x; y = y + 3; w = value_width;
          h = Stdlib.max 1 (canvas.row_height - 6) }
  in
  { index; row; control }

let layouts (canvas : t) =
  List.mapi (fun index widget -> layout canvas index widget) canvas.widgets

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
          ~fill:(Color.with_alpha theme.accent (if pressed then 220 else 175)) ();
        line ~from_:(marker, layout.control.y + 2)
          ~to_:(marker, layout.control.y + layout.control.h - 2)
          ~color:theme.foreground ~width:2 ();
        text_node canvas ~size:11
          (layout.control.x + 6) (layout.control.y + 6)
          (compact_float value);
      ]
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

let scene (canvas : t) =
  let height =
    (List.length canvas.widgets * canvas.row_height) + (2 * canvas.padding)
  in
  let open Prismel in
  let border = Color.with_alpha canvas.theme.foreground 34 in
  let glow = Color.with_alpha canvas.theme.accent 56 in
  Scene.[
    rounded_rect ~at:(canvas.x + 4, canvas.y + 5)
      ~w:canvas.width ~h:height ~radius:8
      ~fill:(Color.rgba 0 0 0 105) ();
    rounded_rect ~at:(canvas.x, canvas.y)
      ~w:canvas.width ~h:height ~radius:8
      ~fill:canvas.theme.panel ~stroke:border ();
    line ~from_:(canvas.x + 12, canvas.y + 1)
      ~to_:(canvas.x + canvas.width - 12, canvas.y + 1)
      ~color:glow ();
  ]
  @ List.concat
      (List.map2 (widget_scene canvas) (layouts canvas) canvas.widgets)

let draw canvas = Prismel.Scene.render (scene canvas)

let hit_index (canvas : t) point =
  List.find_map
    (fun layout ->
      match List.nth_opt canvas.widgets layout.index with
      | Some (Label _) | None -> None
      | Some _ when contains layout.control point -> Some layout.index
      | Some _ -> None)
    (layouts canvas)

let layout_at (canvas : t) index =
  match List.nth_opt (layouts canvas) index with
  | Some layout -> layout
  | None -> invalid_arg "PXUI widget index outside layout"

let update_at index transform widgets =
  List.mapi (fun current widget ->
    if current = index then transform widget else widget) widgets

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
        | widget -> widget)
      canvas.widgets
  in
  { canvas with widgets }, Option.to_list !change

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
      canvas.widgets
  in
  { canvas with widgets }, Option.to_list !change

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
      canvas.widgets
  in
  { canvas with widgets }, Option.to_list !change

let focused_text_field canvas x y =
  List.find_map
    (fun (layout, widget) ->
      match widget with
      | Text_field field when contains layout.control (x, y) ->
          Some field.name
      | _ -> None)
    (List.combine (layouts canvas) canvas.widgets)

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
      { canvas with widgets }, Option.to_list !change

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
  match List.nth_opt canvas.widgets index with
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

let press canvas (x, y) =
  let index = hit_index canvas (x, y) in
  let base = {
    canvas with
    pointer = Some (x, y);
    hover = index;
    focus = focused_text_field canvas x y;
    composition = "";
    active = None;
  } in
  match index with
  | None -> base, []
  | Some index ->
      (match List.nth_opt canvas.widgets index with
       | Some (Button _ | Toggle _ | Choice _) ->
           { base with active = Some (Armed index) }, []
       | Some (Slider _) ->
           let base = { base with active = Some (Drag_slider index) } in
           slider_at base index x
       | Some (Range _) ->
           let handle = range_handle_at canvas index x in
           let base = { base with active = Some (Drag_range (index, handle)) } in
           range_at base index handle x
       | Some (Xy _) ->
           let base = { base with active = Some (Drag_xy index) } in
           xy_at base index x y
       | Some (Text_field _ | Label _) | None -> base, [])

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
        canvas.widgets
    in
    { canvas with widgets }, Option.to_list !change

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

let update_one canvas event =
  match event with
  | Prismel.Event.MousePressed (Prismel.Input.LeftButton, (x, y)) ->
      press canvas (x, y)
  | Prismel.Event.MouseMoved (x, y) ->
      move canvas (x, y)
  | Prismel.Event.MouseReleased (Prismel.Input.LeftButton, (x, y)) ->
      release canvas (x, y)
  | Prismel.Event.TextInput text ->
      let canvas, changes = map_focused canvas (fun value -> value ^ text) in
      { canvas with composition = "" }, changes
  | Prismel.Event.TextEditing { text; _ } ->
      { canvas with composition = text }, []
  | Prismel.Event.KeyPressed Prismel.Input.Backspace ->
      map_focused canvas drop_last_utf8
  | Prismel.Event.WindowFocusLost ->
      { canvas with
        active = None;
        hover = None;
        focus = None;
        composition = "";
      }, []
  | _ -> canvas, []

let update canvas events =
  List.fold_left
    (fun (canvas, changes) event ->
      let canvas, next = update_one canvas event in
      canvas, changes @ next)
    (canvas, []) events

let handle_event canvas = function
  | event ->
      let updated, changes = update_one canvas event in
      canvas.widgets <- updated.widgets;
      canvas.focus <- updated.focus;
      canvas.composition <- updated.composition;
      canvas.pointer <- updated.pointer;
      canvas.hover <- updated.hover;
      canvas.active <- updated.active;
      changes

let find_map name extract canvas =
  List.find_map (extract name) canvas.widgets

let toggle_value canvas name =
  find_map name
    (fun expected -> function
      | Toggle toggle when toggle.name = expected -> Some toggle.value
      | _ -> None)
    canvas

let slider_value canvas name =
  find_map name
    (fun expected -> function
      | Slider slider when slider.name = expected -> Some slider.value
      | _ -> None)
    canvas

let text_value canvas name =
  find_map name
    (fun expected -> function
      | Text_field field when field.name = expected -> Some field.value
      | _ -> None)
    canvas

let choice_value canvas name =
  find_map name
    (fun expected -> function
      | Choice choice when choice.name = expected ->
          Some choice.options.(choice.selected)
      | _ -> None)
    canvas

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
    | Toggle { name; value; _ } ->
        Some (Printf.sprintf "B\t%s\t%d" (hex_of_string name)
          (if value then 1 else 0))
    | Slider { name; value; _ } ->
        Some (Printf.sprintf "F\t%s\t%.17g" (hex_of_string name) value)
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
    | Label _ | Button _ -> None
  in
  "PXUI1\n"
  ^ String.concat "\n" (List.filter_map line canvas.widgets)
  ^ "\n"

type saved =
  | Saved_bool of bool
  | Saved_float of float
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
                        | "B" when raw = "0" -> Ok (Saved_bool false)
                        | "B" when raw = "1" -> Ok (Saved_bool true)
                        | "F" ->
                            (try Ok (Saved_float (float_of_string raw))
                             with Failure _ -> error "invalid float")
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
              | Toggle toggle ->
                  (match Hashtbl.find_opt values toggle.name with
                   | None -> widget
                   | Some (Saved_bool value) -> Toggle { toggle with value }
                   | Some _ -> mismatch toggle.name)
              | Slider slider ->
                  (match Hashtbl.find_opt values slider.name with
                   | None -> widget
                   | Some (Saved_float value) ->
                       Slider { slider with
                         value = clamp slider.min slider.max value;
                       }
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
              | Label _ | Button _ -> widget)
            canvas.widgets
        in
        match !error with
        | Some message -> Error message
        | None -> Ok { canvas with widgets; composition = "" })
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
