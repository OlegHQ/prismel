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
  let ids =
    symbols
    |> List.filter (fun symbol -> string "classification" symbol = "unreviewed" && string "header" symbol = "Metal/MTLLinkedFunctions.h")
    |> List.map (string "id")
  in
  let count needle = List.length (List.filter (fun id -> contains (String.lowercase_ascii id) needle) ids) in
  if List.length ids <> 9 || count "binaryfunctions" <> 3 || count "privatefunctions" <> 3
     || count "groups" <> 3
  then fail "LinkedFunctions9 closure drift";
  Printf.printf "LinkedFunctions9: retained nullable function arrays6 + named group dictionary3; require same-device graph, copied containers, atomic mutation, and destroy-order tests\n%!"
