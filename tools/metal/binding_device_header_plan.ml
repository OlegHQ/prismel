type declaration = { id:string; kind:string; owner:string option; name:string; signature:string }
type lane = Metadata | Mechanical | Handwritten_ownership
type entry = { declaration:declaration; lane:lane }
let headers = ["Metal/MTLDevice.h"]
let expected_count = 94
let expected_digest = "81285a3cf295bf0394f127daafbb8e75972f0cfe70c55e42a5937afc5a2eec71"
let excluded_ids =
 ["method:-[MTLDevice newTextureViewPoolWithDescriptor:error:]";
  "method:-[MTLDevice sparseTileSizeWithTextureType:pixelFormat:sampleCount:]";
  "method:-[MTLDevice accelerationStructureSizesWithDescriptor:]";
  "method:-[MTLDevice functionHandleWithBinaryFunction:]";
  "method:-[MTLDevice functionHandleWithFunction:]";
  "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithDescriptor:]";
  "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithSize:]";
  "method:-[MTLDevice newAccelerationStructureWithDescriptor:]";
  "method:-[MTLDevice newAccelerationStructureWithSize:]"]
let contains text needle =
  let rec loop i=i+String.length needle<=String.length text &&
    (String.sub text i (String.length needle)=needle || loop(i+1)) in loop 0
let mechanical signature =
  not (List.exists (contains signature)
    ["*";"id<";"NSArray";"Handler";"dispatch_data_t";"MTLRegion";
     "MTLSamplePosition";"MTLTimestamp";"MTLAccelerationStructureSizes";
     "MTLSizeAndAlign"])
let classify declaration =
  if declaration.kind<>"method" && declaration.kind<>"property" then Metadata
  else if mechanical declaration.signature then Mechanical else Handwritten_ownership
let select declarations =
  declarations |> List.map(fun declaration->{declaration;lane=classify declaration})
let count lane entries = List.fold_left(fun n e->if e.lane=lane then n+1 else n)0 entries
let validate entries =
  if List.length entries<>expected_count then invalid_arg "MTLDevice/type exact closure drift";
  let ids=List.map(fun e->e.declaration.id)entries in
  if List.length(List.sort_uniq String.compare ids)<>expected_count then
    invalid_arg "MTLDevice.h duplicate IDs"
