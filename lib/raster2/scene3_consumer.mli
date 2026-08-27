type vertex={position:Scene3_lighting.vec3;normal:Scene3_lighting.vec3;color:int32;u:float;v:float}
type shading=Flat|Smooth
type mode=Faces|Wireframe|Vertices
type draw={matrix:float array;model_matrix:float array;camera_position:Scene3_lighting.vec3;viewport:Scene3.viewport;scissor:Triangle.clip;topology:Scene3.topology;vertices:vertex array;indices:int array;lighting:Scene3_lighting.descriptor;shadows:Shadow_map.prepared option array;shading:shading;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend;depth_stencil:Depth_stencil.state;mode:mode;line_width:float;point_size:float;program:Scene3_program.program option}
type target={color:Surface.t;depth:Depth_stencil.t option;multisample:Multisample.t option}
type error=Invalid_target|Invalid_vertex|Lighting_error of Scene3_lighting.error|Geometry_error of Scene3.error|Program_error of Scene3_program.error
val render : target:target -> clear:int32 -> clear_depth:float -> clear_stencil:int -> draws:draw array -> (unit,error) result
