(* The current inventory promotes the nine MTLStages enum cases independently;
   this residual closure is exactly the nine unreviewed ownership/effect IDs. *)
let ids =
  [ "method:-[MTLCommandEncoder barrierAfterQueueStages:beforeStages:]"
  ; "method:-[MTLCommandEncoder device]"
  ; "method:-[MTLCommandEncoder insertDebugSignpost:]"
  ; "method:-[MTLCommandEncoder label]"
  ; "method:-[MTLCommandEncoder popDebugGroup]"
  ; "method:-[MTLCommandEncoder pushDebugGroup:]"
  ; "method:-[MTLCommandEncoder setLabel:]"
  ; "property:MTLCommandEncoder:device"
  ; "property:MTLCommandEncoder:label"
  ]

let () =
  if List.length ids <> 9 || List.length (List.sort_uniq String.compare ids) <> 9
  then failwith "CommandEncoder9 residual closure drift"
