open Prismel
open Geom

let fail message = raise (Failure message)

let assert_float ?(epsilon = 1e-8) message expected actual =
  if abs_float (expected -. actual) > epsilon then
    fail
      (Printf.sprintf "%s: expected %.12g, got %.12g"
         message expected actual)

let assert_vec ?epsilon message expected actual =
  assert_float ?epsilon (message ^ " x") expected.Vec2.x actual.Vec2.x;
  assert_float ?epsilon (message ^ " y") expected.y actual.y

let assert_vec3 ?epsilon message expected actual =
  assert_float ?epsilon (message ^ " x") expected.Vec3.x actual.Vec3.x;
  assert_float ?epsilon (message ^ " y") expected.y actual.y;
  assert_float ?epsilon (message ^ " z") expected.z actual.z

let vec x y = Vec2.create x y

let triangle_area
    ((a : Vec2.t), (b : Vec2.t), (c : Vec2.t)) =
  abs_float
    (((b.Vec2.x -. a.x) *. (c.y -. a.y))
     -. ((b.y -. a.y) *. (c.x -. a.x)))
  /. 2.

let test_affine () =
  let transform =
    Affine2.compose
      (Affine2.translation (vec 4. (-2.)))
      (Affine2.rotation (Float.pi /. 2.))
  in
  let point = Affine2.apply transform (vec 2. 1.) in
  assert_vec "affine composition" (vec 3. 0.) point;
  match Affine2.inverse transform with
  | None -> fail "invertible affine transform returned no inverse"
  | Some inverse ->
      assert_vec "affine inverse" (vec 2. 1.) (Affine2.apply inverse point)

let test_bounds () =
  let bounds =
    Bounds2.of_points [vec 4. 2.; vec (-1.) 8.; vec 2. (-3.)]
    |> Option.get
  in
  assert_vec "bounds minimum" (vec (-1.) (-3.)) bounds.min;
  assert_vec "bounds maximum" (vec 4. 8.) bounds.max;
  assert_float "bounds width" 5. (Bounds2.width bounds);
  assert_float "bounds height" 11. (Bounds2.height bounds);
  if not (Bounds2.contains bounds (vec 0. 0.)) then
    fail "bounds should contain an interior point"

let test_segments () =
  let left = Segment2.make (vec 0. 0.) (vec 4. 4.)
  and right = Segment2.make (vec 0. 4.) (vec 4. 0.) in
  (match Segment2.intersect left right with
   | Segment2.Point { point; along_self; along_other } ->
       assert_vec "segment intersection" (vec 2. 2.) point;
       assert_float "segment self parameter" 0.5 along_self;
       assert_float "segment other parameter" 0.5 along_other
   | _ -> fail "crossing segments did not return a point");
  match
    Segment2.intersect
      (Segment2.make (vec 0. 0.) (vec 1. 0.))
      (Segment2.make (vec 0. 1.) (vec 1. 1.))
  with
  | Segment2.Parallel -> ()
  | _ -> fail "parallel segments were not classified as parallel"

let test_circles () =
  let left = Circle2.make ~center:(vec 0. 0.) ~radius:5.
  and right = Circle2.make ~center:(vec 8. 0.) ~radius:5. in
  match Circle2.intersections left right with
  | [upper; lower] ->
      assert_float "circle intersection x" 4. upper.x;
      assert_float "circle intersection upper y" 3. upper.y;
      assert_float "circle intersection lower y" (-3.) lower.y
  | _ -> fail "two intersecting circles should have two intersections"

let square =
  Polygon2.create_exn
    [vec 0. 0.; vec 10. 0.; vec 10. 10.; vec 0. 10.]

let test_polygon_queries () =
  assert_float "polygon area" 100. (Polygon2.area square);
  assert_float "polygon perimeter" 40. (Polygon2.perimeter square);
  assert_vec "polygon centroid" (vec 5. 5.) (Polygon2.centroid square);
  if not (Polygon2.contains square (vec 3. 4.)) then
    fail "polygon should contain an interior point";
  if Polygon2.contains square (vec 12. 4.) then
    fail "polygon should not contain an exterior point";
  assert_vec "polygon arc-length point" (vec 10. 0.)
    (Polygon2.point_at square 0.25);
  let samples = Polygon2.sample_uniform ~distance:3. square in
  if List.length samples <> 14 then
    fail "uniform polygon sampling returned an unexpected sample count"

let test_polygon_algorithms () =
  let hull =
    Polygon2.convex_hull
      [vec 0. 0.; vec 10. 0.; vec 5. 5.; vec 10. 10.; vec 0. 10.;
       vec 3. 7.]
    |> Option.get
  in
  if Polygon2.vertex_count hull <> 4 then
    fail "convex hull retained interior points";
  assert_float "convex hull area" 100. (Polygon2.area hull);
  let clip =
    Polygon2.create_exn
      [vec 5. (-2.); vec 12. (-2.); vec 12. 8.; vec 5. 8.]
  in
  let clipped = Polygon2.clip_convex ~subject:square ~clip |> Option.get in
  assert_float "convex clipping area" 40. (Polygon2.area clipped);
  let inset =
    match Polygon2.inset ~distance:2. square with
    | Ok value -> value
    | Error message -> fail message
  in
  assert_float "polygon inset area" 36. (Polygon2.area inset);
  let concave =
    Polygon2.create_exn
      [vec 0. 0.; vec 8. 0.; vec 8. 3.; vec 3. 3.; vec 3. 8.; vec 0. 8.]
  in
  let triangles =
    match Polygon2.triangulate concave with
    | Ok value -> value
    | Error message -> fail message
  in
  if List.length triangles <> Polygon2.vertex_count concave - 2 then
    fail "ear clipping returned the wrong triangle count";
  assert_float "triangulation preserves area" (Polygon2.area concave)
    (List.fold_left
       (fun total triangle -> total +. triangle_area triangle)
       0. triangles)

let test_polygon_generators () =
  let regular =
    Polygon2.regular ~center:Vec2.zero ~radius:2. ~sides:7 ()
  and star =
    Polygon2.star ~center:Vec2.zero ~inner_radius:1. ~outer_radius:2.
      ~points:6 ()
  and cog =
    Polygon2.cog ~center:Vec2.zero ~radius:2. ~teeth:8
      ~profile:[0.75; 1.; 1.; 0.75] ()
  in
  if Polygon2.vertex_count regular <> 7 then fail "regular polygon count";
  if Polygon2.vertex_count star <> 12 then fail "star polygon count";
  if Polygon2.vertex_count cog <> 32 then fail "cog polygon count"

let test_curves () =
  let open_curve =
    Curve2.create_exn [vec 0. 0.; vec 10. 0.; vec 10. 10.]
  in
  assert_float "curve length" 20. (Curve2.length open_curve);
  assert_vec "curve arc-length midpoint" (vec 10. 0.)
    (Curve2.point_at open_curve 0.5);
  let sampled = Curve2.sample_uniform ~distance:6. open_curve in
  if List.length sampled <> 5 then
    fail "open curve uniform sample count";
  assert_vec "open curve final sample" (vec 10. 10.) (List.hd (List.rev sampled));
  let chaikin = Curve2.chaikin ~iterations:2 open_curve in
  assert_vec "Chaikin retained start" (vec 0. 0.)
    (List.hd (Curve2.points chaikin));
  assert_vec "Chaikin retained end" (vec 10. 10.)
    (List.hd (List.rev (Curve2.points chaikin)));
  let closed =
    Polygon2.vertices square |> Curve2.create_exn ~closed:true
  in
  if Curve2.point_count (Curve2.chaikin closed) <> 8 then
    fail "closed Chaikin subdivision did not double vertex count";
  if Curve2.point_count (Curve2.cubic_subdivide closed) <> 8 then
    fail "closed cubic subdivision did not double vertex count";
  let bezier =
    Curve2.cubic_bezier ~resolution:10
      ~from_:(vec 0. 0.) ~control1:(vec 2. 8.)
      ~control2:(vec 8. 8.) ~to_:(vec 10. 0.) ()
  in
  if Curve2.point_count bezier <> 11 then fail "cubic Bezier resolution";
  assert_vec "Bezier start" (vec 0. 0.) (List.hd (Curve2.points bezier));
  assert_vec "Bezier end" (vec 10. 0.)
    (List.hd (List.rev (Curve2.points bezier)));
  let spline =
    match
      Curve2.catmull_rom ~resolution:5
        [vec 0. 0.; vec 5. 10.; vec 10. 0.]
    with
    | Ok curve -> curve
    | Error message -> fail message
  in
  if Curve2.point_count spline <> 11 then fail "Catmull-Rom resolution";
  assert_vec "Catmull-Rom interpolation" (vec 5. 10.)
    (List.nth (Curve2.points spline) 5);
  let formula =
    Curve2.superformula ~center:Vec2.zero ~radius:4.
      ~m:6. ~n1:1. ~n2:1. ~n3:1. ~resolution:120 ()
  in
  if not (Curve2.closed formula) || Curve2.point_count formula <> 120 then
    fail "superformula topology"

