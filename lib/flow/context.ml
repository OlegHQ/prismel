type t = Sop | Value | Scene | World | Settings | Editor | Material
let all = [Sop; Value; Scene; World; Settings; Editor; Material]

let name = function
  | Sop -> "sop" | Value -> "value" | Scene -> "scene" | World -> "world" | Settings -> "settings" | Editor -> "editor" | Material -> "material"
let of_string = function
  | "sop" -> Ok Sop | "value" -> Ok Value | "scene" -> Ok Scene | "world" -> Ok World
  | "settings" -> Ok Settings
  | "editor" -> Ok Editor
  | "material" -> Ok Material
  | name -> Error (Diagnostic.error ~code:"E_CONTEXT_UNKNOWN"
      (Printf.sprintf "Unknown context %s. Known contexts: sop, value, scene, world, settings, material" name))
let supports_values = function Sop | Value | Material -> true | Scene | World | Settings | Editor -> false
