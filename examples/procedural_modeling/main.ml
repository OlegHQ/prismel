(* Procedural modeling: three small SOP chains (sweep a curve, group and
   extrude tiles, copy a prototype onto randomized points) cooked once into
   meshes. examples/sop_gallery shows the wider node catalog. *)
open Prismel
open Procedural

type model = {
  session : Session.t;
  meshes : Mesh.t list;
  camera : Easy_camera.t;
}

let cook session frame graph =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context graph with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let graphs () =
  let tube =
    Sop.polyline [|(-3.,0.,0.); (-2.5,1.4,0.4); (-1.5,0.7,-0.5);
      (-0.8,2.2,0.)|]
    |> Sop.resample ~maximum_segment_length:0.08
         ~curve_u_attribute:"curveu" ~tangent_attribute:"curve_tangent"
    |> Sop.sweep_circle ~sides:12 ~radius:0.16
    |> Sop.polyframe ~orthogonal:true (Pdk.Analysis_ops.Attribute_gradient "uv")
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
  and tiles =
    Sop.grid ~columns:4 ~rows:3 ~size:2.8 ()
    |> Sop.mountain ~seed:222 ~height:0.16
         ~frequency:(Vec3.create 1.2 0.8 1.2) ~octaves:4
    |> Sop.group_random ~seed:221 ~probability:0.1
         ~owner:Pdk.Group_ops.Group_points ~name:"growth_seeds"
    |> Sop.group_edge_depth ~depth:1 ~point_group:"growth_seeds"
         ~name:"growth_points"
    |> Sop.peak ~selection:(Sop.Point_group "growth_points") ~distance:0.015
         ~recompute_normals:true
    |> Sop.group_random ~seed:223 ~probability:0.42
         ~owner:Pdk.Group_ops.Group_primitives ~name:"raised_tiles"
    |> Sop.group_bounds ~base:"raised_tiles"
         ~containment:Pdk.Group_ops.Partially_contained
         (Pdk.Group_ops.Bounds_sphere { center = Vec3.zero; radius = 1.35 })
         ~owner:Pdk.Group_ops.Group_primitives ~name:"raised_tiles"
    |> Sop.group_normal ~use_existing_normal:false ~base:"raised_tiles"
         ~direction:Vec3.unit_y
         ~spread_angle:(Float.pi /. 3.) ~owner:Pdk.Group_ops.Group_primitives
         ~name:"raised_tiles"
    |> Sop.group_backface ~merge:Pdk.Group_ops.Group_subtract
         ~viewpoint:(Vec3.create 0. 4. 5.) ~name:"raised_tiles"
    |> Sop.peak ~selection:(Sop.Primitive_group "raised_tiles") ~distance:0.04
    |> Sop.poly_extrude ~group:"raised_tiles"
         ~divide:Pdk.Poly_modeling.Extrude_connected_components ~divisions:3
         ~front_group:"tile_fronts" ~side_group:"tile_sides"
         ~front_boundary_group:"tile_rims" ~distance:0.28
    |> Sop.facet ~unique_points:true ~post_compute_normals:true
    |> Sop.measure ~total_name:"tile_surface_area" Pdk.Analysis.Area
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
    |> Sop.transform (Mat4.translation (Vec3.create 1.5 0. 0.))
  and copies =
    let prototype = Sop.box ~connectivity:Pdk.Box_generator.Box_quads
        ~consolidate_points:true ~size:(Vec3.create 0.28 0.62 0.2) ()
        |> Sop.facet ~cusp_angle:0.6 ~post_compute_normals:true
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15") in
    let targets = Array.init 18 (fun index ->
      let angle = float_of_int index *. 0.72 in
      (2.4 *. cos angle, 0.35 +. (float_of_int index *. 0.12),
       2.4 *. sin angle)) in
    Sop.copy_to_points ~source:prototype
      ~targets:(Sop.points targets
        |> Sop.attribute_randomize ~seed:301 ~owner:Pdk.Attribute.Point
             ~name:"pscale" (Pdk.Attribute_ops.Random_custom_discrete [
               Pdk.Attribute_ops.Scalar 0.45, 1.;
               Pdk.Attribute_ops.Scalar 0.65, 3.;
               Pdk.Attribute_ops.Scalar 0.9, 1.;
             ])
        |> Sop.attribute_randomize ~seed:302 ~owner:Pdk.Attribute.Point
             ~direction_bias:0.8 ~name:"orient"
             (Pdk.Attribute_ops.Random_direction {
               direction = Pdk.Attribute_ops.Vec4 (0., 0., 0., 1.);
               cone_angle = Float.pi *. 0.8;
             })) ()
    |> Sop.connectivity ~name:"copy_piece"
         ~attribute:(Pdk.Analysis.Connectivity_text "copy_")
    |> Sop.groups_from_name ~owner:Pdk.Attribute.Primitive
         ~attribute:"copy_piece"
  in
  [tube; tiles; copies]

let init frame =
  let session = Session.create ~max_entries:64
      ~max_payload_bytes:(128 * 1024 * 1024) |> Result.get_ok in
  { session;
    meshes = List.map (cook session frame) (graphs ());
    camera = Easy_camera.create ~target:(Vec3.create 0. 0.5 0.)
        ~distance:9. ~azimuth:0.7 ~elevation:0.45 (); }

let update model frame =
  { model with camera = Easy_camera.update model.camera frame }

let view model _frame =
  let lights = [Light.directional ~direction:(Vec3.create (-1.) (-2.) (-1.))
      ~ambient:(Color.hex_exn "#1e293b") ()] in
  let nodes = List.map (fun mesh -> Scene3.mesh ~cull:Scene3.Cull_none
      ~material:(Material.create ~diffuse:Color.white ()) mesh) model.meshes in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera)
      (Scene3.create ~lights ~samples:4 nodes);
    text ~at:(16, 16)
      "Procedural modeling: a swept tube, extruded tiles, and copies";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 960; height = 640;
      title = "Prismel Procedural Modeling" }
    ~init ~update ~view ~on_stop ())
