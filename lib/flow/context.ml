type t = Sop | Value | Scene | World

let name = function Sop -> "sop" | Value -> "value" | Scene -> "scene" | World -> "world"
let of_string = function
  | "sop" -> Ok Sop | "value" -> Ok Value | "scene" -> Ok Scene | "world" -> Ok World
  | name -> Error (Diagnostic.error ~code:"E_CONTEXT_UNKNOWN"
      (Printf.sprintf "Unknown context %s. Known contexts: sop, value; reserved: scene, world" name))
let supports_values = function Sop | Value -> true | Scene | World -> false
