val compute :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  operation:string ->
  Geometry.t ->
  ((float array * float array * float array), string) result