let test_delaunay_and_voronoi () =
  let points =
    [vec 0. 0.; vec 10. 0.; vec 10. 10.; vec 0. 10.; vec 5. 5.;
     vec 5. 5.]
  in
  let triangles = Delaunay2.triangulate points in
  if List.length triangles <> 4 then
    fail
      (Printf.sprintf "Delaunay triangle count: expected 4, got %d"
         (List.length triangles));
  if List.exists (fun triangle -> Delaunay2.area triangle <= 0.) triangles then
    fail "Delaunay triangles must be counter-clockwise";
  assert_float "Delaunay covers hull" 100.
    (List.fold_left
       (fun total triangle -> total +. Delaunay2.area triangle)
       0. triangles);
  if List.length (Delaunay2.unique_edges triangles) <> 8 then
    fail "Delaunay unique edge count";
  if List.length (Delaunay2.boundary_edges triangles) <> 4 then
    fail "Delaunay boundary edge count";
  let bounds = Bounds2.make ~min:(vec 0. 0.) ~max:(vec 10. 10.) in
  let cells = Delaunay2.voronoi_cells ~bounds points in
  if List.length cells <> 5 then fail "Voronoi duplicate site removal";
  List.iter
    (fun (cell : Delaunay2.cell) ->
      if not (Polygon2.contains cell.polygon cell.site) then
        fail "Voronoi cell did not contain its site")
    cells;
  assert_float ~epsilon:1e-7 "Voronoi cells cover bounds" 100.
    (List.fold_left
       (fun total (cell : Delaunay2.cell) ->
         total +. Polygon2.area cell.polygon)
       0. cells);
  let generator = ref (Rand.seed 0xd31a) in
  let random_points = List.init 200 (fun _ ->
    let x, next = Rand.range ~min:(-100.) ~max:100. !generator in
    let y, next = Rand.range ~min:(-100.) ~max:100. next in
    generator := next;
    vec x y) in
  let random_triangles = Delaunay2.triangulate random_points in
  if random_triangles <> Delaunay2.triangulate random_points then
    fail "Delaunay triangulation was not deterministic";
  let hull = Polygon2.convex_hull random_points |> Option.get in
  let expected_triangles =
    (2 * List.length random_points) - 2 - Polygon2.vertex_count hull in
  if List.length random_triangles <> expected_triangles then
    fail (Printf.sprintf
      "Delaunay Euler count: expected %d, got %d"
      expected_triangles (List.length random_triangles));
  assert_float ~epsilon:1e-6 "Delaunay random hull coverage"
    (Polygon2.area hull)
    (List.fold_left
       (fun total triangle -> total +. Delaunay2.area triangle)
       0. random_triangles);
  List.iter
    (fun triangle ->
      match Delaunay2.circumcenter triangle with
      | None -> fail "Delaunay produced a degenerate triangle"
      | Some center ->
          let a, _, _ = Delaunay2.vertices triangle in
          let radius_sq = Vec2.length_sq (Vec2.sub a center) in
          let tolerance = 1e-7 *. Float.max 1. radius_sq in
          if List.exists (fun point ->
              Vec2.length_sq (Vec2.sub point center)
              < radius_sq -. tolerance) random_points
          then fail "Delaunay empty-circumcircle invariant failed")
    random_triangles

let result_or_fail = function
  | Ok value -> value
  | Error message -> fail message

let assert_outward name mesh =
  match Mesh.centroid mesh with
  | None -> fail (name ^ " has no centroid")
  | Some center ->
      List.iter
        (fun (face : Mesh.face) ->
          let a, b, c = face.points in
          let face_center =
            Vec3.scale (Vec3.add a (Vec3.add b c)) (1. /. 3.)
          in
          let facing =
            Vec3.dot face.face_normal (Vec3.sub face_center center)
          in
          if facing < -.1e-8 then
            fail
              (Printf.sprintf
                 "%s contains an inward-facing triangle (dot %.6g)"
                 name facing))
        (Mesh.faces mesh)

