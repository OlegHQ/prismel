type t = Sop | Value | Scene | World | Settings

let name = function
  | Sop -> "sop" | Value -> "value" | Scene -> "scene" | World -> "world" | Settings -> "settings"
let of_string = function
  | "sop" -> Ok Sop | "value" -> Ok Value | "scene" -> Ok Scene | "world" -> Ok World
  | "settings" -> Ok Settings
  | name -> Error (Diagnostic.error ~code:"E_CONTEXT_UNKNOWN"
      (Printf.sprintf "Unknown context %s. Known contexts: sop, value, scene, world, settings" name))
let supports_values = function Sop | Value -> true | Scene | World | Settings -> false
