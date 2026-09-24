type package = Constructors | Layer_graph | Descriptor_graph | Rate_map
type item = { id:string; package:package; operation:string; tests:string list }
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let callable_ids=List.sort_uniq String.compare(Binding_rasterization_rate_reachability.mechanical_ids@Binding_rasterization_rate_reachability.ownership_ids)
let make id=
 let package,operation,tests=
  if contains id " initWith"||String.starts_with~prefix:"method:+"id then Constructors,"Metal.Rasterization_rate Layer/Descriptor.create",["dimension/sample validation";"native defaults";"failure unwind"]
  else if contains id "MTLRasterizationRateLayerDescriptor"||contains id "MTLRasterizationRateLayerArray"||contains id "MTLRasterizationRateSampleArray" then Layer_graph,"Metal.Rasterization_rate.Layer",["exact sample round trip";"index and max-count rejection";"mutation ownership"]
  else if contains id "MTLRasterizationRateMapDescriptor" then Descriptor_graph,"Metal.Rasterization_rate.Descriptor",["layer count/index validation";"nullable layer graph";"destroy order"]
  else Rate_map,"Metal.Rasterization_rate.Map",["device identity and label";"coordinate inverse/physical sizes";"copy parameter buffer bounds"]in
 {id;package;operation;tests}
let items=List.map make callable_ids
let items_for p=List.filter(fun x->x.package=p)items
let m1_capability_tests=
 ["supportsRasterizationRateMapWithLayerCount is checked before construction"
 ;"unsupported hardware returns Unsupported without allocating a handle"
 ;"supported hardware runs coordinate/copy exactness; unsupported M1 skips only those GPU assertions"
 ;"wrong-device buffer copy and destroyed-object calls preserve zero handle delta"]
let validate()=
 if List.length callable_ids<>50||List.map(fun p->List.length(items_for p))[Constructors;Layer_graph;Descriptor_graph;Rate_map]<>[5;17;12;16]
    || List.exists(fun x->x.operation=""||x.tests=[])items||List.length m1_capability_tests<>4
 then failwith"RasterizationRate50 safe handoff drift"
let ()=validate()
