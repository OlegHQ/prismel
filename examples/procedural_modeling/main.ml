(* Procedural modeling: three small SOP chains (sweep a curve, group and
   extrude tiles, copy a prototype onto randomized points) cooked once into
   meshes. examples/sop_gallery shows the wider node catalog. *)
open Rays
open Procedural

type model = {
  session : Session.t;
  meshes : Mesh.t list;
  camera : Easy_camera.t;
}

let cook bridge frame graph =
  let context = Sketch_support.Bridge.context_of_frame ~seed:2026L frame
    |> Result.get_ok in
  match Sketch_support.Bridge.cook_to_mesh bridge ~context graph with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let graphs () =
  let tube =
    Sop.polyline [|(-3.,0.,0.); (-2.5,1.4,0.4); (-1.5,0.7,-0.5);
      (-0.8,2.2,0.)|]
    |> Sop.resample ~use_segments:(false) ~use_maximum_segment_length:true ~maximum_segment_length:0.08
         ~curve_u_attribute:"curveu" ~tangent_attribute:"curve_tangent"
    |> (Sop.sweep_circle ~use_sides:true ~use_max_valence:false ~use_u_range:false ~use_v_range:false ~cap_group:"" ~sides:(12) ~radius:(0.16))
    |> Sop.polyframe ~orthogonal:true ~style:Sop.Style_attribute_gradient ~style_attribute:"uv"
    |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:(Vec3.create (34. /. 255.) (211. /. 255.) (238. /. 255.))
  and tiles =
    Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:4 ~rows:3 ~size:2.8 ()
    |> Sop.mountain ~seed:222 ~height:0.16
         ~frequency:(Vec3.create 1.2 0.8 1.2) ~octaves:4
    |> Sop.group_random ~seed:221 ~probability:0.1
         ~owner:Rdk.Group_ops.Group_points ~name:"growth_seeds"
    |> Sop.group_edge_depth ~depth:1 ~point_group:"growth_seeds"
         ~name:"growth_points"
    |> Sop.peak ~direction_attribute:("") ~group_owner:Sop.Element_point ~group:"growth_points" ~distance:0.015
         ~recompute_normals:true
    |> Sop.group_random ~seed:223 ~probability:0.42
         ~owner:Rdk.Group_ops.Group_primitives ~name:"raised_tiles"
    |> Sop.group_bounds ~base:"raised_tiles"
         ~containment:Rdk.Group_ops.Partially_contained
         ~shape:Sop.Sphere ~center:Vec3.zero ~radius:1.35
         ~owner:Rdk.Group_ops.Group_primitives ~name:"raised_tiles"
    |> Sop.group_normal ~use_existing_normal:false ~base:"raised_tiles"
         ~direction:Vec3.unit_y
         ~spread_angle:(Float.pi /. 3.) ~owner:Rdk.Group_ops.Group_primitives
         ~name:"raised_tiles"
    |> Sop.group_backface ~merge:Rdk.Group_ops.Group_subtract
         ~viewpoint:(Vec3.create 0. 4. 5.) ~name:"raised_tiles"
    |> Sop.peak ~direction_attribute:("") ~group_owner:Sop.Element_primitive ~group:"raised_tiles" ~distance:0.04
    |> Sop.poly_extrude ~group:"raised_tiles"
         ~divide:Rdk.Poly_extrude.Extrude_connected_components ~divisions:3
         ~front_group:"tile_fronts" ~side_group:"tile_sides"
         ~front_boundary_group:"tile_rims" ~distance:0.28
    |> Sop.facet ~cusp_mode:Procedural.Sop.Kernel_auto ~inline_distance:0. ~unique_points:true ~post_compute_normals:true
    |> Sop.measure ~total_attribute:"tile_surface_area" ~kind:Rdk.Analysis.Area
    |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:(Vec3.create (251. /. 255.) (113. /. 255.) (133. /. 255.))
    |> (let migration_translation = Vec3.create 1.5 0. 0. in
fun migration_input ->
  Sop.transform ~mode:Sop.Transform_matrix ~m03:migration_translation.Vec3.x
    ~m13:migration_translation.Vec3.y ~m23:migration_translation.Vec3.z
    migration_input)
  and copies =
    let prototype = Sop.box ~normals:None ~connectivity:Rdk.Box_generator.Box_quads
        ~consolidate_points:true ~size:(Vec3.create 0.28 0.62 0.2) ()
        |> Sop.facet ~inline_distance:0. ~cusp_angle:0.6 ~post_compute_normals:true
        |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:(Vec3.create (250. /. 255.) (204. /. 255.) (21. /. 255.)) in
    let targets = Array.init 18 (fun index ->
      let angle = float_of_int index *. 0.72 in
      (2.4 *. cos angle, 0.35 +. (float_of_int index *. 0.12),
       2.4 *. sin angle)) in
    (Sop.copy_to_points prototype
  (((Sop.points targets) |>
      (fun migration_input -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete ~kind:Sop.Numeric_scalar ~entries:(String.concat "\n" [String.concat "\t" [Printf.sprintf "%.17g" (0.45);Printf.sprintf "%.17g" (1.)];String.concat "\t" [Printf.sprintf "%.17g" (0.65);Printf.sprintf "%.17g" (3.)];String.concat "\t" [Printf.sprintf "%.17g" (0.9);Printf.sprintf "%.17g" (1.)]]) ~seed:(301) ~owner:(Rdk.Attribute.Point) ~name:("pscale") migration_input))
     |>
     (fun migration_input -> Sop.attribute_randomize ~distribution:Sop.Random_direction ~kind:Sop.Numeric_vec4 ~a:(Vec3.create (0.) (0.) (0.)) ~a_w:(1.) ~cone_angle:(Float.pi *. 0.8) ~seed:(302) ~owner:(Rdk.Attribute.Point) ~direction_bias:(0.8) ~name:("orient") migration_input)))
    |> Sop.connectivity ~name:"copy_piece"
         ~output:Sop.Text ~text_prefix:"copy_"
    |> Sop.groups_from_name ~owner:Rdk.Attribute.Primitive
         ~attribute:"copy_piece"
  in
  [tube; tiles; copies]

let init frame =
  let session = Session.create ~max_entries:64
      ~max_payload_bytes:(128 * 1024 * 1024) |> Result.get_ok in
  let bridge = Sketch_support.Bridge.create ~max_entries:64
      ~max_payload_bytes:(128 * 1024 * 1024) session |> Result.get_ok in
  { session;
    meshes = List.map (cook bridge frame) (graphs ());
    camera = Easy_camera.create ~target:(Vec3.create 0. 0.5 0.)
        ~distance:9. ~azimuth:0.7 ~elevation:0.45 (); }

let update model frame =
  { model with camera = Easy_camera.update model.camera frame }

let view model _frame =
  let lights = [Light.directional ~direction:(Vec3.create (-1.) (-2.) (-1.)) ()] in
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
      title = "Rays Procedural Modeling" }
    ~init ~update ~view ~on_stop ())
