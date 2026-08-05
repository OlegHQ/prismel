open Prismel
open Procedural

let initial_plane_count = match Sys.getenv_opt "PRISMEL_SHATTER_PLANES" with
  | None -> 50
  | Some value ->
      let count = int_of_string value in
      if count <= 0 || count > 50 then
        invalid_arg "PRISMEL_SHATTER_PLANES must be between 1 and 50";
      count
let initial_noise_factor = match Sys.getenv_opt "PRISMEL_SHATTER_NOISE_FACTOR",
    Sys.getenv_opt "PRISMEL_SHATTER_JITTER" with
  | None, None -> 0.35
  | Some value, _ | None, Some value ->
      let jitter = float_of_string value in
      if not (Float.is_finite jitter) || jitter < 0. then
        invalid_arg
          "PRISMEL_SHATTER_NOISE_FACTOR must be finite and non-negative";
      jitter
let default_explosion = 0.32
let initial_grid_segments = match
    Sys.getenv_opt "PRISMEL_SHATTER_GRID_SEGMENTS" with
  | None -> 2
  | Some value ->
      let segments = int_of_string value in
      if segments < 1 || segments > 12 then invalid_arg
          "PRISMEL_SHATTER_GRID_SEGMENTS must be between 1 and 12";
      segments
let initial_noise_frequency = match
    Sys.getenv_opt "PRISMEL_SHATTER_NOISE_FREQUENCY" with
  | None -> 0.27
  | Some value ->
      let frequency = float_of_string value in
      if not (Float.is_finite frequency) || frequency < 0.02 || frequency > 2.
      then invalid_arg
          "PRISMEL_SHATTER_NOISE_FREQUENCY must be between 0.02 and 2";
      frequency

let requested_frames = match Sys.getenv_opt "PRISMEL_SHATTER_FRAMES" with
  | None -> None
  | Some value ->
      let frames = int_of_string value in
      if frames <= 0 then invalid_arg "PRISMEL_SHATTER_FRAMES must be positive";
      Some frames

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

type source_shape = Cube | Dodecahedron

let initial_shape = match Sys.getenv_opt "PRISMEL_SHATTER_SHAPE" with
  | None | Some "cube" -> Cube
  | Some ("dodeca" | "dodecahedron") -> Dodecahedron
  | Some _ -> invalid_arg
      "PRISMEL_SHATTER_SHAPE must be cube or dodecahedron"

type fracture_parameters = {
  shape : source_shape;
  plane_count : int;
  grid_segments : int;
  noise_frequency : float;
  noise_factor : float;
}

let plane_frames parameters = Array.init parameters.plane_count (fun index ->
  let orient = random_quaternion index in
  let normal = Quat.rotate orient Vec3.unit_y in
  let random = Rand.seed 7349 in
  let offset = ((2. *. Rand.float_at random
      ~index:((1 lsl 30) + index)) -. 1.) *. 0.45 in
  Vec3.scale normal offset, orient, normal)

let plane_height ~phase ~frequency ~factor x z =
  factor *. sin ((x *. frequency) +. (phase *. 0.731))
  *. cos ((z *. frequency) -. (phase *. 0.413))

let noisy_plane ~phase ~frequency ~factor input =
  let parameters = Printf.sprintf "phase=%d;frequency=%.17g;factor=%.17g"
      phase frequency factor in
  Sop.custom ~label:(Printf.sprintf "noise-plane-%02d" phase)
    ~operation:"noise_plane" ~version:1 ~parameters [input]
    (fun ~context geometries ->
      if Context.cancelled context then Error "cancelled"
      else
        let geometry = geometries.(0) in
        let source = Pdk.Packed.Float3.Private.view
            (Pdk.Geometry.positions geometry) in
        let count = Array.length source.x in
        let x = Array.copy source.x and y = Array.copy source.y
        and z = Array.copy source.z in
        let phase = float_of_int phase in
        for point = 0 to count - 1 do
          y.(point) <- y.(point) +.
              plane_height ~phase ~frequency ~factor x.(point) z.(point)
        done;
        let positions = Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z in
        Pdk.Geometry.with_positions positions geometry)

