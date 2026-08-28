open Prismel
open Procedural

type r11_artifact = {
  pieces : int; triangles : int; render_vertices : int;
  cook_seconds : float; cook_seconds_four : float; pack_seconds : float;
  topology_hash : string; attribute_hash : string; order_hash : string;
  render_hash : string; vertices : bytes; indices : bytes;
}

let r11_delegate graph =
  let renderer=ref None and artifact_path=ref None and visibility=ref None
  and seconds=ref None and report=ref None in
  let options=[
    "--r11-renderer",Arg.String(fun value->renderer:=Some value),"R11 renderer";
    "--r11-artifact",Arg.String(fun value->artifact_path:=Some value),"R11 artifact";
    "--r11-visibility",Arg.String(fun value->visibility:=Some value),"R11 visibility";
    "--r11-seconds",Arg.String(fun value->seconds:=Some value),"R11 duration";
    "--r11-report",Arg.String(fun value->report:=Some value),"R11 report";
  ] in
  if Array.exists((=)"--r11-renderer")Sys.argv then begin
    Arg.parse options (fun value->invalid_arg("unexpected R11 argument: "^value))
      "shattered_cube R11 delegate";
    let renderer=Option.get!renderer and artifact_path=Option.get!artifact_path
    and visibility=Option.get!visibility and seconds=Option.get!seconds
    and report=Option.get!report in
    let input=open_in_bin artifact_path in
    let artifact:r11_artifact=Fun.protect~finally:(fun()->close_in input)
      (fun()->Marshal.from_channel input) in
    if (artifact.pieces,artifact.triangles,artifact.render_vertices)<>
       (18_278,278_368,835_104) then
      failwith"shattered_cube R11 artifact cardinality drift";
    let cooked_pieces,cooked_triangles,cooked_vertices,cooked_render_hash,cooked_mesh =
      Parallel.run ~domains:1 (fun () ->
        let node=graph() in
        let get=function Ok value->value|Error message->failwith message in
        let session=get(Session.create~max_entries:24
          ~max_payload_bytes:(256*1024*1024)) in
        let context=get(Context.create~seed:7349L~domains:1~grain:2()) in
        Fun.protect~finally:(fun()->Session.close session)(fun()->
          let output=match Session.cook session~context node with
            |Ok value->value|Error error->failwith(Diagnostic.error_to_string error)in
          let pieces=get(Sketch_support.Packed_pieces.of_geometry
            ~piece_attribute:"piece" output.geometry)in
          let mesh=Sketch_support.Packed_pieces.mesh_for_node node pieces in
          let view=Mesh.Private.packed_view mesh in
          Sketch_support.Packed_pieces.piece_count pieces,
          Mesh.Private.triangle_count mesh,Mesh.vertex_count mesh,
          Digest.to_hex(Digest.string(Marshal.to_string
            (view.mode,view.vertices,view.indices,view.normals,view.colors,
             view.tex_coords)[])),mesh)) in
    if (cooked_pieces,cooked_triangles,cooked_vertices)<>
       (artifact.pieces,artifact.triangles,artifact.render_vertices) ||
       cooked_render_hash<>artifact.render_hash then
      failwith"shattered_cube R11 artifact does not match the sketch graph";
    ignore renderer;
    R11_native.run ~visibility ~seconds:(float_of_string seconds) ~report
      ~metadata:{pieces=artifact.pieces;triangles=artifact.triangles;
        render_vertices=artifact.render_vertices;cook_seconds=artifact.cook_seconds;
        cook_seconds_four=artifact.cook_seconds_four;pack_seconds=artifact.pack_seconds;
        topology_hash=artifact.topology_hash;attribute_hash=artifact.attribute_hash;
        order_hash=artifact.order_hash;render_hash=artifact.render_hash;
        artifact=artifact_path} cooked_mesh;
    exit 0
  end

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
  r11_delegate graph;
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
