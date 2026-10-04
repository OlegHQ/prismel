type projection = {
  positions : Packed.Float3.t;
  converged : bool;
}

type targets = Constant of float | Per_edge of float array

val project :
  ?cancel:Cancel.t ->
  grain:int ->
  operation:string ->
  view:Topology_index.Private.view ->
  source:Packed.Float3.Private.view ->
  point_count:int ->
  selected:(int -> bool) ->
  targets:targets ->
  movable:(int -> bool) ->
  maximum_degree:int ->
  iterations:int ->
  step_size:float ->
  threshold:float ->
  only_shorten:bool ->
  unit ->
  (projection, string) result
