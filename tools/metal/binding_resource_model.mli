type range = { offset : int; length : int }
type extent = { width : int; height : int; depth : int }
type allocation = Buffer of { length : int; alignment : int } | Texture of extent
val validate_range : total:int -> alignment:int -> range -> (unit, string) result
val validate_extent : extent -> (unit, string) result
val lifecycle_invariants : string list
