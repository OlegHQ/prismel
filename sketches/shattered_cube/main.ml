open Prismel
open Procedural

let graph () =
  let cube = Sop_catalog.Box.create ~label:"cube"
      ~size:(Vec3.create 2.6 2.6 2.6) ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~normals:Pdk.Ops.Box_vertex_normals ()
  and dodecahedron = Sop_catalog.Platonic.create ~label:"dodecahedron"
      ~kind:Pdk.Ops.Platonic_dodecahedron
      ~normals:Pdk.Ops.Platonic_vertex_normals
      ~rotation:(Vec3.create 0.173 0.291 0.113) ~radius:2.25 () in
  let source = Sop_catalog.Switch.create ~label:"source-switch"
      [cube; dodecahedron] in
  let cutter_grid = Sop_catalog.Grid.create ~label:"cutter-grid"
      ~counts:Pdk.Ops.Grid_divisions ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:2 ~rows:2 ~size:4.8 ()
    |> Sop_catalog.Mountain.create ~label:"cutter-mountain" ~seed:0
         ~height:0.35 ~frequency:(Vec3.create 0.27 1. 0.27)
         ~octaves:1 ~lacunarity:2. ~roughness:0.5
         ~recompute_normals:true
    |> Sop_catalog.Normal.create ~label:"cutter-normals"
         ~owner:Pdk.Attribute.Vertex ~cusp_angle:Float.pi in
  let cutter_points = Sop_catalog.Point_generate.origin
      ~label:"cutter-points" ~points:50 ()
    |> Sop_catalog.Attribute_noise_quaternion.create
         ~label:"orient-noise" ~seed:7349 ~owner:Pdk.Attribute.Point
         ~name:"orient" ~location:Pdk.Attribute_ops.Noise_element_number
         ~range:Pdk.Attribute_ops.Noise_zero_centered
         ~frequency:(Vec3.create 0.173 0.173 0.173) ~octaves:2
    |> Sop_catalog.Point_jitter.create ~label:"position-jitter" ~seed:7350
         ~id_attribute:"sourceindex" ~scale:0.45 in
  Sop_catalog.Copy_to_points.create ~label:"copy-cutters" ~source:cutter_grid
    ~targets:cutter_points ()
  |> fun cutters -> Sop_catalog.Boolean_fracture.create
       ~label:"boolean-fracture" ~resolve_cutter_self_intersections:true
       ~detriangulation:Pdk.Boolean.Triangles ~require_closed:true
       ~piece_attribute:"piece" ~cutters source
  |> Sop_catalog.Normal.create ~label:"fracture-normals"
       ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.65
  |> Sop_catalog.Exploded_view.create ~label:"exploded-view"

let material = Material.create ~diffuse:(Color.hex_exn "#f2b36d")
    ~ambient:(Color.hex_exn "#422006") ~specular:Color.white ~shininess:48. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
    ~diffuse:(Color.hex_exn "#fff7ed") ~ambient:(Color.hex_exn "#1c1917") ();
  Light.directional ~direction:(Vec3.create 1.2 0.4 (-0.8))
    ~diffuse:(Color.hex_exn "#7dd3fc") ~intensity:0.55 ();
]

type preview = Pieces of Sketch_support.Packed_pieces.t | Mesh of Mesh.t

let prepare output =
  match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive "piece"
      output.Session.geometry with
  | Some attribute ->
      (match Pdk.Attribute.Private.storage attribute with
       | Pdk.Attribute.Int _ | Text _ ->
           Sketch_support.Packed_pieces.of_geometry ~piece_attribute:"piece"
             output.geometry
           |> Result.map (fun pieces -> Pieces pieces)
       | _ -> Bridge.to_mesh output.geometry
           |> Result.map (fun mesh -> Mesh mesh)
           |> Result.map_error Pdk.Error.to_string)
  | None -> Bridge.to_mesh output.geometry
      |> Result.map (fun mesh -> Mesh mesh)
      |> Result.map_error Pdk.Error.to_string

let scene3 node preview =
  let mesh = match preview with
    | Pieces pieces -> Sketch_support.Packed_pieces.mesh_for_node node pieces
    | Mesh mesh -> mesh in
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
  let drawing =
    (* Intermediate sheet SOPs need to remain inspectable from either side,
       like a modelling viewport. Primitive sources use their exact face
       winding instead of an interpolated preview normal. *)
    Scene3.mesh ~cull:Scene3.Cull_none ~shading ~material:preview_material mesh
  in
  let drawing = match primitive_mode with
    | Mesh.Points ->
        Scene3.with_raster (Scene3.raster_state ~point_size:11. ()) [drawing]
    | Lines | Line_strip | Line_loop ->
        Scene3.with_raster (Scene3.raster_state ~line_width:2. ()) [drawing]
    | Triangles | Triangle_strip | Triangle_fan -> drawing in
  Scene3.create ~samples:1 ~lights [drawing]

let overlay graph preview frame =
  let pieces = match preview with
    | None -> "waiting for first cook"
    | Some (Pieces pieces) -> Printf.sprintf "%d closed pieces"
        (Sketch_support.Packed_pieces.piece_count pieces)
    | Some (Mesh mesh) -> Printf.sprintf "%d preview vertices"
        (Mesh.vertex_count mesh) in
  Scene.[
    text ~at:(20, 18) "SOP Shattered Cube";
    text ~at:(20, 43) (Printf.sprintf "%d nodes · %s"
      (List.length (Graph.inspect graph)) pieces);
    text ~at:(20, frame.Frame.height - 82)
      "Select source-switch for Cube / Dodecahedron · VIEW displays any SOP";
  ]

let () =
  Sketch_ui.Environment3.run
    ~config:{ Sketch.default_config with width = 1200; height = 760;
      title = "Prismel sketch · shattered cube"; domains = Some 1 }
    ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.8
      ~azimuth:0.72 ~elevation:0.42 ())
    ~seed:7349L ~grain:2 ~max_entries:24
    ~max_payload_bytes:(256 * 1024 * 1024)
    ~factories:Sop_catalog.Editor.factories
    ~graph:(graph ())
    ~prepare
    ~scene3 ~overlay ()
