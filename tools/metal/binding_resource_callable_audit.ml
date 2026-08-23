type lane = Constant_or_class | Scalar_selector | Handwritten_ownership
type item = { id : string; lane : lane; reason : string }
let contains text needle =
  let n=String.length needle in let rec loop i = i+n<=String.length text &&
    (String.sub text i n=needle || loop (i+1)) in loop 0
let begins text prefix = String.starts_with ~prefix text
let ownership id = List.exists (contains id)
  [ "new"; "objectAtIndexedSubscript"; "setObject:atIndexedSubscript"
  ; "device"; "heap"; "sampleBuffer"; "copyResourceViews"
  ; "setTextureView"; "remoteStorage"; "rootResource"; ":buffer"
  ; "updateFence"; "waitForFence"; "setOwnerWithIdentity"
  ; "sampleBufferAttachments" ]
let classify id =
  if begins id "class:" || begins id "enum-case:" then
    {id;lane=Constant_or_class;reason="compile-time class/constant qualification only"}
  else if ownership id then
    {id;lane=Handwritten_ownership;reason="constructor/object/borrowed-parent/completion ownership"}
  else {id;lane=Scalar_selector;reason="direct scalar/value getter or setter"}
let items=List.map classify Binding_resource_manifest.ids
let count lane=List.fold_left(fun n item->if item.lane=lane then n+1 else n)0 items