let test_mesh_generation () =
  let extrusion =
    Mesh3.extrude ~depth:2. square |> result_or_fail
  in
  if List.length (Mesh.faces extrusion) <> 12 then
    fail "extrusion should produce eight side and four cap triangles";
  assert_outward "extrusion" extrusion;
  let z_values =
    Mesh.vertices extrusion |> List.map (fun point -> point.Vec3.z)
  in
  assert_float "extrusion minimum z" (-1.)
    (List.fold_left Float.min infinity z_values);
  assert_float "extrusion maximum z" 1.
    (List.fold_left Float.max neg_infinity z_values);
  let lathe_profile =
    Curve2.create_exn [vec 1. (-1.); vec 1. 1.]
  in
  let lathe =
    Mesh3.lathe ~segments:8 ~capped:true lathe_profile
    |> result_or_fail
  in
  if List.length (Mesh.faces lathe) <> 32 then
    fail "capped eight-segment lathe triangle count";
  assert_outward "lathe" lathe;
  if not (Mesh.has_normals lathe) || not (Mesh.has_tex_coords lathe) then
    fail "lathe should generate normals and texture coordinates";
  let profile =
    Polygon2.regular ~center:Vec2.zero ~radius:0.5 ~sides:4 ()
  in
  let swept =
    Mesh3.sweep ~profile
      ~spine:[
        Vec3.create 0. 0. 0.;
        Vec3.create 0. 0. 2.;
        Vec3.create 0. 0. 4.;
      ]
      ()
    |> result_or_fail
  in
  if List.length (Mesh.faces swept) <> 20 then
    fail "swept quad profile triangle count";
  assert_outward "sweep" swept;
  let source =
    Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0; 1; 2]
      ~colors:[Color.red; Color.green; Color.blue]
      ~tex_coords:[vec 0. 0.; vec 1. 0.; vec 0. 1.]
      [
        Vec3.create 0. 0. 0.;
        Vec3.create 1. 0. 0.;
        Vec3.create 0. 1. 0.;
      ]
  in
  let subdivided = Mesh3.loop_subdivide source |> result_or_fail in
  if Mesh.vertex_count subdivided <> 6 then
    fail "Loop subdivision edge vertex count";
  if List.length (Mesh.faces subdivided) <> 4 then
    fail "Loop subdivision face count";
  if List.length (Mesh.colors subdivided) <> 6
     || List.length (Mesh.tex_coords subdivided) <> 6
  then fail "Loop subdivision did not preserve vertex attributes"
  else assert_outward "Loop subdivision" subdivided;
  let sphere =
    Mesh.icosahedron ~radius:1.
    |> Mesh3.loop_subdivide
    |> result_or_fail
  in
  if List.length (Mesh.faces sphere) <> 80 then
    fail "Loop subdivision should split every icosahedron face into four";
  assert_outward "subdivided icosahedron" sphere;
  let interpolated = Mesh3.butterfly_subdivide source |> result_or_fail in
  if Mesh.vertex_count interpolated <> 6
     || List.length (Mesh.faces interpolated) <> 4
  then fail "Butterfly subdivision topology";
  assert_vec3 "Butterfly retains old vertices"
    (Mesh.vertex 0 source |> Option.get)
    (Mesh.vertex 0 interpolated |> Option.get);
  if List.length (Mesh.colors interpolated) <> 6 then
    fail "Butterfly subdivision lost colors";
  let catmull = Mesh3.catmull_clark source |> result_or_fail in
  if Mesh.vertex_count catmull <> 7
     || List.length (Mesh.faces catmull) <> 6
  then fail "Catmull-Clark triangle topology";
  if List.length (Mesh.tex_coords catmull) <> 7 then
    fail "Catmull-Clark lost texture coordinates";
  let doo_open = Mesh3.doo_sabin source |> result_or_fail in
  if Mesh.vertex_count doo_open <> 3
     || List.length (Mesh.faces doo_open) <> 1
  then fail "Doo-Sabin open-face topology";
  let icosahedron = Mesh.icosahedron ~radius:1. in
  let butterfly_sphere = Mesh3.butterfly_subdivide icosahedron |> result_or_fail
  and catmull_sphere = Mesh3.catmull_clark icosahedron |> result_or_fail
  and doo_sphere = Mesh3.doo_sabin icosahedron |> result_or_fail in
  if Mesh.vertex_count butterfly_sphere <> 42
     || List.length (Mesh.faces butterfly_sphere) <> 80
  then fail (Printf.sprintf "Butterfly icosahedron topology: %d vertices, %d faces"
    (Mesh.vertex_count butterfly_sphere) (List.length (Mesh.faces butterfly_sphere)));
  if Mesh.vertex_count catmull_sphere <> 62
     || List.length (Mesh.faces catmull_sphere) <> 120
  then fail (Printf.sprintf "Catmull-Clark icosahedron topology: %d vertices, %d faces"
    (Mesh.vertex_count catmull_sphere) (List.length (Mesh.faces catmull_sphere)));
  if Mesh.vertex_count doo_sphere <> 60
     || List.length (Mesh.faces doo_sphere) <> 116
  then fail (Printf.sprintf "Doo-Sabin icosahedron topology: %d vertices, %d faces"
    (Mesh.vertex_count doo_sphere) (List.length (Mesh.faces doo_sphere)));
  let deterministic name operation =
    let run domains =
      Parallel.run ~domains (fun () -> operation icosahedron |> result_or_fail)
    in
    if Mesh.Private.view (run 1) <> Mesh.Private.view (run 4) then
      fail (name ^ " subdivision differed between one and four domains")
  in
  deterministic "Loop" Mesh3.loop_subdivide;
  deterministic "Butterfly" Mesh3.butterfly_subdivide;
  deterministic "Catmull-Clark" Mesh3.catmull_clark;
  deterministic "Doo-Sabin" Mesh3.doo_sabin;
  assert_outward "Butterfly icosahedron" butterfly_sphere;
  assert_outward "Catmull-Clark icosahedron" catmull_sphere;
  assert_outward "Doo-Sabin icosahedron" doo_sphere

let test_isosurfaces () =
  let minimum = Vec3.create (-1.4) (-1.4) (-1.4)
  and maximum = Vec3.create 1.4 1.4 1.4 in
  let field = Iso3.sphere ~center:Vec3.zero ~radius:1. in
  let extract () =
    Iso3.extract ~resolution:(10, 10, 10)
      ~min:minimum ~max:maximum ~iso:0. ~field ()
    |> result_or_fail
  in
  let surface = extract () in
  if Mesh.vertex_count surface = 0 || Mesh.faces surface = [] then
    fail "sphere isosurface was empty";
  if not (Mesh.has_normals surface) then
    fail "smooth isosurface did not include normals";
  assert_outward "sphere isosurface" surface;
  let repeated = extract () in
  if Mesh.vertices surface <> Mesh.vertices repeated then
    fail "isosurface extraction was not deterministic";
  let extract_with_domains domains =
    Parallel.run ~domains extract
  in
  let sequential = extract_with_domains 1
  and multicore = extract_with_domains 4 in
  if Mesh.Private.view sequential <> Mesh.Private.view multicore then
    fail "isosurface output differed between one and four domains";
  let packed = Parallel.run ~domains:4 (fun () ->
    Iso3.extract_dense ~resolution:(10, 10, 10)
      ~min:minimum ~max:maximum ~iso:0.
      ~field:(Iso3.Field.sphere ~center:Vec3.zero ~radius:1.) ()
    |> result_or_fail) in
  if Mesh.Private.view sequential <> Mesh.Private.view packed then
    fail "packed and Vec3 isosurface fields produced different geometry";
  let thin domains = Parallel.run ~domains (fun () ->
    Iso3.extract ~resolution:(9, 7, 1)
      ~min:(Vec3.create (-1.) (-1.) (-1.))
      ~max:(Vec3.create 1. 1. 1.) ~iso:0.
      ~field:(fun point -> point.Vec3.z) () |> result_or_fail) in
  let thin_one = thin 1 and thin_four = thin 4 in
  if Mesh.vertex_count thin_one = 0
     || Mesh.Private.view thin_one <> Mesh.Private.view thin_four
  then fail "single-Z-slab isosurface was empty or domain-dependent";
  (match Iso3.extract ~resolution:(3, 3, 3)
      ~min:(Vec3.create (-1.) (-1.) (-1.))
      ~max:(Vec3.create 1. 1. 1.) ~iso:0.
      ~field:(fun _ -> Float.nan) () with
   | Error _ -> ()
   | Ok _ -> fail "isosurface accepted a non-finite field sample");
  let sphere_with_domains domains =
    Parallel.run ~domains (fun () ->
      Mesh.sphere ~segments:48 ~rings:24 ~radius:1. ()
      |> Mesh.transformed
           (Mat4.mul
              (Mat4.translation (Vec3.create 1. 2. 3.))
              (Mat4.rotation_y 0.37)))
  in
  if Mesh.Private.view (sphere_with_domains 1)
     <> Mesh.Private.view (sphere_with_domains 4)
  then fail "generated mesh differed between one and four domains";
  let balls =
    [
      Iso3.metaball ~center:(Vec3.create (-0.4) 0. 0.) ~radius:0.8 ();
      Iso3.metaball ~center:(Vec3.create 0.4 0. 0.) ~radius:0.8 ();
    ]
  in
  if Iso3.metaballs balls Vec3.zero <= 1. then
    fail "metaball field should join overlapping balls";
  assert_float "gyroid origin" 0. (Iso3.gyroid Vec3.zero)

