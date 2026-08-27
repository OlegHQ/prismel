type t={mutable surface:Surface.t;mutable depth:Depth_stencil.t option;mutable generation:int;mutable destroyed:bool;mutable views:int}
type view={owner:t;generation:int;mutable released:bool}
type capture={width:int;height:int;pitch:int;pixels:bytes;generation:int}
type counters={targets:int;views:int}
type error=Surface_error|Depth_error|Consumer_error of Consumer.error|Destroyed|Stale_generation|Released_view|Live_views of int
let live_targets=Atomic.make 0 and live_views=Atomic.make 0
let increment counter=ignore(Atomic.fetch_and_add counter 1)
let decrement counter=ignore(Atomic.fetch_and_add counter(-1))
let create ?(depth=false) ~width ~height ()=match Surface.create~width~height()with Error _->Error Surface_error|Ok surface->let want_depth=depth in let depth=if want_depth then match Depth_stencil.create~width~height()with Ok x->Some x|Error _->None else None in if want_depth && Option.is_none depth then Error Depth_error else(increment live_targets;Ok{surface;depth;generation=0;destroyed=false;views=0})
let resize owner ~width ~height=if owner.destroyed then Error Destroyed else match Surface.create~width~height()with Error _->Error Surface_error|Ok surface->let depth=match owner.depth with None->Ok None|Some _->(match Depth_stencil.create~width~height()with Ok x->Ok(Some x)|Error _->Error Depth_error)in(match depth with Error _ as e->e|Ok depth->owner.surface<-surface;owner.depth<-depth;owner.generation<-owner.generation+1;Ok())
let view owner=if owner.destroyed then Error Destroyed else(owner.views<-owner.views+1;increment live_views;Ok{owner;generation=owner.generation;released=false})
let release_view view=if view.released then Error Released_view else(view.released<-true;view.owner.views<-view.owner.views-1;decrement live_views;Ok())
let valid view=if view.released then Error Released_view else if view.owner.destroyed then Error Destroyed else if view.generation<>view.owner.generation then Error Stale_generation else Ok()
let render view ~lookup ir=match valid view with Error _ as e->e|Ok()->let depth=Option.map(fun attachment->{Consumer.attachment;state={Depth_stencil.depth_compare=Less;depth_write=true;stencil=None};value=0.5;clear=1.;clear_stencil=0})view.owner.depth in(match Consumer.execute ?depth~lookup~target:view.owner.surface ir with Ok()->Ok()|Error e->Error(Consumer_error e))
let capture view=match valid view with Error _ as e->e|Ok()->let surface=view.owner.surface in Ok{width=Surface.width surface;height=Surface.height surface;pitch=Surface.pitch surface;pixels=Bytes.copy(Surface.bytes surface);generation=view.generation}
let destroy owner=if owner.destroyed then Error Destroyed else if owner.views<>0 then Error(Live_views owner.views)else(owner.destroyed<-true;decrement live_targets;Ok())
let counters()={targets=Atomic.get live_targets;views=Atomic.get live_views}