type fracture = {
  base_x : float array;
  base_y : float array;
  base_z : float array;
  offset_x : float array;
  offset_y : float array;
  offset_z : float array;
  topology : Pdk.Topology.t;
}

let cutter_id_attribute = "__prismel_shatter_cutter_id"

let cutter_surface_sample parameters plane local_x local_z =
  let segments = parameters.grid_segments
  and half = 2.4 in
  let step = (2. *. half) /. float_of_int parameters.grid_segments in
  let coordinate value =
    let scaled = (value +. half) /. step in
    let cell = max 0 (min (segments - 1) (int_of_float (floor scaled))) in
    cell, max 0. (min 1. (scaled -. float_of_int cell)) in
  let column, u = coordinate local_x
  and row, v = coordinate local_z in
  let x0 = -.half +. (float_of_int column *. step)
  and z0 = -.half +. (float_of_int row *. step) in
  let phase = float_of_int plane in
  let height x z = plane_height ~phase
      ~frequency:parameters.noise_frequency ~factor:parameters.noise_factor x z in
  let a = height x0 z0
  and b = height (x0 +. step) z0
  and c = height (x0 +. step) (z0 +. step)
  and d = height x0 (z0 +. step) in
  if v <= u then
    let height = a +. (u *. (b -. a)) +. (v *. (c -. b)) in
    height, Vec3.create (-.((b -. a) /. step)) 1. (-.((c -. b) /. step))
  else
    let height = a +. (u *. (c -. d)) +. (v *. (d -. a)) in
    height, Vec3.create (-.((c -. d) /. step)) 1. (-.((d -. a) /. step))

