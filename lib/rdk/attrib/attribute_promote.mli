type method_ =
  | First | Last | Average | Minimum | Maximum | Mode | Median | Sum
  | Sum_squares | Root_mean_square | Array_all | Unique_values

val promote :
  ?cancel:Cancel.t -> ?grain:int -> ?into:string -> ?method_:method_ ->
  ?delete_source:bool -> ?piece_attribute:string -> ?index_attribute:string ->
  source:Attribute.owner -> destination:Attribute.owner -> name:string ->
  Geometry.t -> (Geometry.t, Error.t) result

val promote_pattern :
  ?cancel:Cancel.t -> ?grain:int -> ?method_:method_ ->
  ?delete_source:bool -> ?piece_attribute:string -> ?into_pattern:string ->
  ?index_pattern:string -> source:Attribute.owner ->
  destination:Attribute.owner -> pattern:string -> Geometry.t ->
  (Geometry.t, Error.t) result
