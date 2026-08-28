let ()=
  if Array.length Sys.argv<>2 then failwith"manifest path";
  let json=Yojson.Safe.from_file Sys.argv.(1)in let open Yojson.Safe.Util in
  if json|>member"schema"|>to_int<>1 then failwith"schema";
  let list field=json|>member field|>to_list|>List.map to_string in
  if List.length(list"delete")<>8||List.length(list"replace")<>46 then failwith"batch cardinality";
  if not(List.mem"lib/runtime/runtime.ml"(list"replace"))then failwith"runtime owner";
  if not(List.mem"tsdl_gfx/dune"(list"delete"))then failwith"binding deletion";
  List.iter(fun path->if List.mem path(list"replace")then failwith"retired Raster2 fixture remains")
    ["lib/prismel/canvas_raster2_snapshot_test.ml";
     "lib/prismel/font_raster2_snapshot_test.ml";
     "lib/prismel/image_raster2_snapshot_test.ml"];
  print_endline"Phase5 atomic switch manifest exact batches passed"
