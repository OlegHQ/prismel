type transform = { xx : float; xy : float; yx : float; yy : float; tx : float; ty : float }
type clip = { x : int; y : int; width : int; height : int }
type antialias = Disabled | Supersample4
type style =
  | Fill of Path.fill_rule
  | Stroke of { width : float; cap : Path.cap; join : Path.join; miter_limit : float }
type error = Path_error of Path.error | Surface_error | Invalid_clip

val identity : transform
val draw :
  target:Surface.t -> path:Path.t -> style:style -> tolerance:float ->
  transform:transform -> clip:clip -> color:int32 -> blend:Composite.blend ->
  antialias:antialias -> (unit, error) result
