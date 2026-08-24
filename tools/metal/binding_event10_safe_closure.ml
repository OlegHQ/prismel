type group = Listener | Queue | Export | Label | Device | Notification

type item =
  { id : string
  ; group : group
  }

let items =
  [ { id = "method:+[MTLSharedEventListener sharedListener]"; group = Listener }
  ; { id = "method:-[MTLSharedEventListener init]"; group = Listener }
  ; { id = "method:-[MTLSharedEventListener initWithDispatchQueue:]"; group = Listener }
  ; { id = "method:-[MTLSharedEventListener dispatchQueue]"; group = Queue }
  ; { id = "property:MTLSharedEventListener:dispatchQueue"; group = Queue }
  ; { id = "method:-[MTLSharedEvent newSharedEventHandle]"; group = Export }
  ; { id = "method:-[MTLSharedEventHandle label]"; group = Label }
  ; { id = "property:MTLSharedEventHandle:label"; group = Label }
  ; { id = "property:MTLEvent:device"; group = Device }
  ; { id = "method:-[MTLSharedEvent notifyListener:atValue:block:]"; group = Notification }
  ]

let ids = List.map (fun item -> item.id) items

let validate () =
  let count group =
    List.length (List.filter (fun item -> item.group = group) items)
  in
  if List.length items <> 10 then failwith "Event10 closure cardinality drift";
  if List.sort_uniq String.compare ids <> List.sort String.compare ids then
    failwith "Event10 closure contains duplicate IDs";
  if List.map count [ Listener; Queue; Export; Label; Device; Notification ]
     <> [ 3; 2; 1; 2; 1; 1 ]
  then failwith "Event10 semantic partition drift";
  if List.sort String.compare ids
     <> List.sort String.compare Binding_event_tail_handoff.callable_ids
  then failwith "Event10 handoff membership drift"

