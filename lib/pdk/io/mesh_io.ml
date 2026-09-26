open Pdk_core
open Prismel_math

type stl_format = Ascii | Binary

let guard operation work =
  Error.guard ~operation ~code:"io_error" (fun () ->
    try work () with
    | Sys_error message | Failure message | Invalid_argument message ->
        Error message
    | End_of_file -> Error "unexpected end of file")

let with_input filename work =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () -> work channel)

let with_output filename work =
  let channel = open_out_bin filename in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () -> work channel)

let read_bytes filename = with_input filename (fun channel ->
  let length = in_channel_length channel in
  let bytes = Bytes.create length in
  really_input channel bytes 0 length;
  bytes)

let finite_float text =
  let value = float_of_string text in
  if not (Float.is_finite value) then failwith "non-finite coordinate";
  value

let words line =
  String.split_on_char ' ' (String.trim line)
  |> List.filter (fun word -> word <> "")

let packed_positions points =
  let count = Array.length points in
  let x = Array.make count 0. and y = Array.make count 0.
  and z = Array.make count 0. in
  Array.iteri (fun index point ->
    if not (Float.is_finite point.Vec3.x && Float.is_finite point.y
      && Float.is_finite point.z) then failwith "non-finite coordinate";
    x.(index) <- point.x; y.(index) <- point.y; z.(index) <- point.z)
    points;
  Packed.Float3.Private.of_owned_exn ~x ~y ~z

let geometry ?(attributes = []) points indices =
  if Array.length indices mod 3 <> 0 then
    Error "triangle index count is not divisible by three"
  else
    let positions = packed_positions points in
    let primitive_offsets = Array.init (Array.length indices / 3 + 1)
        (fun index -> index * 3) in
    Result.bind
      (Topology.polygons_owned ~point_count:(Array.length points)
         ~vertex_points:indices ~primitive_offsets)
      (fun topology -> Geometry.create ~positions ~topology ~attributes ())

let normal_geometry ?cancel points indices =
  Result.bind (geometry points indices) (fun value ->
    Normal_ops.run_checked ?cancel value
    |> Result.map_error Error.message)

let float_of_le bytes offset =
  Bytes.get_int32_le bytes offset |> Int32.float_of_bits

let set_float_le bytes offset value =
  Bytes.set_int32_le bytes offset (Int32.bits_of_float value)

let binary_stl bytes =
  let length = Bytes.length bytes in
  if length < 84 then false
  else
    let count = Bytes.get_int32_le bytes 80 |> Int32.to_int in
    count >= 0 && count <= (length - 84) / 50
    && length = 84 + count * 50

let load_stl ?cancel filename = guard "io.load_stl" (fun () ->
  let bytes = read_bytes filename in
  Cancel.check_opt cancel;
  let points =
    if binary_stl bytes then begin
      let count = Bytes.get_int32_le bytes 80 |> Int32.to_int in
      Array.init (count * 3) (fun index ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        let triangle = index / 3 and corner = index mod 3 in
        let offset = 84 + triangle * 50 + 12 + corner * 12 in
        Vec3.create (float_of_le bytes offset)
          (float_of_le bytes (offset + 4))
          (float_of_le bytes (offset + 8)))
    end else begin
      let points = ref [] in
      String.split_on_char '\n' (Bytes.to_string bytes)
      |> List.iteri (fun index line ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        match words line with
        | "vertex" :: x :: y :: z :: _ ->
            points := Vec3.create (finite_float x) (finite_float y)
                (finite_float z) :: !points
        | _ -> ());
      Array.of_list (List.rev !points)
    end in
  if Array.length points = 0 then Error "STL contains no vertices"
  else if Array.length points mod 3 <> 0 then
    Error "STL vertex count is not divisible by three"
  else normal_geometry ?cancel points (Array.init (Array.length points) Fun.id))

let triangle_surface ?cancel value =
  if Topology.all_triangles (Geometry.topology value) then Ok value
  else Pdk_mesh.Ops.triangulate ?cancel value
    |> Result.map_error Error.message

let face_normals ?cancel value =
  Face_normals.compute ?cancel ~operation:"io" value

let point (positions : Packed.Float3.Private.view) index =
  positions.x.(index), positions.y.(index), positions.z.(index)

