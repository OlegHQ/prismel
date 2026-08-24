module S = Set.Make (String)
let fail format = Printf.ksprintf failwith format
let member name = function `Assoc values -> List.assoc_opt name values | _ -> None
let string name value = match member name value with Some (`String text) -> text | _ -> fail "missing %s" name

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  Binding_pure_tail_plan.validate ();
  let symbols = match member "symbols" (Yojson.Safe.from_file Sys.argv.(1)) with Some (`List xs) -> xs | _ -> fail "symbols" in
  let pending = symbols |> List.filter (fun symbol -> let c=string "classification" symbol in c="unreviewed"||c="bound") |> List.map (string "id") |> S.of_list in
  let ids = List.map (fun (item : Binding_pure_tail_plan.item) -> item.id) Binding_pure_tail_plan.items in
  if List.exists (fun id -> not (S.mem id pending)) ids then fail "pure-tail ID escaped active inventory";
  Printf.printf "Pure mechanical tail plan: exact46 = enums16 + fixed aliases20 + scalar aliases4 + inline constructors6; exclusions are non-public draw structs and ownership/callback/context values\n%!"
