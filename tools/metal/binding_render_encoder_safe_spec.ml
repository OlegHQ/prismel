type group =
  | Draw_dispatch | Stage_binding | Fixed_state | Store_action
  | Synchronization | Residency | Indirect_commands | Counter_sample | Query

type obligation =
  | Encoder_open | Pipeline_bound | Same_device | Range_checked
  | Finite_values | Capability_checked | Retain_until_completion

type disposition = Active | Deprecated_alias

type entry =
  { id : string
  ; group : group
  ; obligations : obligation list
  ; disposition : disposition
  }

let deprecated_ids =
  [ "method:-[MTLRenderCommandEncoder textureBarrier]"
  ; "method:-[MTLRenderCommandEncoder useHeap:]"
  ; "method:-[MTLRenderCommandEncoder useHeaps:count:]"
  ; "method:-[MTLRenderCommandEncoder useResource:usage:]"
  ; "method:-[MTLRenderCommandEncoder useResources:count:usage:]"
  ]

let group_name = function
  | Draw_dispatch -> "draw_dispatch"
  | Stage_binding -> "stage_binding"
  | Fixed_state -> "fixed_state"
  | Store_action -> "store_action"
  | Synchronization -> "synchronization"
  | Residency -> "residency"
  | Indirect_commands -> "indirect_commands"
  | Counter_sample -> "counter_sample"
  | Query -> "query"

let expected_group_counts =
  [ Draw_dispatch, 16; Stage_binding, 71; Fixed_state, 20
  ; Store_action, 6; Synchronization, 5; Residency, 8
  ; Indirect_commands, 2; Counter_sample, 1; Query, 4 ]

let method_name (symbol : Binding_render_encoder_evidence.symbol) =
  let id = symbol.id in
  match String.index_opt id ' ' with
  | None -> id
  | Some start ->
      String.sub id (start + 1) (String.length id - start - 2)

let starts prefixes value =
  List.exists (fun prefix -> String.starts_with ~prefix value) prefixes

let classify symbol =
  let name = method_name symbol in
  if symbol.Binding_render_encoder_evidence.kind = "property"
     || name = "tileHeight" || name = "tileWidth"
  then Query
  else if starts [ "draw"; "dispatch" ] name then Draw_dispatch
  else if starts [ "setVertex"; "setFragment"; "setTile"; "setObject"; "setMesh" ] name
  then Stage_binding
  else if starts [ "setColorStore"; "setDepthStore"; "setStencilStore" ] name
  then Store_action
  else if starts [ "memoryBarrier"; "textureBarrier"; "updateFence"; "waitForFence" ] name
  then Synchronization
  else if String.starts_with ~prefix:"use" name then Residency
  else if String.starts_with ~prefix:"executeCommands" name then Indirect_commands
  else if String.starts_with ~prefix:"sampleCounters" name then Counter_sample
  else Fixed_state

let obligations = function
  | Draw_dispatch -> [ Encoder_open; Pipeline_bound; Range_checked; Capability_checked; Retain_until_completion ]
  | Stage_binding -> [ Encoder_open; Same_device; Range_checked; Capability_checked; Retain_until_completion ]
  | Fixed_state -> [ Encoder_open; Range_checked; Finite_values; Capability_checked ]
  | Store_action -> [ Encoder_open; Range_checked; Capability_checked ]
  | Synchronization -> [ Encoder_open; Same_device; Range_checked; Capability_checked; Retain_until_completion ]
  | Residency -> [ Encoder_open; Same_device; Range_checked; Capability_checked; Retain_until_completion ]
  | Indirect_commands -> [ Encoder_open; Same_device; Range_checked; Capability_checked; Retain_until_completion ]
  | Counter_sample -> [ Encoder_open; Same_device; Range_checked; Capability_checked; Retain_until_completion ]
  | Query -> [ Encoder_open; Capability_checked ]

let select symbols =
  Binding_render_encoder_evidence.validate_inventory symbols |> ignore;
  symbols
  |> List.filter (fun symbol -> symbol.Binding_render_encoder_evidence.owner = Some Binding_render_encoder_plan.owner)
  |> List.map (fun symbol ->
    let group = classify symbol in
    { id = symbol.id; group; obligations = obligations group
    ; disposition = if List.mem symbol.id deprecated_ids then Deprecated_alias else Active })
  |> List.sort (fun left right -> String.compare left.id right.id)

let () =
  if List.length deprecated_ids <> 5 then
    invalid_arg "render encoder deprecated alias count drift"
