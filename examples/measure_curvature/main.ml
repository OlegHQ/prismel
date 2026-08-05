open Prismel
open Procedural

type model = {
  session : Session.t;
  mean : float array;
  gaussian : float array;
  frames_left : int option;
}

let columns = 36
let rows = 22

let fields geometry =
  let field name =
    match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Float values -> Array.copy values
         | _ -> failwith (name ^ " has the wrong storage"))
    | None -> failwith (name ^ " is missing") in
  (field "mean", field "gaussian")

let init frame =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:16_000_000
      |> Result.get_ok in
  let source = Pdk.Ops.torus ~connectivity:Pdk.Ops.Torus_quads
      ~rows ~columns ~major_radius:2. ~minor_radius:0.7 ()
      |> Result.get_ok |> Sop.snapshot in
  let outputs = {
    Pdk.Ops.mean=Some "mean"; gaussian=Some "gaussian";
    minimum=None; maximum=None; curvedness=None; shape_index=None;
  } in
  let node = Sop.measure_curvature ~outputs source in
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  let mean,gaussian = match Session.cook session ~context node with
    | Ok output -> fields output.geometry
    | Error error -> failwith (Diagnostic.error_to_string error) in
  {session;mean;gaussian;
   frames_left=if Sketch.is_headless () then Some 2 else None}

let update model _ =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  {model with frames_left}

let heatmap ~at_x values =
  let maximum = Array.fold_left (fun found value ->
      max found (Float.abs value)) 0. values in
  Array.to_list (Array.mapi (fun point value ->
    let signed = if maximum = 0. then 0. else value /. maximum in
    let amount = int_of_float (Float.round (207. *. Float.abs signed)) in
    let color = if signed < 0. then Color.rgb 48 (120 - (amount / 3))
        (48 + amount)
      else Color.rgb (48 + amount) (120 - (amount / 3)) 48 in
    let column = point mod columns and row = point / columns in
    Scene.rect ~at:(at_x + (column * 10), 80 + (row * 7)) ~w:9 ~h:6
      ~fill:color ()) values)

let view model _ =
  [Scene.clear (Color.hex_exn "#020617");
   Scene.text ~at:(24,18) ~size:22 "Measure Curvature: packed torus fields";
   Scene.text ~at:(24,52) "Signed mean curvature";
   Scene.text ~at:(430,52) "Gaussian curvature"]
  @ heatmap ~at_x:24 model.mean
  @ heatmap ~at_x:430 model.gaussian

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{Sketch.default_config with width=820;height=260;
      title="Prismel Measure Curvature"}
    ~init ~update ~view ~on_stop ())