let save_stl ?cancel ?(format = Binary) value filename =
  guard "io.save_stl" (fun () ->
    Result.bind (triangle_surface ?cancel value) (fun value ->
      let topology = Geometry.topology value in
      let count = Topology.primitive_count topology in
      if count = 0 then Error "mesh has no triangles"
      else Result.bind (face_normals ?cancel value) (fun (nx, ny, nz) ->
        let positions = Packed.Float3.Private.view (Geometry.positions value) in
        let vertex_points = (Topology.Private.view topology).vertex_points in
        let write_vertex channel point_index =
          let x, y, z = point positions point_index in
          Printf.fprintf channel "      vertex %.9g %.9g %.9g\n" x y z in
        match format with
        | Ascii ->
            with_output filename (fun channel ->
              output_string channel "solid prismel\n";
              for triangle = 0 to count - 1 do
                if triangle land 4095 = 0 then Cancel.check_opt cancel;
                Printf.fprintf channel "  facet normal %.9g %.9g %.9g\n"
                  nx.(triangle) ny.(triangle) nz.(triangle);
                output_string channel "    outer loop\n";
                let first = triangle * 3 in
                for corner = 0 to 2 do
                  write_vertex channel vertex_points.(first + corner)
                done;
                output_string channel "    endloop\n  endfacet\n"
              done;
              output_string channel "endsolid prismel\n");
            Ok ()
        | Binary ->
            if count > (Sys.max_string_length - 84) / 50
               || count > Int32.to_int Int32.max_int then
              Error "STL output is too large"
            else begin
              let bytes = Bytes.make (84 + count * 50) '\000' in
              let header = "Prismel binary STL" in
              Bytes.blit_string header 0 bytes 0 (String.length header);
              Bytes.set_int32_le bytes 80 (Int32.of_int count);
              for triangle = 0 to count - 1 do
                if triangle land 4095 = 0 then Cancel.check_opt cancel;
                let base = 84 + triangle * 50 in
                let write_point offset (x, y, z) =
                  set_float_le bytes offset x;
                  set_float_le bytes (offset + 4) y;
                  set_float_le bytes (offset + 8) z in
                write_point base (nx.(triangle), ny.(triangle), nz.(triangle));
                for corner = 0 to 2 do
                  write_point (base + 12 + corner * 12)
                    (point positions vertex_points.(triangle * 3 + corner))
                done;
                Bytes.set_uint16_le bytes (base + 48) 0
              done;
              with_output filename (fun channel -> output_bytes channel bytes);
              Ok ()
            end)))

let tokenize_off text =
  String.split_on_char '\n' text
  |> List.map (fun line ->
    match String.index_opt line '#' with
    | None -> line | Some index -> String.sub line 0 index)
  |> String.concat "\n"
  |> String.map (fun character ->
    if character = '\t' || character = '\r' || character = '\n'
    then ' ' else character)
  |> words

let load_off ?cancel filename = guard "io.load_off" (fun () ->
  let text = read_bytes filename |> Bytes.to_string in
  let tokens = ref (tokenize_off text) in
  let next () = match !tokens with
    | value :: rest -> tokens := rest; value
    | [] -> failwith "unexpected end of OFF file" in
  if next () <> "OFF" then Error "missing OFF header"
  else
    let point_count = int_of_string (next ())
    and face_count = int_of_string (next ()) in
    ignore (next ());
    if point_count < 0 || face_count < 0
       || point_count >= Sys.max_array_length
       || face_count >= Sys.max_array_length
       || point_count > List.length !tokens / 3 then
      Error "invalid OFF counts"
    else begin
      let points = Array.init point_count (fun index ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        Vec3.create (finite_float (next ())) (finite_float (next ()))
          (finite_float (next ()))) in
      let triangles = ref [] in
      for face = 0 to face_count - 1 do
        if face land 4095 = 0 then Cancel.check_opt cancel;
        let count = int_of_string (next ()) in
        if count < 3 || count >= Sys.max_array_length then
          failwith "OFF face has invalid vertex count";
        let face_points = Array.init count (fun _ -> int_of_string (next ())) in
        Array.iter (fun index ->
          if index < 0 || index >= point_count then
            failwith "OFF face index out of range") face_points;
        for corner = 1 to count - 2 do
          triangles := face_points.(0) :: face_points.(corner)
            :: face_points.(corner + 1) :: !triangles
        done
      done;
      normal_geometry ?cancel points (Array.of_list !triangles)
    end)