let prepare_fracture parameters
    (plane_frames : (Vec3.t * Quat.t * Vec3.t) array) geometry =
  let topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
      let cutter_ids = match Pdk.Geometry.find_attribute
          ~owner:Pdk.Attribute.Primitive cutter_id_attribute geometry with
        | Some attribute ->
            (match Pdk.Attribute.Private.storage attribute with
             | Pdk.Attribute.Int values -> values
             | _ -> invalid_arg "shatter cutter ancestry is not integer-valued")
        | None -> invalid_arg "Boolean output lost shatter cutter ancestry" in
      let primitive_count = Pdk.Geometry.primitive_count geometry in
      let plane_count = Array.length plane_frames
      and plane_bytes = (Array.length plane_frames + 7) / 8 in
      let signature_table = Hashtbl.create (max 16 (primitive_count / 4))
      and primitive_cell = Array.make primitive_count 0
      and signature_count = ref 0 in
      let point point =
        Vec3.create positions.x.(point) positions.y.(point) positions.z.(point)
      in
      let plane_sample plane world =
        let origin, orient, _ = plane_frames.(plane) in
        let local = Quat.rotate (Quat.conjugate orient) (Vec3.sub world origin) in
        let height, local_normal =
          cutter_surface_sample parameters plane local.x local.z in
        local.y -. height, Quat.rotate orient local_normal
      in
      for primitive = 0 to primitive_count - 1 do
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        let centroid = ref Vec3.zero in
        for vertex = first to last - 1 do
          centroid := Vec3.add !centroid (point topology.vertex_points.(vertex))
        done;
        centroid := Vec3.scale !centroid (1. /. float_of_int (last - first));
        let a = point topology.vertex_points.(first)
        and b = point topology.vertex_points.(first + 1)
        and c = point topology.vertex_points.(first + 2) in
        let face_normal = Vec3.cross (Vec3.sub b a) (Vec3.sub c a) in
        let coplanar_plane = cutter_ids.(primitive) in
        if coplanar_plane < -1 || coplanar_plane >= plane_count then
          invalid_arg (Printf.sprintf
            "Boolean output has invalid shatter cutter ancestry %d"
            coplanar_plane);
        let key = Bytes.make plane_bytes '\000' in
        for plane = 0 to plane_count - 1 do
          let signed, surface_normal = plane_sample plane !centroid in
          let positive = if plane = coplanar_plane then
              Vec3.dot face_normal surface_normal < 0.
            else signed > 0. in
          if positive then begin
            let byte = plane lsr 3 and bit = plane land 7 in
            Bytes.set key byte
              (Char.chr (Char.code (Bytes.get key byte) lor (1 lsl bit)))
          end
        done;
        let key = Bytes.unsafe_to_string key in
        let signature = match Hashtbl.find_opt signature_table key with
          | Some signature -> signature
          | None ->
              let signature = !signature_count in
              incr signature_count;
              Hashtbl.add signature_table key signature;
              signature in
        primitive_cell.(primitive) <- signature
      done;
      (* A curved cutter can create multiple disconnected regions with the
         same side-of-plane signature. Keep those as independent shards by
         splitting every signature into edge-connected face components. *)
      let parents = Array.init primitive_count Fun.id
      and ranks = Bytes.make primitive_count '\000' in
      let rec root primitive =
        let parent = parents.(primitive) in
        if parent = primitive then primitive
        else begin
          let representative = root parent in
          parents.(primitive) <- representative;
          representative
        end in
      let union a b =
        let a = root a and b = root b in
        if a <> b then
          let rank_a = Char.code (Bytes.get ranks a)
          and rank_b = Char.code (Bytes.get ranks b) in
          if rank_a < rank_b then parents.(a) <- b
          else if rank_a > rank_b then parents.(b) <- a
          else begin
            parents.(b) <- a;
            Bytes.set ranks a (Char.chr (rank_a + 1))
          end in
      let edge_owner = Hashtbl.create (max 16 (Pdk.Geometry.vertex_count geometry)) in
      for primitive = 0 to primitive_count - 1 do
        let signature = primitive_cell.(primitive)
        and first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        for vertex = first to last - 1 do
          let next = if vertex + 1 = last then first else vertex + 1 in
          let a = topology.vertex_points.(vertex)
          and b = topology.vertex_points.(next) in
          let a, b = if a < b then a, b else b, a in
          match Hashtbl.find_opt edge_owner (signature, a, b) with
          | Some neighbor -> union primitive neighbor
          | None -> Hashtbl.add edge_owner (signature, a, b) primitive
        done
      done;
      let component_table = Hashtbl.create (max 16 !signature_count)
      and cell_count = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        let representative = root primitive in
        let cell = match Hashtbl.find_opt component_table representative with
          | Some cell -> cell
          | None ->
              let cell = !cell_count in
              incr cell_count;
              Hashtbl.add component_table representative cell;
              cell in
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
      let base_x = Array.make vertex_count 0.
      and base_y = Array.make vertex_count 0.
      and base_z = Array.make vertex_count 0.
      and point_cell = Array.make vertex_count 0
      and vertex_points = Array.make vertex_count 0
      and next_point = ref 0
      and cell_points = Hashtbl.create (max 16 vertex_count) in
      for primitive = 0 to primitive_count - 1 do
        let cell = primitive_cell.(primitive) in
        for vertex = topology.primitive_offsets.(primitive)
            to topology.primitive_offsets.(primitive + 1) - 1 do
          let source = topology.vertex_points.(vertex) in
          let output = match Hashtbl.find_opt cell_points (cell, source) with
            | Some output -> output
            | None ->
                let output = !next_point in
                incr next_point;
                Hashtbl.add cell_points (cell, source) output;
                base_x.(output) <- positions.x.(source);
                base_y.(output) <- positions.y.(source);
                base_z.(output) <- positions.z.(source);
                point_cell.(output) <- cell;
                output
          in
          vertex_points.(vertex) <- output
        done
      done;
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
        Printf.eprintf
          "Shattered source: %d closed cells, %d points, %d triangles\n%!"
          !cell_count !next_point primitive_count;
        let point_count = !next_point in
        let center_x = Array.init !cell_count (fun cell ->
            0.5 *. (min_x.(cell) +. max_x.(cell)))
        and center_y = Array.init !cell_count (fun cell ->
            0.5 *. (min_y.(cell) +. max_y.(cell)))
        and center_z = Array.init !cell_count (fun cell ->
            0.5 *. (min_z.(cell) +. max_z.(cell))) in
        Ok {
          base_x = Array.sub base_x 0 point_count;
          base_y = Array.sub base_y 0 point_count;
          base_z = Array.sub base_z 0 point_count;
          offset_x = Array.init point_count (fun point ->
              center_x.(point_cell.(point)));
          offset_y = Array.init point_count (fun point ->
              center_y.(point_cell.(point)));
          offset_z = Array.init point_count (fun point ->
              center_z.(point_cell.(point)));
          topology = output_topology;
        }
      end

