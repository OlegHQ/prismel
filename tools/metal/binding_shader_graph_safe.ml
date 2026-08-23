type object_ref={id:int;device:int;live:bool}
type node={id:int;name:string;function_:object_ref;arguments:int list;dependencies:int list}
type graph={device:int;nodes:node list;output:int;archives:object_ref list;functions:object_ref list}
let validate graph =
  let refs=graph.archives@graph.functions@List.map(fun n->n.function_)graph.nodes in
  if List.exists(fun r->not r.live||r.device<>graph.device)refs then Error "shader dependency stale or cross-device"
  else if List.length graph.nodes<>List.length(List.sort_uniq compare(List.map(fun n->n.id)graph.nodes))then Error "duplicate node id"
  else if not(List.exists(fun n->n.id=graph.output)graph.nodes)then Error "missing output node"
  else
    let table=List.map(fun n->n.id,n)graph.nodes in
    let rec visit path id = if List.mem id path then Error "stitching graph cycle" else
      match List.assoc_opt id table with None->Error "unknown dependency"|Some n->
      List.fold_left(fun acc dep->match acc with Error _->acc|Ok()->visit(id::path)dep)(Ok())n.dependencies in
    List.fold_left(fun acc n->match acc with Error _->acc|Ok()->visit[]n.id)(Ok())graph.nodes
