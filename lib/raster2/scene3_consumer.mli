type vertex={position:Scene3_lighting.vec3;normal:Scene3_lighting.vec3;color:int32;u:float;v:float}
type shading=Flat|Smooth
type draw={matrix:float array;viewport:Scene3.viewport;scissor:Triangle.clip;topology:Scene3.topology;vertices:vertex array;indices:int array;lighting:Scene3_lighting.descriptor;shadows:Shadow_map.prepared option array;shading:shading;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend}
type target={color:Surface.t;depth:Depth_stencil.t option;multisample:Multisample.t option}
type error=Invalid_target|Invalid_vertex|Lighting_error of Scene3_lighting.error|Geometry_error of Scene3.error
val render : target:target -> clear:int32 -> clear_depth:float -> draws:draw array -> (unit,error) result
