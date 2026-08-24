let fail format = Printf.ksprintf failwith format

let member name = function `Assoc values -> List.assoc_opt name values | _ -> None
let string name value = match member name value with Some (`String text) -> text | _ -> fail "missing %s" name

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let symbols = match member "symbols" (Yojson.Safe.from_file Sys.argv.(1)) with Some (`List xs) -> xs | _ -> fail "symbols" in
  let items =
    symbols
    |> List.filter (fun symbol -> string "classification" symbol = "unreviewed" && string "header" symbol = "Metal/MTLLogState.h")
    |> List.map (fun symbol -> Binding_log_state_handoff.make ~kind:(string "kind" symbol) (string "id" symbol))
  in
  Binding_log_state_handoff.validate items;
  Printf.printf "LogState9: descriptor mechanical6 + callback1 + metadata2\n%!"
