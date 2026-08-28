open Yojson.Safe

let fail format=Printf.ksprintf failwith format

let report path commit =
  let source=`Assoc["commit",`String commit;"clean",`Bool true]in
  to_file path(`Assoc[
    "backend",`String"real-m1-runtime-next-metal";"profile",`String"release";
    "sample_frames",`Int 600;"camera_only_changes",`Bool true;
    "prepared_upload_bytes",`String"4096";"measurement_upload_bytes",`String"0";
    "native_buffer_creates",`Int 0;"native_buffer_writes",`Int 0;
    "native_mesh_buffer_creates",`Int 0;"native_mesh_buffer_writes",`Int 0;
    "pieces",`Int 12;"draws",`Int 7200;"passes",`Int 600;
    "backend_calls",`Int 600;"cache_entries",`Int 24;
    "source_before",source;"source_after",source;"source_stable_clean",`Bool true])

let run executable root input =
  let proof="/usr/bin/true"in
  let args=[|executable;"--root";root;"--native-report";input;"--scene-batching-test";proof;
    "--text-cache-test";proof;"--font-cache-test";proof;"--raster-cache-test";proof|]in
  let null=Unix.openfile"/dev/null"[Unix.O_WRONLY]0 in
  let pid=Unix.create_process executable args Unix.stdin null null in
  Unix.close null;
  match snd(Unix.waitpid[]pid)with Unix.WEXITED code->code|_->255

let command root arguments =
  let args=Array.of_list("git"::"-C"::root::arguments)in
  match Unix.create_process"git"args Unix.stdin Unix.stdout Unix.stderr|>Unix.waitpid[]|>snd with
  |Unix.WEXITED 0->()|_->fail"git command failed"

let write path text=let output=open_out_bin path in Fun.protect~finally:(fun()->close_out output)(fun()->output_string output text)
let rec mkdir path = if not(Sys.file_exists path)then( mkdir(Filename.dirname path);Unix.mkdir path 0o755)
let fixture root relative text=let path=Filename.concat root relative in mkdir(Filename.dirname path);write path text

let () =
  if Array.length Sys.argv<>3 then fail"synthesis executable and repository root required";
  let input=Filename.temp_file"r9-synthesis-"".json"in
  let root=Filename.temp_file"r9-root-"""in Sys.remove root;Unix.mkdir root 0o755;
  fixture root"lib/scene_execution/scene_execution.ml""let mesh_cache_entry_capacity=256\nlet texture_cache_entry_capacity=256\nlet cache_byte_capacity=256*1024*1024\nwhen entries < 64";
  fixture root"lib/prismel_next_resources/prismel_next_resources.ml""if List.length entries<=256";
  fixture root"lib/prismel_next_api/font.ml""let capacity=256 and font_capacity=32";
  fixture root"lib/ogpu_raster2/ogpu_raster2.ml""let decode_cache_capacity=256\nlet decode_cache_byte_capacity=64*1024*1024";
  command root["init";"-q"];command root["add";"."];
  command root["-c";"user.name=R9 Test";"-c";"user.email=r9@example.invalid";"commit";"-qm";"fixture"];
  let head=let input=Unix.open_process_args_in"git"[|"git";"-C";root;"rev-parse";"HEAD"|]in let x=input_line input in ignore(Unix.close_process_in input);x in
  let executable=Unix.realpath Sys.argv.(1)in
  report input head;
  if run executable root input<>0 then fail"valid clean synthesis failed";
  report input(String.make 40 'a');
  if run executable root input=0 then fail"mismatched report commit was accepted";
  report input head;write(Filename.concat root"dirty")"dirty";
  if run executable root input=0 then fail"dirty worktree was accepted";
  Sys.remove input
