open Prismel
open Procedural

module Attribute = Pdk.Attribute
module Edge_group = Pdk.Edge_group
module Geometry = Pdk.Geometry
module Group = Pdk.Group
module Packed = Pdk.Packed
module Topology = Pdk.Topology

let result_exn = function
  | Ok value -> value
  | Error message -> failwith message

let diagnostic_exn = function
  | Ok value -> value
  | Error error -> failwith (Diagnostic.error_to_string error)

let integer_environment name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let boolean_environment name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "yes" | "on") -> true
  | Some _ | None -> false

let domains = integer_environment "PRISMEL_SHATTER_DOMAINS"
    (max 1 (Parallel.recommended_domains () - 1))
let grain = integer_environment "PRISMEL_SHATTER_GRAIN" 2
let verify_domains = boolean_environment "PRISMEL_SHATTER_VERIFY_DOMAINS"

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

let equal_float_array left right =
  let length = Array.length left in
  length = Array.length right
  && begin
    let equal = ref true in
    let index = ref 0 in
    while !equal && !index < length do
      equal := Int64.bits_of_float left.(!index)
        = Int64.bits_of_float right.(!index);
      incr index
    done;
    !equal
  end

let equal_int_array_storage left right =
  let left = Packed.Int_array.Private.view left
  and right = Packed.Int_array.Private.view right in
  left.offsets = right.offsets && left.values = right.values

let equal_float_array_storage left right =
  let left = Packed.Float_array.Private.view left
  and right = Packed.Float_array.Private.view right in
  left.offsets = right.offsets && equal_float_array left.values right.values

let equal_float2 left right =
  let left = Packed.Float2.Private.view left
  and right = Packed.Float2.Private.view right in
  equal_float_array left.x right.x && equal_float_array left.y right.y

let equal_float3 left right =
  let left = Packed.Float3.Private.view left
  and right = Packed.Float3.Private.view right in
  equal_float_array left.x right.x && equal_float_array left.y right.y
  && equal_float_array left.z right.z

let equal_float4 left right =
  let left = Packed.Float4.Private.view left
  and right = Packed.Float4.Private.view right in
  equal_float_array left.x right.x && equal_float_array left.y right.y
  && equal_float_array left.z right.z && equal_float_array left.w right.w

let equal_storage left right =
  match Attribute.Private.storage left, Attribute.Private.storage right with
  | Float left, Float right -> equal_float_array left right
  | Int left, Int right -> left = right
  | Int_array left, Int_array right -> equal_int_array_storage left right
  | Float_array left, Float_array right -> equal_float_array_storage left right
  | Float2 left, Float2 right -> equal_float2 left right
  | Float3 left, Float3 right -> equal_float3 left right
  | Float4 left, Float4 right -> equal_float4 left right
  | Text left, Text right -> left = right
  | _ -> false

let equal_attribute left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
  && equal_storage left right

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && Bytes.equal (Group.Private.bits_view left) (Group.Private.bits_view right)
  && Group.Private.order_view left = Group.Private.order_view right

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let equal = ref true in
    let index = ref 0 in
    while !equal && !index < Edge_group.length left do
      equal := Edge_group.mem !index left = Edge_group.mem !index right;
      incr index
    done;
    !equal
  end

let equal_geometry left right =
  let left_topology = Topology.Private.view (Geometry.topology left)
  and right_topology = Topology.Private.view (Geometry.topology right) in
  equal_float3 (Geometry.positions left) (Geometry.positions right)
  && left_topology.point_count = right_topology.point_count
  && left_topology.vertex_points = right_topology.vertex_points
  && left_topology.primitive_offsets = right_topology.primitive_offsets
  && Bytes.equal left_topology.primitive_kinds right_topology.primitive_kinds
  && List.equal equal_attribute
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group
       (Geometry.edge_groups left) (Geometry.edge_groups right)

type measurement = {
  geometry : Geometry.t;
  pieces : Sketch_support.Packed_pieces.t;
  mesh : Mesh.t;
  cook_seconds : float;
  pack_seconds : float;
  wall_seconds : float;
  user_seconds : float;
  system_seconds : float;
  allocated_bytes : float;
  promoted_bytes : float;
  major_bytes : float;
  peak_heap_bytes : int;
}

