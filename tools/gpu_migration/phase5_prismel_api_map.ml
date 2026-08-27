open Support

module Strings = Set.Make(String)

let set values = List.fold_left (fun result value -> Strings.add value result)
    Strings.empty values

let require condition format =
  Printf.ksprintf (fun message -> if not condition then fail "%s" message) format

let legacy_dependency_tokens = [ "tsdl"; "sdl2"; "tsdl_gfx"; "opengl" ]

let legacy_dependencies contents =
  let contents = String.lowercase_ascii contents in
  List.filter (fun token -> contains ~needle:token contents) legacy_dependency_tokens

let implementation_path interface_path =
  if Filename.check_suffix interface_path ".mli" then
    Filename.chop_suffix interface_path ".mli" ^ ".ml"
  else fail "direct target is not an interface: %s" interface_path

let verify_direct_source ~root ~name ~target =
  require (String.starts_with ~prefix:"lib/prismel_next_api/" target)
    "%s direct target must be staged under lib/prismel_next_api: %s" name target;
  let interface_path = Filename.concat root target in
  let source_path = implementation_path interface_path in
  require (Sys.file_exists source_path) "%s direct implementation missing: %s" name source_path;
  [ interface_path; source_path ]
  |> List.iter (fun path ->
    let dependencies = legacy_dependencies (read_file path) in
    require (dependencies = []) "%s direct source has legacy dependencies in %s: [%s]"
      name path (String.concat "," dependencies))

let () =
  require (legacy_dependencies "open Vec3\nlet x = 1" = [])
    "legacy dependency scanner rejected target-neutral source";
  require (legacy_dependencies "open Tsdl\nlet backend = `SDL2" = [ "tsdl"; "sdl2" ])
    "legacy dependency scanner failed its exact rejection self-test";
  let root=ref "." in
  Arg.parse ["--root",Arg.Set_string root,"repository root"]
    (fun value->raise(Arg.Bad value)) "phase5_prismel_api_map";
  let root=Unix.realpath !root in
  let load path=Yojson.Safe.from_file(Filename.concat root path) in
  let open Yojson.Safe.Util in
  let baseline=load "specification/evidence/gpu_migration/api_stable.json" in
  let mapping=load "specification/evidence/gpu_migration/phase5_prismel_api_map.json" in
  let baseline_modules=baseline|>member "modules"|>to_list|>List.filter_map(fun entry->
    if entry|>member "library"|>to_string="prismel" then
      Some(entry|>member "module"|>to_string) else None) in
  let rows=mapping|>member "modules"|>to_list in
  let mapped_names=rows|>List.map(fun row->row|>member "module"|>to_string) in
  require(List.length mapped_names=Strings.cardinal(set mapped_names))
    "duplicate module in preservation map";
  let missing=Strings.diff(set baseline_modules)(set mapped_names)|>Strings.elements
  and extra=Strings.diff(set mapped_names)(set baseline_modules)|>Strings.elements in
  require(missing=[]&&extra=[])"module map drift: missing=[%s] extra=[%s]"
    (String.concat "," missing)(String.concat "," extra);
  let direct=ref 0 and implemented=ref 0 and adapted=ref 0 and raw=ref 0 in
  List.iter(fun row->
    let name=row|>member "module"|>to_string
    and status=row|>member "status"|>to_string
    and target=row|>member "target"|>to_string
    and note=row|>member "note"|>to_string in
    require(note<>"")"%s has empty mapping note" name;
    require(Sys.file_exists(Filename.concat root target))"%s target missing: %s" name target;
    match status with
    | "direct" ->
        incr direct;
        let old_path=Filename.concat root
          ("lib/prismel/"^String.lowercase_ascii name^".mli") in
        require(Sys.file_exists old_path)"%s direct baseline source missing" name;
        require(read_file old_path=read_file(Filename.concat root target))
          "%s direct interface is not byte-identical" name;
        verify_direct_source ~root ~name ~target
    | "adapted" -> incr adapted
    | "implemented" -> incr implemented
    | "raw_only" -> incr raw
    | value -> fail "%s has unknown status %s" name value)rows;
  let omissions=mapping|>member "raw_only_omissions"|>to_list|>List.map to_string in
  require(List.length omissions=Strings.cardinal(set omissions))
    "duplicate raw-only omission";
  require(omissions=[
    "Prismel.Low.Graphics.get_renderer";
    "Prismel.Low.Window.get_window";
    "Prismel.Low.Window.get_renderer";
    "Prismel.Low.Window.get_window_flags";
    "Prismel.Low.Window.get_renderer_flags";
    "Prismel.Low.Window.with_gpu_context";
    "Prismel.Low.Window.t.window";
    "Prismel.Low.Window.t.renderer";
    "Prismel.Low.Window.t.renderer_context"])
    "raw-only omission allowlist drift";
  Printf.printf
    "Phase5 Prismel API map passed: %d baseline modules = %d direct + %d implemented-adapted + %d pending-adapted + %d raw-only; %d exact Low omissions\n"
    (List.length rows)!direct !implemented !adapted !raw (List.length omissions)
