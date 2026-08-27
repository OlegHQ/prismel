type format = Rgba8 | Bgra8 | Depth32 | Stencil8 | Depth32_stencil8
type usage = Render_target | Resolve_target
type texture = { id:int64; handle:unit Handle.t; format:format; samples:int; width:int; height:int; usage:usage list }
type load = Load | Clear | Dont_care
type store = Store | Discard | Resolve
type color = { texture:texture; resolve:texture option; load:load; store:store; clear:float*float*float*float }
type depth = { texture:texture; load:load; store:store; clear:float }
type stencil = { texture:texture; load:load; store:store; clear:int }
type rect = { x:int; y:int; width:int; height:int }
type descriptor = { colors:color option array; depth:depth option; stencil:stencil option; viewport:rect; scissor:rect }
type t
val create : Handle.device -> descriptor -> (t,Error.t) result
val descriptor : t -> descriptor
val encode : t -> Command.t -> (unit,Error.t) result
