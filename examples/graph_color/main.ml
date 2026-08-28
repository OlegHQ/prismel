open Prismel
open Procedural

type model = {
  session : Session.t;
  by_edge : int array;
  by_point : int array;
  frames_left : int option;
}

let columns = 18
let rows = 12

let colors geometry =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "color" geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Int values -> Array.copy values
       | _ -> failwith "Graph Color produced non-integer color storage")
  | None -> failwith "Graph Color did not produce color"

let cook session frame node =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Session.cook session ~context node with
  | Ok output -> colors output.geometry
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000
      |> Result.get_ok in
  let source = Pdk.Ops.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns ~rows ~size:2. () |> Result.get_ok |> Sop.snapshot in
  let by_edge = source |> Sop.graph_color
      ~connectivity:Pdk.Ops.Graph_primitives_by_edge |> cook session frame
  and by_point = source |> Sop.graph_color
      ~connectivity:Pdk.Ops.Graph_primitives_by_point |> cook session frame in
  {session;by_edge;by_point;
   frames_left=None}

let update model _ =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  {model with frames_left}

let palette = [|
  Color.hex_exn "#22d3ee"; Color.hex_exn "#f472b6";
  Color.hex_exn "#facc15"; Color.hex_exn "#a78bfa";
  Color.hex_exn "#4ade80"; Color.hex_exn "#fb923c" |]

let panel ~at_x colors =
  Array.to_list (Array.mapi (fun primitive color ->
    let column = primitive mod columns and row = primitive / columns in
    Scene.rect ~at:(at_x + (column * 20), 82 + (row * 20)) ~w:17 ~h:17
      ~fill:palette.(color mod Array.length palette) ()) colors)

let view model _ =
  [Scene.clear (Color.hex_exn "#020617");
   Scene.text ~at:(30,24) ~size:22 "Graph Color: conflict-free work schedules";
   Scene.text ~at:(30,56) "Primitive adjacency by shared polygon edge (2 colors)";
   Scene.text ~at:(450,56) "Primitive adjacency by shared point (4 colors)"]
  @ panel ~at_x:30 model.by_edge @ panel ~at_x:450 model.by_point

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{Sketch.default_config with width=850;height=350;
      title="Prismel Graph Color"}
    ~init ~update ~view ~on_stop ())
