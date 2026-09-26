open Pdk
open Prismel_math

let get = function Ok value -> value | Error error -> failwith (Error.to_string error)
let check condition message = if not condition then failwith message

let with_file suffix work =
  let filename = Filename.temp_file "pdk-io-" suffix in
  Fun.protect ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
    (fun () -> work filename)

let source () =
  let positions = Packed.Float3.of_owned
      ~x:[|0.; 1.; 0.|] ~y:[|0.; 0.; 1.|] ~z:[|0.; 0.; 0.|]
      |> Result.get_ok in
  let topology = Topology.polygons_owned ~point_count:3
      ~vertex_points:[|0; 1; 2|] ~primitive_offsets:[|0; 3|]
      |> Result.get_ok in
  Geometry.create ~positions ~topology () |> Result.get_ok
  |> Normal_ops.run_checked |> get

let snapshot geometry =
  let positions = Geometry.positions geometry
  and topology = Geometry.topology geometry in
  Array.init (Geometry.point_count geometry) (Packed.Float3.get positions),
  Array.init (Geometry.vertex_count geometry)
    (Topology.point_of_vertex topology),
  Geometry.primitive_count geometry

let write filename text =
  let channel = open_out_bin filename in
  Fun.protect ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel text)

let run () =
  let expected = snapshot (source ()) in
  let roundtrip ?(expected = expected) label suffix save load =
    with_file suffix (fun filename ->
      save (source ()) filename |> get |> ignore;
      let sample domains = Parallel.run ~domains (fun () ->
        load filename |> get |> snapshot) in
      check (sample 1 = expected && sample 4 = expected)
        (label ^ " roundtrip or domain parity changed")) in
  roundtrip "binary STL" ".stl" (Io.save_stl ~format:Io.Binary)
    Io.load_stl;
  roundtrip "ASCII STL" ".stl" (Io.save_stl ~format:Io.Ascii)
    Io.load_stl;
  let off_expected =
    [|(0., 0., 0.); (0., 0., 1.); (0., 1., 0.)|], [|0; 1; 2|], 1 in
  roundtrip ~expected:off_expected "OFF" ".off" Io.save_off Io.load_off;
  roundtrip "OBJ" ".obj" Io.save_obj Io.load_obj;
  with_file ".off" (fun filename ->
    write filename "OFF\n-1 1 0\n";
    match Io.load_off filename with
    | Error _ -> () | Ok _ -> failwith "negative OFF count accepted");
  with_file ".obj" (fun filename ->
    write filename "v 0 0 0\nf 1 2 3\n";
    match Io.load_obj filename with
    | Error _ -> () | Ok _ -> failwith "invalid OBJ index accepted");
  with_file ".stl" (fun filename ->
    let cancel = Cancel.create () in
    Cancel.cancel cancel;
    match Io.load_stl ~cancel filename with
    | Error error when Error.code error = "cancelled" -> ()
    | _ -> failwith "cancelled STL load succeeded");
  print_endline "PDK mesh IO fixtures passed"
