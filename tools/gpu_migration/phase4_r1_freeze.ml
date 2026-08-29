open Support

let baseline = "4622091a65bc9a8816a1f10bcc83c1a625ca7522"
let plan_sha256 = "6f95e5738ae263386bbc414299f598f25ba9f604b48a8c2ef9bee84f974e2954"
let api_sha256 = "3d46ec450839d95bfc1a797bf1485caf351b2000faf776752814ff1af5a23e93"

let acceptance =
  [ "examples/audio/dune",
      "fc4599bdc0ca71c8a3c66228449b538b2c0fa53d5cc834a913c46969e19bb6c5"
  ; "examples/audio/main.ml",
      "83021b5e8c42bd621f92ee5483512b23d5f77a4878e0a56a82007b41d6b6bbb8"
  ; "examples/basic/dune",
      "fc4599bdc0ca71c8a3c66228449b538b2c0fa53d5cc834a913c46969e19bb6c5"
  ; "examples/basic/main.ml",
      "2371218b3f9b730b41765fc4693f40d43a85deb28a3136f45fd1b0ec1097be8a"
  ; "examples/generative/dune",
      "fc4599bdc0ca71c8a3c66228449b538b2c0fa53d5cc834a913c46969e19bb6c5"
  ; "examples/generative/main.ml",
      "41927872ba1ad79847aab54a3839f9a18ea703928fd6b7393a3fa390b53afdee"
  ; "examples/noise/dune",
      "fc4599bdc0ca71c8a3c66228449b538b2c0fa53d5cc834a913c46969e19bb6c5"
  ; "examples/noise/main.ml",
      "d0108a8785a9291eb27e83fdf92cde647eb5dbb1817fd7555cafb982a8478c16"
  ; "examples/particles/dune",
      "fc4599bdc0ca71c8a3c66228449b538b2c0fa53d5cc834a913c46969e19bb6c5"
  ; "examples/particles/main.ml",
      "621edf57487dc423603737da69800552a65745493ff8f371aab0731488882b84"
  ; "examples/pxui/dune",
      "86854292e4aebf0abdf0975a83b9e30df1f7982b196a90f2d577d23614fd17dc"
  ; "examples/pxui/main.ml",
      "0b24ffc40b539179ebb4da41fb06de3d58253cfe94aeab98b8332b5f74e9103a" ]

let reviewed_shattered_r11 =
  [ "sketches/shattered_cube/dune",
      "ca6993ba10353aea05b28784061bd823b9ee4fef236cfb7c242051c6a82fce27"
  ; "sketches/shattered_cube/main.ml",
      "32f421c14ce0866e09bfc4f7e362beff7718286a44cfe805459b9dcf5f203dab"
  ; "sketches/shattered_cube/r11_native.ml",
      "eec23556a3b31335ada58539333b4bbf2a0b5c38df6f7d70a09ccf0c673a05c8"
  ]

let require condition format =
  Printf.ksprintf (fun message -> if not condition then raise (Error message)) format

let git root arguments = command_output ~cwd:root "/usr/bin/git" arguments

let () =
  let root = ref "." in
  Arg.parse [ "--root", Arg.Set_string root, "repository root" ]
    (fun value -> raise (Arg.Bad value)) "phase4_r1_freeze";
  let root = Unix.realpath !root in
  let baseline_value =
    Yojson.Safe.from_file
      (Filename.concat root "specification/evidence/gpu_migration/phase0_baseline.json")
  in
  let open Yojson.Safe.Util in
  require (baseline_value |> member "baseline_commit" |> to_string = baseline)
    "Phase-0 baseline commit drift";
  require (git root [ "merge-base"; "HEAD"; baseline ] = baseline)
    "Phase-0 baseline is not an ancestor of HEAD";
  let plan = read_file (Filename.concat root "NEW_GPU_STUFF.md") in
  require (sha256 plan = plan_sha256) "frozen plan hash drift";
  List.iter
    (fun (path, expected) ->
      let actual = read_file (Filename.concat root path) |> sha256 in
      require (actual = expected) "native acceptance source drift: %s" path)
    acceptance;
  List.iter
    (fun (path, expected) ->
      let actual = read_file (Filename.concat root path) |> sha256 in
      require (actual = expected)
        "reviewed shattered-cube R11 source drift: %s" path)
    reviewed_shattered_r11;
  let api_path =
    Filename.concat root "specification/evidence/gpu_migration/api_stable.json"
  in
  require (sha256 (read_file api_path) = api_sha256)
    "stable API manifest bytes drift";
  let public_interfaces =
    command_output ~cwd:root "/usr/bin/find"
      [ "lib/prismel"; "lib/runtime"; "-maxdepth"; "1"; "-name"; "*.mli";
        "-type"; "f" ]
    |> String.split_on_char '\n'
    |> List.filter (fun path -> path <> "")
  in
  let forbidden = [ "GPU_MIGRATION"; "USE_RASTER2"; "USE_OGPU" ] in
  List.iter
    (fun path ->
      let source = read_file (Filename.concat root path) |> String.uppercase_ascii in
      List.iter
        (fun token -> require (not (contains ~needle:token source))
            "public migration flag %s is exposed by %s" token path)
        forbidden)
    public_interfaces;
  let sketch = read_file (Filename.concat root "lib/prismel/sketch.ml") in
  let prismel_dune = read_file (Filename.concat root "lib/prismel/dune") in
  require (not (Sys.file_exists (Filename.concat root "lib/raster2")))
    "retired Raster2 library directory still exists";
  require (contains ~needle:"Scene.Private.stage_native" sketch
           && contains ~needle:"Prismel_next_execution.step" sketch)
    "Sketch no longer stages and submits through native execution";
  List.iter
    (fun token -> require (not (contains ~needle:token prismel_dune))
        "retired renderer dependency %s remains linked into Prismel" token)
    [ "raster2"; "tsdl"; "runtime_next_compat" ];
  Printf.printf
    "Phase4 R1 freeze: plan/API hashes, 6 native acceptance examples, reviewed shattered-cube R11 sources, ancestry, private flags, and native-only selection passed\n"
