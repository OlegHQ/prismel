open Yojson.Safe.Util

let run executable visibility width height =
  let arguments=[|executable;"basic";"--visibility";visibility;"--warmup";"1";
    "--samples";"1";"--width";string_of_int width;"--height";string_of_int height|]in
  let input=Unix.open_process_args_in executable arguments in
  let json=Fun.protect~finally:(fun()->match Unix.close_process_in input with Unix.WEXITED 0->()|_->failwith"native dimension child failed")(fun()->Yojson.Safe.from_channel input)in
  let window=member"window"json in
  if member"width"json<>`Int width||member"height"json<>`Int height||
    member"drawable_width"window<>`Int width||member"drawable_height"window<>`Int height||
    member"sample_frames"json<>`Int 1||
    member"observed_visible"json<>`Bool(visibility="visible")||
    member"peak_sampled_rss_kib"json|>to_int<=0 then
    failwith"native dimension/visibility/RSS facts mismatch";
  match member"workload_signature"json,member"framebuffer_digest"json with
  |`String signature,`String digest when signature<>""&&digest<>""->signature,digest
  |_->failwith"native dimension evidence missing"

let ()=
  if Sys.os_type<>"Unix"||not(Sys.file_exists"/usr/bin/otool")then
    print_endline"runtime-next native dimensions skipped off Darwin"
  else let executable=let value=Sys.argv.(1)in if Filename.dirname value="."then"./"^value else value in
    let small=run executable"hidden"64 64
    and phase0=run executable"hidden"640 480
    and phase0_visible=run executable"visible"640 480 in
    if small=phase0 then failwith"dimension-specific evidence aliased";
    if phase0<>phase0_visible then failwith"visible/hidden exact output drift";
    print_endline"runtime-next native dimensions, visibility and sampled RSS passed"
