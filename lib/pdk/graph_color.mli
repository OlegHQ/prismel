type connectivity =
  | Graph_primitives_by_point
  | Graph_points_by_primitive
  | Graph_primitives_by_edge

type worksets = {
  begin_attribute : string;
  length_attribute : string;
}

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:Element_selection.t ->
  ?connectivity:connectivity ->
  ?color_attribute:string ->
  ?sort_output:bool ->
  ?worksets:worksets ->
  Geometry.t ->
  (Geometry.t, string) result
