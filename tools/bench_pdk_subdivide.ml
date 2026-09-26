open Pdk

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let get = function Ok value -> value
  | Error error -> failwith (Error.to_string error)

let digest geometry =
  let positions = Geometry.positions geometry
  and topology = Geometry.topology geometry in
  let hash = ref 0 in
  for point = 0 to Geometry.point_count geometry - 1 do
    hash := Hashtbl.hash (!hash, Packed.Float3.get positions point)
  done;
  for vertex = 0 to Geometry.vertex_count geometry - 1 do
    hash := Hashtbl.hash (!hash, Topology.point_of_vertex topology vertex)
  done;
  !hash

let median values =
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let () =
  let resolution = integer_env "PRISMEL_PDK_SUBDIVIDE_RESOLUTION" 96
  and repeats = integer_env "PRISMEL_BENCH_REPEATS" 5
  and domains = integer_env "PRISMEL_BENCH_DOMAINS" 1 in
  let source = Plane_generators.grid_checked ~connectivity:Plane_generators.Grid_triangles
      ~columns:resolution ~rows:resolution ~size:10. () |> get in
  let measure name operation =
    let run () = Prismel.Parallel.run ~domains (fun () ->
      operation source |> get) in
    let expected = run () |> digest in
    let seconds = Array.make repeats 0.
    and allocated = Array.make repeats 0. in
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let result = run () in
      seconds.(repeat) <- Unix.gettimeofday () -. started;
      allocated.(repeat) <- Gc.allocated_bytes () -. before;
      if digest result <> expected then failwith (name ^ " digest changed")
    done;
    let result = run () in
    Printf.printf "%s,%d,%d,%d,%d,%d,%d,%.6f,%.0f\n%!"
      name resolution domains repeats
      (Geometry.point_count result) (Geometry.primitive_count result)
      expected (median seconds) (median allocated) in
  print_endline "benchmark,resolution,domains,repeats,points,primitives,digest,median_seconds,median_allocated_bytes";
  measure "butterfly" Subdivision_extra.butterfly;
  measure "doo_sabin" Subdivision_extra.doo_sabin