let test_extended_types_and_intersections () =
  let triangle2 = Triangle2.make (vec 0. 0.) (vec 4. 0.) (vec 0. 4.) in
  assert_float "triangle2 area" 8. (Triangle2.area triangle2);
  if not (Triangle2.contains triangle2 (vec 1. 1.)) then
    fail "Triangle2 should contain barycentric interior point";
  assert_vec "Triangle2 closest point" (vec 2. 2.)
    (Triangle2.closest_point triangle2 (vec 4. 4.));
  let ray2 = Ray2.make ~origin:(vec (-2.) 0.) ~direction:(vec 1. 0.) in
  let circle2 = Circle2.make ~center:(vec 2. 0.) ~radius:1. in
  (match Intersect2.ray_circle ray2 circle2 with
   | first :: second :: _ ->
       assert_float "ray-circle entry" 3. first.distance;
       assert_float "ray-circle exit" 5. second.distance
   | _ -> fail "ray-circle should return entry and exit");
  let segment = Segment2.make (vec 0. (-2.)) (vec 0. 2.) in
  (match Intersect2.ray_segment ray2 segment with
   | Some hit -> assert_vec "ray-segment point" Vec2.zero hit.point
   | None -> fail "ray should intersect segment");
  let box2 = Bounds2.make ~min:(vec (-1.) (-1.)) ~max:(vec 1. 1.) in
  (match Intersect2.ray_bounds ray2 box2 with
   | Some hit -> assert_float "ray-bounds entry" 1. hit.distance
   | None -> fail "ray should intersect 2D bounds");
  if not (Intersect2.polygon_polygon square
      (Polygon2.translate (vec 8. 8.) square))
  then fail "overlapping polygons were missed";

  let bounds3 = Bounds3.make
      ~min:(Vec3.create (-1.) (-2.) (-3.))
      ~max:(Vec3.create 3. 2. 1.) in
  assert_float "bounds3 volume" 64. (Bounds3.volume bounds3);
  assert_vec3 "bounds3 center" (Vec3.create 1. 0. (-1.))
    (Bounds3.center bounds3);
  let sphere3 = Sphere3.make ~center:Vec3.zero ~radius:1. in
  assert_float "sphere3 volume" (4. /. 3. *. Float.pi)
    (Sphere3.volume sphere3);
  let plane = Plane3.through ~normal:Vec3.unit_y ~point:Vec3.zero in
  assert_vec3 "plane projection" (Vec3.create 2. 0. 3.)
    (Plane3.project plane (Vec3.create 2. 5. 3.));
  let triangle3 = Triangle3.make
      (Vec3.create (-1.) (-1.) 0.)
      (Vec3.create 1. (-1.) 0.)
      (Vec3.create 0. 1. 0.) in
  assert_float "triangle3 area" 2. (Triangle3.area triangle3);
  let ray3 = Ray3.make ~origin:(Vec3.create 0. 0. 3.)
      ~direction:(Vec3.create 0. 0. (-1.)) in
  (match Intersect3.ray_triangle ray3 triangle3 with
   | Some hit ->
       assert_float "ray-triangle distance" 3. hit.distance;
       assert_vec3 "ray-triangle point" Vec3.zero hit.point;
       if Option.is_none hit.barycentric then fail "missing barycentric hit"
   | None -> fail "ray should intersect triangle");
  (match Intersect3.ray_sphere ray3 sphere3 with
   | first :: second :: _ ->
       assert_float "ray-sphere entry" 2. first.distance;
       assert_float "ray-sphere exit" 4. second.distance
   | _ -> fail "ray-sphere should return two hits");
  let unit_bounds = Bounds3.make
      ~min:(Vec3.create (-1.) (-1.) (-1.))
      ~max:(Vec3.create 1. 1. 1.) in
  (match Intersect3.ray_bounds ray3 unit_bounds with
   | Some hit -> assert_float "ray-bounds3 entry" 2. hit.distance
   | None -> fail "ray should intersect 3D bounds");
  if not (Intersect3.sphere_bounds sphere3 unit_bounds) then
    fail "sphere/bounds overlap was missed";
  if not (Intersect3.triangle_bounds triangle3 unit_bounds) then
    fail "triangle/bounds overlap was missed";
  let x_plane = Plane3.through ~normal:Vec3.unit_x
      ~point:(Vec3.create 1. 0. 0.)
  and y_plane = Plane3.through ~normal:Vec3.unit_y
      ~point:(Vec3.create 0. 2. 0.) in
  (match Intersect3.plane_plane x_plane y_plane with
   | Some line ->
       assert_float "plane-plane x" 1. line.origin.x;
       assert_float "plane-plane y" 2. line.origin.y;
       assert_float "plane-plane direction" 1.
         (abs_float line.direction.z)
   | None -> fail "orthogonal planes should intersect")

let test_spatial_trees () =
  let bounds2 = Bounds2.make ~min:(vec 0. 0.) ~max:(vec 100. 100.) in
  let empty2 = Quadtree.create ~capacity:1 bounds2 in
  let values2 =
    [vec 10. 10., "a"; vec 20. 20., "b"; vec 80. 80., "c";
     vec 75. 15., "d"; vec 50. 50., "e"] in
  let tree2 =
    Quadtree.of_list ~capacity:1 bounds2 values2
    |> result_or_fail
  in
  let persistent2 = List.fold_left (fun tree (point, value) ->
      Quadtree.insert_exn point value tree) empty2 values2 in
  let sorted2 entries =
    List.map (fun (entry : string Quadtree.entry) -> entry.value) entries
    |> List.sort String.compare in
  if sorted2 (Quadtree.entries tree2) <> sorted2 (Quadtree.entries persistent2)
  then fail "quadtree transient bulk build differed from persistent insertion";
  if Quadtree.size empty2 <> 0 || Quadtree.size tree2 <> 5 then
    fail "quadtree persistence or size";
  let selected2 =
    Quadtree.query_bounds
      (Bounds2.make ~min:(vec 0. 0.) ~max:(vec 25. 25.)) tree2
  in
  if List.length selected2 <> 2 then fail "quadtree range query";
  (match Quadtree.nearest (vec 77. 79.) tree2 with
   | Some entry when entry.value = "c" -> ()
   | _ -> fail "quadtree nearest query");
  if List.length (Quadtree.query_circle ~center:(vec 15. 15.)
      ~radius:8. tree2) <> 2
  then fail "quadtree circle query";
  let filtered2 = Quadtree.remove_if
      (fun (entry : string Quadtree.entry) -> entry.value = "b") tree2 in
  if Quadtree.size filtered2 <> 4 || Quadtree.size tree2 <> 5 then
    fail "quadtree persistent removal";
  (match Quadtree.insert (vec 101. 0.) "outside" tree2 with
   | Error _ -> ()
   | Ok _ -> fail "quadtree accepted an out-of-bounds point");

  let bounds3 = Bounds3.make
      ~min:(Vec3.create (-10.) (-10.) (-10.))
      ~max:(Vec3.create 10. 10. 10.) in
  let values3 =
      [
        Vec3.create (-5.) (-5.) (-5.), 1;
        Vec3.create 5. 5. 5., 2;
        Vec3.create 1. 1. 1., 3;
        Vec3.create (-2.) 4. 0., 4;
      ] in
  let tree3 =
    Octree.of_list ~capacity:1 bounds3 values3
    |> result_or_fail
  in
  let persistent3 = List.fold_left (fun tree (point, value) ->
      Octree.insert_exn point value tree)
      (Octree.create ~capacity:1 bounds3) values3 in
  let sorted3 entries =
    List.map (fun (entry : int Octree.entry) -> entry.value) entries
    |> List.sort Int.compare in
  if sorted3 (Octree.entries tree3) <> sorted3 (Octree.entries persistent3)
  then fail "octree transient bulk build differed from persistent insertion";
  if Octree.size tree3 <> 4 then fail "octree size";
  let selected3 = Octree.query_sphere ~center:Vec3.zero ~radius:2. tree3 in
  if List.map (fun (entry : int Octree.entry) -> entry.value) selected3 <> [3]
  then fail "octree sphere query";
  (match Octree.nearest (Vec3.create 4.8 5.1 5.2) tree3 with
   | Some entry when entry.value = 2 -> ()
   | _ -> fail "octree nearest query");
  let mapped3 = Octree.map string_of_int tree3 in
  if Octree.size mapped3 <> 4
     || not (List.exists (fun (entry : string Octree.entry) -> entry.value = "4")
               (Octree.entries mapped3))
  then fail "octree map"

let with_temp_file suffix operation =
  let filename = Filename.temp_file "prismel-geom-" suffix in
  Fun.protect ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
    (fun () -> operation filename)

