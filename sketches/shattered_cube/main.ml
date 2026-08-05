open Prismel
open Procedural

let plane_count = match Sys.getenv_opt "PRISMEL_SHATTER_PLANES" with
  | None -> 50
  | Some value ->
      let count = int_of_string value in
      if count <= 0 || count > 100 then
        invalid_arg "PRISMEL_SHATTER_PLANES must be between 1 and 100";
      count
let explosion = 0.32

let random_quaternion index =
  let random = Rand.seed 7349 in
  let u1 = Rand.float_at random ~index:(index * 3)
  and u2 = Rand.float_at random ~index:((index * 3) + 1)
  and u3 = Rand.float_at random ~index:((index * 3) + 2) in
  let a = sqrt (1. -. u1) and b = sqrt u1
  and two_pi = 2. *. Float.pi in
  Quat.create
    ~x:(a *. sin (two_pi *. u2)) ~y:(a *. cos (two_pi *. u2))
    ~z:(b *. sin (two_pi *. u3)) ~w:(b *. cos (two_pi *. u3))

let explode_plane_cells ~amount ~plane_normals input =
  let parameters = Printf.sprintf "amount=%.17g;planes=%d"
      amount (Array.length plane_normals) in
  Sop.custom ~label:"explode-plane-cells" ~operation:"explode_plane_cells"
    ~version:1 ~parameters [input] (fun ~context geometries ->
      let geometry = geometries.(0) in
      if Context.cancelled context then Error "cancelled"
      else
      let topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
      let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
      let primitive_count = Pdk.Geometry.primitive_count geometry
      and plane_count = Array.length plane_normals in
      let plane_bytes = (plane_count + 7) / 8
      and tolerance = 1e-8 in
      let cell_table = Hashtbl.create (max 16 (primitive_count / 4))
      and primitive_cell = Array.make primitive_count 0
      and cell_count = ref 0 in
      let point point =
        Vec3.create positions.x.(point) positions.y.(point) positions.z.(point)
      in
      for primitive = 0 to primitive_count - 1 do
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        let centroid = ref Vec3.zero in
        for vertex = first to last - 1 do
          centroid := Vec3.add !centroid (point topology.vertex_points.(vertex))
        done;
        centroid := Vec3.scale !centroid
            (1. /. float_of_int (last - first));
        let a = point topology.vertex_points.(first)
        and b = point topology.vertex_points.(first + 1)
        and c = point topology.vertex_points.(first + 2) in
        let face_normal = Vec3.cross (Vec3.sub b a) (Vec3.sub c a) in
        let coplanar_plane = ref (-1) and coplanar_alignment = ref 0. in
        Array.iteri (fun plane normal ->
          let on_plane = ref true in
          for vertex = first to last - 1 do
            let p = point topology.vertex_points.(vertex) in
            if abs_float (Vec3.dot normal p) > tolerance then on_plane := false
          done;
          let alignment = abs_float (Vec3.dot face_normal normal) in
          if !on_plane && alignment > !coplanar_alignment then begin
            coplanar_plane := plane;
            coplanar_alignment := alignment
          end)
          plane_normals;
        let key = Bytes.make plane_bytes '\000' in
        Array.iteri (fun plane normal ->
          let positive = if plane = !coplanar_plane then
              (* A closed cell lies opposite the outward-facing wall normal. *)
              Vec3.dot face_normal normal < 0.
            else Vec3.dot normal !centroid > 0. in
          if positive then begin
            let byte = plane lsr 3 and bit = plane land 7 in
            Bytes.set key byte
              (Char.chr (Char.code (Bytes.get key byte) lor (1 lsl bit)))
          end)
          plane_normals;
        let key = Bytes.unsafe_to_string key in
        let cell = match Hashtbl.find_opt cell_table key with
          | Some cell -> cell
          | None ->
              let cell = !cell_count in
              incr cell_count;
              Hashtbl.add cell_table key cell;
              cell
        in
        primitive_cell.(primitive) <- cell
      done;
      let min_x = Array.make !cell_count infinity
      and min_y = Array.make !cell_count infinity
      and min_z = Array.make !cell_count infinity
      and max_x = Array.make !cell_count neg_infinity
      and max_y = Array.make !cell_count neg_infinity
      and max_z = Array.make !cell_count neg_infinity in
      for primitive = 0 to primitive_count - 1 do
        let cell = primitive_cell.(primitive) in
        for vertex = topology.primitive_offsets.(primitive)
            to topology.primitive_offsets.(primitive + 1) - 1 do
          let source = topology.vertex_points.(vertex) in
          let px = positions.x.(source) and py = positions.y.(source)
          and pz = positions.z.(source) in
          min_x.(cell) <- min min_x.(cell) px;
          min_y.(cell) <- min min_y.(cell) py;
          min_z.(cell) <- min min_z.(cell) pz;
          max_x.(cell) <- max max_x.(cell) px;
          max_y.(cell) <- max max_y.(cell) py;
          max_z.(cell) <- max max_z.(cell) pz
        done
      done;
      let vertex_count = Pdk.Geometry.vertex_count geometry in
      let output_x = Array.make vertex_count 0.
      and output_y = Array.make vertex_count 0.
      and output_z = Array.make vertex_count 0.
      and vertex_points = Array.make vertex_count 0
      and next_point = ref 0
      and cell_points = Hashtbl.create (max 16 vertex_count) in
      for primitive = 0 to primitive_count - 1 do
        let cell = primitive_cell.(primitive) in
        let dx = amount *. 0.5 *. (min_x.(cell) +. max_x.(cell))
        and dy = amount *. 0.5 *. (min_y.(cell) +. max_y.(cell))
        and dz = amount *. 0.5 *. (min_z.(cell) +. max_z.(cell)) in
        for vertex = topology.primitive_offsets.(primitive)
            to topology.primitive_offsets.(primitive + 1) - 1 do
          let source = topology.vertex_points.(vertex) in
          let output = match Hashtbl.find_opt cell_points (cell, source) with
            | Some output -> output
            | None ->
                let output = !next_point in
                incr next_point;
                Hashtbl.add cell_points (cell, source) output;
                output_x.(output) <- positions.x.(source) +. dx;
                output_y.(output) <- positions.y.(source) +. dy;
                output_z.(output) <- positions.z.(source) +. dz;
                output
          in
          vertex_points.(vertex) <- output
        done
      done;
      let positions = Pdk.Packed.Float3.Private.of_owned_exn
          ~x:(Array.sub output_x 0 !next_point)
          ~y:(Array.sub output_y 0 !next_point)
          ~z:(Array.sub output_z 0 !next_point) in
      let output_topology = Pdk.Topology.Private.create_validated_owned
          ~point_count:!next_point ~vertex_points
          ~primitive_offsets:(Array.copy topology.primitive_offsets)
          ~primitive_kinds:(Bytes.copy topology.primitive_kinds) in
      let edge_incidence = Hashtbl.create (max 16 vertex_count) in
      for primitive = 0 to primitive_count - 1 do
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        for vertex = first to last - 1 do
          let next = if vertex + 1 = last then first else vertex + 1 in
          let a = vertex_points.(vertex)
          and b = vertex_points.(next) in
          let edge = if a < b then a, b else b, a in
          Hashtbl.replace edge_incidence edge
            (1 + Option.value ~default:0 (Hashtbl.find_opt edge_incidence edge))
        done
      done;
      let boundary_edges, nonmanifold_edges = Hashtbl.fold
          (fun _ incidence (boundary, nonmanifold) ->
            if incidence = 1 then boundary + 1, nonmanifold
            else if incidence = 2 then boundary, nonmanifold
            else boundary, nonmanifold + 1)
          edge_incidence (0, 0) in
      if boundary_edges <> 0 || nonmanifold_edges <> 0 then
        Error (Printf.sprintf
          "plane-cell split produced %d boundary and %d non-manifold edges"
          boundary_edges nonmanifold_edges)
      else begin
        Printf.eprintf "Shattered cube: %d closed plane cells\n%!" !cell_count;
        Pdk.Geometry.create ~positions ~topology:output_topology ()
      end)

