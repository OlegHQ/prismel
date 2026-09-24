type implementation = Generated_typed | Handwritten_safe
type item = { id : string; implementation : implementation; evidence : string }
let contains text needle =
  let n=String.length needle in
  let rec loop i = i+n<=String.length text &&
    (String.sub text i n=needle || loop (i+1)) in loop 0
let handwritten id = List.exists (contains id)
  [ "newBuffer"; "newTexture"; "newTextureView"; "newResourceView"
  ; "resourceStateCommandEncoder"; "updateTextureMapping"; "moveTextureMappings"
  ; "contents"; "getBytes"; "replaceRegion"; "makeAliasable"; "setPurgeableState" ]
let items = List.map (fun id -> if handwritten id then
  {id;implementation=Handwritten_safe;evidence="range/device/capability/ownership validation"}
  else {id;implementation=Generated_typed;evidence="static direct selector or enum mapping"})
  Binding_resource_manifest.ids
let count expected = List.fold_left (fun n item -> if item.implementation=expected then n+1 else n) 0 items
let generated_count=count Generated_typed
let handwritten_count=count Handwritten_safe
