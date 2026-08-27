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
type primitive = Triangle_list | Triangle_strip
type index_type = Uint16 | Uint32
type buffer_binding = { stage:Command.stage; index:int; buffer_id:int64; offset:int64 }
type texture_binding = { stage:Command.stage; index:int; texture_id:int64 }
type sampler_binding = { stage:Command.stage; index:int; sampler:Types.sampler_descriptor }
type draw = { pipeline_key:string; buffers:buffer_binding list; textures:texture_binding list; samplers:sampler_binding list; primitive:primitive; vertex_start:int; vertex_count:int; index:(index_type*int64*int64*int) option }
type submission
val create : Handle.device -> descriptor -> (t,Error.t) result
val descriptor : t -> descriptor
val encode : t -> Command.t -> (unit,Error.t) result
val submit : t -> draw list -> (submission,Error.t) result
val submission_pass : submission -> t
val submission_draws : submission -> draw list