let graph () =
  let cube =
    Sop.box ~size:(Vec3.create 2.6 2.6 2.6)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals ()
  in
  let plane =
    Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_quads ~columns:2 ~rows:2 ~size:4.8 ()
    |> Sop.delete_attribute ~owner:Pdk.Attribute.Point ~name:"N"
    |> Sop.delete_attribute ~owner:Pdk.Attribute.Vertex ~name:"N"
  in
  let cutters = List.init plane_count (fun index ->
    let orient = random_quaternion index in
    let origin = Vec3.zero in
    let targets =
      Sop.points [|origin.x, origin.y, origin.z|]
      |> Sop.set_orient ~label:(Printf.sprintf "plane-orient-%02d" index)
           orient
    in
    index, origin, orient,
    Sop.copy_to_points ~label:(Printf.sprintf "copy-plane-%02d" index)
      ~source:plane ~targets ())
  in
  let plane_normals = Array.of_list (List.map (fun (_, _, orient, _) ->
      Quat.rotate orient Vec3.unit_y) cutters) in
  let cutter = Sop.merge (List.map (fun (_, _, _, cutter) -> cutter) cutters) in
  let sliced =
    Sop.boolean ~label:"slice-cube"
      ~operation:Pdk.Boolean.Difference
      ~left_treatment:Pdk.Boolean.Solid
      ~right_treatment:Pdk.Boolean.Surface
      ~resolve_right_self_intersections:true
      ~seam_points:Pdk.Boolean.Shared_seam_points
      ~detriangulation:Pdk.Boolean.Triangles
      ~require_closed:true ~right:cutter cube
  in
  sliced
  |> explode_plane_cells ~amount:explosion ~plane_normals
  |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f2b36d")

