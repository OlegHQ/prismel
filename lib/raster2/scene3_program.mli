type vec2={x:float;y:float}
type vec3={x:float;y:float;z:float}
type vertex={clip_x:float;clip_y:float;clip_z:float;clip_w:float;world:vec3;normal:vec3;color:int32;tex_coord:vec2;varyings:float array}
type primitive=Point of vertex|Line of vertex*vertex|Triangle of vertex*vertex*vertex
type fragment_input={screen:vec2;depth:float;front_facing:bool;world:vec3;normal:vec3;color:int32;tex_coord:vec2;varyings:float array}
type fragment_output={color:int32;depth:float option}
type error=Non_finite|Varying_cardinality|Fragment_failure|Invalid_depth
type program={primitives:primitive array;varying_count:int;fragment:fragment_input->fragment_output option}
val render : ?sample_offset:float*float -> color:Surface.t -> depth:Depth_stencil.t option -> depth_state:Depth_stencil.state -> blend:Composite.blend -> cull:Triangle.cull -> clip:Triangle.clip -> point_size:float -> line_width:float -> varying_count:int -> fragment:(fragment_input->fragment_output option) -> primitive array -> (unit,error)result