let save_off ?cancel value filename = guard "io.save_off" (fun () ->
  let topology = Geometry.topology value in
  let count = Topology.primitive_count topology in
  if count = 0 then Error "mesh has no polygons"
  else begin
    let positions = Packed.Float3.Private.view (Geometry.positions value) in
    with_output filename (fun channel ->
      output_string channel "OFF\n";
      Printf.fprintf channel "%d %d 0\n" (Geometry.point_count value) count;
      for index = 0 to Geometry.point_count value - 1 do
        if index land 4095 = 0 then Cancel.check_opt cancel;
        let x, y, z = point positions index in
        Printf.fprintf channel "%.17g %.17g %.17g\n" x y z
      done;
      for primitive = 0 to count - 1 do
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        if Topology.primitive_kind topology primitive <> Topology.Polygon then
          failwith "OFF requires polygon primitives";
        let first, last = Topology.primitive_vertex_range topology primitive in
        Printf.fprintf channel "%d" (last - first);
        for vertex = first to last - 1 do
          Printf.fprintf channel " %d" (Topology.point_of_vertex topology vertex)
        done;
        output_char channel '\n'
      done);
    Ok ()
  end)

let obj_words line =
  let line = match String.index_opt line '#' with
    | None -> line | Some index -> String.sub line 0 index in
  String.map (fun character -> if character = '\t' then ' ' else character) line
  |> words

let obj_corner value =
  let integer text = if text = "" then None else Some (int_of_string text) in
  match String.split_on_char '/' value with
  | [position] -> int_of_string position, None, None
  | [position; texture] -> int_of_string position, integer texture, None
  | [position; texture; normal] ->
      int_of_string position, integer texture, integer normal
  | _ -> failwith ("invalid OBJ corner " ^ value)

let resolve_obj count raw =
  let index = if raw > 0 then raw - 1 else count + raw in
  if index < 0 || index >= count then failwith "OBJ index out of range";
  index

let load_obj ?cancel filename = guard "io.load_obj" (fun () ->
  let source_positions = ref [] and source_normals = ref []
  and source_uv = ref [] and faces = ref [] in
  with_input filename (fun channel ->
    let line = ref 0 in
    (try while true do
      incr line;
      if !line land 4095 = 0 then Cancel.check_opt cancel;
      match obj_words (input_line channel) with
      | [] -> ()
      | "v" :: x :: y :: z :: _ ->
          source_positions := Vec3.create (finite_float x) (finite_float y)
              (finite_float z) :: !source_positions
      | "vn" :: x :: y :: z :: _ ->
          source_normals := Vec3.create (finite_float x) (finite_float y)
              (finite_float z) :: !source_normals
      | "vt" :: u :: v :: _ ->
          source_uv := Vec2.create (finite_float u) (finite_float v)
            :: !source_uv
      | "f" :: corners when List.length corners >= 3 ->
          faces := List.map obj_corner corners :: !faces
      | ("v" | "vn" | "vt" | "f") :: _ ->
          failwith (Printf.sprintf "incomplete OBJ record at line %d" !line)
      | _ -> ()
    done with End_of_file -> ()));
  let source_positions = Array.of_list (List.rev !source_positions)
  and source_normals = Array.of_list (List.rev !source_normals)
  and source_uv = Array.of_list (List.rev !source_uv) in
  let table = Hashtbl.create 128 and positions = ref []
  and normals = ref [] and uv = ref [] and indices = ref []
  and count = ref 0 and has_normal = ref false and has_uv = ref false in
  let intern ((position, texture, normal) as corner) =
    match Hashtbl.find_opt table corner with
    | Some index -> index
    | None ->
        let position = resolve_obj (Array.length source_positions) position in
        let texture = Option.map (resolve_obj (Array.length source_uv)) texture
        and normal = Option.map (resolve_obj (Array.length source_normals)) normal in
        let index = !count in
        incr count;
        Hashtbl.add table corner index;
        positions := source_positions.(position) :: !positions;
        uv := Option.fold ~none:Vec2.zero ~some:(Array.get source_uv) texture
          :: !uv;
        normals := Option.fold ~none:Vec3.zero
          ~some:(Array.get source_normals) normal :: !normals;
        if Option.is_some texture then has_uv := true;
        if Option.is_some normal then has_normal := true;
        index in
  List.rev !faces |> List.iteri (fun face_number corners ->
    if face_number land 4095 = 0 then Cancel.check_opt cancel;
    match corners with
    | first :: second :: rest ->
        let rec fan left = function
          | right :: remaining ->
              let a = intern first and b = intern left and c = intern right in
              indices := c :: b :: a :: !indices;
              fan right remaining
          | [] -> () in
        fan second rest
    | _ -> assert false);
  let positions = Array.of_list (List.rev !positions)
  and normals = Array.of_list (List.rev !normals)
  and uv = Array.of_list (List.rev !uv)
  and indices = Array.of_list (List.rev !indices) in
  let attributes = ref [] in
  if !has_normal then begin
    let packed = packed_positions normals in
    let attribute = Attribute.create_key_owned
        (Attribute.normal ~owner:Attribute.Point) packed |> Result.get_ok in
    attributes := attribute :: !attributes
  end;
  if !has_uv then begin
    let count = Array.length uv in
    let u = Array.init count (fun index -> uv.(index).Vec2.x)
    and v = Array.init count (fun index -> uv.(index).y) in
    let packed = Packed.Float2.of_owned ~x:u ~y:v |> Result.get_ok in
    let attribute = Attribute.create_key_owned
        (Attribute.tex_coord ~owner:Attribute.Point) packed |> Result.get_ok in
    attributes := attribute :: !attributes
  end;
  Result.bind (geometry ~attributes:!attributes positions indices)
    (fun value -> if !has_normal then Ok value
      else Normal_ops.run_checked ?cancel value
        |> Result.map_error Error.message))

