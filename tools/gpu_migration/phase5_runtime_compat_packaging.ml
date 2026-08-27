open Support

let require condition format =
  Printf.ksprintf (fun message -> if not condition then raise (Error message)) format

let words source =
  String.map (function
    | ('a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '.') as character -> character
    | _ -> ' ') source
  |> String.split_on_char ' ' |> List.filter ((<>) "")

let () =
  let root = ref "." in
  Arg.parse ["--root",Arg.Set_string root,"repository root"]
    (fun value->raise(Arg.Bad value)) "phase5_runtime_compat_packaging";
  let root=Unix.realpath !root in
  let read relative=read_file(Filename.concat root relative)in
  let dune=read"lib/runtime_next_compat/dune"and mli=read"lib/runtime_next_compat/runtime_next_compat.mli"in
  let library_dune = match String.index_opt dune '\n' with
    | None -> dune
    | Some _ ->
        let marker = "\n(test" in
        let rec find index =
          if index + String.length marker > String.length dune then String.length dune
          else if String.sub dune index (String.length marker) = marker then index
          else find (index + 1) in
        String.sub dune 0 (find 0) in
  require(contains~needle:"(public_name prismel.runtime_next_compat)"dune)
    "runtime-next compatibility library is not publicly installable";
  require(contains~needle:"(libraries runtime_next_orchestrator scene_execution ogpu)"dune)
    "runtime-next compatibility dependency set drift";
  List.iter(fun forbidden->require(not(List.mem forbidden(words library_dune)))
    "compatibility package imports forbidden legacy dependency %s"forbidden)
    ["runtime";"prismel";"wap";"tsdl";"tsdl_gfx"];
  List.iter(fun required->require(contains~needle:required mli)
    "compatibility public signature lost %s"required)
    ["val start";"val stop";"val render";"val capture";
     "val api_coverage";"val omitted_raw_api"];
  let project=read"dune-project"in
  List.iter(fun dependency->require(contains~needle:dependency project)
    "package discovery dependency missing: %s"dependency)
    ["conf-sdl3";"conf-sdl3-image";"conf-sdl3-ttf";"conf-sdl3-mixer"];
  let next_dune=read"lib/runtime_next/dune"in
  require(not(contains~needle:"runtime_next_compat"next_dune))
    "foundational runtime-next points upward to compatibility facade";
  let packaging=read"specification/packaging.md"in
  require(contains~needle:"prismel.runtime_next_compat"packaging)
    "packaging documentation omits compatibility facade";
  print_endline"Phase5 Runtime compatibility packaging: public install, exact dependency direction, SDL3 discovery, API and docs passed"
