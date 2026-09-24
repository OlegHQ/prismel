open Prismel
open Geom

let scale =
  match Sys.getenv_opt "PRISMEL_BENCH_SCALE" with
  | None -> 1
  | Some value -> max 1 (int_of_string value)

let domains = match Sys.getenv_opt "PRISMEL_BENCH_DOMAINS" with
  | None -> Parallel.recommended_domains ()
  | Some value -> max 1 (int_of_string value)
let repeats = match Sys.getenv_opt "PRISMEL_BENCH_REPEATS" with
  | None -> 5
  | Some value -> max 1 (int_of_string value)
let sink = ref 0

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let measure name input operation =
  let execute () = Parallel.run ~domains operation in
  let expected = execute () in
  sink := !sink lxor expected;
  let seconds = Array.make repeats 0.
  and allocated_bytes = Array.make repeats 0.
  and promoted_bytes = Array.make repeats 0.
  and major_bytes = Array.make repeats 0. in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.quick_stat () in
    let allocated_before = Gc.allocated_bytes () in
    let started = Unix.gettimeofday () in
    let cardinality = execute () in
    seconds.(repeat) <- Unix.gettimeofday () -. started;
    allocated_bytes.(repeat) <- Gc.allocated_bytes () -. allocated_before;
    let after = Gc.quick_stat () in
    promoted_bytes.(repeat) <-
      (after.Gc.promoted_words -. before.promoted_words) *. 8.;
    major_bytes.(repeat) <-
      (after.Gc.major_words -. before.major_words) *. 8.;
    if cardinality <> expected then
      failwith (name ^ ": output cardinality changed between repeats");
    sink := !sink lxor cardinality
  done;
  Printf.printf "%s,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d\n%!"
    name input domains repeats (median seconds) (median allocated_bytes)
    (median promoted_bytes) (median major_bytes) expected

let deterministic_points count =
  let generator = ref (Rand.seed 0x5eed) in
  List.init count (fun _ ->
    let x, next = Rand.range ~min:0. ~max:1000. !generator in
    let y, next = Rand.range ~min:0. ~max:1000. next in
    generator := next;
    Vec2.create x y)

let deterministic_points3 count =
  let generator = ref (Rand.seed 0x51a7) in
  List.init count (fun _ ->
    let x, next = Rand.range ~min:0. ~max:1023.999 !generator in
    let y, next = Rand.range ~min:0. ~max:1023.999 next in
    let z, next = Rand.range ~min:0. ~max:1023.999 next in
    generator := next;
    Vec3.create x y z)

