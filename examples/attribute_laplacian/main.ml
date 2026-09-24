open Prismel
open Procedural

type model = {
  session : Session.t;
  cotan : float array;
  uniform : float array;
  frames_left : int option;
}

let columns = 36
let rows = 22

let magnitudes geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point
      "laplacian" geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Float3 values ->
           let values = Pdk.Packed.Float3.Private.view values in
           Array.init (Array.length values.x) (fun point ->
             Float.hypot values.x.(point)
               (Float.hypot values.y.(point) values.z.(point)))
       | _ -> failwith "laplacian has the wrong storage")
  | None -> failwith "laplacian is missing"

let cook session context weighting source =
  let node = Sop.attribute_laplacian ~weighting ~source:"P" source in
  match Session.cook session ~context node with
  | Ok output -> magnitudes output.geometry
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:32_000_000
      |> Result.get_ok in
  let source = Pdk.Ops.torus ~connectivity:Pdk.Ops.Torus_quads
      ~rows ~columns ~major_radius:2. ~minor_radius:0.7 ()
      |> Result.get_ok |> Sop.snapshot in
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  let cotan = cook session context Pdk.Ops.Laplacian_cotan source
  and uniform = cook session context Pdk.Ops.Laplacian_uniform source in
  {session;cotan;uniform;
   frames_left=None}

let update model _ =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  {model with frames_left}

let heatmap ~at_x values =
  let maximum = Array.fold_left max 0. values in
  Array.to_list (Array.mapi (fun point value ->
    let u = if maximum = 0. then 0. else value /. maximum in
    let red = int_of_float (Float.round (255. *. u))
    and green = int_of_float (Float.round (200. *. (1. -. u))) in
    let column = point mod columns and row = point / columns in
    Scene.rect ~at:(at_x + (column * 10), 80 + (row * 7)) ~w:9 ~h:6
      ~fill:(Color.rgb red green 160) ()) values)

let view model _ =
  [Scene.clear (Color.hex_exn "#020617");
   Scene.text ~at:(24,18) ~size:22 "Attribute Laplacian: torus position field";
   Scene.text ~at:(24,52) "Pointwise cotangent magnitude";
   Scene.text ~at:(430,52) "Uniform neighbor average"]
  @ heatmap ~at_x:24 model.cotan @ heatmap ~at_x:430 model.uniform

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{Sketch.default_config with width=820;height=260;
      title="Prismel Attribute Laplacian"}
    ~init ~update ~view ~on_stop ())