type model = {
  session : Session.t;
  mesh : Mesh.t;
  camera : Easy_camera.t;
  frames_left : int option;
}

let cook session frame =
  (* Fracture refinement has many independently owned source faces. A small
     grain keeps those face cooks distributed across the process-wide pool. *)
  let context = Context.of_frame ~seed:7349L ~grain:2 frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context (graph ()) with
  | Ok (mesh, warnings) ->
      List.iter (fun (warning : Diagnostic.t) ->
        Printf.eprintf "Shattered cube warning [%s]: %s\n%!"
          warning.Diagnostic.code warning.message) warnings;
      mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(512 * 1024 * 1024) |> Result.get_ok in
  {
    session;
    mesh = cook session frame;
    camera = Easy_camera.create ~target:Vec3.zero ~distance:6.8
        ~azimuth:0.72 ~elevation:0.42 ();
    frames_left = if Sketch.is_headless () then Some 2 else None;
  }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let material = Material.create ~diffuse:Color.white
    ~ambient:(Color.hex_exn "#422006") ~specular:Color.white ~shininess:48. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
    ~diffuse:(Color.hex_exn "#fff7ed")
    ~ambient:(Color.hex_exn "#1c1917") ();
  Light.directional ~direction:(Vec3.create 1.2 0.4 (-0.8))
    ~diffuse:(Color.hex_exn "#7dd3fc") ~intensity:0.55 ();
]

let view model _frame =
  Scene.[
    clear (Color.hex_exn "#09090b");
    view3d ~camera:(Easy_camera.camera model.camera)
      (Scene3.create ~samples:4 ~lights [
        Scene3.mesh ~cull:Scene3.Cull_none ~shading:Scene3.Flat
          ~material model.mesh
      ]);
    text ~at:(22, 18) "SOP Shattered Cube";
    text ~at:(22, 44)
      (Printf.sprintf "%d quaternion-oriented cutting planes" plane_count);
    text ~at:(22, 682)
      "Drag to orbit · middle-drag to pan · scroll to zoom";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 1024; height = 720;
      title = "Prismel sketch · shattered cube" }
    ~init ~update ~view ~on_stop ())
