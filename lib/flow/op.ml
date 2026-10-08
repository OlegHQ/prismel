open Value
type signature = {
  pos : (string * Ty.t) list; opt : (string * Ty.t) list;
  rest : (string * Ty.t) option; kw : (string * Ty.t) list;
}
type shape = Scalar | Struct of { splice : bool }
type arithmetic = { apply : 'f 'r. ('f, 'r) Value.t -> ('f, 'r) Value.t -> ('f, 'r) Value.t }
type t = {
  name : string; ctx : Context.t; signature : signature;
  out : Ty.t list -> Ty.t; any_num : bool;
  choices : (string * string list) list; shape : shape;
  live : bool;
  check : 'f 'r. (string * ('f, 'r) Value.t) list -> unit;
  body : 'f 'r. live:Frame_input.t -> node:(string -> (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t) ->
    (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t;
  category : string; arithmetic : arithmetic option;
}
type implementation = { run : 'f 'r. name:string -> node:(string -> (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t) ->
  (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t }
type validation = { validate : 'f 'r. (string * string list) list -> (string * ('f, 'r) Value.t) list -> unit }
let max_iterations = 4096
let mk ?(ctx = Context.value) ?(opt = []) ?rest ?(kw = []) ?(any_num = false)
    ?(choices = []) ?(shape = Scalar) ?(check = { validate = fun _ _ -> () })
    ?(category = "Math") ?arithmetic name pos out (body : implementation) =
  { name; ctx; signature = {pos; opt; rest; kw}; out; any_num; choices; shape; live = false;
    check = (fun args -> check.validate choices args);
    body = (fun ~live:_ ~node args -> body.run ~name ~node args); category; arithmetic }
let fl = Ty.Float
let lst j ts = match List.nth_opt ts j with Some (Ty.List _ as t) -> t | _ -> Ty.List Ty.Any
let elm j ts = match lst j ts with Ty.List e -> e | _ -> Ty.Any
let binary name f =
  let arithmetic = { apply = fun a b -> Value.arith name f a b } in
  mk ~any_num:true ~arithmetic name ["a", fl; "b", fl] (fun ts ->
    match List.find_opt (fun ty -> List.mem ty [Ty.Vec2;Ty.Vec3;Ty.Vec4]) ts with
    | Some ty -> ty
    | None -> if name <> "/" && name <> "pow" && List.for_all ((=) Ty.Int) ts then Ty.Int else fl)
    {run = fun ~name ~node:_ args -> match List.map snd args with
      | [a;b] -> arithmetic.apply a b
      | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name}
let unary ~category name out = mk ~category name ["x", fl] out
let compare_op ~category name = mk ~category name ["a", fl; "b", fl] (fun _ -> Ty.Bool)
let bool_op ~category name pos = mk ~category name pos (fun _ -> Ty.Bool)
let concrete f = function Residual _ -> () | v -> f v
let range_error msg = fail "E_RANGE" msg
let axis choices args = match List.assoc_opt "axis" args with
  | Some v -> concrete (function Text t when List.mem t (List.assoc "axis" choices) -> ()
      | _ -> range_error "Split axis is horizontal or vertical.") v
  | None -> ()
let one_of args key what choices = match List.assoc_opt key args with
  | Some v -> concrete (function Text t when List.mem t choices -> ()
      | _ -> range_error (Printf.sprintf "%s is %s." what (String.concat ", " choices))) v
  | None -> ()
let split_check choices args =
  axis choices args;
  let points key = match List.assoc_opt key args with
    | Some v -> concrete (fun v -> if num v < 1. then range_error "A fixed split size is 1 point or more.") v
    | None -> () in
  points "first_size"; points "second_size";
  if List.mem_assoc "first_size" args && List.mem_assoc "second_size" args then
    range_error "A split fixes one side: :first_size or :second_size."
let split_at_check choices args =
  axis choices args;
  match List.assoc_opt "ratio" args with
  | Some v -> concrete (fun v -> let r = num v in
      if r < 0.1 || r > 0.9 then range_error "Split ratio is 0.1–0.9.") v
  | None -> ()
let tile_check args =
  let n = List.length args in
  if n < 1 || n > 16 then range_error "A tile holds 1–16 panels."
let switch_check args =
  let n = List.length (List.filter (fun (k, _) -> k <> "active") args) in
  if n < 1 || n > 16 then range_error "A switch holds 1–16 layouts.";
  match List.assoc_opt "active" args with
  | Some v -> concrete (fun v -> let a = num v in
      if a < 0. || a >= float n then range_error "The active layout is 0 to the layout count minus one.") v
  | None -> ()
let structure ?(ctx = Context.editor) ?opt ?rest ?kw ?choices ?check ?(splice = false) name pos out =
  (* Deferred SOP element lists have no cooked element type during evaluation. *)
  let ty = if ctx = Context.sop then Ty.List Ty.Any else out [] in
  mk ~ctx ?opt ?rest ?kw ?choices ?check ~shape:(Struct {splice}) name pos out
    {run = fun ~name ~node:_ args -> Value.Struct (name, ty, args)}
let panel ?opt ?rest ?kw ?choices ?check ?splice name pos =
  structure ?opt ?rest ?kw ?choices ?check ?splice name pos (fun _ -> Ty.panel)
let leaf ?opt ?(kw = []) ?choices ?check name pos =
  panel ?opt ~kw:(kw @ ["focus", Ty.Bool]) ?choices ?check name pos
let hsv h s v =
  let h = Float.rem (Float.rem h 1. +. 1.) 1. in
  let i = int_of_float (Float.floor (h *. 6.)) in
  let f = h *. 6. -. float_of_int i in
  let p = v *. (1. -. s) and q = v *. (1. -. f *. s) and t = v *. (1. -. (1. -. f) *. s) in
  match i mod 6 with
  | 0 -> (v, t, p) | 1 -> (q, v, p) | 2 -> (p, v, t) | 3 -> (p, q, v) | 4 -> (t, p, v)
  | _ -> (v, p, q)

let range lo hi =
  if hi - lo > max_iterations then
    failf "E_ITER_BOUND" "range %d‥%d exceeds 4,096 iterations." lo hi;
  List (Array.init (max 0 (hi - lo)) (fun i -> Int (lo + i)))

type frame_read = { read : 'f 'r. Frame_input.t -> (string * ('f, 'r) Value.t) list -> ('f, 'r) Value.t }
let frame_op ?opt name pos out read =
  let o = mk ?opt ~category:"Frame" name pos (fun _ -> out)
    {run = fun ~name:_ ~node:_ args -> read.read (Frame_input.at_time 0.) args} in
  {o with live = true; body = (fun ~live ~node:_ args -> read.read live args)}

let event_fields = ["kind", Ty.Text; "key", Ty.Text; "button", Ty.Text;
  "position", Ty.Vec3; "delta", Ty.Vec3; "text", Ty.Text; "start", Ty.Int;
  "length", Ty.Int; "paths", Ty.List Ty.Text; "error", Ty.Text; "id", Ty.Int;
  "width", Ty.Int; "height", Ty.Int; "phase", Ty.Text; "time", Ty.Float; "scale", Ty.Float]
let frame_ty = Ty.Record ["t", fl; "dt", fl; "index", Ty.Int;
  "width", Ty.Int; "height", Ty.Int; "pointer", Ty.Vec3;
  "buttons", Ty.List Ty.Text; "keys", Ty.List Ty.Text; "events", Ty.List (Ty.Record event_fields)]
let text_list xs = List (Array.of_list (List.map (fun s -> Text s) xs))
let event_value event =
  let point (x, y) = Vec3 (x, y, 0.) in
  let kind, fields = match event with
    | Frame_input.Key_pressed key -> "key-pressed", ["key", Text key]
    | Key_released key -> "key-released", ["key", Text key]
    | Pointer_moved (x, y) -> "pointer-moved", ["position", point (x, y)]
    | Pointer_pressed (b, p) -> "pointer-pressed", ["button", Text b; "position", point p]
    | Pointer_released (b, p) -> "pointer-released", ["button", Text b; "position", point p]
    | Pointer_cancelled b -> "pointer-cancelled", ["button", Text b]
    | Scrolled (x, y) -> "scrolled", ["delta", point (x, y)]
    | Text_input s -> "text-input", ["text", Text s]
    | Text_editing {text; start; length} -> "text-editing", ["text", Text text; "start", Int start; "length", Int length]
    | File_dropped s -> "file-dropped", ["text", Text s]
    | File_drag_moved (x, y) -> "file-drag-moved", ["position", point (x, y)]
    | File_drag_ended -> "file-drag-ended", []
    | Pinched x -> "pinched", ["scale", Float x]
    | File_dialog {id; result} -> "file-dialog", ("id", Int id) ::
        (match result with Ok xs -> ["paths", text_list xs] | Error s -> ["error", Text s])
    | Dialog_opened id -> "dialog-opened", ["id",Int id]
    | Resized (w, h) -> "resized", ["width", Int w; "height", Int h]
    | Focus_lost -> "focus-lost", [] | Closed -> "closed", []
    | Trackpad_scrolled {delta; phase; time} -> "trackpad-scrolled", ["delta", point delta; "phase", Text phase; "time", Float time] in
  Record (List.map (fun (name, ty) -> name, if name = "kind" then Text kind else
    match List.assoc_opt name fields with Some v -> v | None ->
      match ty with Ty.Int -> Int 0 | Float -> Float 0. | Vec3 -> Vec3 (0., 0., 0.)
      | List _ -> List [||] | _ -> Text "") event_fields)

let frame_value (f : Frame_input.t) = Record ["t", Float f.t; "dt", Float f.dt;
  "index", Int f.frame; "width", Int (fst f.size); "height", Int (snd f.size);
  "pointer", Vec3 (fst f.pointer, snd f.pointer, 0.); "buttons", text_list f.buttons;
  "keys", text_list f.keys; "events", List (Array.of_list (List.map event_value f.events))]

let frame = [
  frame_op "frame/input" [] frame_ty {read = fun f _ -> frame_value f};
  frame_op "frame/dt" [] fl {read = fun f _ -> Float f.dt};
  frame_op "frame/index" [] Ty.Int {read = fun f _ -> Int f.frame};
  frame_op "frame/width" [] Ty.Int {read = fun f _ -> Int (fst f.size)};
  frame_op "frame/height" [] Ty.Int {read = fun f _ -> Int (snd f.size)};
  frame_op "pointer/x" [] fl {read = fun f _ -> Float (fst f.pointer)};
  frame_op "pointer/y" [] fl {read = fun f _ -> Float (snd f.pointer)};
  frame_op ~opt:["button", Ty.Text] "pointer/down" [] Ty.Bool {read = fun f args ->
    match args with [] -> Bool (List.mem "left" f.buttons)
    | [_, Text button] ->
        if not (List.mem button ["left"; "right"; "middle"; "x1"; "x2"]) then
          fail "E_RANGE" "Pointer button is left, right, middle, x1 or x2.";
        Bool (List.mem button f.buttons)
    | _ -> fail "E_TYPE" "pointer/down takes a button name."};
  frame_op "key/down" ["key", Ty.Text] Ty.Bool {read = fun f args ->
    match args with [_, Text key] -> Bool (List.mem key f.keys)
    | _ -> fail "E_TYPE" "key/down takes a key name."};
]

let array_count name v =
  let n = num v in
  if n < 0. || n <> Float.floor n || n > float Sys.max_floatarray_length then
    failf "E_ARRAY_RANGE" "%s needs a non-negative whole length." name;
  int_of_float n
let arrays = [
  mk ~category:"Array" "array/range" ["count", Ty.Int] (fun _ -> Ty.Array fl)
    {run = fun ~name ~node:_ args ->
      array_init fl (array_count name (List.assoc "count" args)) (fun i -> Float (float i))};
  mk ~category:"Array" ~opt:["value", fl] "array/float" ["count", Ty.Int] (fun _ -> Ty.Array fl)
    {run = fun ~name ~node:_ args ->
      let value = Option.value ~default:(Float 0.) (List.assoc_opt "value" args) in
      array_init fl (array_count name (List.assoc "count" args)) (fun _ -> value)};
  mk ~category:"Array" ~opt:["value", Ty.Vec3] "array/vec3" ["count", Ty.Int] (fun _ -> Ty.Array Ty.Vec3)
    {run = fun ~name ~node:_ args ->
      let value = Option.value ~default:(Vec3 (0., 0., 0.)) (List.assoc_opt "value" args) in
      array_init Ty.Vec3 (array_count name (List.assoc "count" args)) (fun _ -> value)};
  mk ~category:"Array" "array/count" ["array", Ty.Array Ty.Any] (fun _ -> Ty.Int)
    {run = fun ~name:_ ~node:_ args -> Int (array_length (List.assoc "array" args))};
  mk ~category:"Array" "array/nth" ["array", Ty.Array Ty.Any; "index", Ty.Int]
    (function Ty.Array e :: _ -> e | _ -> Ty.Any)
    {run = fun ~name ~node:_ args -> array_get (List.assoc "array" args)
      (array_count name (List.assoc "index" args))};
  mk ~category:"Array" "array/slice" ["array",Ty.Array Ty.Any;"first",Ty.Int;"count",Ty.Int]
    (function (Ty.Array _ as ty)::_ ->ty|_->Ty.Array Ty.Any)
    {run=fun ~name ~node:_ args->
      let first=array_count name(List.assoc "first" args)and count=array_count name(List.assoc "count" args)in
      let slice width values=if first>Array.length values/width || count>Array.length values/width-first
        then fail "E_ARRAY_RANGE" "An array slice must be within its source.";
        Array.sub values (first*width)(count*width)in
      match List.assoc "array" args with Float_array xs->Float_array(slice 1 xs)
        |Vec2_array xs->Vec2_array(slice 2 xs)
        |Vec3_array xs->Vec3_array(slice 3 xs)|Vec4_array xs->Vec4_array(slice 4 xs)
        |_->fail "E_TYPE" "Expected a packed array."};
  mk ~category:"Array" "array/concat" ["first",Ty.Array Ty.Any;"second",Ty.Array Ty.Any]
    (function (Ty.Array _ as ty)::_ ->ty|_->Ty.Array Ty.Any)
    {run=fun ~name:_ ~node:_ args->match List.assoc "first" args,List.assoc "second" args with
      |Float_array a,Float_array b->Float_array(Array.append a b)
      |Vec2_array a,Vec2_array b->Vec2_array(Array.append a b)
      |Vec3_array a,Vec3_array b->Vec3_array(Array.append a b)
      |Vec4_array a,Vec4_array b->Vec4_array(Array.append a b)
      |_->fail "E_ARRAY_TYPE" "Concatenated arrays must have the same element type."};
  mk ~category:"Array" "array/sum" ["array", Ty.Array Ty.Any]
    (function Ty.Array e :: _ -> e | _ -> Ty.Any)
    {run = fun ~name:_ ~node:_ args ->
      let xs = List.assoc "array" args in
      let sum = ref (match xs with Vec2_array _ -> Vec2 (0., 0.)
        | Vec3_array _ -> Vec3 (0., 0., 0.) | Vec4_array _ -> Vec4 (0., 0., 0., 0.) | _ -> Float 0.) in
      for i = 0 to array_length xs - 1 do sum := Value.arith "array/sum" ( +. ) !sum (array_get xs i) done;
      !sum};
]

let is_display_kind name = String.starts_with ~prefix:"draw/" name
  || String.starts_with ~prefix:"ui/" name

let draw_op ?rest ?kw name pos =
  mk ~ctx:Context.draw ?rest ?kw ~category:"Drawing" name pos (fun _ -> Ty.drawing)
    {run = fun ~name ~node args -> node name args}

let draw = [
  draw_op ~kw:["at",Ty.Vec3;"scale",Ty.Float;"angle",Ty.Float] "draw/image" ["image",Ty.image];
  draw_op "draw/background" ["color", Ty.Color];
  draw_op ~kw:["color", Ty.Color] "draw/point" ["at", Ty.Vec3];
  draw_op ~kw:["color", Ty.Color] "draw/points" ["positions", Ty.Array Ty.Vec3];
  draw_op ~kw:["color", Ty.Color; "width", Ty.Int] "draw/line" ["from", Ty.Vec3; "to", Ty.Vec3];
  draw_op ~kw:["fill", Ty.Color; "stroke", Ty.Color] "draw/rect" ["at", Ty.Vec3; "size", Ty.Vec3];
  draw_op ~kw:["fill", Ty.Color; "stroke", Ty.Color] "draw/circle" ["at", Ty.Vec3; "radius", Ty.Int];
  (* Noise and generative sketches need packed RGB; stroke widths remain uniform. *)
  draw_op ~kw:["radius", Ty.Any; "fill", Ty.Any; "stroke", Ty.Any] "draw/circles" ["positions", Ty.Array Ty.Vec3];
  draw_op ~kw:["fill", Ty.Any; "stroke", Ty.Any] "draw/rects" ["positions", Ty.Array Ty.Vec3; "sizes", Ty.Any];
  draw_op ~kw:["color", Ty.Any; "width", Ty.Float] "draw/lines" ["from", Ty.Array Ty.Vec3; "to", Ty.Array Ty.Vec3];
  draw_op ~kw:["color", Ty.Color; "size", Ty.Int] "draw/text" ["at", Ty.Vec3; "text", Ty.Text];
  draw_op "draw/translate" ["offset", Ty.Vec3; "drawing", Ty.drawing];
  draw_op "draw/rotate" ["angle", Ty.Float; "drawing", Ty.drawing];
  draw_op "draw/scale" ["factor", Ty.Any; "drawing", Ty.drawing];
  draw_op ~kw:["radius", Ty.Int; "fill", Ty.Color; "stroke", Ty.Color] "draw/rounded_rect" ["at", Ty.Vec3; "size", Ty.Vec3];
  draw_op ~kw:["fill", Ty.Color; "stroke", Ty.Color] "draw/polygon" ["points", Ty.Array Ty.Vec3];
  draw_op ~kw:["color", Ty.Color] "draw/polyline" ["points", Ty.Array Ty.Vec3];
  draw_op ~rest:("drawing", Ty.Any) "draw/merge" [];
]

let host_op ?kw ?choices name pos out =
  mk ~ctx:Context.host ?kw ?choices ~category:"Host" name pos (fun _->Ty.Named out)
    {run=fun ~name ~node args->node name args}
let host = [
  host_op "host/quit" ["when",Ty.Bool] "effect";
  host_op "host/save_png" ["path",Ty.Text;"when",Ty.Bool] "effect";
  host_op ~kw:["filters",Ty.Any;"default",Ty.Text]
    ~choices:["kind",["open_file";"open_files";"save_file";"open_folder"]]
    "host/dialog" ["kind",Ty.Text;"when",Ty.Bool] "effect";
  host_op ~kw:["volume",Ty.Float;"loops",Ty.Int] "host/play"
    ["sample",Ty.Named "sample";"when",Ty.Bool] "effect";
  host_op ~kw:["waveform",Ty.Text;"frequency",Ty.Float;"duration",Ty.Float;"volume",Ty.Float]
    ~choices:["waveform",["sine";"square";"triangle";"sawtooth"]] "audio/synth" [] "sample";
  host_op "audio/load" ["path",Ty.Text] "sample";
]
let integers = List.map(fun(name,operation)->
  mk ~category:"Integer" name ["a",Ty.Int;"b",Ty.Int] (fun _->Ty.Int)
    {run=fun ~name:_ ~node:_ args->
      let integer=function Int value->value|value->int_of value in
      let a=integer(List.assoc "a" args)and b=integer(List.assoc "b" args)in
      try Int(operation a b)with Division_by_zero->fail "E_RANGE" "Integer division by zero."})
  ["int/mul",( * );"int/div",( / );"int/mod",( mod );"int/and",( land );"int/xor",( lxor )]

(* Constructor arguments remain typed values, including live fields; [node]
   creates the deferred payload instead of residualizing the whole call. *)
let images = [
  mk ~category:"Image" ~shape:(Struct {splice=false}) "image/load" ["path",Ty.Text] (fun _->Ty.image)
    {run=fun ~name ~node args->node name args};
  mk ~category:"Image" ~shape:(Struct {splice=false}) ~kw:["width",Ty.Int;"height",Ty.Int] "image/render"
    ["drawing",Ty.drawing] (fun _->Ty.image) {run=fun ~name ~node args->node name args};
  mk ~category:"Image" ~shape:(Struct {splice=false}) ~kw:["width",Ty.Int;"height",Ty.Int;"frequency",Ty.Float;"freq",Ty.Float;"seed",Ty.Int]
    "image/noise" [] (fun _->Ty.image) {run=fun ~name ~node args->node name args};
]

let all = frame @ arrays @ draw @ host @ integers @ images @ [
  mk ~category:"Vector" "length" ["vector", Ty.Vec3] (fun _ -> fl)
    {run = fun ~name ~node:_ args -> match List.assoc "vector" args with
      | Vec3 (x,y,z) ->
          (* Match the separately rounded Mul/Add instructions of packed kernels. *)
          let xx = Sys.opaque_identity (x *. x)
          and yy = Sys.opaque_identity (y *. y)
          and zz = Sys.opaque_identity (z *. z) in
          Float (fin name (sqrt ((xx +. yy) +. zz)))
      | _ -> fail "E_TYPE" "length needs a vec3."};
  mk ~category:"Compare" "equal?" ["a",Ty.Any;"b",Ty.Any] (fun _->Ty.Bool)
    {run=fun ~name:_ ~node:_ args->try Bool(List.assoc "a" args=List.assoc "b" args)
      with Invalid_argument _->fail "E_TYPE" "Functions cannot be compared."};
  unary ~category:"Math" "exp" (fun _->fl) {run=fun ~name ~node:_ args->
    Float(fin name(exp(num(List.assoc "x" args))))};
  mk ~category:"Convert" "exact" ["value", Ty.Any]
    (function ty :: _ -> ty | _ -> Ty.Any)
    {run = fun ~name:_ ~node:_ args -> List.assoc "value" args};
  binary "+" (( +. ));
  binary "-" (( -. ));
  binary "*" (( *. ));
  binary "/" ((fun x y -> if y = 0. then 0. else x /. y));
  binary "mod" ((fun x y -> if y = 0. then 0. else Float.rem (Float.rem x y +. y) y));
  binary "pow" ((fun x y -> Float.pow (Float.abs x) y));
  binary "min" (Float.min);
  binary "max" (Float.max);
  unary ~category:"Math" "sin" (fun _ -> fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Float (fin name (sin (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Math" "cos" (fun _ -> fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Float (fin name (cos (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Math" "sqrt" (fun _ -> fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Float (sqrt (Float.abs (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Convert" "floor" (fun _ -> Ty.Int) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Int (to_int name (Float.floor (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Convert" "ceil" (fun _ -> Ty.Int) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Int (to_int name (Float.ceil (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Convert" "round" (fun _ -> Ty.Int) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Int (to_int name (Float.round (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Convert" "int" (fun _ -> Ty.Int) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Int (to_int name (Float.trunc (num x)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Convert" "float" (fun _ -> fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ x ] -> Float (num x)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  unary ~category:"Math" "abs" (function Ty.Int :: _ -> Ty.Int | _ -> fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ Int n ] -> Int (abs n)
    | [ x ] -> Float (Float.abs (num x))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  compare_op ~category:"Compare" "<" { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (num a < num b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  compare_op ~category:"Compare" ">" { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (num a > num b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  compare_op ~category:"Compare" "<=" { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (num a <= num b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  compare_op ~category:"Compare" ">=" { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (num a >= num b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  compare_op ~category:"Compare" "=" { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (num a = num b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  bool_op ~category:"Compare" "and" [ "a", Ty.Bool; "b", Ty.Bool ] { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (truthy a && truthy b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  bool_op ~category:"Compare" "or" [ "a", Ty.Bool; "b", Ty.Bool ] { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b ] -> Bool (truthy a || truthy b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  bool_op ~category:"Compare" "not" [ "a", Ty.Bool ] { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a ] -> Bool (not (truthy a))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"Math" ~rest:("key", fl) "value/rand" [] (fun _ -> fl)
    { run = fun ~name:_ ~node:_ args -> Float (hash (List.map (fun (_,v) -> num v) args)) };
  mk ~category:"Math" "value/hsv" [ "h", fl; "s", fl; "v", fl ] (fun _ -> Ty.Vec3) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ h; s; v ] -> let r, g, b = hsv (num h) (num s) (num v) in Vec3 (fin name r, fin name g, fin name b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"Math" ~any_num:true "value/lerp" [ "a", fl; "b", fl; "u", fl ] (fun ts ->
    match ts with a :: b :: _ when a = Ty.Vec3 || b = Ty.Vec3 -> Ty.Vec3 | _ -> fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b; u ] -> let u = num u in
      if is_vec a || is_vec b then begin
        let ax, ay, az = comps a and bx, by, bz = comps b in
        let l x y = x *. (1. -. u) +. y *. u in
        Vec3 (fin name (l ax bx), fin name (l ay by), fin name (l az bz))
      end else Float (fin name (num a *. (1. -. u) +. num b *. u))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"Math" ~opt:[ "height", fl ] "value/polar" [ "radius", fl; "angle", fl ] (fun _ -> Ty.Vec3) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | (r :: a :: h) -> let r = num r and a = num a in
      Vec3 (fin name (r *. cos a), (match h with [ h ] -> num h | _ -> 0.), fin name (r *. sin a))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" ~opt:[ "end", Ty.Int ] "range" [ "count", Ty.Int ] (fun _ -> Ty.List Ty.Int) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ n ] -> range 0 (int_of n)
    | [ a; b ] -> range (int_of a) (int_of b)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "linspace" [ "from", fl; "to", fl; "count", Ty.Int ] (fun _ -> Ty.List fl) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ a; b; n ] -> let a = num a and b = num b and n = int_of n in
      if n > max_iterations then fail "E_ITER_BOUND" "linspace exceeds 4,096 values.";
      List (Array.init (max 0 n) (fun k ->
        Float (if n = 1 then a else a +. (b -. a) *. float_of_int k /. float_of_int (n - 1))))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "count" [ "list", Ty.List Ty.Any ] (fun _ -> Ty.Int) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ l ] -> Int (Array.length (list_arg l))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "first" [ "list", Ty.List Ty.Any ] (elm 0) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ l ] -> let xs = list_arg l in
      if xs = [||] then fail "E_LIST_RANGE" "first of an empty list." else xs.(0)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "last" [ "list", Ty.List Ty.Any ] (elm 0) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ l ] -> let xs = list_arg l in
      if xs = [||] then fail "E_LIST_RANGE" "last of an empty list." else xs.(Array.length xs - 1)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "rest" [ "list", Ty.List Ty.Any ] (lst 0) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ l ] -> let xs = list_arg l in
      List (if xs = [||] then xs else Array.sub xs 1 (Array.length xs - 1))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "nth" [ "list", Ty.List Ty.Any; "index", Ty.Int ] (elm 0) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ l; i ] -> (match i with
       | Float f when not (Float.is_integer f) -> failf "E_LIST_RANGE" "nth index %g is not a whole number." f
       | _ -> ());
      let xs = list_arg l and i = int_of i in
      if i < 0 || i >= Array.length xs then
        failf "E_LIST_RANGE" "nth index %d is out of range for a list of length %d." i (Array.length xs)
      else xs.(i)
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "reverse" [ "list", Ty.List Ty.Any ] (lst 0) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ l ] -> let xs = list_arg l in
      let n = Array.length xs in List (Array.init n (fun i -> xs.(n - 1 - i)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "take" [ "n", Ty.Int; "list", Ty.List Ty.Any ] (lst 1) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ n; l ] -> let xs = list_arg l and n = max 0 (int_of n) in List (Array.sub xs 0 (min n (Array.length xs)))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~category:"List" "drop" [ "n", Ty.Int; "list", Ty.List Ty.Any ] (lst 1) { run = fun ~name ~node:_ args ->
    match List.map snd args with
    | [ n; l ] -> let xs = list_arg l in
      let n = min (max 0 (int_of n)) (Array.length xs) in List (Array.sub xs n (Array.length xs - n))
    | _ -> failf "E_ARITY" "%s got the wrong number of inputs." name };
  mk ~ctx:Context.sop ~kw:[ "closed", Ty.Bool ] "sop/curve" [ "points", Ty.List Ty.Vec3 ] (fun _ -> Ty.geometry) { run = fun ~name ~node args -> node name args };
  structure ~ctx:Context.sop ~kw:[ "key", Ty.Text ] "sop/point_list" [ "geometry", Ty.geometry ] (fun _ -> Ty.List Ty.Vec3);
  structure ~ctx:Context.sop ~kw:[ "key", Ty.Text ] "sop/piece_list" [ "geometry", Ty.geometry ] (fun _ -> Ty.List Ty.geometry);
  structure ~splice:true ~ctx:Context.scene ~rest:("scene", Ty.scene) "scene/merge" [] (fun _ -> Ty.scene);
  structure ~ctx:Context.material ~kw:["name", Ty.Text; "color", Ty.Color;
    "roughness", Ty.Float; "emission", Ty.Color] "material/standard" [] (fun _ -> Ty.material);
  structure ~ctx:Context.world "world/none" [] (fun _ -> Ty.world);
  structure ~ctx:Context.editor ~kw:["effects",Ty.Any] "ui/workspace" [ "root", Ty.panel ] (fun _ -> Ty.editor);
  leaf ~kw:[ "look_through", Ty.Bool ] "ui/viewport" [ "scene", Ty.scene ];
  leaf "ui/canvas" ["drawing", Ty.drawing];
  leaf ~choices:["wires", ["rect"; "straight"]; "view", ["graph"; "list"; "text"]]
    ~check:{ validate = fun choices args -> one_of args "view" "A graph panel's view" (List.assoc "view" choices) }
    ~opt:["graph", Ty.Text] ~kw:["wires", Ty.Text; "view", Ty.Text] "ui/graph" [];
  leaf ~kw:[ "of", Ty.panel ] "ui/inspector" [];
  leaf ~kw:[ "of", Ty.panel ] "ui/spreadsheet" [];
  leaf "ui/outline" [];
  leaf ~kw:[ "of", Ty.panel ] "ui/list" [];
  leaf ~choices:["tab", ["selection"; "graph"; "document"]]
    ~check:{ validate = fun choices args -> one_of args "tab" "A lisp panel's tab" (List.assoc "tab" choices) }
    ~kw:[ "tab", Ty.Text; "of", Ty.panel ] "ui/lisp" [];
  leaf "ui/timeline" [];
  panel ~choices:["axis", ["horizontal"; "vertical"]] ~check:{ validate = split_check } ~kw:[ "first_size", Ty.Int; "second_size", Ty.Int ] "ui/split"
    [ "axis", Ty.Text; "first", Ty.panel; "second", Ty.panel ];
  panel ~choices:["axis", ["horizontal"; "vertical"]] ~check:{ validate = split_at_check } "ui/split-at" [ "axis", Ty.Text; "ratio", fl; "first", Ty.panel; "second", Ty.panel ];
  panel ~splice:true ~check:{ validate = fun _ args -> tile_check args } ~rest:("panel", Ty.panel) "ui/tile" [];
  panel "ui/floating" [ "panel", Ty.panel ];
  panel ~check:{ validate = fun _ args -> switch_check args } ~rest:("panel", Ty.panel) ~kw:["active", Ty.Int] "ui/switch" []
]

let table =
  let h = Hashtbl.create 64 in
  List.iter (fun o -> if Hashtbl.mem h o.name then invalid_arg ("Duplicate operator: " ^ o.name);
    Hashtbl.add h o.name o) all;
  h
let lookup extra name = match extra with
  | [] -> Hashtbl.find_opt table name
  | _ -> (match List.find_opt (fun op -> op.name = name) extra with
      | Some _ as op -> op | None -> Hashtbl.find_opt table name)
let find ?(extra = []) name ctx =
  match lookup extra name with
  | Some _ as o -> o
  | None -> (match lookup extra ("value/" ^ name) with
      | Some _ as o -> o
      | None -> lookup extra (Context.name ctx ^ "/" ^ name))
let of_context ?(extra = []) ctx =
  let all = all @ extra in
  (if ctx = Context.value then [] else List.filter (fun o -> o.ctx = ctx) all)
  @ List.filter (fun o -> o.ctx = Context.value) all
let arith name = Option.bind (Hashtbl.find_opt table name) (fun o -> o.arithmetic)

let validate extra =
  let seen = Hashtbl.create 16 in
  List.find_map (fun op ->
    let valid = match String.split_on_char '/' op.name with
      | [name] -> Symbol.valid_name name && not (Symbol.reserved name)
      | [prefix; name] -> Symbol.valid_name prefix && Symbol.valid_name name
      | _ -> false in
    if not valid || Hashtbl.mem table op.name || Hashtbl.mem seen op.name then
      Some (Diagnostic.error ~code:"E_OP_DECLARATION" ("Invalid or duplicate extra operator " ^ op.name))
    else (Hashtbl.add seen op.name (); None)) extra
