type stage = Vertex | Fragment | Compute
type kind = Buffer | Texture | Sampler | Acceleration_structure
type layout_entry = { binding : int; kind : kind; visibility : stage list }
type layout
type pipeline_layout
type resource
type group_entry = { binding : int; resource : resource }
type bind_group
type resource_snapshot = { binding : int; kind : kind; id : int64 }

val create_layout : layout_entry list -> (layout, Error.t) result
val layout_entries : layout -> layout_entry list
val create_pipeline_layout :
  device:Handle.device -> capabilities:Capabilities.t -> (int * layout) list ->
  (pipeline_layout, Error.t) result
val pipeline_layouts : pipeline_layout -> (int * layout_entry list) list

val buffer : 'a Handle.t -> resource
val texture : 'a Handle.t -> resource
val sampler : 'a Handle.t -> resource
val acceleration_structure : 'a Handle.t -> resource
val create_group : pipeline_layout -> group:int -> group_entry list -> (bind_group, Error.t) result
val group_entries : bind_group -> resource_snapshot list
val validate_group : pipeline_layout -> bind_group -> (unit, Error.t) result
