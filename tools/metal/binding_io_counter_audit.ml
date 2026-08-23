type lane=Mechanical_value|Handwritten_io
type item={id:string;lane:lane}
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let scalar=[":endOfEncoderSampleIndex";":startOfEncoderSampleIndex";":sampleCount";":storageMode";
 ":status";":maxCommandBufferCount";":maxCommandsInFlight";":priority";":type";
 "setEndOfEncoderSampleIndex:";"setStartOfEncoderSampleIndex:";"setSampleCount:";
 "setStorageMode:";"setMaxCommandBufferCount:";"setMaxCommandsInFlight:";"setPriority:";"setType:"]
let mechanical id=List.exists(fun p->String.starts_with~prefix:p id)["class:";"protocol:";"typedef:"]||List.exists(contains id)scalar
let items=List.map(fun id->{id;lane=if mechanical id then Mechanical_value else Handwritten_io})Binding_io_counter_manifest.ids
let count lane=List.fold_left(fun n x->if x.lane=lane then n+1 else n)0 items