let test_mesh_io () =
  let mesh = Mesh.icosahedron ~radius:1. in
  let check_roundtrip name save load suffix =
    with_temp_file suffix (fun filename ->
      save mesh filename |> result_or_fail;
      let loaded = load filename |> result_or_fail in
      if List.length (Mesh.faces loaded) <> 20 then
        fail (name ^ " roundtrip changed triangle count");
      if not (Mesh.has_normals loaded) then
        fail (name ^ " loader did not regenerate normals"))
  in
  check_roundtrip "binary STL"
    (Mesh_io.save_stl ~format:Mesh_io.Binary) Mesh_io.load_stl ".stl";
  check_roundtrip "ASCII STL"
    (Mesh_io.save_stl ~format:Mesh_io.Ascii) Mesh_io.load_stl ".stl";
  check_roundtrip "OFF" Mesh_io.save_off Mesh_io.load_off ".off"

let test_mesh_repair () =
  let clean = Mesh.icosahedron ~radius:1. |> Mesh_repair.weld ~epsilon:1e-12 in
  if Mesh.vertex_count clean <> 12 then fail "mesh weld did not merge positions";
  let diagonal = Mesh.create_exn ~mode:Mesh.Points
      [Vec3.zero; Vec3.create 0.000_000_9 0.000_000_9 0.] in
  if Mesh.vertex_count (Mesh_repair.weld ~epsilon:1e-6 diagonal) <> 1 then
    fail "Geom weld no longer preserves componentwise epsilon compatibility";
  let boundary = Mesh.create_exn ~mode:Mesh.Points
      [Vec3.zero; Vec3.create 0.000_001 0. 0.] in
  if Mesh.vertex_count (Mesh_repair.weld ~epsilon:1e-6 boundary) <> 2 then
    fail "Geom weld no longer preserves strict epsilon-boundary compatibility";
  let report = Mesh_repair.analyze clean in
  if not (Mesh_repair.is_closed report)
     || not (Mesh_repair.is_manifold report)
     || report.components <> 1
  then fail "closed icosahedron topology report";
  let indices = Mesh.indices clean in
  let a, b, c = match indices with a :: b :: c :: _ -> a, b, c | _ -> assert false in
  let dirty = Mesh.create_exn ~mode:Mesh.Triangles
      ~indices:(a :: c :: b :: a :: a :: b :: indices)
      (Mesh.vertices clean) in
  let dirty_report = Mesh_repair.analyze dirty in
  if dirty_report.duplicate_faces = [] || dirty_report.degenerate_faces = [] then
    fail "mesh diagnostics missed duplicate or degenerate faces";
  let repaired = Mesh_repair.repair dirty |> result_or_fail in
  let repaired_report = Mesh_repair.analyze repaired in
  if repaired_report.faces <> 20 || not (Mesh_repair.is_closed repaired_report)
  then fail "mesh repair did not restore closed unique topology";
  assert_outward "repaired icosahedron" repaired;
  let flipped_indices = match indices with
    a :: b :: c :: rest -> a :: c :: b :: rest | _ -> assert false in
  let flipped = Mesh.create_exn ~mode:Mesh.Triangles
      ~indices:flipped_indices (Mesh.vertices clean) in
  let oriented = Mesh_repair.orient_consistently flipped |> result_or_fail in
  assert_outward "consistently oriented mesh" oriented;
  let t_mesh = Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0;1;2]
      [Vec3.create 0. 0. 0.; Vec3.create 2. 0. 0.;
       Vec3.create 0. 2. 0.; Vec3.create 1. 0. 0.] in
  let t_fixed = Mesh_repair.repair_t_junctions t_mesh |> result_or_fail in
  if List.length (Mesh.faces t_fixed) <> 2 then fail "T-junction face split";
  let multiple_t_mesh =
    Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0; 1; 2]
      [ Vec3.create 0. 0. 0.; Vec3.create 2. 0. 0.;
        Vec3.create 0. 2. 0.; Vec3.create 1. 0. 0.;
        Vec3.create 1. 1. 0.; Vec3.create 0. 1. 0. ]
  in
  let multiple_t_fixed =
    Mesh_repair.repair_t_junctions multiple_t_mesh |> result_or_fail
  in
  if Mesh.Private.triangle_count multiple_t_fixed <> 4
     || Mesh.indices multiple_t_fixed
        <> [2; 5; 3; 5; 0; 3; 1; 4; 3; 4; 2; 3]
  then fail "multiple T-junction splits were incomplete or reordered";
  let short = Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0;1;2]
      [Vec3.zero; Vec3.create 1e-10 0. 0.; Vec3.create 0. 1. 0.] in
  let collapsed = Mesh_repair.collapse_short_edges ~epsilon:1e-6 short
      |> result_or_fail in
  if Mesh.faces collapsed <> [] then fail "short edge collapse cleanup"

let mesh_volume mesh =
  Mesh.faces mesh
  |> List.fold_left (fun total (face : Mesh.face) ->
    let a, b, c = face.points in
    total +. Vec3.dot a (Vec3.cross b c) /. 6.) 0.
  |> abs_float

let test_csg () =
  let left = Mesh.box ~width:2. ~height:2. ~depth:2. ()
  and right =
    Mesh.box ~width:2. ~height:2. ~depth:2. ()
    |> Mesh.transformed (Mat4.translation (Vec3.create 1. 0. 0.))
  in
  let union = Csg3.union left right |> result_or_fail
  and intersection = Csg3.intersection left right |> result_or_fail
  and difference = Csg3.difference left right |> result_or_fail in
  assert_float ~epsilon:1e-5 "CSG union volume" 12. (mesh_volume union);
  assert_float ~epsilon:1e-5 "CSG intersection volume" 4.
    (mesh_volume intersection);
  assert_float ~epsilon:1e-5 "CSG difference volume" 4.
    (mesh_volume difference);
  if Mesh.faces union = [] || Mesh.faces intersection = []
     || Mesh.faces difference = []
  then fail "CSG returned empty triangle geometry";
  let saddle = Mesh3.saddle ~size:1. |> result_or_fail in
  assert_float ~epsilon:1e-5 "saddle polycube volume" 4. (mesh_volume saddle);
  let saddle_report = Mesh_repair.analyze saddle in
  if not (Mesh_repair.is_closed saddle_report) ||
     not (Mesh_repair.is_manifold saddle_report) then
    fail (Printf.sprintf "saddle polycube topology: %d boundary, %d non-manifold"
      (List.length saddle_report.boundary_edges)
      (List.length saddle_report.non_manifold_edges))

let test_verlet2 () =
  let falling = Verlet2.particle Vec2.zero
  and anchor = Verlet2.particle ~locked:true (vec 0. 0.) in
  let world = Verlet2.create ~drag:0. ~iterations:1
      ~behaviors:[Verlet2.gravity (vec 0. 10.)]
      [falling; anchor] [] |> result_or_fail in
  let stepped = Verlet2.step ~dt:1. world in
  assert_vec "Verlet gravity" (vec 0. 10.)
    (Verlet2.particle_at 0 stepped |> Option.get |> Verlet2.position);
  assert_vec "Verlet locked particle" Vec2.zero
    (Verlet2.particle_at 1 stepped |> Option.get |> Verlet2.position);
  assert_vec "Verlet world persistence" Vec2.zero
    (Verlet2.particle_at 0 world |> Option.get |> Verlet2.position);
  let spring_world = Verlet2.create ~drag:0. ~iterations:1
      [Verlet2.particle (vec 0. 0.); Verlet2.particle (vec 2. 0.)]
      [Verlet2.spring ~rest_length:1. ~strength:1. 0 1]
    |> result_or_fail |> Verlet2.step ~dt:0.1 in
  let left = Verlet2.particle_at 0 spring_world |> Option.get |> Verlet2.position
  and right = Verlet2.particle_at 1 spring_world |> Option.get |> Verlet2.position in
  assert_float "Verlet spring rest length" 1. (Vec2.distance left right);
  let bounded = Verlet2.create ~drag:0. ~iterations:1
      ~constraints:[Verlet2.inside_bounds
        (Bounds2.make ~min:(vec (-1.) (-1.)) ~max:(vec 1. 1.))]
      [Verlet2.particle ~velocity:(vec 5. 0.) Vec2.zero] []
    |> result_or_fail |> Verlet2.step ~dt:1. in
  assert_vec "Verlet bounds constraint" (vec 1. 0.)
    (Verlet2.particle_at 0 bounded |> Option.get |> Verlet2.position);
  let parallel_world =
    Verlet2.create ~drag:0.03 ~iterations:2
      (List.init 4096 (fun index ->
         Verlet2.particle ~velocity:(vec 0.25 (-0.125))
           (vec (float_of_int index) (sin (float_of_int index)))))
      [] |> result_or_fail in
  let step domains = Parallel.run ~domains (fun () ->
      Verlet2.step ~dt:(1. /. 60.) parallel_world |> Verlet2.particles) in
  if step 1 <> step 4 then
    fail "Verlet2 output differed between one and four domains"

