type t = Sop | Value | Draw | Scene | World | Settings | Editor | Material
let all = [Sop; Value; Draw; Scene; World; Settings; Editor; Material]

let name = function
  | Sop -> "sop" | Value -> "value" | Draw -> "draw" | Scene -> "scene" | World -> "world" | Settings -> "settings" | Editor -> "editor" | Material -> "material"
let of_string = function
  | "sop" -> Ok Sop | "value" -> Ok Value | "scene" -> Ok Scene | "world" -> Ok World
  | "draw" -> Ok Draw
  | "settings" -> Ok Settings
  | "editor" -> Ok Editor
  | "material" -> Ok Material
  | unknown -> Error (Diagnostic.error ~code:"E_CONTEXT_UNKNOWN"
      (Printf.sprintf "Unknown context %s. Known contexts: %s" unknown (String.concat ", " (List.map name all))))
let supports_values = function Sop | Value | Draw | Material -> true | Scene | World | Settings | Editor -> false