let exploded_geometry fracture amount =
  let point_count = Array.length fracture.base_x in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        fracture.base_x.(point) +. (amount *. fracture.offset_x.(point))))
      ~y:(Array.init point_count (fun point ->
        fracture.base_y.(point) +. (amount *. fracture.offset_y.(point))))
      ~z:(Array.init point_count (fun point ->
        fracture.base_z.(point) +. (amount *. fracture.offset_z.(point)))) in
  Pdk.Geometry.create ~positions ~topology:fracture.topology ()

type render_fracture = {
  base : Mesh.Private.packed_view;
  render_offset_x : float array;
  render_offset_y : float array;
  render_offset_z : float array;
}

let prepare_render_fracture fracture =
  let point_mesh =
    exploded_geometry fracture 0.
    |> Result.get_ok
    |> Bridge.to_mesh
    |> Result.get_ok in
  let point_view = Mesh.Private.packed_view point_mesh in
  if point_view.mode <> Mesh.Triangles then
    invalid_arg "shattered cube render mesh must be triangles";
  let flat = Mesh.flat_shaded point_mesh in
  let base = Mesh.Private.packed_view flat in
  let source_points = point_view.indices in
  if Array.length source_points <> Mesh.vertex_count flat then
    invalid_arg "shattered cube flat render ancestry is inconsistent";
  {
    base;
    render_offset_x = Array.map (Array.get fracture.offset_x) source_points;
    render_offset_y = Array.map (Array.get fracture.offset_y) source_points;
    render_offset_z = Array.map (Array.get fracture.offset_z) source_points;
  }

let render_mesh fracture amount =
  let point_count = Array.length fracture.render_offset_x in
  let base = fracture.base.vertices in
  let positions = {
    Mesh.Private.x = Array.init point_count (fun point ->
      base.x.(point) +. (amount *. fracture.render_offset_x.(point)));
    y = Array.init point_count (fun point ->
      base.y.(point) +. (amount *. fracture.render_offset_y.(point)));
    z = Array.init point_count (fun point ->
      base.z.(point) +. (amount *. fracture.render_offset_z.(point)));
  } in
  Mesh.Private.create_packed_shared ~mode:fracture.base.mode
    ~indices:fracture.base.indices ?normals:fracture.base.normals
    ?colors:fracture.base.colors ?tex_coords:fracture.base.tex_coords positions
  |> Result.get_ok

let graph parameters
    (plane_frames : (Vec3.t * Quat.t * Vec3.t) array) =
  let source = match parameters.shape with
    | Cube ->
        Sop.box ~size:(Vec3.create 2.6 2.6 2.6)
          ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
          ~normals:Pdk.Ops.Box_no_normals ()
    | Dodecahedron ->
        Sop.platonic ~kind:Pdk.Ops.Platonic_dodecahedron
          ~normals:Pdk.Ops.Platonic_no_normals
          ~rotation:(Vec3.create 0.173 0.291 0.113) ~radius:2.25 ()
        |> Sop.triangulate
  in
  let source = Sop.set_int ~owner:Pdk.Attribute.Primitive
      ~name:cutter_id_attribute (-1) source in
  let plane =
    Sop.grid ~counts:Pdk.Ops.Grid_divisions
      ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:parameters.grid_segments ~rows:parameters.grid_segments
      ~size:4.8 ()
    |> Sop.delete_attribute ~owner:Pdk.Attribute.Point ~name:"N"
    |> Sop.delete_attribute ~owner:Pdk.Attribute.Vertex ~name:"N"
  in
  let cutters = List.init parameters.plane_count (fun index ->
    let origin, orient, _ = plane_frames.(index) in
    let plane = noisy_plane ~phase:index
        ~frequency:parameters.noise_frequency
        ~factor:parameters.noise_factor plane
      |> Sop.set_int ~owner:Pdk.Attribute.Primitive
           ~name:cutter_id_attribute index in
    let targets =
      Sop.points [|origin.x, origin.y, origin.z|]
      |> Sop.set_orient ~label:(Printf.sprintf "plane-orient-%02d" index)
           orient
    in
    index, origin, orient,
    Sop.copy_to_points ~label:(Printf.sprintf "copy-plane-%02d" index)
      ~source:plane ~targets ())
  in
  let cutter = Sop.merge (List.map (fun (_, _, _, cutter) -> cutter) cutters) in
  Sop.boolean ~label:"slice-source"
      ~operation:Pdk.Boolean.Difference
      ~left_treatment:Pdk.Boolean.Solid
      ~right_treatment:Pdk.Boolean.Surface
      ~resolve_right_self_intersections:true
      ~seam_points:Pdk.Boolean.Shared_seam_points
      ~detriangulation:Pdk.Boolean.Triangles
      ~require_closed:true ~right:cutter source