let test_verlet3 () =
  let gravity = Vec3.create 0. (-1.) 0. in
  let world =
    Verlet3.create ~drag:0. ~iterations:8 ~behaviors:[Verlet3.gravity gravity]
      [
        Verlet3.particle ~locked:true Vec3.zero;
        Verlet3.particle (Vec3.create 2. 0. 0.);
      ]
      [Verlet3.spring ~rest_length:1. 0 1]
    |> result_or_fail
    |> Verlet3.step ~dt:1.
  in
  assert_vec3 "locked 3D Verlet particle" Vec3.zero
    (Verlet3.particle_at 0 world |> Option.get |> Verlet3.position);
  let free = Verlet3.particle_at 1 world |> Option.get |> Verlet3.position in
  assert_float "3D Verlet spring length" 1. (Vec3.distance Vec3.zero free);
  if free.y >= 0. then fail "3D Verlet gravity did not affect free particle";
  let sphere = Sphere3.make ~center:Vec3.zero ~radius:2. in
  let constrained =
    Verlet3.create ~drag:0. ~iterations:1
      ~constraints:[Verlet3.inside_sphere sphere]
      [Verlet3.particle ~velocity:(Vec3.create 5. 0. 0.) Vec3.zero] []
    |> result_or_fail |> Verlet3.step ~dt:1.
  in
  assert_vec3 "3D Verlet sphere constraint" (Vec3.create 2. 0. 0.)
    (Verlet3.particle_at 0 constrained |> Option.get |> Verlet3.position);
  let parallel_world =
    Verlet3.create ~drag:0.03 ~iterations:2
      (List.init 4096 (fun index ->
         let value = float_of_int index in
         Verlet3.particle ~velocity:(Vec3.create 0.25 (-0.125) 0.5)
           (Vec3.create value (sin value) (cos value))))
      [] |> result_or_fail in
  let step domains = Parallel.run ~domains (fun () ->
      Verlet3.step ~dt:(1. /. 60.) parallel_world |> Verlet3.particles) in
  if step 1 <> step 4 then
    fail "Verlet3 output differed between one and four domains"

let test_voxels () =
  let empty = Voxel3.create ~origin:Vec3.zero ~dimensions:(4, 4, 4)
      ~voxel_size:1. in
  let builder = Voxel3.Builder.create ~origin:Vec3.zero
      ~dimensions:(4, 4, 4) ~voxel_size:1. in
  List.iter (fun cell -> Voxel3.Builder.set cell builder |> result_or_fail)
    [1,1,1; 2,1,1; 1,2,1];
  let built = Voxel3.Builder.freeze builder in
  if Voxel3.count built <> 3 then fail "voxel bulk builder count";
  let initialized domains = Parallel.run ~domains (fun () ->
    Voxel3.init ~origin:Vec3.zero ~dimensions:(16, 12, 8) ~voxel_size:1.
      ~occupied:(fun (x, y, z) -> (x + (2 * y) + (3 * z)) mod 7 = 0)) in
  let initialized_one = initialized 1 and initialized_four = initialized 4 in
  if Voxel3.cells initialized_one <> Voxel3.cells initialized_four then
    fail "voxel dense initialization differed between one and four domains";
  let voxels =
    List.fold_left (fun voxels cell -> Voxel3.set cell voxels |> result_or_fail)
      empty [1,1,1; 2,1,1; 1,2,1; 2,2,1; 1,1,2; 2,1,2; 1,2,2; 2,2,2] in
  if Voxel3.count empty <> 0 || Voxel3.count voxels <> 8 then
    fail "persistent voxel set/count";
  if List.length (Voxel3.boundary voxels) <> 8 then
    fail "voxel boundary selection";
  let block_mesh = Voxel3.surface_mesh voxels |> result_or_fail in
  if List.length (Mesh.faces block_mesh) <> 48 then
    fail "voxel exposed-face mesh topology";
  assert_float "voxel block volume" 8. (mesh_volume block_mesh);
  assert_outward "voxel block surface" block_mesh;
  let single = Voxel3.set (2,2,2) empty |> result_or_fail in
  let thick = Voxel3.thicken ~layers:1 single in
  if Voxel3.count thick <> 7 then fail "six-neighbor voxel thickening";
  let tree = Voxel3.to_octree voxels in
  if Octree.size tree <> 8 then fail "voxel to octree conversion";
  let smooth = Voxel3.isosurface voxels |> result_or_fail in
  if Mesh.faces smooth = [] then fail "voxel isosurface was empty";
  let sparse = Svo3.of_points ~origin:Vec3.zero ~size:8. ~precision:1.
      [Vec3.create 0.2 0.2 0.2; Vec3.create 1.2 0.2 0.2;
       Vec3.create 7.8 7.8 7.8] |> result_or_fail in
  if Svo3.max_depth sparse <> 2 || Svo3.dimensions_at_depth sparse 2 <> 8 then
    fail "sparse voxel depth configuration";
  if Svo3.depth_at (Vec3.create 0.2 0.2 0.2) sparse <> Some 2 then
    fail "sparse voxel occupied depth";
  if Svo3.depth_at (Vec3.create 0.2 3.2 0.2) sparse <> Some 0 then
    fail "sparse voxel branch depth";
  if List.length (Svo3.select_cells ~depth:2 sparse) <> 3 ||
     List.length (Svo3.select_cells ~depth:0 sparse) <> 2 then
    fail "sparse voxel depth selection";
  let deleted = Svo3.delete_at (Vec3.create 0.2 0.2 0.2) sparse in
  if Svo3.contains (Vec3.create 0.2 0.2 0.2) deleted
     || Svo3.depth_at (Vec3.create 0.2 0.2 0.2) deleted <> Some 1
     || Svo3.depth_at (Vec3.create 1.2 0.2 0.2) deleted <> Some 2
  then fail "sparse voxel deletion corrupted shared ancestor counts";
  let duplicate =
    Svo3.set_at (Vec3.create 1.2 0.2 0.2) sparse |> result_or_fail in
  if Svo3.select_cells ~depth:2 duplicate <> Svo3.select_cells ~depth:2 sparse
  then fail "duplicate sparse voxel insertion changed occupancy";
  let inserted_point = Vec3.create 0.2 1.2 0.2 in
  let expanded = Svo3.set_at inserted_point sparse |> result_or_fail in
  if not (Svo3.contains inserted_point expanded)
     || Svo3.contains inserted_point sparse
     || List.length (Svo3.select_cells ~depth:2 expanded) <> 4
  then fail "compressed sparse voxel insertion broke persistence";
  let single_point = Vec3.create 3.2 4.2 5.2 in
  let single = Svo3.of_points ~origin:Vec3.zero ~size:8. ~precision:1.
      [single_point] |> result_or_fail in
  if not (Svo3.contains single_point single)
     || Svo3.select_cells ~depth:0 single = []
     || Svo3.contains single_point (Svo3.delete_at single_point single)
  then fail "compressed sparse voxel leaf lifecycle";
  let coarse = Svo3.to_voxel3 ~depth:0 sparse in
  if Voxel3.count coarse <> 2 then fail "sparse tree to voxel grid"

