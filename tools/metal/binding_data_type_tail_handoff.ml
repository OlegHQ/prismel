type package=Opaque_resource_type|Packed_value_type
type item={id:string;package:package;public_value:string;tests:string list}
let resource_names=["ComputePipeline";"DepthStencilState";"IndirectCommandBuffer";"InstanceAccelerationStructure";"IntersectionFunctionTable";"PrimitiveAccelerationStructure";"RenderPipeline";"Tensor";"VisibleFunctionTable"]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let classify id=let package=if List.exists(contains id)resource_names then Opaque_resource_type else Packed_value_type in let name=String.sub id(String.rindex id ':'+1)(String.length id-String.rindex id ':'-1)in{id;package;public_value="Metal.Data_type."^name;tests=["SDK numeric static_assert";"generated to_int/of_int exhaustive round trip";"unknown value rejection";"availability provenance"]}
let validate items=let count p=List.length(List.filter(fun x->x.package=p)items)in if List.length items<>25||count Opaque_resource_type<>9||count Packed_value_type<>16||List.exists(fun x->x.public_value=""||List.length x.tests<>4)items then failwith"MTLDataType25 tail drift"
