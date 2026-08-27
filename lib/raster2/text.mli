type metric={advance:float;bearing_x:float;bearing_y:float;width:int;height:int}
type glyph={codepoint:int;metric:metric}
type kerning={left:int;right:int;adjustment:float}
type run={font:int64;density:int;origin_x:float;baseline:float;color:int32;clip:Render_ir.rect option;glyphs:glyph array;kernings:kerning array}
type prepared
type error=Invalid_density|Invalid_metric|Invalid_page|Missing_glyph of int|Too_many_glyphs|Capacity_exceeded|Ir_error of Render_ir.error|Consumer_error of Consumer.error
val prepare : atlas:Atlas.t -> page_width:int -> page_height:int -> resource_id:int -> hard_capacity:int -> run -> (prepared,error) result
val ir : prepared -> Render_ir.t
val physical_bounds : prepared -> Render_ir.rect
val render : prepared -> target:Surface.t -> (unit,error) result
