type stage = Vertex | Fragment | Compute
type binding_kind = Uniform_buffer | Storage_buffer | Sampled_texture | Storage_texture | Sampler
type entry_point = { name : string; stage : stage }
type binding =
  { group : int; binding : int; kind : binding_kind; visibility : stage list }
type descriptor =
  { backend : string
  ; label : string option
  ; bytes : bytes
  ; entry_points : entry_point list
  ; bindings : binding list
  }
type t

val create : descriptor -> (t, Error.t) result
val backend : t -> string
val label : t -> string option
val bytes : t -> bytes
val entry_points : t -> entry_point list
val bindings : t -> binding list
val provenance_hash : t -> string