let test_svg_paths () =
  let path =
    Svg_path.parse
      "M10 10 h 20 v 10 l -5 5 Q 20 35 15 25 t -5 -5 C 8 18 7 17 6 16 s -2 -3 -4 -5 z"
    |> result_or_fail
  in
  let commands = Path.commands path in
  if List.length commands <> 9 then
    fail (Printf.sprintf "SVG path command count: %d" (List.length commands));
  if not (Path.is_closed path) then fail "SVG close-path parsing";
  let serialized = Svg_path.to_string path in
  let reparsed = Svg_path.parse serialized |> result_or_fail in
  if Path.commands reparsed <> commands then fail "SVG path serialization round-trip";
  let arc = Svg_path.parse "M 0 0 A 10 5 30 1 1 20 0" |> result_or_fail in
  (match Path.commands arc with
   | Path.Move_to _ :: Path.Cubic_to _ :: _ -> ()
   | _ -> fail "SVG elliptical arc was not converted to cubic segments");
  if List.length (Path.points ~steps:8 arc) < 9 then
    fail "SVG arc flattening produced too few points";
  match Svg_path.parse "M0 0 A10 10 0 2 0 5 5" with
  | Error _ -> ()
  | Ok _ -> fail "SVG parser accepted invalid arc flag"

let test_svg_export () =
  let bounds = Bounds2.make ~min:(vec 0. 0.) ~max:(vec 100. 80.) in
  let polygon = Polygon2.regular ~center:(vec 50. 40.) ~radius:20. ~sides:5 () in
  let gradient = Svg.linear_gradient ~id:"paint"
      [0., Color.red; 1., Color.blue] in
  let document = Svg.document ~view_box:bounds ~width:200. ~height:160. [
      Svg.defs [gradient];
      Svg.polygon ~attrs:["fill", "url(#paint)"] polygon;
      Svg.text ~at:(vec 2. 12.) "a < b & c";
    ] in
  let contains substring =
    let sub_length = String.length substring in
    let rec search index =
      index + sub_length <= String.length document &&
      (String.sub document index sub_length = substring || search (index + 1))
    in
    search 0
  in
  if not (contains "<linearGradient") || not (contains "<polygon") then
    fail "SVG exporter omitted geometry or definitions";
  if not (contains "a &lt; b &amp; c") then fail "SVG text escaping";
  if not (contains "viewBox=\"0 0 100 80\"") then fail "SVG viewBox export";
  let camera = Camera.perspective ~at:(Vec3.create 0. 0. 4.)
      ~target:Vec3.zero () in
  let projected = Svg3.mesh ~viewport:(0,0,200,160) ~camera
      (Polyhedra3.icosahedron ~radius:1. ()) in
  let projected_document = Svg.document ~width:200. ~height:160. [projected] in
  let polygon_count =
    let needle = "<polygon" in
    let rec count index total =
      if index + String.length needle > String.length projected_document then total
      else if String.sub projected_document index (String.length needle) = needle
      then count (index + String.length needle) (total + 1)
      else count (index + 1) total in
    count 0 0 in
  if polygon_count = 0 || polygon_count >= 20 then
    fail "SVG 3D projection/backface culling"

let test_polyhedra () =
  let cases = [
    "tetrahedron", Polyhedra3.tetrahedron ~radius:2. (), 4, 4;
    "cube", Polyhedra3.cube ~radius:2. (), 8, 12;
    "octahedron", Polyhedra3.octahedron ~radius:2. (), 6, 8;
    "icosahedron", Polyhedra3.icosahedron ~radius:2. (), 12, 20;
    "dodecahedron", Polyhedra3.dodecahedron ~radius:2. (), 20, 36;
    "soccer ball", Polyhedra3.soccer_ball ~radius:2. (), 60, 116;
  ] in
  List.iter (fun (name, mesh, vertex_count, face_count) ->
    if Mesh.vertex_count mesh <> vertex_count || List.length (Mesh.faces mesh) <> face_count then
      fail (Printf.sprintf "%s topology" name);
    List.iter (fun point -> assert_float (name ^ " radius") 2. (Vec3.length point))
      (Mesh.vertices mesh);
    assert_outward name mesh) cases;
  let flat = Polyhedra3.soccer_ball ~flat:true ~radius:2. () in
  if Mesh.vertex_count flat <> 348 || List.length (Mesh.normals flat) <> 348 then
    fail (Printf.sprintf
      "flat soccer-ball adapter did not preserve hard PDK corners (%d vertices, %d normals)"
      (Mesh.vertex_count flat) (List.length (Mesh.normals flat)))

let test_mesh_attributes () =
  let cube_uvs = Mesh_attrib.uv_cube_map_horizontal ~power_of_two:true
      ~face_size:100 () in
  if List.length cube_uvs <> 6 || List.exists (fun face -> List.length face <> 4) cube_uvs then
    fail "cube UV atlas generation";
  let mesh = Polyhedra3.tetrahedron ~radius:1. () in
  let mapped = Mesh_attrib.with_generated_uvs
      (fun ~face:_ ~vertex:_ ~point ->
        Vec2.create ((point.Vec3.x +. 1.) /. 2.) ((point.y +. 1.) /. 2.)) mesh
    |> result_or_fail in
  if Mesh.vertex_count mapped <> 12 || List.length (Mesh.tex_coords mapped) <> 12 then
    fail "face-local generated UV expansion";
  assert_outward "UV-expanded tetrahedron" mapped

let test_mesh_topology () =
  let topology = Polyhedra3.tetrahedron ~radius:1. () |> Mesh_topology.of_mesh in
  if List.length (Mesh_topology.edges topology) <> 6 ||
     Mesh_topology.vertex_valence 0 topology <> 3 ||
     List.length (Mesh_topology.connected_components topology) <> 1 then
    fail "mesh topology adjacency";
  let edited = Mesh_topology.remove_faces (fun face _ -> face = 0) topology
      |> result_or_fail in
  if List.length (Mesh.faces (Mesh_topology.mesh edited)) <> 3 then
    fail "immutable topology face removal"

let test_transport_frames () =
  let path = [Vec3.create 1. 0. 0.; Vec3.create 0. 1. 0.;
    Vec3.create (-1.) 0. 0.; Vec3.create 0. (-1.) 0.] in
  let frames = Transport3.frames ~closed:true path |> result_or_fail in
  if List.length frames <> 4 then fail "parallel transport frame count";
  List.iter (fun (frame : Transport3.frame) ->
    assert_float "transport tangent unit" 1. (Vec3.length frame.tangent);
    assert_float "transport normal unit" 1. (Vec3.length frame.normal);
    assert_float "transport frame orthogonal" 0. (Vec3.dot frame.tangent frame.normal);
    assert_float "transport binormal orientation" 1.
      (Vec3.dot (Vec3.cross frame.tangent frame.normal) frame.binormal)) frames

