open Pdk
open Prismel_math

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let median values =
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let digest geometry =
  let positions = Geometry.positions geometry
  and topology = Geometry.topology geometry in
  let hash = ref 0 in
  for index = 0 to Geometry.point_count geometry - 1 do
    hash := Hashtbl.hash (!hash, Packed.Float3.get positions index)
  done;
  for vertex = 0 to Geometry.vertex_count geometry - 1 do
    hash := Hashtbl.hash (!hash, Topology.point_of_vertex topology vertex)
  done;
  !hash

let () =
  let resolution = integer_env "PRISMEL_PDK_ISO_RESOLUTION" 40
  and domains = integer_env "PRISMEL_BENCH_DOMAINS" 1
  and repeats = integer_env "PRISMEL_BENCH_REPEATS" 7 in
  let field = Iso_surface.Field.gyroid ~scale:1.25 () in
  let extract () = Parallel.run ~domains (fun () ->
    Iso_surface.extract_dense
      ~resolution:(resolution, resolution, resolution)
      ~min:(Vec3.create (-3.) (-3.) (-3.))
      ~max:(Vec3.create 3. 3. 3.) ~iso:0. ~field ()
    |> function Ok value -> value
      | Error error -> failwith (Error.to_string error)) in
  let expected = extract () |> digest in
  let seconds = Array.make repeats 0.
  and allocated = Array.make repeats 0. in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.allocated_bytes ()
    and started = Unix.gettimeofday () in
    let geometry = extract () in
    seconds.(repeat) <- Unix.gettimeofday () -. started;
    allocated.(repeat) <- Gc.allocated_bytes () -. before;
    if digest geometry <> expected then failwith "isosurface digest changed"
  done;
  Printf.printf "benchmark,resolution,domains,repeats,points,primitives,digest,median_seconds,median_allocated_bytes\n";
  let geometry = extract () in
  Printf.printf "pdk_iso_gyroid,%d,%d,%d,%d,%d,%d,%.6f,%.0f\n%!"
    resolution domains repeats (Geometry.point_count geometry)
    (Geometry.primitive_count geometry) expected
    (median seconds) (median allocated)
