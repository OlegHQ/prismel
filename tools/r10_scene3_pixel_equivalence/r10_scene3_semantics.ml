let signature =
  "scene3:sphere96x48:instances12:ellipse1.9x1.2:scale0.38:camera0,0,5.4:diffuse38bdf8:ambient18,22,30:light-0.6,-1,-1.4:cull-back:msaa4"

let width = 64
let height = 64
let pixels = width * height

let write path bytes =
  let output = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr output) (fun () -> output_bytes output bytes)

let metadata path ~backend ~rgba =
  let json =
    `Assoc
      [ "schema", `Int 1; "backend", `String backend;
        "semantic_signature", `String signature; "width", `Int width;
        "height", `Int height;
        "rgba_digest", `String (Digest.to_hex (Digest.bytes rgba)) ]
  in
  write path (Bytes.of_string (Yojson.Safe.to_string json ^ "\n"))