let standard_attribute geometry name owner kind =
  match Geometry.find_attribute ~owner name geometry with
  | None -> Ok None
  | Some attribute ->
      (match kind (Attribute.storage attribute) with
       | Some value -> Ok (Some value)
       | None -> Error ("attribute " ^ name ^ " has wrong storage"))

let save_obj ?cancel value filename = guard "io.save_obj" (fun () ->
  Result.bind (triangle_surface ?cancel value) (fun value ->
    let topology = Geometry.topology value in
    let normals =
      match standard_attribute value "N" Attribute.Vertex
          (function Attribute.Float3 packed -> Some packed | _ -> None) with
      | Ok (Some packed) -> Ok (Some (Attribute.Vertex, packed))
      | Ok None -> Result.map (Option.map (fun packed -> Attribute.Point, packed))
          (standard_attribute value "N" Attribute.Point
             (function Attribute.Float3 packed -> Some packed | _ -> None))
      | Error _ as error -> error
    and uv =
      match standard_attribute value "uv" Attribute.Vertex
          (function Attribute.Float2 packed -> Some packed | _ -> None) with
      | Ok (Some packed) -> Ok (Some (Attribute.Vertex, packed))
      | Ok None -> Result.map (Option.map (fun packed -> Attribute.Point, packed))
          (standard_attribute value "uv" Attribute.Point
             (function Attribute.Float2 packed -> Some packed | _ -> None))
      | Error _ as error -> error in
    match normals, uv with
    | Error message, _ | _, Error message -> Error message
    | Ok normals, Ok uv ->
        let positions = Packed.Float3.Private.view (Geometry.positions value) in
        with_output filename (fun channel ->
          for index = 0 to Geometry.point_count value - 1 do
            if index land 4095 = 0 then Cancel.check_opt cancel;
            let x, y, z = point positions index in
            Printf.fprintf channel "v %.17g %.17g %.17g\n" x y z
          done;
          Option.iter (fun (_, packed) ->
            for index = 0 to Packed.Float2.length packed - 1 do
              let u, v = Packed.Float2.get packed index in
              Printf.fprintf channel "vt %.17g %.17g\n" u v
            done) uv;
          Option.iter (fun (_, packed) ->
            for index = 0 to Packed.Float3.length packed - 1 do
              let x, y, z = Packed.Float3.get packed index in
              Printf.fprintf channel "vn %.17g %.17g %.17g\n" x y z
            done) normals;
          let corner vertex =
            let point = Topology.point_of_vertex topology vertex in
            let index owner =
              (if owner = Attribute.Vertex then vertex else point) + 1 in
            let p = point + 1 in
            match uv, normals with
            | None, None -> string_of_int p
            | Some (owner, _), None -> Printf.sprintf "%d/%d" p (index owner)
            | None, Some (owner, _) -> Printf.sprintf "%d//%d" p (index owner)
            | Some (texture_owner, _), Some (normal_owner, _) ->
                Printf.sprintf "%d/%d/%d" p (index texture_owner)
                  (index normal_owner) in
          for primitive = 0 to Topology.primitive_count topology - 1 do
            if primitive land 4095 = 0 then Cancel.check_opt cancel;
            let first, last = Topology.primitive_vertex_range topology primitive in
            if last - first <> 3 then failwith "OBJ requires triangles";
            Printf.fprintf channel "f %s %s %s\n"
              (corner first) (corner (first + 1)) (corner (first + 2))
          done);
        Ok ()))
