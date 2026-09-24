type stage = Object | Mesh | Fragment | Tile
type object_ref = { id:int; device:int; live:bool }
type linking = { functions:object_ref list; archives:object_ref list; libraries:object_ref list }
type attachment = { index:int; pixel_format:int; write_mask:int }
type pipeline =
  { device:int; stages:(stage*object_ref) list; linking:linking
  ; buffers:(int*int) list; attachments:attachment list }
val validate : pipeline -> (unit,string) result
val retain_for_completion : pipeline -> (object_ref list,string) result
