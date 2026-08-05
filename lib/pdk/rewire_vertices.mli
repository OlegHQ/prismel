val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:Element_selection.t ->
  ?recursive:bool ->
  ?delete_target_attribute:bool ->
  ?keep_unused_points:bool ->
  ?original_point_attribute:string ->
  owner:Attribute.owner ->
  target_attribute:string ->
  Geometry.t ->
  (Geometry.t, string) result
