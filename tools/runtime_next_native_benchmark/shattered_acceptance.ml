open Prismel
open Procedural

type result = {
  pieces : int;
  triangles : int;
  render_vertices : int;
  mesh : Mesh.t;
  cook_seconds : float;
  pack_seconds : float;
  topology_hash : string;
  attribute_hash : string;
  order_hash : string;
  render_hash : string;
}

let get = function Ok value -> value | Error message -> failwith message
let diagnostic = function
  | Ok value -> value
  | Error error -> failwith (Diagnostic.error_to_string error)
let digest value = Digest.to_hex (Digest.string (Marshal.to_string value []))
let storage_payload = function
  | Pdk.Attribute.Float values -> `Float values
  | Int values -> `Int values
  | Int_array values -> let view=Pdk.Packed.Int_array.Private.view values in `Int_array(view.offsets,view.values)
  | Float_array values -> let view=Pdk.Packed.Float_array.Private.view values in `Float_array(view.offsets,view.values)
  | Float2 values -> let view=Pdk.Packed.Float2.Private.view values in `Float2(view.x,view.y)
  | Float3 values -> let view=Pdk.Packed.Float3.Private.view values in `Float3(view.x,view.y,view.z)
  | Float4 values -> let view=Pdk.Packed.Float4.Private.view values in `Float4(view.x,view.y,view.z,view.w)
  | Text values -> `Text values
let attribute_payload attribute =
  Pdk.Attribute.owner attribute,Pdk.Attribute.name attribute,
  Pdk.Attribute.kind_name attribute,
  storage_payload(Pdk.Attribute.Private.storage attribute)

(* This is the target-neutral construction used by the frozen acceptance
   sketch. Keep changes synchronized by the correctness hash fixture; the
   acceptance source itself remains immutable during migration. *)
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

let cook ~domains = Parallel.run ~domains (fun () ->
  let node=graph() in
  let session=get(Session.create~max_entries:24~max_payload_bytes:(256*1024*1024))in
  let context=get(Context.create~seed:7349L~domains~grain:2())in
  Fun.protect ~finally:(fun()->Session.close session) (fun()->
    let started=Unix.gettimeofday()in
    let output=diagnostic(Session.cook session~context node)in
    let cooked=Unix.gettimeofday()in
    let pieces=get(Sketch_support.Packed_pieces.of_geometry~piece_attribute:"piece"output.geometry)in
    let mesh=Sketch_support.Packed_pieces.mesh_for_node node pieces in
    let packed=Unix.gettimeofday()in
    let topology=Pdk.Topology.Private.view(Pdk.Geometry.topology output.geometry)in
    let topology_hash=digest(topology.point_count,topology.vertex_points,topology.primitive_offsets,topology.primitive_kinds)in
    let attribute_hash=digest(List.map attribute_payload(Pdk.Geometry.attributes output.geometry))in
    let order_hash=digest(Pdk.Geometry.groups output.geometry,Pdk.Geometry.edge_groups output.geometry)in
    let view=Mesh.Private.packed_view mesh in
    let render_hash=digest(view.mode,view.vertices,view.indices,view.normals,view.colors,view.tex_coords)in
    let result={pieces=Sketch_support.Packed_pieces.piece_count pieces;triangles=Mesh.Private.triangle_count mesh;render_vertices=Mesh.vertex_count mesh;mesh;cook_seconds=cooked-.started;pack_seconds=packed-.cooked;topology_hash;attribute_hash;order_hash;render_hash}in
    if(result.pieces,result.triangles,result.render_vertices)<>(18_278,278_368,835_104)then failwith"acceptance shattered cardinality drift";
    result))

let exact left right =
  left.topology_hash=right.topology_hash&&left.attribute_hash=right.attribute_hash&&
  left.order_hash=right.order_hash&&left.render_hash=right.render_hash
