open Support

let baseline = "4622091a65bc9a8816a1f10bcc83c1a625ca7522"
let plan_sha256 = "75cb47632aa2b26199677560c6382b8b94786af5f704867b40d306ccefbe19d3"
let api_sha256 = "ca6861c5dfbfafd6ea64d1c9837bc218e2af0dfe83a5b9589183384ffefcb7e2"

let acceptance =
  [ "examples/basic"; "examples/particles"; "examples/noise"
  ; "examples/canvas"; "examples/audio"; "examples/pxui"
  ; "examples/generative"; "sketches/shattered_cube" ]

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
    (fun path ->
      let changed = git root ([ "diff"; "--name-only"; baseline; "--"; path ]) in
      require (changed = "") "acceptance source changed: %s (%s)" path changed)
    acceptance;
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
  let forbidden = [ "GPU_MIGRATION"; "RUNTIME_NEXT"; "USE_RASTER2"; "USE_OGPU" ] in
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
  require (contains ~needle:"Scene.render" sketch)
    "legacy Scene.render comparison path is no longer selected by Sketch";
  require (contains ~needle:"Scene_raster2_lowering" prismel_dune
           && contains ~needle:"Scene_ogpu_renderer" prismel_dune)
    "private side-by-side renderer modules are not registered";
  Printf.printf
    "Phase4 R1 freeze: plan/API hashes, 8 acceptance trees, ancestry, private flags, and side-by-side selection passed\n"