let cook ~domains node =
  Parallel.run ~domains (fun () ->
    Gc.full_major ();
    let before_gc = Gc.quick_stat ()
    and before_allocated = Gc.allocated_bytes ()
    and before_times = Unix.times ()
    and started = Unix.gettimeofday () in
    let session = Session.create ~max_entries:24
        ~max_payload_bytes:(256 * 1024 * 1024) |> result_exn in
    let context = Context.create ~seed:7349L ~domains ~grain () |> result_exn in
    let cook_started = Unix.gettimeofday () in
    let output = Session.cook session ~context node |> diagnostic_exn in
    let cooked = Unix.gettimeofday () in
    let pieces =
      Sketch_support.Packed_pieces.of_geometry ~piece_attribute:"piece"
        output.geometry |> result_exn
    in
    let mesh = Sketch_support.Packed_pieces.mesh_for_node node pieces in
    let finished = Unix.gettimeofday () in
    let after_times = Unix.times () and after_gc = Gc.quick_stat () in
    Session.close session;
    {
      geometry = output.geometry;
      pieces;
      mesh;
      cook_seconds = cooked -. cook_started;
      pack_seconds = finished -. cooked;
      wall_seconds = finished -. started;
      user_seconds = after_times.tms_utime -. before_times.tms_utime;
      system_seconds = after_times.tms_stime -. before_times.tms_stime;
      allocated_bytes = Gc.allocated_bytes () -. before_allocated;
      promoted_bytes = (after_gc.promoted_words -. before_gc.promoted_words)
        *. float_of_int (Sys.word_size / 8);
      major_bytes = (after_gc.major_words -. before_gc.major_words)
        *. float_of_int (Sys.word_size / 8);
      peak_heap_bytes = after_gc.top_heap_words * (Sys.word_size / 8);
    })

let verify_cardinality measurement =
  let pieces = Sketch_support.Packed_pieces.piece_count measurement.pieces
  and triangles = Mesh.Private.triangle_count measurement.mesh
  and render_vertices = Mesh.vertex_count measurement.mesh in
  if pieces <> 18_278 then
    failwith (Printf.sprintf
      "shattered-cube piece count changed: expected 18278, got %d" pieces);
  if triangles <> 278_368 then
    failwith (Printf.sprintf
      "shattered-cube triangle count changed: expected 278368, got %d"
      triangles);
  if render_vertices <> 835_104 then
    failwith (Printf.sprintf
      "shattered-cube render vertex count changed: expected 835104, got %d"
      render_vertices)

let print_measurement measurement exact =
  Printf.printf
    "{\"schema\":1,\"benchmark\":\"shattered_cube\",\"domains\":%d,\"grain\":%d,\"pieces\":%d,\"points\":%d,\"geometry_vertices\":%d,\"primitives\":%d,\"triangles\":%d,\"render_vertices\":%d,\"geometry_payload_bytes\":%d,\"packed_payload_bytes\":%d,\"cook_seconds\":%.9f,\"pack_seconds\":%.9f,\"wall_seconds\":%.9f,\"user_seconds\":%.9f,\"system_seconds\":%.9f,\"cpu_percent\":%.6f,\"allocated_bytes\":%.0f,\"promoted_bytes\":%.0f,\"major_bytes\":%.0f,\"peak_heap_bytes\":%d,\"one_multi_domain_exact\":%s}\n%!"
    domains grain
    (Sketch_support.Packed_pieces.piece_count measurement.pieces)
    (Geometry.point_count measurement.geometry)
    (Geometry.vertex_count measurement.geometry)
    (Geometry.primitive_count measurement.geometry)
    (Mesh.Private.triangle_count measurement.mesh)
    (Mesh.vertex_count measurement.mesh)
    (Geometry.payload_bytes measurement.geometry)
    (Sketch_support.Packed_pieces.payload_bytes measurement.pieces)
    measurement.cook_seconds measurement.pack_seconds measurement.wall_seconds
    measurement.user_seconds measurement.system_seconds
    ((measurement.user_seconds +. measurement.system_seconds)
      /. measurement.wall_seconds *. 100.)
    measurement.allocated_bytes measurement.promoted_bytes measurement.major_bytes
    measurement.peak_heap_bytes
    (match exact with None -> "null" | Some value -> string_of_bool value)

let () =
  let node = graph () in
  let measurement = cook ~domains node in
  verify_cardinality measurement;
  let exact =
    if not verify_domains then None
    else
      let other_domains = if domains = 1 then max 2 (Parallel.recommended_domains ())
        else 1 in
      let comparison = cook ~domains:other_domains node in
      verify_cardinality comparison;
      let exact = equal_geometry measurement.geometry comparison.geometry in
      if not exact then failwith "shattered cube differs across domain counts";
      Some exact
  in
  print_measurement measurement exact
