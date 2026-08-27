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
  let maximum=ref 0 and total=ref 0 and error_pixels=ref 0 and candidate_changed=ref 0 and legacy_changed=ref 0 and exclusive=ref 0 and common_max=ref 0 and channel_max=Array.make 4 0 and min_x=ref max_int and min_y=ref max_int and max_x=ref min_int and max_y=ref min_int in
  for pixel=0 to R10_scene3_semantics.pixels-1 do let changed=ref false in
    for channel=0 to 3 do let offset=pixel*4+channel in let delta=abs(Char.code(Bytes.get legacy offset)-Char.code(Bytes.get candidate offset))in maximum:=max !maximum delta;channel_max.(channel)<-max channel_max.(channel)delta;total:=!total+delta;if delta>3 then changed:=true done;
    if !changed then(incr error_pixels;let x=pixel mod R10_scene3_semantics.width and y=pixel/R10_scene3_semantics.width in min_x:=min !min_x x;max_x:=max !max_x x;min_y:=min !min_y y;max_y:=max !max_y y);
    let offset=pixel*4 in let lc=Bytes.sub legacy offset 4<>Bytes.sub legacy 0 4 and cc=Bytes.sub candidate offset 4<>Bytes.sub candidate 0 4 in if lc then incr legacy_changed;if cc then incr candidate_changed;if lc<>cc then incr exclusive;if lc&&cc then for channel=0 to 3 do common_max:=max !common_max(abs(Char.code(Bytes.get legacy(offset+channel))-Char.code(Bytes.get candidate(offset+channel))))done
  done;
  if !candidate_changed=0 then failwith"candidate capture is blank";
  let mean=float !total/.float(Bytes.length legacy)in
  let within= !maximum<=3 in
  let summary=`Assoc["schema",`Int 1;"semantic_signature",`String R10_scene3_semantics.signature;"legacy_digest",`String(string"rgba_digest"legacy_meta);"candidate_digest",`String(string"rgba_digest"candidate_meta);"max_channel_error",`Int !maximum;"channel_max_error",`List(Array.to_list(Array.map(fun value->`Int value)channel_max));"mean_channel_error",`Float mean;"error_pixels_over_tolerance",`Int !error_pixels;"error_bounds",(if !error_pixels=0 then`Null else`List[`Int !min_x;`Int !min_y;`Int !max_x;`Int !max_y]);"tolerance",`Int 3;"legacy_changed_pixels",`Int !legacy_changed;"candidate_changed_pixels",`Int !candidate_changed;"exclusive_coverage_pixels",`Int !exclusive;"common_coverage_max_error",`Int !common_max;"within_tolerance",`Bool within]in
  print_endline(Yojson.Safe.to_string summary);
  if not within then
    if Array.length Sys.argv=6 then begin
      let expected=Yojson.Safe.from_file Sys.argv.(5)in
      if expected<>summary then
        failwith"Scene3 mismatch changed; refresh only after diagnosis"
    end else failwith"frozen per-channel tolerance exceeded"
