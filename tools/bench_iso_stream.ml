open Prismel
open Geom

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let () =
  let resolution = integer_env "PRISMEL_ISO_STREAM_RESOLUTION" 256
  and z_resolution = integer_env "PRISMEL_ISO_STREAM_Z"
      (integer_env "PRISMEL_ISO_STREAM_RESOLUTION" 256)
  and domains = integer_env "PRISMEL_BENCH_DOMAINS"
      (Parallel.recommended_domains ()) in
  Gc.full_major ();
  let allocated_before = Gc.allocated_bytes ()
  and started = Unix.gettimeofday () in
  let result = Parallel.run ~domains (fun () ->
    Iso3.extract_dense ~resolution:(resolution, resolution, z_resolution)
      ~min:Vec3.zero
      ~max:(Vec3.create 1. 1. 1.) ~iso:0.
      ~field:(Iso3.Field.constant (-1.)) ()) in
  let elapsed = Unix.gettimeofday () -. started
  and allocated = Gc.allocated_bytes () -. allocated_before
  and stats = Gc.quick_stat () in
  (match result with
   | Error "Iso3.extract: the requested isosurface is empty" -> ()
   | Error message -> failwith message
   | Ok _ -> failwith "constant field unexpectedly produced an isosurface");
  Printf.printf
    "benchmark,resolution_x,resolution_y,resolution_z,samples,domains,seconds,allocated_bytes,peak_heap_bytes\n";
  Printf.printf "iso_stream_empty,%d,%d,%d,%d,%d,%.6f,%.0f,%.0f\n%!"
    resolution resolution z_resolution
    ((resolution + 1) * (resolution + 1) * (z_resolution + 1))
    domains elapsed allocated
    (float_of_int stats.Gc.top_heap_words *. float_of_int (Sys.word_size / 8))