let test_extended_primitive_tools () =
  let circle = Circle2.make ~center:Vec2.zero ~radius:1. in
  let tangents = Circle2.tangent_points circle (vec 2. 0.) in
  if List.length tangents <> 2 then fail "circle tangent point count";
  List.iter (fun point ->
    assert_float "circle tangent radius" 1. (Vec2.length point);
    assert_float "circle tangent perpendicular" 0.
      (Vec2.dot point (Vec2.sub (vec 2. 0.) point))) tangents;
  let mirror = Segment2.make (vec (-1.) 0.) (vec 1. 0.) in
  assert_vec "line reflection" (vec 2. (-3.))
    (Segment2.reflect_point (vec 2. 3.) mirror);
  let equilateral = Triangle2.equilateral_on (vec 0. 0.) (vec 2. 0.) in
  assert_float "equilateral-on area" (sqrt 3.) (Triangle2.area equilateral);
  assert_float "triangle altitude" (sqrt 3.)
    (Segment2.length (Triangle2.altitude Triangle2.C equilateral));
  let triangle3 = Triangle3.equilateral_on ~normal:Vec3.unit_z
      Vec3.zero (Vec3.create 2. 0. 0.) |> result_or_fail in
  assert_float "3D equilateral area" (sqrt 3.) (Triangle3.area triangle3);
  let tetrahedron = Tetrahedron3.regular ~center:Vec3.zero ~radius:1. in
  if not (Tetrahedron3.contains tetrahedron Vec3.zero) then
    fail "regular tetrahedron containment";
  if List.length (Tetrahedron3.faces tetrahedron) <> 4 then
    fail "tetrahedron face count";
  let left = Segment3.make (Vec3.create (-1.) 0. 0.) (Vec3.create 1. 0. 0.)
  and right = Segment3.make (Vec3.create 0. (-1.) 1.) (Vec3.create 0. 1. 1.) in
  let on_left, on_right = Segment3.closest_between left right in
  assert_vec3 "closest point on 3D segment" Vec3.zero on_left;
  assert_vec3 "closest point on other 3D segment" (Vec3.create 0. 0. 1.) on_right;
  let curve = Curve3.cubic_bezier ~resolution:8 ~from_:Vec3.zero
      ~control1:(Vec3.create 1. 0. 1.) ~control2:(Vec3.create 2. 0. 1.)
      ~to_:(Vec3.create 3. 0. 0.) () in
  if Curve3.point_count curve <> 9 then fail "3D Bezier resolution";
  assert_vec3 "3D Bezier endpoint" (Vec3.create 3. 0. 0.)
    (Curve3.point_at curve 1.);
  let subdivided = Curve3.chaikin curve in
  if Curve3.point_count subdivided <> 18 then fail "3D Chaikin topology";
  let quad = Quad3.square ~size:2. () in
  assert_float "3D quad area" 4. (Quad3.area quad);
  if not (Quad3.contains quad Vec3.zero) then fail "3D quad containment";
  let inset = Quad3.inset ~distance:0.25 quad |> result_or_fail in
  assert_float "3D quad inset area" 2.25 (Quad3.area inset);
  if List.length (Mesh.faces (Quad3.to_mesh quad)) <> 2 then
    fail "3D quad mesh topology";
  let camera = Camera.perspective ~at:(Vec3.create 0. 0. 4.)
      ~target:Vec3.zero () in
  let frustum = Frustum3.of_camera ~viewport:(0,0,640,480) camera in
  if not (Frustum3.contains frustum Vec3.zero) ||
     Frustum3.contains frustum (Vec3.create 0. 0. 5.) then
    fail "camera frustum point classification";
  if not (Frustum3.intersects_bounds frustum
      (Bounds3.make ~min:(Vec3.create (-1.) (-1.) (-1.))
         ~max:(Vec3.create 1. 1. 1.))) then
    fail "camera frustum bounds intersection";
  let shifted amount = Tetrahedron3.transform
      (Mat4.translation (Vec3.create amount 0. 0.)) tetrahedron in
  if not (Intersect3.tetrahedron_tetrahedron tetrahedron (shifted 0.5)) ||
     Intersect3.tetrahedron_tetrahedron tetrahedron (shifted 10.) then
    fail "tetrahedron separating-axis intersection";
  assert_vec3 "bilinear corner mapping" (Vec3.create 1. 1. 0.)
    (Util.map_bilinear ~a:Vec3.zero ~b:Vec3.unit_x
      ~c:(Vec3.create 1. 1. 0.) ~d:Vec3.unit_y ~u:1. ~v:1.);
  let fitted = Util.fit_points2
      ~target:(Bounds2.make ~min:(vec 0. 0.) ~max:(vec 10. 20.))
      [vec 0. 0.; vec 1. 1.] in
  (match fitted with
   | [a;b] -> assert_vec "uniform fit lower" (vec 0. 5.) a;
       assert_vec "uniform fit upper" (vec 10. 15.) b
   | _ -> fail "fit points result");
  assert_float "mesh utility volume" (Tetrahedron3.volume tetrahedron)
    (Util.mesh_volume (Polyhedra3.tetrahedron ~radius:1. ()))

let test_viz () =
  let linear = Viz.linear_scale ~domain:(0., 10.) ~range:(100., 200.) in
  assert_float "linear visualization scale" 150. (Viz.project linear 5.);
  assert_float "linear visualization inverse" 5. (Viz.invert linear 150.);
  let logarithmic = Viz.log_scale ~domain:(1., 1000.) ~range:(0., 3.) () in
  assert_float "log visualization scale" 2. (Viz.project logarithmic 100.);
  assert_float "log visualization inverse" 100. (Viz.invert logarithmic 2.);
  let lens = Viz.lens_scale ~focus:5. ~strength:0.6
      ~domain:(0.,10.) ~range:(0.,100.) in
  assert_float ~epsilon:1e-8 "lens scale inverse" 2.5
    (Viz.invert lens (Viz.project lens 2.5));
  let axis = Viz.linear_axis ~major:2. ~minor:1.
      ~domain:(0., 5.) ~range:(0., 100.) () in
  if axis.major <> [0.;2.;4.] || axis.minor <> [1.;3.;5.] then
    fail "visualization tick generation";
  let rows = Viz.stack_intervals ~range:Fun.id
      [0.,2.; 1.,3.; 3.1,4.; 4.,5.] in
  if List.length rows <> 2 then fail "interval row stacking";
  let y = Viz.linear_scale ~domain:(0.,10.) ~range:(100.,0.) in
  let chart = Svg.document ~width:120. ~height:120. [
      Viz.line_plot ~x:linear ~y [0.,0.; 5.,8.; 10.,4.];
      Viz.scatter_plot ~x:linear ~y [2.,3.; 7.,9.];
      Viz.bar_plot ~width:5. ~x:linear ~y [1.,2.; 4.,6.];
    ] in
  if String.length chart < 200 then fail "visualization SVG layouts";
  let matrix = [|[|0.;0.;0.|]; [|0.;1.;0.|]; [|0.;0.;0.|]|] in
  let contours = Contour2.extract ~iso:0.5 matrix |> result_or_fail in
  (match contours with
   | [curve] when Curve2.closed curve && Curve2.point_count curve = 4 -> ()
   | _ -> fail "marching-squares closed contour stitching");
  ignore (Viz.contour_plot ~x:(Viz.linear_scale ~domain:(0.,2.) ~range:(0.,100.))
    ~y:(Viz.linear_scale ~domain:(0.,2.) ~range:(0.,100.))
    ~levels:[0.25;0.5] ~palette:[Color.red;Color.blue] matrix
    |> result_or_fail)

let () =
  test_affine ();
  test_bounds ();
  test_segments ();
  test_circles ();
  test_polygon_queries ();
  test_polygon_algorithms ();
  test_polygon_generators ();
  test_curves ();
  test_delaunay_and_voronoi ();
  test_mesh_generation ();
  test_isosurfaces ();
  test_extended_types_and_intersections ();
  test_spatial_trees ();
  test_mesh_io ();
  test_mesh_repair ();
  test_csg ();
  test_verlet2 ();
  test_verlet3 ();
  test_voxels ();
  test_svg_paths ();
  test_svg_export ();
  test_polyhedra ();
  test_mesh_attributes ();
  test_mesh_topology ();
  test_transport_frames ();
  test_extended_primitive_tools ();
  test_viz ();
  Printf.printf "geom primitive tests passed\n"
