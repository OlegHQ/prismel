open Yojson.Safe.Util

let fail format = Printf.ksprintf failwith format
let require condition format = Printf.ksprintf (fun text -> if not condition then failwith text) format

let run executable =
  let executable = Unix.realpath executable in
  let null = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
  Fun.protect ~finally:(fun () -> Unix.close null) (fun () ->
    let pid = Unix.create_process executable [|executable|] Unix.stdin null null in
    match snd (Unix.waitpid [] pid) with
    | Unix.WEXITED 0 -> ()
    | Unix.WEXITED code -> fail "%s exited %d" executable code
    | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
        fail "%s was interrupted by signal %d" executable signal)

let string64 value field = value |> member field |> to_string |> Int64.of_string

let read path =
  let input=open_in_bin path in
  Fun.protect~finally:(fun()->close_in input)(fun()->really_input_string input(in_channel_length input))

let contains text needle =
  let n=String.length needle in
  let rec loop i=i+n<=String.length text&&(String.sub text i n=needle||loop(i+1))in
  loop 0

let command_output program arguments =
  let input=Unix.open_process_args_in program(Array.of_list(program::arguments))in
  let buffer=Buffer.create 80 in
  (try while true do Buffer.add_string buffer(input_line input);Buffer.add_char buffer '\n' done
   with End_of_file->());
  match Unix.close_process_in input with
  |Unix.WEXITED 0->String.trim(Buffer.contents buffer)
  |Unix.WEXITED code->fail"%s exited %d"program code
  |Unix.WSIGNALED signal|Unix.WSTOPPED signal->fail"%s interrupted by signal %d"program signal

let canonical_commit value =
  String.length value=40&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)value

let validate_provenance root report =
  let root=Unix.realpath root in
  require(command_output"git"["-C";root;"rev-parse";"--show-toplevel"] = root)
    "root is not the canonical Git worktree root";
  require(command_output"git"["-C";root;"status";"--porcelain";"--untracked-files=all"] = "")
    "R9 synthesis requires a clean Git worktree";
  let head=command_output"git"["-C";root;"rev-parse";"HEAD"]in
  require(canonical_commit head)"Git HEAD is not a canonical commit";
  let snapshot name =
    let value=report|>member name in
    let commit=value|>member"commit"|>to_string in
    require(value|>member"clean"|>to_bool)"%s is not clean"name;
    require(canonical_commit commit)"%s commit is not canonical"name;
    commit in
  let before=snapshot"source_before"and after=snapshot"source_after"in
  require(report|>member"source_stable_clean"|>to_bool)
    "native source was not stable and clean";
  require(before=after)"native source changed during measurement";
  require(after=head)"native report commit %s does not equal root HEAD %s"after head;
  head

let validate_capacities root =
  let require_source relative facts =
    let source=read(Filename.concat root relative)in
    List.iter(fun fact->require(contains source fact)"missing bounded-cache policy %S in %s"fact relative)facts in
  require_source "lib/scene_execution/scene_execution.ml"
    ["let mesh_cache_entry_capacity=256";"let texture_cache_entry_capacity=256";
     "let cache_byte_capacity=256*1024*1024";"when entries < 64"];
  require_source "lib/prismel_next_resources/prismel_next_resources.ml"
    ["if List.length entries<=256" ];
  require_source "lib/prismel_next_api/font.ml"
    ["let capacity=256 and font_capacity=32"];
  require_source "lib/ogpu_raster2/ogpu_raster2.ml"
    ["let decode_cache_capacity=256";"let decode_cache_byte_capacity=64*1024*1024"]

let validate_native value =
  require (value |> member "backend" |> to_string = "real-m1-runtime-next-metal")
    "native proof has the wrong backend";
  require (value |> member "profile" |> to_string = "release")
    "native proof is not release-profile";
  require (value |> member "sample_frames" |> to_int = 600)
    "native proof must contain 600 measured frames";
  require (value |> member "camera_only_changes" |> to_bool)
    "native proof omitted camera-only changes";
  require (string64 value "prepared_upload_bytes" > 0L &&
           string64 value "measurement_upload_bytes" = 0L)
    "native stable mesh upload invariant failed";
  ["native_buffer_creates";"native_buffer_writes";
   "native_mesh_buffer_creates";"native_mesh_buffer_writes"]
  |> List.iter (fun field -> require (value |> member field |> to_int = 0)
      "native counter %s is nonzero" field);
  let frames=value|>member"sample_frames"|>to_int
  and pieces=value|>member"pieces"|>to_int
  and draws=value|>member"draws"|>to_int
  and passes=value|>member"passes"|>to_int
  and calls=value|>member"backend_calls"|>to_int
  and cache=value|>member"cache_entries"|>to_int in
  require (pieces>0 && draws=frames*pieces) "draw count is not batch-scaled";
  require (passes=frames && calls=frames) "pass/FFI count is not one per frame";
  require (cache>0 && cache<=64) "native mesh/pipeline cache exceeds 64 entries"

let () =
  let root=ref"" and native=ref"" and scene=ref"" and text=ref"" and font=ref"" and raster=ref"" in
  Arg.parse
    ["--root",Arg.Set_string root,"DIR clean repository root";
     "--native-report",Arg.Set_string native,"FILE clean native R9 JSON";
     "--scene-batching-test",Arg.Set_string scene,"EXE Scene_execution batching proof";
     "--text-cache-test",Arg.Set_string text,"EXE automatic text LRU proof";
     "--font-cache-test",Arg.Set_string font,"EXE explicit font LRU proof";
     "--raster-cache-test",Arg.Set_string raster,"EXE Raster2 decode/image cache proof"]
    (fun value->fail"unexpected argument %S"value) "runtime_next_r9_synthesis";
  List.iter(fun(name,value)->require(!value<>"")"missing %s"name)
    ["repository root",root;"native report",native;"scene batching test",scene;"text cache test",text;
     "font cache test",font;"raster cache test",raster];
  let report=Yojson.Safe.from_file !native in
  let head=validate_provenance !root report in
  validate_native report;
  validate_capacities !root;
  List.iter run [!scene;!text;!font;!raster];
  `Assoc ["schema",`Int 1;"gate",`String"R9";"source_commit",`String head;
    "frames",`Int 600;"measurement_upload_bytes",`String"0";
    "passes_per_frame",`Int 1;"backend_calls_per_frame",`Int 1;
    "native_cache_max",`Int 64;"mesh_cache_max",`Int 256;
    "image_cache_max",`Int 256;"glyph_cache_max",`Int 256;
    "proofs",`List(List.map(fun x->`String x)
      ["native-camera-zero-upload";"scene-material-clip-batching";
       "automatic-text-lru";"explicit-font-lru";"raster-decoded-image-lru"])]
  |> Yojson.Safe.pretty_to_channel stdout;
  output_char stdout '\n'
