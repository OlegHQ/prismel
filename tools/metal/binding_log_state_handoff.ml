type lane = Mechanical | Callback | Metadata

type item =
  { id : string
  ; lane : lane
  ; operation : string
  ; tests : string list
  }

let callable_ids =
  [ "method:-[MTLLogState addLogHandler:]"
  ; "method:-[MTLLogStateDescriptor bufferSize]"
  ; "method:-[MTLLogStateDescriptor level]"
  ; "method:-[MTLLogStateDescriptor setBufferSize:]"
  ; "method:-[MTLLogStateDescriptor setLevel:]"
  ; "property:MTLLogStateDescriptor:bufferSize"
  ; "property:MTLLogStateDescriptor:level"
  ]

let make ~kind id =
  if kind = "class" || kind = "protocol" then
    { id; lane = Metadata; operation = "Metal.Log_state opaque capability"
    ; tests = [ "public type provenance" ] }
  else if String.ends_with ~suffix:"addLogHandler:]" id then
    { id; lane = Callback; operation = "Metal.Log_state.add_handler"
    ; tests = [ "nullable message snapshot"; "callback root lifetime"; "exception containment" ] }
  else
    { id; lane = Mechanical; operation = "Metal.Log_state.Descriptor level/buffer_size"
    ; tests = [ "typed level round trip"; "positive buffer range"; "native defaults" ] }

let validate items =
  let count lane = List.length (List.filter (fun item -> item.lane = lane) items) in
  if List.length items <> 9 || count Mechanical <> 6 || count Callback <> 1
     || count Metadata <> 2
  then failwith "LogState9 handoff drift"
