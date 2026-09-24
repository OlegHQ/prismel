type kind = Buffer_layout | Sample_attachment | Resource_view_pool | Texture_view_pool
type handle = { id:int; generation:int }
type entry = { kind:kind; device:int; parent:handle option; generation:int; live:bool }
type t = { next_id:int; entries:(int * entry) list }
let empty={next_id=1;entries=[]}
let find state handle =
  match List.assoc_opt handle.id state.entries with
  | Some entry when entry.generation=handle.generation -> Some entry | _ -> None
let require_live state handle ~kind ~device =
  match find state handle with
  | None -> Error "unknown or stale resource handle"
  | Some entry when not entry.live -> Error "resource handle is destroyed"
  | Some entry when entry.kind<>kind -> Error "resource handle kind mismatch"
  | Some entry when entry.device<>device -> Error "resource belongs to another device"
  | Some _ -> Ok ()
let create state ~kind ~device ~parent =
  if device<0 then Error "invalid device identity" else
  match parent with
  | Some parent when Option.fold ~none:true ~some:(fun e->not e.live || e.device<>device) (find state parent) ->
      Error "parent is stale or belongs to another device"
  | _ ->
      let handle={id=state.next_id;generation=1} in
      let entry={kind;device;parent;generation=1;live=true} in
      Ok ({next_id=state.next_id+1;entries=(handle.id,entry)::state.entries},handle)
let destroy state handle =
  match find state handle with
  | None -> Error "unknown or stale resource handle"
  | Some entry when not entry.live -> Error "resource handle already destroyed"
  | Some _ when List.exists (fun (_,e)->e.live && e.parent=Some handle) state.entries ->
      Error "resource handle has live children"
  | Some entry ->
      Ok {state with entries=List.map(fun(id,e)->if id=handle.id then(id,{entry with live=false})else(id,e))state.entries}
let retain_for_completion state handles ~device =
  let rec loop=function
    | []->Ok ()
    | handle::rest ->
        (match find state handle with
         | Some entry when entry.live && entry.device=device -> loop rest
         | Some _ -> Error "completion resource is stale or cross-device"
         | None -> Error "unknown completion resource")
  in loop handles
let live_count state=List.fold_left(fun n(_,e)->if e.live then n+1 else n)0 state.entries
