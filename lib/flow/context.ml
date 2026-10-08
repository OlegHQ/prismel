type t = string
type descriptor = {name : string; result : Ty.t; supports_values : bool;
  label : string; color : Ty.color; group : string; catalog_prefix : string option}
let sop = "sop" and value = "value" and draw = "draw" and scene = "scene" and host="host"
and world = "world" and settings = "settings" and editor = "editor" and material = "material" and image = "image"
let entry name result supports_values label color group catalog_prefix =
  {name; result; supports_values; label; color; group; catalog_prefix}
let registry = ref [
  entry scene Ty.scene false "Scene" `Vec3 "Scene" (Some "scene");
  entry sop Ty.geometry true "SOP" `Geometry "Geometry" (Some "sop");
  entry material Ty.material true "Material" `Record "Materials" None;
  entry world Ty.world false "World" `Record "World" (Some "world");
  entry editor Ty.editor false "Editor" `Int "Layout" None;
  entry settings Ty.settings false "Settings" `Bool "Settings" (Some "settings");
  entry value Ty.Float true "Value" `Float "Values" None;
  entry draw Ty.drawing true "Drawing" `Vec3 "Drawing" None;
  entry image Ty.image true "Image" `Output "Images" None;
  entry "host" Ty.Any true "Host" `Bool "Effects" None]
let all () = List.map (fun descriptor -> descriptor.name) !registry
let descriptor id = List.find (fun descriptor -> descriptor.name = id) !registry
let name id = (descriptor id).name
let result id = (descriptor id).result
let supports_values id = (descriptor id).supports_values
let register (entry : descriptor) =
  let error code message = Error (Diagnostic.error ~code message) in
  if not (Symbol.valid_name entry.name) || Symbol.reserved entry.name || entry.label = "" || entry.group = ""
    || Ty.of_string (Ty.to_string entry.result) <> Some entry.result
    || Option.fold ~none:false ~some:(fun prefix -> not (Symbol.valid_name prefix)) entry.catalog_prefix then
    error "E_CONTEXT_DESCRIPTOR" ("Invalid context descriptor " ^ entry.name)
  else match List.find_opt (fun previous -> previous.name = entry.name) !registry with
    | Some previous when previous = entry -> Ok entry.name
    | Some _ -> error "E_CONTEXT_DUPLICATE" ("Conflicting context " ^ entry.name)
    | None when Option.fold ~none:false ~some:(fun prefix ->
        List.exists (fun previous -> previous.catalog_prefix = Some prefix) !registry) entry.catalog_prefix ->
        error "E_CONTEXT_PREFIX" "A catalog prefix belongs to one context."
    | None -> registry := !registry @ [entry]; Ok entry.name
let of_string name = if List.exists (fun descriptor -> descriptor.name = name) !registry then Ok name else
  Error (Diagnostic.error ~code:"E_CONTEXT_UNKNOWN"
    (Printf.sprintf "Unknown context %s. Known contexts: %s" name (String.concat ", " (all ()))))
let of_qualified qualified = List.find_map (fun entry ->
  Option.bind entry.catalog_prefix (fun prefix ->
    if String.starts_with ~prefix:(prefix ^ "/") qualified then Some entry.name else None)) !registry
