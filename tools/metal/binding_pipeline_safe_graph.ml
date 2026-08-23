type device=int
type function_ref={device:device;id:int}
type descriptor={device:device;vertex:function_ref option;retained:int}
type pipeline={parent:descriptor;mutable released:bool}
let descriptor device={device;vertex=None;retained=0}
let set_vertex (d:descriptor) (f:function_ref option)=match f with Some x when x.device<>d.device->Error"pipeline function belongs to another device"|_->Ok{d with vertex=f;retained=(match f with None->0|Some _->1)}
let materialize d=match d.vertex with None->Error"pipeline requires a vertex function"|Some _->Ok{parent=d;released=false}
let release_pipeline p=if not p.released then p.released<-true
let retained_count d=d.retained
