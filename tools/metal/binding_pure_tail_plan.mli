type lane = Enum_case | Fixed_alias | Scalar_alias | Constructor
type item = { id : string; lane : lane }
val items : item list
val excluded : string list
val validate : unit -> unit
