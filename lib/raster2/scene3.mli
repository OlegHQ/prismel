type vertex={x:float;y:float;z:float;color:int32;u:float;v:float}
type topology=Point_list|Line_list|Line_strip|Line_loop|Triangle_list|Triangle_strip|Triangle_fan
type viewport={x:float;y:float;width:float;height:float;min_depth:float;max_depth:float}
type prepared={points:Triangle.vertex array;lines:(Triangle.vertex*Triangle.vertex)array;triangles:(Triangle.vertex*Triangle.vertex*Triangle.vertex)array;clip:Triangle.clip}
type error=Invalid_matrix|Non_finite|Invalid_cardinality|Invalid_index of int|Invalid_viewport|Invalid_scissor|Complexity_limit
(** [matrix] is row-major. Varyings are divided by clip [w] before output. *)
val prepare : matrix:float array -> viewport:viewport -> scissor:Triangle.clip -> topology:topology -> vertices:vertex array -> indices:int array -> (prepared,error) result
