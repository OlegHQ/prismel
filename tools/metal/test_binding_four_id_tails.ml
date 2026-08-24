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
  let count needle ids = List.length (List.filter (fun id -> contains (String.lowercase_ascii id) needle) ids) in
  let pipeline = ids "Metal/MTLPipeline.h"
  and function_descriptor = ids "Metal/MTLFunctionDescriptor.h"
  and ml_encoder = ids "Metal/MTL4MachineLearningCommandEncoder.h" in
  if List.length pipeline <> 4 || count "class:" pipeline <> 2
     || count "objectatindexedsubscript:" pipeline <> 1 || count "setobject:atindexedsubscript:" pipeline <> 1
  then fail "Pipeline4 drift";
  if List.length function_descriptor <> 4 || count "class:" function_descriptor <> 1
     || count "binaryarchives" function_descriptor <> 3 then fail "FunctionDescriptor4 drift";
  if List.length ml_encoder <> 4 || count "dispatchnetwork" ml_encoder <> 1
     || count "setargumenttable:" ml_encoder <> 1 || count "setpipelinestate:" ml_encoder <> 1
     || count "protocol:" ml_encoder <> 1 then fail "MTL4MachineLearningEncoder4 drift";
  Printf.printf "Four-ID tails: Pipeline descriptor array ownership2/metadata2; FunctionDescriptor archive graph3/metadata1; MTL4ML encoder retained bindings3/metadata1\n%!"
