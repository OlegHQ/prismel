let ()=
  if Array.length Sys.argv<>2 then invalid_arg"inventory"else
  let open Yojson.Safe.Util in
  let symbols=Yojson.Safe.from_file Sys.argv.(1)|>member"symbols"|>to_list in
  let metadata_ids=["class:MTLSharedEventHandle";"class:MTLSharedEventListener";
    "record:MTLSharedEventHandlePrivate";"typedef:MTLSharedEventNotificationBlock"]in
  let closure_ids=Binding_event_tail_handoff.callable_ids@metadata_ids in
  let event_symbols=List.filter(fun j->
    j|>member"header"|>to_string="Metal/MTLEvent.h"&&
    List.mem(j|>member"id"|>to_string)closure_ids)symbols in
  let items=List.map(fun j->Binding_event_tail_handoff.classify
    ~kind:(j|>member"kind"|>to_string)(j|>member"id"|>to_string))event_symbols in
  Binding_event_tail_handoff.validate items;
  let status id=
    match List.find_opt(fun j->j|>member"id"|>to_string=id)event_symbols with
    |None->failwith("missing Event ID "^id)
    |Some j->j|>member"classification"|>to_string
  in
  List.iter(fun id->if status id<>"bound"then failwith("Event callable is not bound: "^id))
    Binding_event_tail_handoff.callable_ids;
  let metadata=List.filter(fun item->item.Binding_event_tail_handoff.package=Type_metadata)items in
  List.iter(fun(item:Binding_event_tail_handoff.item)->if status item.id<>"bound"then failwith("Event metadata status drift: "^item.id))metadata;
  print_endline"Event14: exact14 bound"
