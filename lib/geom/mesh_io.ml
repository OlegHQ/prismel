open Prismel

type stl_format = Ascii | Binary

let protect_io context operation =
  try Ok (operation ()) with
  | Sys_error message | Failure message | Invalid_argument message ->
      Error (context ^ ": " ^ message)
  | End_of_file -> Error (context ^ ": unexpected end of file")

let load_exn loader filename =
  match loader filename with Ok mesh -> mesh | Error message -> failwith message

let float_of_le bytes offset =
  Bytes.get_int32_le bytes offset |> Int32.float_of_bits

let set_float_le bytes offset value =
  Bytes.set_int32_le bytes offset (Int32.bits_of_float value)

let binary_stl bytes =
  if Bytes.length bytes < 84 then false
  else
    let count = Bytes.get_int32_le bytes 80 |> Int32.to_int in
    count >= 0 && Bytes.length bytes = 84 + (count * 50)

let mesh_of_triangle_vertices vertices =
  if List.length vertices mod 3 <> 0 then
    Error "triangle vertex count is not divisible by three"
  else
    Mesh.create ~mode:Mesh.Triangles vertices
    |> Result.map Mesh.flat_shaded

let load_binary_stl bytes =
  let count = Bytes.get_int32_le bytes 80 |> Int32.to_int in
  let vertices = ref [] in
  for triangle = 0 to count - 1 do
    let base = 84 + (triangle * 50) + 12 in
    for vertex = 0 to 2 do
      let offset = base + (vertex * 12) in
      vertices := Vec3.create
          (float_of_le bytes offset)
          (float_of_le bytes (offset + 4))
          (float_of_le bytes (offset + 8)) :: !vertices
    done
  done;
  mesh_of_triangle_vertices (List.rev !vertices)

let words line =
  String.split_on_char ' ' (String.trim line)
  |> List.filter (fun value -> value <> "")

let load_ascii_stl text =
  let vertices = ref [] in
  String.split_on_char '\n' text
  |> List.iter (fun line ->
    match words line with
    | "vertex" :: x :: y :: z :: _ ->
        vertices := Vec3.create (float_of_string x) (float_of_string y)
            (float_of_string z) :: !vertices
    | _ -> ());
  if !vertices = [] then Error "ASCII STL contains no vertices"
  else mesh_of_triangle_vertices (List.rev !vertices)

let load_stl filename =
  Result.bind
    (protect_io ("Mesh_io.load_stl " ^ filename) (fun () ->
      let channel = open_in_bin filename in
      Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
        let length = in_channel_length channel in
        let bytes = Bytes.create length in
        really_input channel bytes 0 length;
        bytes)))
    (fun bytes ->
    if binary_stl bytes then load_binary_stl bytes
    else load_ascii_stl (Bytes.to_string bytes))

let load_stl_exn = load_exn load_stl

let save_ascii_stl mesh filename =
  let channel = open_out filename in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () ->
    output_string channel "solid prismel\n";
    List.iter (fun (face : Mesh.face) ->
      Printf.fprintf channel "  facet normal %.9g %.9g %.9g\n"
        face.face_normal.x face.face_normal.y face.face_normal.z;
      output_string channel "    outer loop\n";
      let a, b, c = face.points in
      List.iter (fun point -> Printf.fprintf channel
        "      vertex %.9g %.9g %.9g\n" point.Vec3.x point.y point.z)
        [a; b; c];
      output_string channel "    endloop\n  endfacet\n")
      (Mesh.faces mesh);
    output_string channel "endsolid prismel\n")

let save_binary_stl mesh filename =
  let faces = Mesh.faces mesh in
  let count = List.length faces in
  let bytes = Bytes.make (84 + (count * 50)) '\000' in
  let header = "Prismel binary STL" in
  Bytes.blit_string header 0 bytes 0 (String.length header);
  Bytes.set_int32_le bytes 80 (Int32.of_int count);
  List.iteri (fun triangle (face : Mesh.face) ->
    let base = 84 + (triangle * 50) in
    let write_point offset point =
      set_float_le bytes offset point.Vec3.x;
      set_float_le bytes (offset + 4) point.y;
      set_float_le bytes (offset + 8) point.z
    in
    write_point base face.face_normal;
    let a, b, c = face.points in
    write_point (base + 12) a;
    write_point (base + 24) b;
    write_point (base + 36) c;
    Bytes.set_uint16_le bytes (base + 48) 0) faces;
  let channel = open_out_bin filename in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_bytes channel bytes)

let save_stl ?(format = Binary) mesh filename =
  if Mesh.faces mesh = [] then Error "Mesh_io.save_stl: mesh has no triangles"
  else protect_io ("Mesh_io.save_stl " ^ filename) (fun () ->
    match format with Ascii -> save_ascii_stl mesh filename
                    | Binary -> save_binary_stl mesh filename)

let tokenize_off text =
  String.split_on_char '\n' text
  |> List.map (fun line ->
    match String.index_opt line '#' with
    | None -> line | Some index -> String.sub line 0 index)
  |> String.concat "\n"
  |> String.map (fun character -> if character = '\t' || character = '\r' || character = '\n' then ' ' else character)
  |> words

let load_off filename =
  Result.bind
    (protect_io ("Mesh_io.load_off " ^ filename) (fun () ->
      let channel = open_in filename in
      Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
        really_input_string channel (in_channel_length channel))))
    (fun text ->
    let tokens = ref (tokenize_off text) in
    let next () = match !tokens with value :: rest -> tokens := rest; value | [] -> failwith "unexpected end of OFF file" in
    protect_io "Mesh_io.load_off" (fun () ->
      if next () <> "OFF" then failwith "missing OFF header";
      let vertex_count = int_of_string (next ())
      and face_count = int_of_string (next ()) in
      ignore (next ());
      if vertex_count < 0 || face_count < 0 then failwith "negative OFF counts";
      let vertices = Array.init vertex_count (fun _ ->
        Vec3.create (float_of_string (next ())) (float_of_string (next ())) (float_of_string (next ()))) in
      let indices = ref [] in
      for _ = 1 to face_count do
        let count = int_of_string (next ()) in
        if count < 3 then failwith "OFF face has fewer than three vertices";
        let face = Array.init count (fun _ -> int_of_string (next ())) in
        Array.iter (fun index -> if index < 0 || index >= vertex_count then failwith "OFF face index out of range") face;
        for corner = 1 to count - 2 do
          indices := face.(0) :: face.(corner) :: face.(corner + 1) :: !indices
        done
      done;
      Mesh.create_exn ~mode:Mesh.Triangles ~indices:!indices (Array.to_list vertices)
      |> Mesh.recalculate_normals))

let load_off_exn = load_exn load_off

let save_off mesh filename =
  let faces = Mesh.triangles mesh in
  if faces = [] then Error "Mesh_io.save_off: mesh has no triangles"
  else protect_io ("Mesh_io.save_off " ^ filename) (fun () ->
    let vertices = Mesh.vertices mesh in
    let channel = open_out filename in
    Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () ->
      output_string channel "OFF\n";
      Printf.fprintf channel "%d %d 0\n" (List.length vertices) (List.length faces);
      List.iter (fun point -> Printf.fprintf channel "%.17g %.17g %.17g\n" point.Vec3.x point.y point.z) vertices;
      List.iter (fun (a, b, c) -> Printf.fprintf channel "3 %d %d %d\n" a b c) faces))
