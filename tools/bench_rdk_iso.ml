open Rdk
open Rays_math

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let median values =
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let digest geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let attributes = List.map (fun attribute ->
    let data = match Attribute.storage attribute with
      | Float3 values -> let v = Packed.Float3.Private.view values in v.x, v.y, v.z
      | _ -> failwith "isosurface benchmark expects float3 attributes" in
    Attribute.owner attribute, Attribute.name attribute, Attribute.kind_name attribute, data)
    (Geometry.attributes geometry) in
  assert (Geometry.groups geometry = [] && Geometry.edge_groups geometry = []);
  Digest.to_hex (Digest.string (Marshal.to_string
    (positions.x, positions.y, positions.z, Topology.Private.view (Geometry.topology geometry), attributes)
    [Marshal.No_sharing]))

let () =
  let size = integer_env "RAYS_RDK_ISO_RESOLUTION" 40
  and domains = integer_env "RAYS_BENCH_DOMAINS" 1
  and repeats = integer_env "RAYS_BENCH_REPEATS" 7 in
  let mode = match Array.to_list Sys.argv with
    | [_] -> "median" | [_; ("--raw" | "--sphere" | "--sampled-sphere" | "--asymmetric" as mode)] -> mode
    | _ -> invalid_arg "bench_rdk_iso [--raw | --sphere | --sampled-sphere | --asymmetric]" in
  let sphere center radius = Iso_surface.Field.custom (fun p ->
    let x = p.(0) -. center.Vec3.x and y = p.(1) -. center.y and z = p.(2) -. center.z in
    sqrt ((x *. x +. y *. y) +. z *. z) -. radius) in
  let fixture, resolution, min, max, field = match mode with
    | "--sphere" | "--sampled-sphere" -> "sphere", (size,size,size), Vec3.create (-2.) (-2.) (-2.),
        Vec3.create 2. 2. 2., sphere Vec3.zero 1.
    | "--asymmetric" -> "asymmetric", (129,256,2), Vec3.create (-2.) (-1.5) (-1.),
        Vec3.create 3. 2. 1.7, sphere (Vec3.create 0.2 (-0.3) 0.1) 0.8
    | _ -> "gyroid", (size,size,size), Vec3.create (-3.) (-3.) (-3.),
        Vec3.create 3. 3. 3., Iso_surface.Field.gyroid ~scale:1.25 () in
  let samples = if mode <> "--sampled-sphere" then [||] else
    let n = size + 1 in
    Array.init (n*n*n) (fun i ->
      let coord index = -2. +. float_of_int index *. (4. /. float_of_int size) in
      let x = coord (i mod n) and y = coord ((i / n) mod n) and z = coord (i / (n*n)) in
      sqrt ((x *. x +. y *. y) +. z *. z) -. 1.) in
  let extract () = Parallel.run ~domains (fun () ->
    (if mode = "--sampled-sphere" then
       Iso_surface.extract_sampled ~resolution ~min ~max ~iso:0. ~samples ()
     else Iso_surface.extract_dense ~resolution ~min ~max ~iso:0. ~field ())
    |> function Ok value -> value
      | Error error -> failwith (Error.to_string error)) in
  let expected = extract () |> digest in
  let seconds = Array.make repeats 0.
  and allocated = Array.make repeats 0. in
  let rx, ry, rz = resolution in
  if mode <> "median" then Printf.printf
    "fixture,domains,repetition,rx,ry,rz,cells,samples,seconds,allocated_bytes_all_domains,promoted_bytes,major_bytes,points,vertices,primitives,hash\n%!";
  for repeat = 0 to repeats - 1 do
    let before = Gc.stat () in
    let started = Unix.gettimeofday () in
    let geometry = extract () in
    seconds.(repeat) <- Unix.gettimeofday () -. started;
    let after = Gc.stat () in
    let word_bytes = float (Sys.word_size / 8) in
    let promoted = (after.promoted_words -. before.promoted_words) *. word_bytes
    and major = (after.major_words -. before.major_words) *. word_bytes in
    allocated.(repeat) <- (after.minor_words -. before.minor_words) *. word_bytes +. major -. promoted;
    let hash = digest geometry in
    if hash <> expected then failwith "isosurface digest changed";
    if mode <> "median" then Printf.printf
      "%s,%d,%d,%d,%d,%d,%d,%d,%.9f,%.0f,%.0f,%.0f,%d,%d,%d,%s\n%!"
      fixture domains repeat rx ry rz (rx*ry*rz) ((rx+1)*(ry+1)*(rz+1))
      seconds.(repeat) allocated.(repeat) promoted major
      (Geometry.point_count geometry) (Geometry.vertex_count geometry)
      (Geometry.primitive_count geometry) hash
  done;
  if mode = "median" then begin
  Printf.printf "benchmark,resolution,domains,repeats,points,primitives,digest,median_seconds,median_allocated_bytes_all_domains\n";
  let geometry = extract () in
  Printf.printf "rdk_iso_gyroid,%d,%d,%d,%d,%d,%s,%.6f,%.0f\n%!"
    size domains repeats (Geometry.point_count geometry)
    (Geometry.primitive_count geometry) expected
    (median seconds) (median allocated)
  end
