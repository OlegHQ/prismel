open Yojson.Safe

let checkpoint frame digest pixels colors = `Assoc [ "frame", `Int frame; "digest", `String digest;
  "non_clear_pixels", `Int pixels; "distinct_non_background_colors", `Int colors ]
let scenario name digest pixels colors = `Assoc [ "scenario", `String name;
  "visibility_observed", `List [`Bool true;`Bool true;`Bool true];
  "checkpoints", `List (List.map (fun frame -> checkpoint frame digest pixels colors) [ 1; 2; 60; 600 ]);
  "resized", checkpoint 601 digest pixels colors ]
let report ?(colors = 8) basic_digest pxui_digest pixels = `Assoc [ "schema", `Int 2; "target", `String "native";
  "comparison",`String "exact-framebuffer-digest";
  "provenance",`Assoc ["renderer_commit",`String(String.make 40 '1');"tracked_tree_clean",`Bool true;
    "host",`String "Apple M1";"executable_digest",`String(String.make 32 '2')];
  "width", `Int 640; "height", `Int 480; "pixel_tolerance", `Int 3;
  "scenarios", `List [ scenario "basic" basic_digest pixels colors; scenario "pxui" pxui_digest pixels colors ] ]
let run executable actual authority =
  let executable = Unix.realpath executable in
  let pid = Unix.create_process executable [| executable; "--validate"; actual; "--authority"; authority |] Unix.stdin Unix.stdout Unix.stderr in
  match snd (Unix.waitpid [] pid) with Unix.WEXITED code -> code | _ -> 255

let () =
  if Array.length Sys.argv <> 2 then failwith "gate executable required";
  let actual = Filename.temp_file "native-scene2-actual" ".json" in
  let authority = Filename.temp_file "native-scene2-authority" ".json" in
  Fun.protect ~finally:(fun () -> Sys.remove actual; Sys.remove authority) (fun () ->
    let stable = report (String.make 32 'a') (String.make 32 'b') 32 in
    to_file actual stable; to_file authority stable;
    if run Sys.argv.(1) actual authority <> 0 then failwith "valid authority rejected";
    to_file actual (report (String.make 32 'a') (String.make 32 'b') 0);
    if run Sys.argv.(1) actual authority = 0 then failwith "clear-only fixture accepted";
    to_file actual (report (String.make 32 'a') (String.make 32 'a') 32);
    if run Sys.argv.(1) actual authority = 0 then failwith "indistinguishable fixture accepted";
    to_file actual (report ~colors:1 (String.make 32 'a') (String.make 32 'b') 32);
    if run Sys.argv.(1) actual authority = 0 then failwith "fallback-blue fixture accepted";
    to_file actual (report (String.make 32 'c') (String.make 32 'b') 32);
    if run Sys.argv.(1) actual authority = 0 then failwith "digest drift accepted";
    to_file actual (report (String.make 32 'a') (String.make 32 'b') 33);
    if run Sys.argv.(1) actual authority = 0 then failwith "coverage drift accepted";
    let dirty=match report (String.make 32 'a') (String.make 32 'b') 32 with
      |`Assoc fields->`Assoc(List.map(function "provenance",`Assoc p->
          "provenance",`Assoc(("tracked_tree_clean",`Bool false)::List.remove_assoc "tracked_tree_clean" p)|x->x)fields)
      |_ -> assert false in
    to_file actual dirty;
    if run Sys.argv.(1) actual authority = 0 then failwith "dirty provenance accepted")
