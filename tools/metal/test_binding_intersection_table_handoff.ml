let fail format = Printf.ksprintf failwith format
let member name = function `Assoc values -> List.assoc_opt name values | _ -> None
let string name value = match member name value with Some (`String text) -> text | _ -> fail "missing %s" name
let contains haystack needle =
  let n = String.length needle in
  let rec loop i = i + n <= String.length haystack && (String.sub haystack i n = needle || loop (i + 1)) in
  loop 0

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let symbols = match member "symbols" (Yojson.Safe.from_file Sys.argv.(1)) with Some (`List xs) -> xs | _ -> fail "symbols" in
  let ids = symbols |> List.filter (fun symbol -> let c=string "classification" symbol in (c="unreviewed"||c="bound") && string "header" symbol = "Metal/MTLIntersectionFunctionTable.h") |> List.map (string "id") |> List.filter(fun id->contains id "setOpaque"||contains id "setBuffers:"||contains id "setFunctions:"||contains id "setVisibleFunctionTables:"||id="typedef:MTLIntersectionFunctionBufferArguments") in
  let count needle = List.length (List.filter (fun id -> contains id needle) ids) in
  if List.length ids <> 8 || count "setOpaque" <> 4 || count "setBuffers:" <> 1
     || count "setFunctions:" <> 1 || count "setVisibleFunctionTables:" <> 1
     || count "typedef:" <> 1
  then fail "IntersectionFunctionTable8 closure drift";
  Printf.printf "IntersectionFunctionTable8: retained nullable binding arrays3 + checked opaque signature writes4 + fixed value typedef1; require cardinality/range/device atomicity and completion retention\n%!"