type model = {
  session : Session.t;
  parameters : fracture_parameters;
  failed_parameters : fracture_parameters option;
  cook_error : string option;
  fracture : render_fracture;
  mesh : Mesh.t;
  camera : Easy_camera.t;
  ui : Pxui.t;
  explosion : float;
  frames_left : int option;
}

let cook_fracture session frame parameters =
  (* Fracture refinement has many independently owned source faces. A small
     grain keeps those face cooks distributed across the process-wide pool. *)
  let context = Context.of_frame ~seed:7349L ~grain:2 frame |> Result.get_ok in
  let frames = plane_frames parameters in
  match Session.cook session ~context (graph parameters frames) with
  | Ok output ->
      List.iter (fun (warning : Diagnostic.t) ->
        Printf.eprintf "Shattered cube warning [%s]: %s\n%!"
          warning.Diagnostic.code warning.message) output.diagnostics;
      prepare_fracture parameters frames output.geometry
  | Error error -> Error (Diagnostic.error_to_string error)

let init frame =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(192 * 1024 * 1024) |> Result.get_ok in
  let ui =
    Pxui.create ~x:20 ~y:76 ~width:280 ()
    |> Pxui.label ~text:"Shatter controls"
    |> Pxui.toggle ~name:"dodecahedron" ~label:"Dodecahedron"
         ~value:(initial_shape = Dodecahedron)
    |> Pxui.slider ~name:"plane-count" ~label:"Planes"
         ~min:1. ~max:50. ~value:(float_of_int initial_plane_count)
    |> Pxui.slider ~name:"grid-segments" ~label:"Grid segments"
         ~min:1. ~max:12. ~value:(float_of_int initial_grid_segments)
    |> Pxui.slider ~name:"noise-frequency" ~label:"Noise frequency"
         ~min:0.02 ~max:2. ~value:initial_noise_frequency
    |> Pxui.slider ~name:"noise-factor" ~label:"Noise factor"
         ~min:0. ~max:1.2 ~value:initial_noise_factor
    |> Pxui.slider ~name:"explosion" ~label:"Explosion"
         ~min:0. ~max:1.2 ~value:default_explosion
  in
  let parameters = {
    shape = initial_shape;
    plane_count = initial_plane_count;
    grid_segments = initial_grid_segments;
    noise_frequency = initial_noise_frequency;
    noise_factor = initial_noise_factor;
  } in
  let fracture = match cook_fracture session frame parameters with
    | Ok fracture -> prepare_render_fracture fracture
    | Error message -> failwith message in
  {
    session;
    parameters;
    failed_parameters = None;
    cook_error = None;
    fracture;
    mesh = render_mesh fracture default_explosion;
    camera = Easy_camera.create ~target:Vec3.zero ~distance:6.8
        ~azimuth:0.72 ~elevation:0.42 ();
    ui;
    explosion = default_explosion;
    frames_left = match requested_frames with
      | Some frames -> Some frames
      | None -> if Sketch.is_headless () then Some 2 else None;
  }

