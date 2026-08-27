type vertex={x:float;y:float;depth:float;color:int32;u:float;v:float}
type cull=Cull_none|Back|Front
type texture={surface:Surface.t;filter:Image.filter}
type clip={x:int;y:int;width:int;height:int}
val draw : color:Surface.t -> depth:Depth_stencil.t option -> depth_state:Depth_stencil.state -> blend:Composite.blend -> cull:cull -> clip:clip -> texture:texture option -> vertex -> vertex -> vertex -> unit
