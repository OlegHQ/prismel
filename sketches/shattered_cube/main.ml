open Rays
open Procedural

(* The document (network, lights, camera) is sketch.rays. *)

let material = Material.create ~diffuse:(Color.hex_exn "#f2b36d")
    ~ambient:(Color.hex_exn "#422006") ~specular:Color.white ~shininess:48. ()

(* [Mesh] carries a packed cook's instance transforms. *)
type preview = Pieces of Sketch_support.Packed_pieces.t
  | Mesh of Mesh.t * Mat4.t array option

let prepare output =
  match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "piece"
      output.Session.geometry with
  | Some attribute ->
      (match Rdk.Attribute.Private.storage attribute with
       | Rdk.Attribute.Int _ | Text _ ->
           Sketch_support.Packed_pieces.of_geometry ~piece_attribute:"piece"
             output.geometry
           |> Result.map (fun pieces -> Pieces pieces)
       | _ -> Rdk_rays.Rays_mesh.to_mesh output.geometry
           |> Result.map (fun mesh -> Mesh (mesh, output.instances))
           |> Result.map_error Rdk.Error.to_string)
  | None -> Rdk_rays.Rays_mesh.to_mesh output.geometry
      |> Result.map (fun mesh -> Mesh (mesh, output.instances))
      |> Result.map_error Rdk.Error.to_string

let scene3 node preview =
  let mesh = match preview with
    | Pieces pieces -> Sketch_support.Packed_pieces.mesh_for_node node pieces
    | Mesh (mesh, _) -> mesh in
  let primitive_mode = Mesh.mode mesh in
  let shading = match Node.operation node with
    | "box" | "grid" | "platonic" -> Scene3.Flat
    | _ -> Scene3.Smooth in
  (* Curves and points have no surface normal to light. Keep their modelling
     preview bright and unlit; Point Generate intentionally stacks its points
     at the origin, so coincident points correctly appear as one marker. *)
  let preview_material = match primitive_mode with
    | Mesh.Points | Lines | Line_strip | Line_loop ->
        Material.unlit (Color.hex_exn "#fbbf74")
    | Triangles | Triangle_strip | Triangle_fan -> material in
  let cull = match preview, primitive_mode with
    | Pieces _, (Mesh.Triangles | Triangle_strip | Triangle_fan) ->
        Scene3.Cull_back
    | _ -> Scene3.Cull_none in
  let drawing =
    (* Intermediate sheet SOPs need to remain inspectable from either side,
       like a modelling viewport. Primitive sources use their exact face
       winding instead of an interpolated preview normal. *)
    match preview with
    | Mesh (_, Some transforms) ->
        Scene3.instances_array ~cull ~shading ~material:preview_material mesh transforms
    | Mesh (_, None) | Pieces _ -> Scene3.mesh ~cull ~shading ~material:preview_material mesh
  in
  let drawing = match primitive_mode with
    | Mesh.Points ->
        Scene3.with_raster (Scene3.raster_state ~point_size:11. ()) [drawing]
    | Lines | Line_strip | Line_loop ->
        Scene3.with_raster (Scene3.raster_state ~line_width:2. ()) [drawing]
    | Triangles | Triangle_strip | Triangle_fan -> drawing in
  Scene3.create ~samples:1 [drawing]

let overlay graph preview frame =
  let pieces = match preview with
    | None -> "waiting for first cook"
    | Some (Pieces pieces) -> Printf.sprintf "%d closed pieces"
        (Sketch_support.Packed_pieces.piece_count pieces)
    | Some (Mesh (mesh, _)) -> Printf.sprintf "%d preview vertices"
        (Mesh.vertex_count mesh) in
  Scene.[
    text ~at:(20, 18) "SOP Shattered Cube";
    text ~at:(20, 43) (Printf.sprintf "%d nodes · %s"
      (List.length (Graph.inspect graph)) pieces);
    text ~at:(20, frame.Frame.height - 82)
      "Select source-switch for Cube / Dodecahedron · VIEW displays any SOP";
  ]

let () =
  let workspace, source = Rays_editor.Workspace.open_text ~path:Sketch_source.path
      ~digest:Sketch_source.digest Sketch_source.text in
  Rays_editor.Editor3.run
    ~config:{ Sketch.default_config with width = 1200; height = 760;
      title = "Rays sketch · shattered cube"; domains = Some 1 }
    ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.8
      ~azimuth:0.72 ~elevation:0.42 ())
    ~seed:7349L ~grain:2 ~max_entries:24
    ~max_payload_bytes:(256 * 1024 * 1024)
    ~workspace ?source
    ~prepare:(fun _ -> prepare)
    ~scene3 ~overlay ()
