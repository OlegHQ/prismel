open Rays
open Procedural

let get = Result.get_ok
let path = Sys.argv.(1)
let workspace = In_channel.with_open_bin path In_channel.input_all
  |> Rays_editor.Workspace.load |> Result.map_error (fun ds ->
      String.concat "\n" (List.map Flow.Diagnostic.to_string ds)) |> get
let graph = Rays_editor.Workspace.sop_graphs workspace |> get |> List.assoc "shards"
let fracture = Graph.inspect graph |> List.find (fun (i : Graph.info) -> i.operation = "boolean")
  |> fun i -> Graph.find graph ~node_id:i.id |> Option.get

let cook domains node =
  let session = Session.create ~max_entries:32 ~max_payload_bytes:(256 * 1024 * 1024) |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    Session.cook session ~context:(Context.create ~domains ~grain:2 () |> get) node
      |> Result.map_error Diagnostic.error_to_string |> get)

let () =
  let one = cook 1 fracture and four = cook 4 fracture in
  let g = one.geometry and h = four.geometry in
  assert (Rdk.Geometry.point_count g = Rdk.Geometry.point_count h);
  assert (Rdk.Geometry.primitive_count g = Rdk.Geometry.primitive_count h);
  for i = 0 to Rdk.Geometry.point_count g - 1 do
    assert (Rdk.Packed.Float3.get (Rdk.Geometry.positions g) i
            = Rdk.Packed.Float3.get (Rdk.Geometry.positions h) i)
  done;
  let tg = Rdk.Topology.Private.view (Rdk.Geometry.topology g)
  and th = Rdk.Topology.Private.view (Rdk.Geometry.topology h) in
  assert (tg.vertex_points = th.vertex_points && tg.primitive_offsets = th.primitive_offsets);
  let pieces geometry = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "piece" geometry
      |> Option.get |> Rdk.Attribute.storage |> function
    | Rdk.Attribute.Int a -> a | _ -> failwith "fracture lost its piece IDs" in
  let piece_ids = pieces g in
  assert (piece_ids = pieces h);
  let dense = Hashtbl.create 512 and count = ref 0 in
  let membership = Array.map (fun id -> match Hashtbl.find_opt dense id with
    | Some i -> i | None -> let i = !count in incr count; Hashtbl.add dense id i; i) piece_ids in
  assert (!count >= 1000);
  let parts = Rdk.Deletion.primitive_partitions ~piece_count:!count ~primitive_pieces:membership g in
  Array.iter (fun part ->
    let index = Rdk.Topology_index.create (Rdk.Geometry.topology part) in
    assert (Rdk.Topology_index.boundary_edge_count index = 0);
    assert (Rdk.Topology_index.non_manifold_edge_count index = 0)) parts;
  let source = Node.inputs fracture |> List.hd |> cook 1 in
  let original_volume = Rdk.Analysis.signed_volume source.geometry |> get
  and fractured_volume = Rdk.Analysis.signed_volume g |> get in
  assert (abs_float (original_volume -. fractured_volume) < 1e-7 *. abs_float original_volume);
  let colored = cook 1 graph in
  let prepared = Sketch_support.Surface.of_output colored |> get in
  let drawings = Sketch_support.Surface.scene3 graph prepared |> Scene3.Private.drawings in
  assert (List.length drawings = 4);
  Printf.printf "studio fracture: %d closed manifold shards, %d faces, volume %.9g; exact across 1/4 domains; four material batches\n%!"
    !count (Rdk.Geometry.primitive_count g) fractured_volume
