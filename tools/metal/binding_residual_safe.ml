type object_ref={id:int;device:int;live:bool}
type graph={device:int;archives:object_ref list;functions:object_ref list;fences:object_ref list;indirect_buffers:object_ref list}
let all g=g.archives@g.functions@g.fences@g.indirect_buffers
let validate g=if List.exists(fun o->not o.live||o.device<>g.device)(all g)then Error"residual dependency stale or cross-device"
 else if List.length(all g)<>List.length(List.sort_uniq(fun a b->Int.compare a.id b.id)(all g))then Error"duplicate residual object"else Ok()
let retained g=match validate g with Error e->Error e|Ok()->Ok(all g)
