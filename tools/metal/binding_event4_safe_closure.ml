let promotable_ids =
  [ "class:MTLSharedEventHandle"
  ; "class:MTLSharedEventListener"
  ; "record:MTLSharedEventHandlePrivate"
  ; "typedef:MTLSharedEventNotificationBlock" ]

let validate () =
  if List.length promotable_ids <> 4
     || List.length (List.sort_uniq String.compare promotable_ids) <> 4
  then failwith "Event residual exact4 drift"
