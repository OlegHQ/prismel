open Rays
module E = Flow.Eval
module V = Flow.Value
module I = Flow_ir.Executor

type prepared = {plan : E.plan; value : I.program; states : I.program; args : (string*I.program)list array;
  static:bool array; retained:((int*int)*Scene.t) option array}
let prepare ?profile ?(approx=Flow.Workspace.Paths.empty) ?(states = []) plan value =
  let ( let* ) = Result.bind in
  let* value = I.compile ?profile value in
  let* states = I.compile ?profile (E.List (Array.of_list states)) in
  let args = Array.map (fun (node : E.node) ->
    List.fold_right(fun(name,value)result->let* rest=result in
      let* program=I.compile ?profile ~approx ~sink:(Flow_ir.Display node.kind) value in
      Ok((name,program)::rest))node.args(Ok[])) plan.E.nodes in
  match Array.find_opt Result.is_error args with
  | Some (Error d) -> Error d
  | _ ->
      let known=Array.make(Array.length plan.nodes)None in
      let rec static = function
        |E.Deferred(Flow.Ty.Named "drawing",id)->node id
        |E.Deferred _->false
        |E.List values->Array.for_all static values
        |E.Record fields|E.Struct(_,_,fields)->List.for_all(fun(_,value)->static value)fields
        |value->not(E.is_live value)
      and node id=match known.(id)with
        |Some value->value
        |None->known.(id)<-Some false;
            let value=List.for_all(fun(_,value)->static value)plan.nodes.(id).args in
            known.(id)<-Some value;value in
      Ok {plan; value; states; args = Array.map Result.get_ok args;
        static=Array.init(Array.length plan.nodes)node;
        retained=Array.make(Array.length plan.nodes)None}