let () =
  Parallel.run ~domains (fun () -> ());
  Printf.printf "benchmark,input,domains,repeats,median_seconds,median_allocated_bytes,median_promoted_bytes,median_major_bytes,output\n%!";
  let sphere_segments = 192 * scale and sphere_rings = 96 * scale in
  measure "mesh_sphere" (sphere_segments * sphere_rings) (fun () ->
    let mesh = Mesh.sphere ~segments:sphere_segments ~rings:sphere_rings
        ~radius:100. () in
    Mesh.vertex_count mesh + Mesh.index_count mesh);

  let iso_resolution = 40 * scale in
  measure "iso_gyroid" (iso_resolution * iso_resolution * iso_resolution)
    (fun () ->
      match Iso3.extract_dense ~smooth:true
          ~resolution:(iso_resolution, iso_resolution, iso_resolution)
          ~min:(Vec3.create (-3.) (-3.) (-3.))
          ~max:(Vec3.create 3. 3. 3.) ~iso:0.
          ~field:(Iso3.Field.gyroid ~scale:1.25 ()) () with
      | Ok mesh -> Mesh.vertex_count mesh
      | Error message -> failwith message);

  let delaunay_count = 1_500 * scale in
  let points = deterministic_points delaunay_count in
  measure "delaunay" delaunay_count (fun () ->
    Delaunay2.triangulate points |> List.length);

  let tree_count = 50_000 * scale in
  let tree_points = deterministic_points tree_count in
  measure "quadtree_build_query" tree_count (fun () ->
    let entries = List.mapi (fun index point -> point,index) tree_points in
    let bounds = Bounds2.make ~min:Vec2.zero ~max:(Vec2.create 1000. 1000.) in
    let tree = Quadtree.of_list bounds entries |> Result.get_ok in
    Quadtree.query_circle ~center:(Vec2.create 500. 500.) ~radius:250. tree
    |> List.length);

  let cloth_width = 256 * scale and cloth_height = 128 * scale in
  let particle_count = cloth_width * cloth_height in
  let particles = List.init particle_count (fun index ->
    Verlet2.particle (Vec2.create
      (float_of_int (index mod cloth_width))
      (float_of_int (index / cloth_width)))) in
  let springs = List.init (particle_count - 1) (fun index ->
    Verlet2.spring ~rest_length:1. index (index + 1)) in
  let world = Verlet2.create ~iterations:2 particles springs |> Result.get_ok in
  measure "verlet2_step" particle_count (fun () ->
    let world = Verlet2.step ~dt:(1. /. 60.) world in
    Verlet2.particle_count world);

  let transform_vertices = 200_000 * scale in
  let mesh = Mesh.create_exn ~mode:Mesh.Points
      (List.init transform_vertices (fun index ->
         let value = float_of_int index in
         Vec3.create value (sin value) (cos value))) in
  measure "mesh_transform" transform_vertices (fun () ->
    Mesh.transformed
      (Mat4.mul (Mat4.translation (Vec3.create 1. 2. 3.))
         (Mat4.rotation ~axis:(Vec3.create 1. 2. 3.) 0.75)) mesh
    |> Mesh.vertex_count);

  let weld_vertices = 200_000 * scale in
  let weld_source =
    Mesh.create_exn ~mode:Mesh.Points
      (List.init weld_vertices (fun index ->
         let source = index / 2 in
         let offset = if index land 1 = 0 then 0. else 1e-7 in
         Vec3.create (float_of_int source +. offset)
           (float_of_int (source mod 997))
           (float_of_int (source mod 101))))
  in
  measure "mesh_weld" weld_vertices (fun () ->
    Mesh.merge_duplicate_vertices ~epsilon:1e-6 weld_source
    |> Mesh.vertex_count);
  measure "mesh_repair_weld_pdk" weld_vertices (fun () ->
    Mesh_repair.weld ~epsilon:1e-6 weld_source |> Mesh.vertex_count);

  let lathe_profile_count = 512 * scale in
  let lathe_profile =
    Curve2.create_exn
      (List.init lathe_profile_count (fun index ->
         let t = float_of_int index /. float_of_int (lathe_profile_count - 1) in
         Vec2.create (1. +. (0.25 *. sin (t *. 8. *. Float.pi)))
           ((t *. 20.) -. 10.))) in
  let lathe_segments = 192 in
  measure "mesh3_lathe" (lathe_profile_count * lathe_segments) (fun () ->
    match Mesh3.lathe ~segments:lathe_segments ~capped:true lathe_profile with
    | Ok mesh -> Mesh.vertex_count mesh + Mesh.index_count mesh
    | Error message -> failwith message);

  let sweep_profile_count = 64 * scale
  and sweep_spine_count = 1_024 * scale in
  let sweep_profile =
    Polygon2.regular ~center:Vec2.zero ~radius:1.
      ~sides:sweep_profile_count ()
  and sweep_spine =
    List.init sweep_spine_count (fun index ->
      let t = float_of_int index *. 0.02 in
      Vec3.create (cos t *. 5.) (sin t *. 5.) (t *. 2.)) in
  measure "mesh3_sweep" (sweep_profile_count * sweep_spine_count) (fun () ->
    match Mesh3.sweep ~capped:true ~profile:sweep_profile ~spine:sweep_spine () with
    | Ok mesh -> Mesh.vertex_count mesh + Mesh.index_count mesh
    | Error message -> failwith message);

  let topology_source = Mesh.icosphere ~subdivisions:3 ~radius:10. () in
  measure "mesh_topology" (Mesh.Private.triangle_count topology_source)
    (fun () ->
      let topology = Mesh_topology.of_mesh topology_source in
      List.length (Mesh_topology.edges topology));
  measure "loop_subdivide" (Mesh.Private.triangle_count topology_source)
    (fun () ->
      match Mesh3.loop_subdivide topology_source with
      | Ok mesh -> Mesh.vertex_count mesh + Mesh.index_count mesh
      | Error message -> failwith message);
  measure "butterfly_subdivide" (Mesh.Private.triangle_count topology_source)
    (fun () ->
      match Mesh3.butterfly_subdivide topology_source with
      | Ok mesh -> Mesh.vertex_count mesh + Mesh.index_count mesh
      | Error message -> failwith message);
  measure "catmull_clark" (Mesh.Private.triangle_count topology_source)
    (fun () ->
      match Mesh3.catmull_clark topology_source with
      | Ok mesh -> Mesh.vertex_count mesh + Mesh.index_count mesh
      | Error message -> failwith message);
  measure "doo_sabin" (Mesh.Private.triangle_count topology_source)
    (fun () ->
      match Mesh3.doo_sabin topology_source with
      | Ok mesh -> Mesh.vertex_count mesh + Mesh.index_count mesh
      | Error message -> failwith message);
  measure "mesh_repair_analyze" (Mesh.Private.triangle_count topology_source)
    (fun () ->
      let report = Mesh_repair.analyze topology_source in
      report.faces + report.components
      + List.length report.boundary_edges
      + List.length report.non_manifold_edges);
  let t_face_count = 10_000 * scale in
  let t_vertices = Array.make (t_face_count * 4) Vec3.zero
  and t_indices = Array.make (t_face_count * 3) 0 in
  for face = 0 to t_face_count - 1 do
    let vertex = face * 4 and index = face * 3 in
    let x = float_of_int (face mod 100) *. 3.
    and y = float_of_int (face / 100) *. 3. in
    t_vertices.(vertex) <- Vec3.create x y 0.;
    t_vertices.(vertex + 1) <- Vec3.create (x +. 2.) y 0.;
    t_vertices.(vertex + 2) <- Vec3.create x (y +. 2.) 0.;
    t_vertices.(vertex + 3) <- Vec3.create (x +. 1.) y 0.;
    t_indices.(index) <- vertex;
    t_indices.(index + 1) <- vertex + 1;
    t_indices.(index + 2) <- vertex + 2
  done;
  let t_source =
    Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices:t_indices t_vertices
    |> Result.get_ok
  in
  measure "mesh_repair_t_junctions" t_face_count (fun () ->
    Mesh_repair.repair_t_junctions t_source
    |> Result.get_ok
    |> Mesh.Private.triangle_count);

  let csg_left = Mesh.sphere ~segments:18 ~rings:10 ~radius:2. ()
  and csg_right =
    Mesh.box ~width:2.5 ~height:2.5 ~depth:2.5 ()
    |> Mesh.transformed (Mat4.translation (Vec3.create 0.8 0. 0.)) in
  measure "csg_intersection"
    (Mesh.Private.triangle_count csg_left
     + Mesh.Private.triangle_count csg_right)
    (fun () ->
      match Csg3.intersection csg_left csg_right with
      | Ok mesh -> Mesh.Private.triangle_count mesh
      | Error message -> failwith message);
  let dense_csg_left = Mesh.sphere ~segments:36 ~rings:18 ~radius:2. ()
  and dense_csg_right =
    Mesh.sphere ~segments:36 ~rings:18 ~radius:2. ()
    |> Mesh.transformed (Mat4.translation (Vec3.create 0.75 0. 0.)) in
  measure "csg_dense_intersection"
    (Mesh.Private.triangle_count dense_csg_left
     + Mesh.Private.triangle_count dense_csg_right)
    (fun () ->
      match Csg3.intersection dense_csg_left dense_csg_right with
      | Ok mesh -> Mesh.Private.triangle_count mesh
      | Error message -> failwith message);

  let voxel_size = 64 * scale in
  measure "voxel_init" (voxel_size * voxel_size * voxel_size) (fun () ->
    Voxel3.init ~origin:Vec3.zero
      ~dimensions:(voxel_size, voxel_size, voxel_size) ~voxel_size:1.
      ~occupied:(fun (x, y, z) ->
        let dx = x - (voxel_size / 2)
        and dy = y - (voxel_size / 2)
        and dz = z - (voxel_size / 2) in
        (dx * dx) + (dy * dy) + (dz * dz)
        <= (voxel_size * voxel_size / 9))
    |> Voxel3.count);
  let surface_voxels = Voxel3.init ~origin:Vec3.zero
      ~dimensions:(48, 48, 48) ~voxel_size:1.
      ~occupied:(fun (x, y, z) ->
        x >= 8 && x < 40 && y >= 8 && y < 40 && z >= 8 && z < 40) in
  measure "voxel_surface_mesh" (Voxel3.count surface_voxels) (fun () ->
      match Voxel3.surface_mesh surface_voxels with
      | Ok mesh -> Mesh.vertex_count mesh
      | Error message -> failwith message);
  let svo_count = 100_000 * scale in
  let svo_points = deterministic_points3 svo_count in
  measure "svo_build_depth_query" svo_count (fun () ->
    match Svo3.of_points ~origin:Vec3.zero ~size:1024. ~precision:1. svo_points with
    | Error message -> failwith message
    | Ok tree ->
        List.fold_left
          (fun total point ->
            total + Option.value ~default:(-1) (Svo3.depth_at point tree))
          0 (List.filteri (fun index _ -> index mod 100 = 0) svo_points));
  if !sink = min_int then Printf.eprintf "unreachable\n"
