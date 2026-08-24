let fail format = Printf.ksprintf failwith format
let member name = function `Assoc values -> List.assoc_opt name values | _ -> None
let string name value = match member name value with Some (`String text) -> text | _ -> fail "missing %s" name
let contains haystack needle =
  let n = String.length needle in
  let rec loop i = i + n <= String.length haystack && (String.sub haystack i n = needle || loop (i + 1)) in loop 0

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let symbols = match member "symbols" (Yojson.Safe.from_file Sys.argv.(1)) with Some (`List xs) -> xs | _ -> fail "symbols" in
  let ids header = symbols |> List.filter (fun symbol -> string "classification" symbol = "unreviewed" && string "header" symbol = header) |> List.map (string "id") in
  let count needle ids = List.length (List.filter (fun id -> contains id needle) ids) in
  let queue = ids "Metal/MTL4CommandQueue.h"
  and types = ids "Metal/MTLTypes.h"
  and indirect = ids "Metal/MTLIndirectCommandBuffer.h"
  and fence = ids "Metal/MTLFence.h" in
  if List.length queue <> 8 || count "copy" queue <> 2 || count "Drawable:" queue <> 2
     || count "typedef:" queue <> 2 || count "ResidencySet:" queue <> 1 || count "Event:value:" queue <> 1
  then fail "MTL4CommandQueue8 closure drift";
  if List.length types <> 6 || count "function:" types <> 4 || count "typedef:" types <> 2
  then fail "MTLTypes6 closure drift";
  if List.length indirect <> 6 || count "function:" indirect <> 1 || count "gpuResourceID" indirect <> 2
     || count "indirectRenderCommandAtIndex:" indirect <> 1 || count "protocol:" indirect <> 1 || count "typedef:" indirect <> 1
  then fail "IndirectCommandBuffer6 closure drift";
  if List.length fence <> 6 || count "device" fence <> 2 || count "label" fence <> 2
     || count "setLabel:" fence <> 1 || count "protocol:" fence <> 1
  then fail "Fence6 closure drift";
  Printf.printf "Small tails: MTL4Queue8 sparse graph4/synchronization4; Types6 constructors4/aliases2; IndirectBuffer6 value2/identity2/child1/metadata1; Fence6 identity2/label3/metadata1\n%!"
