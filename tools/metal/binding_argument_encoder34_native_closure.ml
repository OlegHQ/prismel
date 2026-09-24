let ids = Binding_argument_encoder_handoff.mechanical_ids
let validate manifest_ids =
  let sorted = List.sort String.compare manifest_ids in
  if List.length sorted <> 34 || List.length (List.sort_uniq String.compare sorted) <> 34
  then failwith "ArgumentEncoder34 inventory drift";
  let mechanical = List.filter (fun id -> List.mem id ids) sorted in
  if List.length mechanical <> 4 then failwith "ArgumentEncoder34 mechanical drift"