let update model (frame : Frame.t) =
  let ui, changes = Pxui.update model.ui frame.events in
  let explosion = Option.value ~default:model.explosion
      (Pxui.slider_value ui "explosion") in
  let parameters = {
    shape = (match Pxui.toggle_value ui "dodecahedron" with
      | Some true -> Dodecahedron | Some false | None -> Cube);
    plane_count = Option.value ~default:(float_of_int model.parameters.plane_count)
        (Pxui.slider_value ui "plane-count")
      |> Float.round |> int_of_float |> max 1 |> min 50;
    grid_segments =
      Option.value ~default:(float_of_int model.parameters.grid_segments)
        (Pxui.slider_value ui "grid-segments")
      |> Float.round |> int_of_float |> max 1 |> min 12;
    noise_frequency = Option.value ~default:model.parameters.noise_frequency
        (Pxui.slider_value ui "noise-frequency");
    noise_factor = Option.value ~default:model.parameters.noise_factor
        (Pxui.slider_value ui "noise-factor");
  } in
  let geometry_changed = parameters <> model.parameters in
  let previous_failed_parameters, previous_cook_error =
    if geometry_changed then model.failed_parameters, model.cook_error
    else None, None in
  (* Geometry sliders preview their values while held, then perform one costly
     Boolean cook on release. Explosion remains a topology-free live update. *)
  let recook = geometry_changed
      && Some parameters <> previous_failed_parameters
      && not (Frame.mouse_down Input.LeftButton frame) in
  let fracture, mesh, parameters, failed_parameters, cook_error = if recook then
      match cook_fracture model.session frame parameters with
      | Ok fracture ->
          let fracture = prepare_render_fracture fracture in
          fracture, render_mesh fracture explosion, parameters, None, None
      | Error message ->
          Printf.eprintf "Shattered source cook rejected: %s\n%!" message;
          model.fracture, model.mesh, model.parameters, Some parameters,
          Some message
    else if explosion <> model.explosion then
      model.fracture, render_mesh model.fracture explosion, model.parameters,
      previous_failed_parameters, previous_cook_error
    else model.fracture, model.mesh, model.parameters,
      previous_failed_parameters, previous_cook_error in
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  let camera = if changes <> [] then model.camera
      else Easy_camera.update model.camera frame in
  { model with camera; ui; parameters; failed_parameters; cook_error;
    fracture; mesh; explosion; frames_left }

let material = Material.create ~diffuse:(Color.hex_exn "#f2b36d")
    ~ambient:(Color.hex_exn "#422006") ~specular:Color.white ~shininess:48. ()

let lights = [
  Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
    ~diffuse:(Color.hex_exn "#fff7ed")
    ~ambient:(Color.hex_exn "#1c1917") ();
  Light.directional ~direction:(Vec3.create 1.2 0.4 (-0.8))
    ~diffuse:(Color.hex_exn "#7dd3fc") ~intensity:0.55 ();
]

let view model _frame =
  let shape_name = match model.parameters.shape with
    | Cube -> "Cube" | Dodecahedron -> "Dodecahedron" in
  let error_scene = match model.cook_error with
    | None -> []
    | Some message ->
        let message = if String.length message <= 92 then message
          else String.sub message 0 89 ^ "..." in
        Scene.[text ~at:(22, 376) ~color:(Color.hex_exn "#fb7185")
          ("Cook rejected: " ^ message)] in
  Scene.[
    clear (Color.hex_exn "#09090b");
    view3d ~camera:(Easy_camera.camera model.camera)
      (Scene3.create ~samples:1 ~lights [
        Scene3.mesh ~cull:Scene3.Cull_back ~shading:Scene3.Smooth
          ~material model.mesh
      ]);
    text ~at:(22, 18) "SOP Shattered Cube";
    text ~at:(22, 44)
      (Printf.sprintf "%s · %d noisy quaternion cutting planes"
         shape_name model.parameters.plane_count);
    text ~at:(22, 682)
      "Drag to orbit · middle-drag to pan · scroll to zoom";
  ] @ error_scene @ Pxui.scene model.ui

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 1024; height = 720;
      title = "Prismel sketch · shattered cube" }
    ~init ~update ~view ~on_stop ())
