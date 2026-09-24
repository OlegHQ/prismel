open Prismel
open Procedural

type artifact = {
  pieces : int; triangles : int; render_vertices : int;
  cook_seconds : float; cook_seconds_four : float; pack_seconds : float;
  topology_hash : string; attribute_hash : string; order_hash : string;
  render_hash : string; vertices : bytes; indices : bytes;
}

let maybe_run graph =
  if Array.exists ((=) "--r11-artifact") Sys.argv then begin
    let artifact_path = ref None and visibility = ref None
    and seconds = ref None and report = ref None in
    Arg.parse [
      "--r11-artifact", Arg.String (fun value -> artifact_path := Some value), "R11 artifact";
      "--r11-visibility", Arg.String (fun value -> visibility := Some value), "R11 visibility";
      "--r11-seconds", Arg.String (fun value -> seconds := Some value), "R11 duration";
      "--r11-report", Arg.String (fun value -> report := Some value), "R11 report";
    ] (fun value -> invalid_arg ("unexpected R11 argument: " ^ value))
      "shattered_cube R11 benchmark";
    let artifact_path = Option.get !artifact_path
    and visibility = Option.get !visibility
    and seconds = Option.get !seconds
    and report = Option.get !report in
    let input = open_in_bin artifact_path in
    let artifact : artifact = Fun.protect ~finally:(fun () -> close_in input)
      (fun () -> Marshal.from_channel input) in
    if (artifact.pieces, artifact.triangles, artifact.render_vertices) <>
       (18_278, 278_368, 835_104) then
      failwith "shattered_cube R11 artifact cardinality drift";
    if Bytes.length artifact.vertices <> artifact.render_vertices * 68
       || Bytes.length artifact.indices <> artifact.triangles * 12 then
      failwith "shattered_cube R11 packed artifact cardinality drift";
    let cooked_pieces, cooked_triangles, cooked_vertices, cooked_render_hash, cooked_mesh =
      Parallel.run ~domains:1 (fun () ->
        let node = graph () in
        let get = function Ok value -> value | Error message -> failwith message in
        let session = get (Session.create ~max_entries:24
          ~max_payload_bytes:(256 * 1024 * 1024)) in
        let context = get (Context.create ~seed:7349L ~domains:1 ~grain:2 ()) in
        Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
          let output = match Session.cook session ~context node with
            | Ok value -> value
            | Error error -> failwith (Diagnostic.error_to_string error) in
          let pieces = get (Sketch_support.Packed_pieces.of_geometry
            ~piece_attribute:"piece" output.geometry) in
          let mesh = Sketch_support.Packed_pieces.mesh_for_node node pieces in
          let view = Mesh.Private.packed_view mesh in
          Sketch_support.Packed_pieces.piece_count pieces,
          Mesh.Private.triangle_count mesh, Mesh.vertex_count mesh,
          Digest.to_hex (Digest.string (Marshal.to_string
            (view.mode, view.vertices, view.indices, view.normals, view.colors,
             view.tex_coords) [])), mesh)) in
    if (cooked_pieces, cooked_triangles, cooked_vertices) <>
       (artifact.pieces, artifact.triangles, artifact.render_vertices)
       || cooked_render_hash <> artifact.render_hash then
      failwith "shattered_cube R11 artifact does not match the sketch graph";
    R11_native.run ~visibility ~seconds:(float_of_string seconds) ~report
      ~metadata:{pieces=artifact.pieces;triangles=artifact.triangles;
        render_vertices=artifact.render_vertices;cook_seconds=artifact.cook_seconds;
        cook_seconds_four=artifact.cook_seconds_four;pack_seconds=artifact.pack_seconds;
        topology_hash=artifact.topology_hash;attribute_hash=artifact.attribute_hash;
        order_hash=artifact.order_hash;render_hash=artifact.render_hash;
        artifact=artifact_path} cooked_mesh;
    exit 0
  end
