type lane=Mechanical_value|Handwritten_ownership
type item={id:string;lane:lane}
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let scalar=[":allocatedSize";":resourceOptions";":drawableID";":gpuResourceID";":supportIndirectCommandBuffers";
 ":status";":signaledValue";":pixelFormat";":width";":height";":depth"]
let mechanical id=List.exists(fun p->String.starts_with~prefix:p id)["class:";"protocol:";"typedef:";"enum-case:";"record:"]||List.exists(contains id)scalar
let items=List.map(fun id->{id;lane=if mechanical id then Mechanical_value else Handwritten_ownership})Binding_residual_manifest.ids
let count lane=List.fold_left(fun n x->if x.lane=lane then n+1 else n)0 items
let routed_active_counts=
 ["render-pipeline-and-mesh-tile",191;"device",101;"tensor-raster",102;
  "acceleration",83;"compute-pipeline",27;"render19-remainder",10;
  "presentation-availability",9;"resource-view-remainder",1]
