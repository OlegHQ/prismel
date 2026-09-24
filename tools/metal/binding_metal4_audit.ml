type lane=Mechanical_value|Handwritten_lifecycle
type item={id:string;lane:lane}
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let scalar=[":functionType";":GPUEndTime";":GPUStartTime";":count";":type";
 ":intermediatesHeapSize";"setCount:";"setType:"]
let mechanical id=List.exists(fun p->String.starts_with~prefix:p id)["class:";"protocol:";"typedef:";"enum-case:";"function:MTL4BufferRange"]||List.exists(contains id)scalar
let items=List.map(fun id->{id;lane=if mechanical id then Mechanical_value else Handwritten_lifecycle})Binding_metal4_manifest.ids
let count lane=List.fold_left(fun n x->if x.lane=lane then n+1 else n)0 items
