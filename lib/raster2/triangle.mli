type vertex={x:float;y:float;depth:float;color:int32;u:float;v:float}
type cull=Cull_none|Back|Front
type texture={surface:Surface.t;filter:Image.filter}
type clip={x:int;y:int;width:int;height:int}
val draw : color:Surface.t -> depth:Depth_stencil.t option -> depth_state:Depth_stencil.state -> blend:Composite.blend -> cull:cull -> clip:clip -> texture:texture option -> vertex -> vertex -> vertex -> unit
val visible : cull:cull -> vertex -> vertex -> vertex -> bool
val draw_line : color:Surface.t -> depth:Depth_stencil.t option -> depth_state:Depth_stencil.state -> blend:Composite.blend -> clip:clip -> texture:texture option -> width:float -> vertex -> vertex -> unit
val draw_point : color:Surface.t -> depth:Depth_stencil.t option -> depth_state:Depth_stencil.state -> blend:Composite.blend -> clip:clip -> texture:texture option -> size:float -> vertex -> unit
