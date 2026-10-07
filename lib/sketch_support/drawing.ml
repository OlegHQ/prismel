open Rays
module E = Flow.Eval
module V = Flow.Value
module I = Flow_ir.Executor

type prepared = {plan : E.plan; value : I.program; states : I.program; args : I.program array}
let prepare ?profile ?(states = []) plan value =
  let ( let* ) = Result.bind in
  let* value = I.compile ?profile value in
  let* states = I.compile ?profile (E.List (Array.of_list states)) in
  let args = Array.map (fun (node : E.node) -> I.compile ?profile (E.Record node.args)) plan.E.nodes in
  match Array.find_opt Result.is_error args with
  | Some (Error d) -> Error d
  | _ -> Ok {plan; value; states; args = Array.map Result.get_ok args}

let render_prepared ?state ?(reference = false) prepared ~live ~size:(width, height) =
  let plan = prepared.plan in
  let state = Option.value ~default:(E.create_state ()) state in
  E.transaction state (fun () ->
    let exception Stop of Flow.Diagnostic.t in
    let force program = match I.force ~state ~reference program ~live with Ok v -> v | Error d -> raise (Stop d) in
    let color = function
      | E.Text s -> (match Color.hex s with Ok c -> c | Error message -> V.fail "E_DRAW_COLOR" message)
      | Vec3 (r, g, b) -> Color.of_floats r g b 1.
      | _ -> V.fail "E_TYPE" "A drawing color is hex text or a vec3." in
    let point v = let x, y, _ = V.comps v in
      let int x = if not (Float.is_finite x) || x >= float max_int || x < float min_int
        then V.fail "E_DRAW_RANGE" "A drawing coordinate must fit an integer." else int_of_float x in
      int x, int y in
    (* Each deferred node lowers once per picture. The table is bounded by the
       static plan; repeated references retain painter order. *)
    let memo = Array.make (Array.length plan.nodes) None in
    let rec drawing = function
      | E.Deferred ((Flow.Ty.Named "drawing"), id) when id >= 0 && id < Array.length memo ->
          (match memo.(id) with Some scene -> scene | None ->
            let node = plan.nodes.(id) in
            if node.ty <> Flow.Ty.drawing then V.fail "E_TYPE" "The canvas needs a Drawing node.";
            let args = match force prepared.args.(id) with E.Record fs -> fs | _ -> assert false in
            let arg k = match List.assoc_opt k args with Some v -> v
              | None -> V.failf "E_DRAW_INPUT" "%s needs %s." node.kind k in
            let optional k f = Option.map f (List.assoc_opt k args) in
            let ink = Option.value (optional "color" color) ~default:Color.white in
            let at () = point (arg "at") in
            let scene = match node.kind with
              | "draw/background" -> [Scene.rect ~at:(0, 0) ~w:width ~h:height ~fill:(color (arg "color")) ()]
              | "draw/point" -> [Scene.point ~at:(at ()) ~color:ink ()]
              | "draw/points" ->
                  let xs = arg "positions" in
                  let batch = Ink.create () in
                  for i = 0 to V.array_length xs - 1 do
                    let x, y = point (V.array_get xs i) in Ink.rect batch x y 1 1 ink
                  done;
                  Option.to_list (Ink.take batch)
              | "draw/line" -> [Scene.line ~from_:(point (arg "from")) ~to_:(point (arg "to"))
                  ~color:ink ?width:(optional "width" V.int_of) ()]
              | "draw/rect" -> let w, h = point (arg "size") in
                  [Scene.rect ~at:(at ()) ~w ~h ?fill:(optional "fill" color) ?stroke:(optional "stroke" color) ()]
              | "draw/circle" -> [Scene.circle ~at:(at ()) ~radius:(V.int_of (arg "radius"))
                  ?fill:(optional "fill" color) ?stroke:(optional "stroke" color) ()]
              | "draw/text" -> [Scene.text ~at:(at ()) ~color:ink ?size:(optional "size" V.int_of)
                  (match arg "text" with E.Text s -> s | _ -> V.fail "E_TYPE" "Drawing text is text.")]
              | "draw/translate" -> let x, y = point (arg "offset") in
                  [Scene.translate x y (drawing (arg "drawing"))]
              | "draw/merge" -> List.concat_map (fun (_, v) -> drawing v) args
              | kind -> V.failf "E_DRAW_KIND" "No native drawing implementation for %s." kind in
            memo.(id) <- Some scene; scene)
      | _ -> V.fail "E_TYPE" "The canvas needs a Drawing value." in
    try
      ignore (force prepared.states);
      Ok (drawing (force prepared.value))
    with Stop d -> Error d
       | V.Fail (code, message, _) -> Error (Flow.Diagnostic.error ~code message))

let render ?state ?states plan value ~live ~size =
  Result.bind (prepare ?states plan value) (fun prepared -> render_prepared ?state prepared ~live ~size)