let render_prepared ?state ?image ?gpu ?(gpu_policy=Flow_ir.Gpu.Measured) ?(reference = false) prepared ~live ~size:(width, height) =
  let plan = prepared.plan in
  let state = Option.value ~default:(E.create_state ()) state in
  E.transaction state (fun () ->
    let exception Stop of Flow.Diagnostic.t in
    let force program = match I.force ~state ~reference program ~live with Ok v -> v | Error d -> raise (Stop d) in
    let color = Flow_ir.Operators.drawing_color in
    let point v = let x, y, _ = V.comps v in
      let int x = if not (Float.is_finite x) || x >= float max_int || x < float min_int
        then V.fail "E_DRAW_RANGE" "A drawing coordinate must fit an integer." else int_of_float x in
      int x, int y in
    (* Each deferred node lowers once per picture. The table is bounded by the
       static plan; repeated references retain painter order. *)
    let memo = Array.make (Array.length plan.nodes) None in
    let rec drawing = function
      | E.List values -> Array.to_list values |> List.concat_map drawing
      | E.Deferred ((Flow.Ty.Named "drawing"), id) when id >= 0 && id < Array.length memo ->
          (match memo.(id) with Some scene -> scene | None ->
            match prepared.retained.(id)with
            |Some(size,scene)when prepared.static.(id)&&size=(width,height)->
                memo.(id)<-Some scene;scene
            |_->
            let node = plan.nodes.(id) in
            if node.ty <> Flow.Ty.drawing then V.fail "E_TYPE" "The canvas needs a Drawing node.";
            let positions=ref None in
            let remaining=List.filter(fun(name,_)->name<>"positions")prepared.args.(id)
              |>List.map(fun(name,program)->name,force program)in
            let uniform key=match List.assoc_opt key remaining with
              |Some(E.Float_array _|E.Vec3_array _|E.List _)->false|_->true in
            let candidate=node.kind="draw/circles" && gpu<>None &&
              List.for_all uniform ["radius";"fill";"stroke"]in
            let args=match List.assoc_opt "positions" prepared.args.(id)with
              |None->remaining
              |Some program when candidate->(match I.force_display ~state ~reference ~policy:gpu_policy program ~live with
                |Ok(I.Cpu value)->("positions",value)::remaining
                |Ok(I.Gpu value)->positions:=Some value;remaining
                |Error diagnostic->raise(Stop diagnostic))
              |Some program->("positions",force program)::remaining in
            let arg k = match List.assoc_opt k args with Some v -> v
              | None -> V.failf "E_DRAW_INPUT" "%s needs %s." node.kind k in
            let optional k f = Option.map f (List.assoc_opt k args) in
            let ink = match List.assoc_opt "color" args with
              |Some(E.Vec3_array _)->Color.white|Some value->color value|None->Color.white in
            let at () = point (arg "at") in
            let rgba (c:Color.t) = Int32.of_int ((c.r lsl 24) lor (c.g lsl 16) lor (c.b lsl 8) lor c.a) in
            let current=ref 0 in
            let style key = optional key (function
              |E.Vec3_array xs->let i=3* !current in
                  if i+2>=Array.length xs then V.fail "E_DRAW_LENGTH" "Colors and positions have different lengths.";
                  rgba(color(E.Vec3(xs.(i),xs.(i+1),xs.(i+2))))
              |v->rgba(color v)) in
            let packed_point values i = match values with
              | E.Vec3_array xs -> xs.(3*i),xs.(3*i+1)
              | _ -> let x,y,_=V.comps(V.array_get values i)in x,y in
            let batch count append =
              List.iter(fun key->match List.assoc_opt key args with
                |Some(E.Vec3_array xs) when Array.length xs<>3*count ->
                    V.fail "E_DRAW_LENGTH" "Colors and positions have different lengths."
                |_->())["fill";"stroke";"color"];
              let b=Scene_command.Shape_batch.Builder.create ~capacity:count () in
              for i=0 to count-1 do current:=i;append b i done;
              [Scene.Private.shapes(Scene_command.Shape_batch.Builder.publish b)] in
            let circle b x y radius = Scene_command.Shape_batch.Builder.circle b ~x ~y
              ~radius ?fill:(style "fill") ?stroke:(style "stroke") () in
            let rect b x y width height = Scene_command.Shape_batch.Builder.rect b ~x ~y
              ~width ~height ?fill:(style "fill") ?stroke:(style "stroke") () in
            let line b x0 y0 x1 y1 = Scene_command.Shape_batch.Builder.line b ~x0 ~y0 ~x1 ~y1
              ~color:(match List.assoc_opt "color" args with
                |Some(E.Vec3_array _)->Option.get(style "color")|_->rgba ink)
              ~width:(Option.value (optional "width" V.num) ~default:1.) in
            let scene = match node.kind with
              | "draw/image" ->
                  let loaded=match image with Some resolve->(match resolve(arg "image")with
                    |Ok image->image|Error diagnostic->raise(Stop diagnostic))
                    |None->V.fail "E_IMAGE" "Drawing images need an environment-owned image resolver."in
                  [Scene.image loaded ~at:(Option.value(optional "at" point)~default:(0,0))
                    ?scale:(optional "scale" V.num) ?angle:(optional "angle" V.num) ()]
              | "draw/background" -> [Scene.rect ~at:(0, 0) ~w:width ~h:height ~fill:(color (arg "color")) ()]
              | "draw/point" -> [Scene.point ~at:(at ()) ~color:ink ()]
              | "draw/points" ->
                  let xs = arg "positions" in
                  let batch = Ink.create () in
                  for i = 0 to V.array_length xs - 1 do
                    let x, y = point (V.array_get xs i) in Ink.rect batch x y 1 1 ink
                  done;
                  Option.to_list (Ink.take batch)
              | "draw/line" -> let x0,y0,_=V.comps(arg "from")and x1,y1,_=V.comps(arg "to")in
                  batch 1 (fun b _->line b x0 y0 x1 y1)
              | "draw/rect" -> let x,y,_=V.comps(arg "at")and w,h,_=V.comps(arg "size")in
                  batch 1 (fun b _->rect b x y w h)
              | "draw/circle" -> let x,y,_=V.comps(arg "at")in
                  batch 1 (fun b _->circle b x y (V.num(arg "radius")))
              | "draw/circles" when !positions<>None ->
                  let output=Option.get !positions in
                  if output.Flow_ir.Gpu.width<>3 then V.fail "E_GPU" "Drawing circles need a width-three GPU array.";
                  let radius=Option.value(optional "radius" V.num)~default:1. in
                  let fill=Option.value(style "fill")~default:0l and stroke=Option.value(style "stroke")~default:0l in
                  let fill,stroke=if not(List.mem_assoc "fill" args || List.mem_assoc "stroke" args)
                    then 0xffffffffl,0l else fill,stroke in
                  let token=match (Option.get gpu) output ~radius ~fill ~stroke ~stroke_width:(if stroke=0l then 0. else 1.)with
                    |Ok token->token|Error diagnostic->raise(Stop diagnostic)in
                  [Scene.Private.shapes(Scene_command.Shape_batch.Private.of_gpu token)]
              | "draw/circles" -> let positions=arg "positions" in
                  let n=V.array_length positions in
                  let radius=Option.value (List.assoc_opt "radius" args) ~default:(E.Float 1.)in
                  let radii=match radius with E.Float_array xs->
                    if Array.length xs<>n then V.fail "E_DRAW_LENGTH" "Radii and positions have different lengths.";
                    Some xs | E.Int _|E.Float _->None
                    |_ -> V.fail "E_TYPE" "Radius is a number or packed float array." in
                  batch n(fun b i->let x,y=packed_point positions i in
                    circle b x y (match radii with Some xs->xs.(i)|None->V.num radius))
              | "draw/rects" -> let positions=arg "positions"and sizes=arg "sizes"in
                  let n=V.array_length positions in
                  let packed=match sizes with E.Vec3_array xs->
                    if Array.length xs<>3*n then V.fail "E_DRAW_LENGTH" "Sizes and positions have different lengths.";
                    true| E.Vec3 _->false|_->V.fail "E_TYPE" "Sizes are a vec3 or packed vec3 array."in
                  let w,h=if packed then 0.,0. else let w,h,_=V.comps sizes in w,h in
                  batch n(fun b i->let x,y=packed_point positions i in
                    let w,h=if packed then packed_point sizes i else w,h in rect b x y w h)
              | "draw/lines" -> let from=arg "from"and dest=arg "to"in
                  let n=V.array_length from in
                  if V.array_length dest<>n then V.fail "E_DRAW_LENGTH" "Line endpoints have different lengths.";
                  batch n(fun b i->let x0,y0=packed_point from i and x1,y1=packed_point dest i in line b x0 y0 x1 y1)
              | "draw/text" -> let text=match arg "text" with E.Text s->s
                  |_->V.fail "E_TYPE" "Drawing text is text."in
                  if text=""then []else [Scene.text ~at:(at ()) ~color:ink ?size:(optional "size" V.int_of) text]
              | "draw/translate" -> let x, y = point (arg "offset") in
                  [Scene.translate x y (drawing (arg "drawing"))]
              | "draw/rotate" -> [Scene.rotate (V.fin "angle" (V.num(arg "angle"))) (drawing(arg "drawing"))]
              | "draw/scale" -> let x,y=match arg "factor" with
                  |E.Vec3(x,y,_)->x,y|v->let n=V.num v in n,n in
                  [Scene.scale (V.fin "scale" x) (V.fin "scale" y) (drawing(arg "drawing"))]
              | "draw/rounded_rect" -> let w,h=point(arg "size")in
                  [Scene.rounded_rect ~at:(at()) ~w ~h
                    ~radius:(Option.value (optional "radius" V.int_of) ~default:0)
                    ?fill:(optional "fill" color) ?stroke:(optional "stroke" color) ()]
              | "draw/polygon" -> let xs=arg "points"in
                  [Scene.polygon (List.init (V.array_length xs) (fun i->point(V.array_get xs i)))
                    ?fill:(optional "fill" color) ?stroke:(optional "stroke" color) ()]
              | "draw/polyline" -> let xs=arg "points"in
                  [Scene.polyline (List.init (V.array_length xs) (fun i->point(V.array_get xs i))) ~color:ink ()]
              | "draw/merge" -> List.concat_map (fun (_, v) -> drawing v) args
              | kind -> V.failf "E_DRAW_KIND" "No native drawing implementation for %s." kind in
            memo.(id) <- Some scene;
            if prepared.static.(id)then prepared.retained.(id)<-Some((width,height),scene);
            scene)
      | _ -> V.fail "E_TYPE" "The canvas needs a Drawing value." in
    try
      ignore (force prepared.states);
      Ok (drawing (force prepared.value))
    with Stop d -> Error d
       | Invalid_argument message -> Error (Flow.Diagnostic.error ~code:"E_DRAW_RANGE" message)
       | V.Fail (code, message, _) -> Error (Flow.Diagnostic.error ~code message))
