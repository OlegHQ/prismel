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
type cull = Cull_none | Cull_front | Cull_back
type comparison = Never | Less | Equal | Less_equal | Greater | Not_equal | Greater_equal | Always
type raster_state = { cull:cull; depth_compare:comparison; depth_write:bool }
type stencil_operation = Keep | Zero | Replace | Increment_clamp | Decrement_clamp | Invert | Increment_wrap | Decrement_wrap
type stencil_face = { compare:comparison; stencil_fail:stencil_operation; depth_fail:stencil_operation; pass:stencil_operation; read_mask:int32; write_mask:int32 }
type stencil_state = { front:stencil_face; back:stencil_face; front_reference:int32; back_reference:int32 }
type t
type primitive = Triangle_list | Triangle_strip
type index_type = Uint16 | Uint32
type buffer_binding = { stage:Command.stage; index:int; buffer_id:int64; offset:int64 }
type texture_binding = { stage:Command.stage; index:int; texture_id:int64 }
type sampler_binding = { stage:Command.stage; index:int; sampler:Types.sampler_descriptor }
type draw = { pipeline_key:string; buffers:buffer_binding list; textures:texture_binding list; samplers:sampler_binding list; primitive:primitive; vertex_start:int; vertex_count:int; index:(index_type*int64*int64*int) option }
type submission
val default_raster_state : raster_state
val default_stencil_face : stencil_face
val default_stencil_state : stencil_state
val create : ?raster_state:raster_state -> ?stencil_state:stencil_state -> Handle.device -> descriptor -> (t,Error.t) result
val descriptor : t -> descriptor
val raster_state : t -> raster_state
val stencil_state : t -> stencil_state option
val encode : t -> Command.t -> (unit,Error.t) result
val submit : t -> draw list -> (submission,Error.t) result
val submission_pass : submission -> t
val submission_draws : submission -> draw list
