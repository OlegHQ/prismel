type lane=Mechanical_value|Handwritten_graph
type item={id:string;lane:lane}
let contains text needle=let n=String.length needle in let rec loop i=i+n<=String.length text&&(String.sub text i n=needle||loop(i+1))in loop 0
let scalar_names=
  [ ":active"; ":attributeIndex"; ":attributeType"; ":patchControlPointData"; ":patchData"
  ; ":bufferIndex"; ":format"; ":offset"; ":requiredThreadsPerThreadgroup"
  ; ":options"; ":patchControlPointCount"; ":patchType"; ":argumentIndex"
  ; ":indexBufferIndex"; ":indexType"; "setActive:"; "setAttributeIndex:"
  ; "setAttributeType:"; "setPatchControlPointData:"; "setPatchData:"
  ; "setBufferIndex:"; "setFormat:"; "setOffset:"; "setRequiredThreadsPerThreadgroup:"
  ; "setOptions:"; "setArgumentIndex:"; "setIndexBufferIndex:"; "setIndexType:" ]
let mechanical id=String.starts_with~prefix:"enum-case:"id||List.exists(contains id)scalar_names
let items=List.map(fun id->{id;lane=if mechanical id then Mechanical_value else Handwritten_graph})Binding_shader_graph_manifest.ids
let count lane=List.fold_left(fun n i->if i.lane=lane then n+1 else n)0 items
