type stage=Object|Mesh|Fragment|Tile
type object_ref={id:int;device:int;live:bool}
type linking={functions:object_ref list;archives:object_ref list;libraries:object_ref list}
type attachment={index:int;pixel_format:int;write_mask:int}
type pipeline={device:int;stages:(stage*object_ref)list;linking:linking;buffers:(int*int)list;attachments:attachment list}
let unique values = List.length values=List.length(List.sort_uniq compare values)
let validate_object device value =
  if not value.live then Error "pipeline dependency is destroyed"
  else if value.device<>device then Error "pipeline dependency belongs to another device" else Ok()
let validate pipeline =
  let objects=List.map snd pipeline.stages @ pipeline.linking.functions @
    pipeline.linking.archives @ pipeline.linking.libraries in
  match List.find_opt(fun value->validate_object pipeline.device value<>Ok())objects with
  | Some value->validate_object pipeline.device value
  | None when not(unique(List.map fst pipeline.stages))->Error "duplicate shader stage"
  | None when not(unique(List.map fst pipeline.buffers))->Error "duplicate buffer index"
  | None when List.exists(fun(index,_)->index<0||index>=31)pipeline.buffers->Error "buffer index out of range"
  | None when not(unique(List.map(fun a->a.index)pipeline.attachments))->Error "duplicate attachment index"
  | None when List.exists(fun a->a.index<0||a.index>=8||a.pixel_format<0||a.write_mask<0)pipeline.attachments->Error "attachment out of range"
  | None->Ok()
let retain_for_completion pipeline =
  match validate pipeline with Error e->Error e|Ok()->Ok(List.map snd pipeline.stages @
    pipeline.linking.functions @ pipeline.linking.archives @ pipeline.linking.libraries)
