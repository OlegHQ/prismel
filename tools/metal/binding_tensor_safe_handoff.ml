type public_module = Extents | Descriptor | Tensor | Byte_slice
type item = { id:string; public_module:public_module; operation:string; tests:string list }

let contains s n =
  let l=String.length n in let rec loop i=i+l<=String.length s&&(String.sub s i l=n||loop(i+1)) in loop 0

let mechanical_ids =
  [ "bufferOffset"; "dataType"; "gpuResourceID"; "usage" ]
  |> List.concat_map (fun n->["method:-[MTLTensor "^n^"]";"property:MTLTensor:"^n])
  |> fun xs -> xs @
    ([ "cpuCacheMode"; "dataType"; "hazardTrackingMode"; "resourceOptions"; "storageMode"; "usage" ]
     |> List.concat_map (fun n->["method:-[MTLTensorDescriptor "^n^"]";"property:MTLTensorDescriptor:"^n;
       "method:-[MTLTensorDescriptor set"^String.capitalize_ascii n^":]"]))
  |> fun xs -> xs @ ["method:-[MTLTensorExtents extentAtDimensionIndex:]";"method:-[MTLTensorExtents rank]";"property:MTLTensorExtents:rank"]

let ownership_ids =
  [ "method:-[MTLTensor buffer]";"method:-[MTLTensor dimensions]";"method:-[MTLTensor strides]"
  ; "property:MTLTensor:buffer";"property:MTLTensor:dimensions";"property:MTLTensor:strides"
  ; "method:-[MTLTensor getBytes:strides:fromSliceOrigin:sliceDimensions:]"
  ; "method:-[MTLTensor replaceSliceOrigin:sliceDimensions:withBytes:strides:]"
  ; "method:-[MTLTensorDescriptor dimensions]";"method:-[MTLTensorDescriptor setDimensions:]"
  ; "method:-[MTLTensorDescriptor strides]";"method:-[MTLTensorDescriptor setStrides:]"
  ; "property:MTLTensorDescriptor:dimensions";"property:MTLTensorDescriptor:strides"
  ; "method:-[MTLTensorExtents initWithRank:values:]" ]

let callable_ids=List.sort_uniq String.compare(mechanical_ids@ownership_ids)
let device_enablers=
  ["method:-[MTLDevice newTensorWithDescriptor:error:]";"method:-[MTLDevice tensorSizeAndAlignWithDescriptor:]"]
let buffer_enabler="method:-[MTLBuffer newTensorWithDescriptor:offset:error:]"

let make id =
  let public_module,operation,tests =
    if contains id "MTLTensorExtents" then Extents,"Metal.Tensor.Extents",["positive rank and exact values";"index/rank rejection";"destroyed handle"]
    else if contains id "MTLTensorDescriptor" then Descriptor,"Metal.Tensor.Descriptor",["defaults and scalar round trip";"dimension/stride rank validation";"mutation ownership and destroy order"]
    else if contains id "getBytes"||contains id "replaceSlice" then Byte_slice,"Metal.Tensor.get_bytes/replace_bytes",["exact byte round trip";"origin/dimension/stride bounds";"undersized bytes and no-handle-delta rejection"]
    else Tensor,"Metal.Tensor resource queries",["device/buffer identity";"dimension/stride snapshot";"parent destroy blocking"] in
  {id;public_module;operation;tests}
let items=List.map make callable_ids
let items_for m=List.filter(fun x->x.public_module=m)items
let validate()=
  if List.length mechanical_ids<>29||List.length ownership_ids<>15||List.length callable_ids<>44
     || List.map(fun m->List.length(items_for m))[Extents;Descriptor;Tensor;Byte_slice]<>[4;24;14;2]
     || List.exists(fun x->x.operation=""||x.tests=[])items||List.length device_enablers<>2
  then failwith"Tensor44 safe handoff drift"
let ()=validate()
