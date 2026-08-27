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
  let ids = symbols |> List.filter (fun symbol -> string "classification" symbol = "bound" && string "header" symbol = "Metal/MTLParallelRenderCommandEncoder.h") |> List.map (string "id") in
  let count needle = List.length (List.filter (fun id -> contains id needle) ids) in
  if List.length ids <> 8 || count "setColorStoreAction" <> 2
     || count "setDepthStoreAction" <> 2 || count "setStencilStoreAction" <> 2
     || count "renderCommandEncoder" <> 1 || count "protocol:" <> 1
  then fail "ParallelRender8 closure drift";
  Printf.printf "ParallelRender8: child encoder constructor1 + typed store-state setters6 + metadata1; require nullable unwind, shared pass ownership, index/state rejection, child completion retention\n%!"
