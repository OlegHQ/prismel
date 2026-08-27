let read path=let input=open_in_bin path in Fun.protect~finally:(fun()->close_in_noerr input)(fun()->really_input_string input(in_channel_length input))
let member name json=Yojson.Safe.Util.member name json
let string name json=Yojson.Safe.Util.to_string(member name json)
let int name json=Yojson.Safe.Util.to_int(member name json)
let () =
  if Array.length Sys.argv<>5&&Array.length Sys.argv<>6 then invalid_arg"compare: LEGACY_RGBA LEGACY_META CANDIDATE_RGBA CANDIDATE_META [EXPECTED_MISMATCH]";
  let legacy_meta=Yojson.Safe.from_file Sys.argv.(2)and candidate_meta=Yojson.Safe.from_file Sys.argv.(4)in
  if string"semantic_signature"legacy_meta<>string"semantic_signature"candidate_meta||string"semantic_signature"legacy_meta<>R10_scene3_semantics.signature then failwith"topology/state signature mismatch";
  if int"width"legacy_meta<>R10_scene3_semantics.width||int"height"legacy_meta<>R10_scene3_semantics.height||int"width"candidate_meta<>R10_scene3_semantics.width||int"height"candidate_meta<>R10_scene3_semantics.height then failwith"extent mismatch";
  let legacy=Bytes.of_string(read Sys.argv.(1))and candidate=Bytes.of_string(read Sys.argv.(3))in
  if Bytes.length legacy<>R10_scene3_semantics.pixels*4||Bytes.length candidate<>Bytes.length legacy then failwith"RGBA cardinality mismatch";
  let maximum=ref 0 and total=ref 0 and error_pixels=ref 0 and candidate_changed=ref 0 in
  for pixel=0 to R10_scene3_semantics.pixels-1 do let changed=ref false in
    for channel=0 to 3 do let offset=pixel*4+channel in let delta=abs(Char.code(Bytes.get legacy offset)-Char.code(Bytes.get candidate offset))in maximum:=max !maximum delta;total:=!total+delta;if delta>3 then changed:=true done;
    if !changed then incr error_pixels;
    let offset=pixel*4 in if Bytes.sub candidate offset 4<>Bytes.sub candidate 0 4 then incr candidate_changed
  done;
  if !candidate_changed=0 then failwith"candidate capture is blank";
  let mean=float !total/.float(Bytes.length legacy)in
  let within= !maximum<=3 in
  let summary=`Assoc["schema",`Int 1;"semantic_signature",`String R10_scene3_semantics.signature;"legacy_digest",`String(string"rgba_digest"legacy_meta);"candidate_digest",`String(string"rgba_digest"candidate_meta);"max_channel_error",`Int !maximum;"mean_channel_error",`Float mean;"error_pixels_over_tolerance",`Int !error_pixels;"tolerance",`Int 3;"candidate_changed_pixels",`Int !candidate_changed;"within_tolerance",`Bool within]in
  print_endline(Yojson.Safe.to_string summary);
  if not within then
    if Array.length Sys.argv=6 then begin
      let expected=Yojson.Safe.from_file Sys.argv.(5)in
      if expected<>summary then
        failwith"Scene3 mismatch changed; refresh only after diagnosis"
    end else failwith"frozen per-channel tolerance exceeded"
